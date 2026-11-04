import Testing
import Foundation
import SwiftData
@testable import IBVault

/// Daily review tests that exercise the opt-in limit declare it with this trait,
/// so they never touch the real user defaults or race other tests.
struct EnforcedDailyLimitTrait: TestTrait, SuiteTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        try await ReviewDailyLimitPolicy.$enforcementOverride.withValue(true) {
            try await function()
        }
    }
}

extension Trait where Self == EnforcedDailyLimitTrait {
    static var enforcedDailyLimit: Self { Self() }
}

@Suite("Daily goal is a target unless enforced")
@MainActor
struct DailyGoalTests {
    private func store(goal: Int, cards: Int) throws -> ModelContainer {
        let container = try ModelContainer(for: StudyCard.self, Subject.self, ReviewSession.self, UserProfile.self,
                                           configurations: .init(isStoredInMemoryOnly: true))
        let profile = UserProfile()
        profile.dailyGoal = goal
        container.mainContext.insert(profile)
        for index in 0..<cards {
            let card = StudyCard(topicName: "Topic", front: "Question \(index)", back: "Answer \(index)")
            card.nextReviewDate = .distantPast
            container.mainContext.insert(card)
        }
        return container
    }

    @Test func aLearnerCanReviewPastTheirGoalByDefault() throws {
        try ReviewDailyLimitPolicy.$enforcementOverride.withValue(false) {
            let container = try store(goal: 30, cards: 90)
            let manager = ReviewQueueManager()
            manager.refreshDueCardsSynchronously(context: container.mainContext)
            #expect(manager.dueCards.count == 90)
            #expect(manager.dailyGoal == 30)
            #expect(manager.isLimitEnforced == false)
            #expect(manager.deferredDueCount == 0)
        }
    }

    @Test func optingInStopsReviewsAtTheGoal() throws {
        try ReviewDailyLimitPolicy.$enforcementOverride.withValue(true) {
            let container = try store(goal: 30, cards: 90)
            let manager = ReviewQueueManager()
            manager.refreshDueCardsSynchronously(context: container.mainContext)
            #expect(manager.dueCards.count == 30)
            #expect(manager.isLimitEnforced)
            #expect(manager.deferredDueCount == 60)
        }
    }

    @Test func aCardStillCountsOnlyOncePerDayWithoutALimit() throws {
        try ReviewDailyLimitPolicy.$enforcementOverride.withValue(false) {
            let container = try store(goal: 5, cards: 3)
            let context = container.mainContext
            let card = try context.fetch(FetchDescriptor<StudyCard>())[0]
            context.insert(ReviewSession(cardID: card.id, subjectName: "", topicName: "Topic", qualityRating: 3))
            let day = try ReviewDailyLimitPolicy.day(in: context)
            #expect(day.canReview(card) == false)
        }
    }
}

@Suite("Large card sets")
@MainActor
struct LargeCardSetTests {
    @Test func plansAreAllowedUpToTheNewMaximumAndNoFurther() throws {
        let jobs = try CardBatchService.plan(scopes: [.init(topic: "Cells")], styles: [.basic], count: 200)
        #expect(jobs.map(\.count) == [200])
        #expect(throws: CardBatchError.self) {
            try CardBatchService.plan(scopes: [.init(topic: "Cells")], styles: [.basic], count: 201)
        }
    }

    private func subject() throws -> (ModelContainer, Subject) {
        let container = try ModelContainer(for: Schema([Subject.self, StudyCard.self, Grade.self]),
                                           configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let subject = Subject(name: "Biology", level: "HL", accentColorHex: "000000")
        container.mainContext.insert(subject)
        return (container, subject)
    }

    @Test func bigSetsAreRequestedInSlicesThatEachKeepGoing() async throws {
        let (container, subject) = try subject()
        let jobs = try CardBatchService.plan(scopes: [.init(topic: "Cells")], styles: [.basic], count: 60)
        var sliceSizes: [Int] = []
        let result = try await CardBatchService.generate(subject: subject, jobs: jobs, options: .default,
            context: container.mainContext, generateCards: { detached, job, settings, _ in
                #expect(settings.count == job.count)
                let offset = sliceSizes.reduce(0, +)
                sliceSizes.append(settings.count)
                return (0..<settings.count).map {
                    StudyCard(topicName: "Cells", front: "Distinct question number \(offset + $0) about cells",
                              back: "Answer \(offset + $0)", subject: detached)
                }
            }, onProgress: { _, _, _ in })
        #expect(sliceSizes == [25, 25, 10])
        #expect(result.drafts.count == 60)
        #expect(result.issues.isEmpty)
    }

    @Test func aFailedSliceKeepsTheCardsAlreadyWritten() async throws {
        struct ProviderDown: Error {}
        let (container, subject) = try subject()
        let jobs = try CardBatchService.plan(scopes: [.init(topic: "Cells")], styles: [.basic], count: 60)
        var calls = 0
        let result = try await CardBatchService.generate(subject: subject, jobs: jobs, options: .default,
            context: container.mainContext, generateCards: { detached, _, settings, _ in
                calls += 1
                if calls == 2 { throw ProviderDown() }
                return (0..<settings.count).map {
                    StudyCard(topicName: "Cells", front: "Distinct question number \($0) about cells",
                              back: "Answer \($0)", subject: detached)
                }
            }, onProgress: { _, _, _ in })
        #expect(result.drafts.count == 25)
        #expect(result.issues.count == 1)
    }
}

@Suite("Study consistency")
struct StudyConsistencyTests {
    private let calendar = Calendar(identifier: .gregorian)
    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000)))!
    }

    @Test func streaksCountConsecutiveActiveDaysAndTodayMayStillBePending() {
        let days: [Date: (cards: Int, minutes: Double)] = [
            day(-9): (5, 0), day(-8): (0, 30), day(-7): (1, 1), day(-6): (2, 0),
            day(-2): (1, 0), day(-1): (0, 20)
        ]
        let stats = StudyConsistency.compute(days: days, today: day(0), calendar: calendar)
        #expect(stats.longestStreak == 4)
        #expect(stats.currentStreak == 2)
        #expect(stats.activeDays == 6)
        #expect(stats.totalCards == 9)
        #expect(stats.totalMinutes == 51)
    }

    @Test func aMissedDayEndsTheCurrentStreakAndEmptyDaysDoNotCount() {
        let days: [Date: (cards: Int, minutes: Double)] = [day(-3): (5, 0), day(0): (0, 0)]
        let stats = StudyConsistency.compute(days: days, today: day(0), calendar: calendar)
        #expect(stats.currentStreak == 0)
        #expect(stats.activeDays == 1)
    }
}

@Suite("Evidence-based mastery levels")
struct MasteryLevelTests {
    private func card(repetitions: Int, stability: Double?, interval: Int = 0) -> StudyCard {
        let card = StudyCard(topicName: "Topic", front: "Q", back: "A")
        card.repetitions = repetitions
        card.successfulReviewCount = repetitions
        card.totalReviewCount = repetitions
        card.consecutiveCorrect = repetitions
        card.interval = interval
        card.fsrsStability = stability
        return card
    }

    @Test func durableNeedsRepeatedSuccessAndAMemoryThatHoldsForWeeks() {
        let durable = card(repetitions: 4, stability: 25)
        ProficiencyTracker.updateProficiency(for: durable)
        #expect(durable.proficiency == .mastered)

        let tooFewRecalls = card(repetitions: 3, stability: 40)
        ProficiencyTracker.updateProficiency(for: tooFewRecalls)
        #expect(tooFewRecalls.proficiency == .proficient)

        let notHoldingYet = card(repetitions: 8, stability: 10)
        ProficiencyTracker.updateProficiency(for: notHoldingYet)
        #expect(notHoldingYet.proficiency == .proficient)
    }

    @Test func aForgottenCardWithLowStabilityFallsBack() {
        let lapsed = card(repetitions: 8, stability: 2)
        ProficiencyTracker.updateProficiency(for: lapsed)
        #expect(lapsed.proficiency == .developing)
    }

    @Test func cardsFromBeforeFSRSUseTheirInterval() {
        let legacy = card(repetitions: 4, stability: nil, interval: 30)
        ProficiencyTracker.updateProficiency(for: legacy)
        #expect(legacy.proficiency == .mastered)
    }

    @Test func everyLevelHasAGuideAndEveryCitationALink() {
        #expect(MasteryLevelGuide.all().map(\.level) == ProficiencyLevel.allCases)
        #expect(MasteryLevelGuide.citations.allSatisfy { $0.url != nil })
        #expect(Set(ProficiencyLevel.allCases.map(\.stageName)).count == ProficiencyLevel.allCases.count)
    }
}

@Suite("Rank ladder")
@MainActor
struct RankLadderLiveMasteryTests {
    @Test func liveMasteryMatchesTheEnginesTeachingHourWeighting() {
        let high = Subject(name: "Biology", level: "HL", accentColorHex: "000000")
        let standard = Subject(name: "Economics", level: "SL", accentColorHex: "000000")
        let highTrack = SubjectTrack(subjectName: "Biology")
        highTrack.cachedMastery = 1
        let standardTrack = SubjectTrack(subjectName: "Economics")
        standardTrack.cachedMastery = 0
        let live = RankLadderView.liveMastery(subjects: [high, standard], tracks: [highTrack, standardTrack])
        let highWeight = SubjectLevel(rawLevel: "HL").masteryWeight
        let standardWeight = SubjectLevel(rawLevel: "SL").masteryWeight
        #expect(abs(live - highWeight / (highWeight + standardWeight)) < 0.0001)
        #expect(RankLadderView.liveMastery(subjects: [], tracks: []) == 0)
    }
}

@Suite("Codex model catalog", .serialized)
struct CodexCatalogSyncTests {
    private func model(_ id: String) -> CodexCatalogModel {
        CodexCatalogModel(model: id, displayName: id, description: "", hidden: false, isDefault: false, supportedReasoningEfforts: [])
    }

    @Test func aRetiredSelectionFallsBackButACustomOneIsKept() {
        let defaults = UserDefaults.standard
        let savedModel = defaults.string(forKey: "codexModel")
        let savedCatalog = defaults.data(forKey: "codexModelCatalog")
        defer {
            defaults.set(savedModel, forKey: "codexModel")
            defaults.set(savedCatalog, forKey: "codexModelCatalog")
        }

        AIConfiguration.cachedCodexModels = [model("old"), model("current")]
        defaults.set("old", forKey: "codexModel")
        AIConfiguration.syncCodexCatalog([model("current")])
        #expect(defaults.string(forKey: "codexModel") == nil)

        defaults.set("my-private-model", forKey: "codexModel")
        AIConfiguration.syncCodexCatalog([model("newer")])
        #expect(defaults.string(forKey: "codexModel") == "my-private-model")
        #expect(AIConfiguration.cachedCodexModels.map(\.model) == ["newer"])
    }
}

@Suite("Practice exam, against real provider output")
struct RealProviderPaperTests {
    // Shape and maths taken from a paper Codex really generated.
    private let response = #"""
    {
      "question": "# Mathematics AA HL\n\n### Question 1\n\nLet \\(f(x)=\\sin x\\), where \\(0\\leq x\\).\n\n(c) Evaluate \\(\\displaystyle\\int_0^{\\pi/2}f(x)\\,dx\\). [7 marks]\n\n### Question 2\n\n\\[\n\\frac{dy}{dx}=2,\\qquad y(0)=1 [3]\n\\]\n\nSolve it. [10 marks]",
      "markScheme": "Q1: substitution.",
      "maximumMarks": 17
    }
    """#

    @Test func parsesAndCountsOnlyMarksOutsideMaths() throws {
        let paper = try PracticeExamPaper.parse(response)
        #expect(paper.maximumMarks == 17)
        #expect(paper.question.contains(#"\displaystyle"#))
    }

    @Test func aPaperGetsLongEnoughToBeWritten() {
        #expect(PracticeExamPaper.generationTimeout > 200)
    }

    @Test func layoutCommandsNeverAppearAsText() {
        let integral = MathExpressionFormatter.inlineString(from: #"\displaystyle\int_0^1 f(x)\,dx"#)
        #expect(!integral.contains("displaystyle"))
        #expect(!integral.contains(",dx"))
        #expect(integral.contains("∫"))
        let spaced = MathExpressionFormatter.inlineString(from: #"a,\qquad b\quad c"#)
        #expect(!spaced.contains("quad"))
        #expect(MathExpressionFormatter.inlineString(from: #"x \in A"#).contains("∈"))
        #expect(MathExpressionFormatter.inlineString(from: #"\int x"#).contains("∫"))
        #expect(MathExpressionFormatter.inlineString(from: #"\infty"#) == "∞")
    }
}
