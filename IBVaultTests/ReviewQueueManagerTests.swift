import Testing
import Foundation
import SwiftData
@testable import IBVault

@Suite("ReviewQueueManager Tests")
struct ReviewQueueManagerTests {
    
    @MainActor
    @Test("dueCount should return correct count of due cards for a given subject")
    func testDueCountForSubject() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: StudyCard.self, Subject.self, StudySession.self, ReviewSession.self, UserProfile.self, configurations: config)
        let context = container.mainContext
        
        let subject1 = Subject(name: "Mathematics", level: "HL", accentColorHex: "#FF0000")
        let subject2 = Subject(name: "Physics", level: "HL", accentColorHex: "#0000FF")
        context.insert(subject1)
        context.insert(subject2)
        
        let now = Date()
        let past = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let future = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        
        let card1 = StudyCard(topicName: "Calculus", front: "Front 1", back: "Back 1", subject: subject1)
        card1.nextReviewDate = past
        
        let card2 = StudyCard(topicName: "Algebra", front: "Front 2", back: "Back 2", subject: subject1)
        card2.nextReviewDate = future
        
        let card3 = StudyCard(topicName: "Mechanics", front: "Front 3", back: "Back 3", subject: subject2)
        card3.nextReviewDate = past
        
        context.insert(card1)
        context.insert(card2)
        context.insert(card3)
        
        let manager = ReviewQueueManager()
        manager.refreshDueCardsSynchronously(context: context)
        
        #expect(manager.dueCount(for: subject1) == 1)
        #expect(manager.dueCount(for: subject2) == 1)
        #expect(manager.dueCards.count == 2)
    }

    @MainActor
    @Test("dueCardsForSubject falls back to all subject cards when no study scope exists")
    func testDueCardsForSubjectWithoutStudyScopes() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: StudyCard.self, Subject.self, StudySession.self, ReviewSession.self, UserProfile.self, configurations: config)
        let context = container.mainContext

        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "#10B981")
        context.insert(subject)

        let past = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let future = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let dueCard = StudyCard(topicName: "Cells", front: "Front", back: "Back", subject: subject)
        dueCard.nextReviewDate = past
        let futureCard = StudyCard(topicName: "Genetics", front: "Front", back: "Back", subject: subject)
        futureCard.nextReviewDate = future

        context.insert(dueCard)
        context.insert(futureCard)

        let manager = ReviewQueueManager()
        let dueCards = manager.dueCardsForSubject(subject, context: context)

        #expect(dueCards.map(\.id) == [dueCard.id])
    }

    @MainActor
    @Test("eligibleCardsCount should return exact count of study cards when studied scopes are empty")
    func testEligibleCardsCountWithoutStudySessions() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: StudyCard.self, Subject.self, StudySession.self, ReviewSession.self, UserProfile.self, configurations: config)
        let context = container.mainContext
        
        let card1 = StudyCard(topicName: "Calculus", front: "Front 1", back: "Back 1")
        let card2 = StudyCard(topicName: "Algebra", front: "Front 2", back: "Back 2")
        context.insert(card1)
        context.insert(card2)
        
        let manager = ReviewQueueManager()
        manager.refreshDueCardsSynchronously(context: context)
        let eligibleCount = manager.eligibleCardsCount()
        
        #expect(eligibleCount == 2)
    }

    @MainActor
    @Test("eligibleCardsCount stays the full pool even when studied scopes exist")
    func testEligibleCardsCountWithStudySessions() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: StudyCard.self, Subject.self, StudySession.self, ReviewSession.self, UserProfile.self, configurations: config)
        let context = container.mainContext

        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "#10B981")
        context.insert(subject)

        let card = StudyCard(topicName: "Cells", front: "F", back: "B", subject: subject)
        card.nextReviewDate = Date().addingTimeInterval(-60)
        context.insert(card)

        // A meaningful scope makes `studiedScopes` non-empty. The eligible
        // count must still reflect the whole card pool, not a scoped subset,
        // and the refresh no longer materializes that table to find out.
        let session = StudySession(
            subjectName: "Biology",
            topicsCovered: "Cells",
            startDate: Date().addingTimeInterval(-3600),
            cardsReviewed: 1,
            correctCount: 1,
            xpEarned: 5
        )
        context.insert(session)

        let manager = ReviewQueueManager()
        manager.refreshDueCardsSynchronously(context: context)

        #expect(manager.eligibleCardCount == 1)
        #expect(manager.dueCards.count == 1)
    }

    @MainActor
    @Test("A successful refresh clears the error flag and caches all due counts")
    func testSuccessfulRefreshCachesCounts() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: StudyCard.self, Subject.self, StudySession.self, ReviewSession.self, UserProfile.self, configurations: config)
        let context = container.mainContext

        let subject1 = Subject(name: "Biology", level: "SL", accentColorHex: "#10B981")
        let subject2 = Subject(name: "Physics", level: "HL", accentColorHex: "#3B82F6")
        context.insert(subject1)
        context.insert(subject2)

        let now = Date()
        let past = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let future = Calendar.current.date(byAdding: .day, value: 1, to: now)!

        let due1 = StudyCard(topicName: "Cells", front: "F", back: "B", subject: subject1)
        due1.nextReviewDate = past
        let due2a = StudyCard(topicName: "Mechanics", front: "F", back: "B", subject: subject2)
        due2a.nextReviewDate = past
        let due2b = StudyCard(topicName: "Waves", front: "F", back: "B", subject: subject2)
        due2b.nextReviewDate = past
        let notDue = StudyCard(topicName: "Optics", front: "F", back: "B", subject: subject2)
        notDue.nextReviewDate = future
        context.insert(due1)
        context.insert(due2a)
        context.insert(due2b)
        context.insert(notDue)
        try context.save()

        let manager = ReviewQueueManager()
        manager.refreshDueCardsSynchronously(context: context)

        // A successful refresh never leaves a stale error flag.
        #expect(manager.lastRefreshError == nil)
        #expect(manager.dueCards.count == 3)
        #expect(manager.totalDueCount == 3)
        // The eligible-card cache counts the whole pool, including not-yet-due.
        #expect(manager.eligibleCardCount == 4)
        #expect(manager.dueCount(for: subject1) == 1)
        #expect(manager.dueCount(for: subject2) == 2)
        #expect(manager.dueCountPerSubject()[subject2.id.uuidString] == 2)
    }

    @MainActor
    @Test("The daily queue respects the personal goal and defers the backlog")
    func dailyQueueRespectsProfileGoal() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: StudyCard.self,
            Subject.self,
            StudySession.self,
            ReviewSession.self,
            UserProfile.self,
            configurations: config
        )
        let context = container.mainContext
        let profile = UserProfile()
        profile.dailyGoal = 18
        context.insert(profile)

        let past = Date().addingTimeInterval(-3600)
        for index in 0..<56 {
            let card = StudyCard(topicName: "Topic", front: "Question \(index)", back: "Answer \(index)")
            card.nextReviewDate = past
            context.insert(card)
        }
        try context.save()

        let manager = ReviewQueueManager()
        manager.refreshDueCardsSynchronously(context: context)

        #expect(manager.totalDueBacklogCount == 56)
        #expect(manager.dueCards.count == 18)
        #expect(manager.deferredDueCount == 38)
    }
}

@Suite("Daily Review Limit Policy")
struct ReviewDailyLimitPolicyTests {
    @Test("Daily maximum adapts to study intensity and respects a lower personal goal")
    func adaptsDailyMaximum() {
        #expect(ReviewDailyLimitPolicy.maximumCards(for: .belowAverage) == 15)
        #expect(ReviewDailyLimitPolicy.maximumCards(for: .average) == 20)
        #expect(ReviewDailyLimitPolicy.maximumCards(for: .aboveAverage) == 25)
        #expect(ReviewDailyLimitPolicy.maximumCards(for: .intensive) == 30)
        #expect(ReviewDailyLimitPolicy.maximumCards(for: .intensive, dailyGoal: 10) == 10)
        #expect(ReviewDailyLimitPolicy.maximumCards(for: .belowAverage, dailyGoal: 30) == 15)
    }

    @Test("Daily queue caps unique cards and excludes cards already reviewed today")
    func capsDailyQueue() {
        let cards = (0..<45).map { index in
            StudyCard(topicName: "Topic", front: "Question \(index)", back: "Answer \(index)")
        }
        let alreadyReviewed = Set(cards.prefix(7).map(\.id))

        let limited = ReviewDailyLimitPolicy.limitedCards(cards, reviewedCardIDs: alreadyReviewed)

        #expect(limited.count == 33)
        #expect(limited.allSatisfy { !alreadyReviewed.contains($0.id) })
        #expect(ReviewDailyLimitPolicy.allowance(reviewedCardIDs: alreadyReviewed) == 33)
    }
}

@Suite("Review Queue Recovery")
struct ReviewQueueRecoveryTests {
    @MainActor
    @Test("refresh exposes all due cards")
    func refreshExposesAllDueCards() throws {
        let container = try ModelContainer(for: StudyCard.self, Subject.self, StudySession.self, ReviewSession.self, UserProfile.self, configurations: .init(isStoredInMemoryOnly: true))
        let context = container.mainContext
        for index in 0..<3 {
            let card = StudyCard(topicName: "Topic", front: "Q\(index)", back: "A\(index)")
            card.nextReviewDate = Date.distantPast
            context.insert(card)
        }
        let manager = ReviewQueueManager()
        manager.refreshDueCardsSynchronously(context: context)
        #expect(manager.totalDueBacklogCount == 3)
    }

    @Test("daily allowance never hides backlog")
    func dailyAllowancePreservesBacklog() {
        #expect(ReviewDailyLimitPolicy.allowance(reviewedCardIDs: Set(), maximum: 30) == 30)
        #expect(ReviewDailyLimitPolicy.allowance(reviewedCardIDs: Set<UUID>(), maximum: 30) == 30)
    }

    @Test("intensity caps remain bounded")
    func intensityCapsRemainBounded() {
        #expect(ReviewDailyLimitPolicy.maximumCards(for: .intensive) == 30)
        #expect(ReviewDailyLimitPolicy.maximumCards(for: .belowAverage, dailyGoal: 100) == 15)
    }

    @Test("limited cards preserve source order")
    func limitedCardsPreserveSourceOrder() {
        let cards = (0..<3).map { StudyCard(topicName: "Topic", front: "Q\($0)", back: "A\($0)") }
        let limited = ReviewDailyLimitPolicy.limitedCards(cards, reviewedCardIDs: [], maximum: 2)
        #expect(limited.map(\.front) == ["Q0", "Q1"])
    }

    @Test("zero allowance returns no cards")
    func zeroAllowanceReturnsNoCards() {
        let card = StudyCard(topicName: "Topic", front: "Q", back: "A")
        #expect(ReviewDailyLimitPolicy.limitedCards([card], reviewedCardIDs: [], maximum: 0).isEmpty)
    }
}


@Suite("Daily allowance regressions")
@MainActor
struct DailyAllowanceRegressionTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: StudyCard.self, Subject.self, ReviewSession.self, UserProfile.self,
                           configurations: .init(isStoredInMemoryOnly: true))
    }

    @Test func allowanceIsSharedAcrossSubjectsAndIncludesUnsavedReviews() throws {
        let store = try container()
        defer { withExtendedLifetime(store) {} }
        let context = store.mainContext
        let profile = UserProfile()
        profile.dailyGoal = 5
        context.insert(profile)
        let a = Subject(name: "Biology", level: "SL", accentColorHex: "000000")
        let b = Subject(name: "Economics", level: "SL", accentColorHex: "000000")
        context.insert(a)
        context.insert(b)
        var cards: [StudyCard] = []
        for index in 0..<12 {
            let card = StudyCard(topicName: "Topic", front: "Question \(index)", back: "Answer \(index)",
                                 subject: index < 6 ? a : b)
            card.nextReviewDate = .distantPast
            context.insert(card)
            cards.append(card)
        }
        try context.save()
        let manager = ReviewQueueManager()
        #expect(manager.dueCardsForSubject(a, context: context).count == 5)
        for card in cards.prefix(4) {
            context.insert(ReviewSession(cardID: card.id, subjectName: a.name, topicName: card.topicName, qualityRating: 0))
        }
        manager.refreshDueCardsSynchronously(context: context)
        #expect(manager.reviewedTodayCount == 4)
        #expect(manager.dueCards.count == 1)
        #expect(manager.remainingDailyAllowance == 1)
        #expect(manager.dueCardsForSubject(b, context: context).count == 1)
        context.insert(ReviewSession(cardID: cards[6].id, subjectName: b.name, topicName: "Topic", qualityRating: 3))
        #expect(try ReviewDailyLimitPolicy.day(in: context).canReview(cards[7]) == false)
        #expect(manager.cardsForReview(from: cards, context: context).isEmpty)
        manager.refreshDueCardsSynchronously(context: context)
        #expect(manager.dueCards.isEmpty)
        #expect(manager.deferredDueCount == 7)
        #expect(manager.totalDueBacklogCount == 7)
    }

    @Test func aLargeBacklogCannotExceedFortyEvenWithoutAProfile() throws {
        let store = try container()
        defer { withExtendedLifetime(store) {} }
        let context = store.mainContext
        for index in 0..<90 {
            let card = StudyCard(topicName: "Topic", front: "Question \(index)", back: "Answer \(index)")
            card.nextReviewDate = .distantPast
            context.insert(card)
        }
        let day = try ReviewDailyLimitPolicy.day(in: context)
        #expect(day.limited(day.backlog).count == 40)
        #expect(ReviewDailyLimitPolicy.allowance(reviewedCardIDs: [], maximum: 999) == 40)
        let ids = Set((0..<79).map { _ in UUID() })
        #expect(ReviewDailyLimitPolicy.allowance(reviewedCardIDs: ids) == 0)
    }

    @Test func profileChangesRefreshAnOtherwiseUnchangedQueue() throws {
        let store = try container()
        defer { withExtendedLifetime(store) {} }
        let context = store.mainContext
        let profile = UserProfile()
        context.insert(profile)
        for index in 0..<40 {
            context.insert(StudyCard(topicName: "Topic", front: "Question \(index)", back: "Answer \(index)"))
        }
        let manager = ReviewQueueManager()
        manager.refreshDueCardsSynchronously(context: context)
        #expect(manager.dueCards.count == 20)
        profile.dailyGoal = 10
        manager.refreshDueCardsSynchronously(context: context)
        #expect(manager.dueCards.count == 10)
        #expect(manager.deferredDueCount == 30)
    }

    @Test func localDayBoundariesResetTheAllowanceAcrossDaylightSaving() throws {
        let store = try container()
        defer { withExtendedLifetime(store) {} }
        let context = store.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Madrid"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 12)))
        let start = calendar.startOfDay(for: now)
        let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: start))
        #expect(nextDay.timeIntervalSince(start) == 23 * 3600)
        let previous = ReviewSession(cardID: UUID(), subjectName: "", topicName: "", qualityRating: 3)
        previous.timestamp = start.addingTimeInterval(-1)
        let current = ReviewSession(cardID: UUID(), subjectName: "", topicName: "", qualityRating: 3)
        current.timestamp = start
        let future = ReviewSession(cardID: UUID(), subjectName: "", topicName: "", qualityRating: 3)
        future.timestamp = nextDay
        [previous, current, future].forEach(context.insert)
        let today = try ReviewDailyLimitPolicy.day(in: context, now: now, calendar: calendar)
        #expect(today.reviewedIDs == [current.cardID])
        let tomorrow = try ReviewDailyLimitPolicy.day(in: context, now: nextDay, calendar: calendar)
        #expect(tomorrow.reviewedIDs == [future.cardID])
    }

    @Test func aReviewedDuplicateCannotReturnUnderAnotherCardID() throws {
        let store = try container()
        defer { withExtendedLifetime(store) {} }
        let context = store.mainContext
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "000000")
        context.insert(subject)
        let first = StudyCard(topicName: "Cells", front: "What produces ATP?", back: "Mitochondria", subject: subject)
        let copy = StudyCard(topicName: "Cells", front: "What produces ATP!", back: "Mitochondria", subject: subject)
        first.nextReviewDate = .distantPast
        copy.totalReviewCount = 3
        copy.nextReviewDate = .distantFuture
        context.insert(first)
        context.insert(copy)
        context.insert(ReviewSession(cardID: first.id, subjectName: subject.name, topicName: "Cells", qualityRating: 3))
        let day = try ReviewDailyLimitPolicy.day(in: context)
        #expect(day.library.cards.map(\.id) == [copy.id])
        #expect(day.backlog.isEmpty)
        #expect(day.canReview(copy) == false)
        #expect(day.limited([first, copy]).isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<StudyCard>()) == 2)
    }
}
