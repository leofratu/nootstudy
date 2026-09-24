import Foundation
import SwiftData
import Testing
@testable import IBVault

@Suite("Biology curriculum and study reliability")
struct BiologyCurriculumTests {
    @Test func bundledCatalogMatchesRoadmap() throws {
        let topics = try BiologyCatalog.result.get()
        #expect(topics.count == 40)
        #expect(Set(topics.map(\.code)).count == 40)
        #expect(topics.filter { $0.theme == "A" }.count == 9)
        #expect(topics.filter { $0.theme == "B" }.count == 10)
        #expect(topics.filter { $0.theme == "C" }.count == 9)
        #expect(topics.filter { $0.theme == "D" }.count == 12)
        #expect(Set(topics.filter(\.hlOnly).map(\.code)) == ["A2.1", "A2.3", "A3.2", "B3.3", "C2.1", "D2.2"])
        #expect(BiologyCatalog.topics(at: .sl).count == 34)
        #expect(topics.allSatisfy { !$0.remaining.isEmpty })
    }

    @Test func realResourcesExistAtEveryTopicAndLesson() throws {
        for topic in try BiologyCatalog.result.get() {
            #expect(!topic.sections.isEmpty && !topic.questions.isEmpty)
            for section in topic.sections {
                #expect(section.body.count > 100)
                #expect(topic.questions.contains { $0.sectionKey == section.key })
            }
        }
    }

    @Test func focusedEcologyMappingsAreExplicit() throws {
        let niche = try #require(BiologyCatalog.topics.first { $0.code == "B4.2" })
        let energy = try #require(BiologyCatalog.topics.first { $0.code == "C4.2" })
        #expect(Set(niche.sections.flatMap { $0.syllabusPoints ?? [] }) == Set((1...13).map { "B4.2.\($0)" }))
        #expect(Set(energy.sections.flatMap { $0.syllabusPoints ?? [] }) == Set((1...22).map { "C4.2.\($0)" }))
        #expect(niche.sections(at: .sl).count == niche.sections(at: .hl).count)
        #expect(energy.questions(at: .sl).count == energy.questions(at: .hl).count)
    }

    @Test func mixedTopicsGateTheirHLSectionsAndQuestions() throws {
        for code in ["D1.3", "D2.3", "D3.3"] {
            let topic = try #require(BiologyCatalog.topics.first { $0.code == code })
            #expect(!topic.hlOnly)
            #expect(topic.sections(at: .hl).count > topic.sections(at: .sl).count)
            #expect(topic.questions(at: .sl).allSatisfy { $0.hlOnly != true })
            #expect(topic.sections(at: .sl).allSatisfy { $0.hlOnly != true })
        }
        let water = try #require(BiologyCatalog.topics.first { $0.code == "D2.3" })
        #expect(!water.questions(at: .sl).contains { $0.key == "d2" })
        #expect(water.questions(at: .hl).contains { $0.key == "d2" })
    }

    @Test func validationRejectsMissingAndDuplicatedTopics() throws {
        var topics = try BiologyCatalog.result.get()
        #expect(throws: BiologyCatalog.CatalogError.self) { try BiologyCatalog.validate(Array(topics.dropLast())) }
        topics[1] = topics[0]
        #expect(throws: BiologyCatalog.CatalogError.self) { try BiologyCatalog.validate(topics) }
    }

    @Test func missingBundleResourceIsAnErrorNotEmptySuccess() {
        #expect(throws: (any Error).self) { try BiologyCatalog.load(urls: [URL(fileURLWithPath: "/nonexistent/noot-biology.json")]) }
    }

    @Test func codeAndConceptSearchRespectLevel() throws {
        let topic = try #require(BiologyCatalog.topics.first { $0.code == "D2.3" })
        #expect(topic.contains(" d2.3 ", at: .sl))
        #expect(topic.contains("plasmolysis", at: .sl))
        #expect(!topic.contains("−400 kPa", at: .sl))
        #expect(!topic.contains("impossible-search-term", at: .hl))
    }

    @Test func normalizedLookupsCannotPoisonTheCache() {
        #expect(!SyllabusSeeder.curriculum(for: "  bIOLogy\n").isEmpty)
        #expect(SyllabusSeeder.curriculum(for: "Biology", level: " sl ").flatMap(\.topics).count == 34)
        #expect(SyllabusSeeder.curriculum(for: " biology ", level: " hl ").flatMap(\.topics).count == 40)
        #expect(IBCourseLevel(" hL ") == .hl)
        #expect(SyllabusSeeder.metadata(for: " biology ").firstAssessment == "2025")
    }

    @Test func failuresAloneNeverPromoteProficiency() {
        let card = StudyCard(topicName: "A1.1 Water", front: "Test", back: "Answer")
        card.totalReviewCount = 12
        card.successfulReviewCount = 0
        card.consecutiveCorrect = 0
        ProficiencyTracker.updateProficiency(for: card)
        #expect(card.proficiency == .novice)
        card.successfulReviewCount = 2
        ProficiencyTracker.updateProficiency(for: card)
        #expect(card.proficiency == .developing)
    }

    @MainActor private func container() throws -> ModelContainer {
        try ModelContainer(for: Subject.self, StudyCard.self, Grade.self, CurriculumNode.self,
                           ReviewSession.self, UserProfile.self, StudySession.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @MainActor @Test func importIsIdempotentAndPreservesReviewHistory() throws {
        let store = try container()
        let context = store.mainContext
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        context.insert(subject)
        let topic = try #require(BiologyCatalog.topics.first { $0.code == "A1.1" })
        #expect(try BiologyStudyService.addToReview(topic: topic, subject: subject, context: context) == topic.questions.count)
        let first = try #require(context.fetch(FetchDescriptor<StudyCard>()).first)
        let due = Date(timeIntervalSince1970: 2_000_000_000)
        first.nextReviewDate = due
        first.totalReviewCount = 9
        first.successfulReviewCount = 8
        try context.save()
        #expect(try BiologyStudyService.addToReview(topic: topic, subject: subject, context: context) == 0)
        let fresh = try ModelContext(store).fetch(FetchDescriptor<StudyCard>())
        #expect(fresh.count == topic.questions.count)
        let retained = try #require(fresh.first { $0.id == first.id })
        #expect(retained.totalReviewCount == 9 && retained.nextReviewDate == due)
        #expect(try BiologyStudyService.addToReview(topic: topic, subject: subject, context: context, flashcards: true) == topic.sections.count)
        #expect(try BiologyStudyService.addToReview(topic: topic, subject: subject, context: context, flashcards: true) == 0)
    }

    @MainActor @Test func importedMCQsAreUsableByTheExistingReviewRenderer() throws {
        let store = try container()
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        store.mainContext.insert(subject)
        let topic = try #require(BiologyCatalog.topics.first { $0.code == "B4.2" })
        try BiologyStudyService.addToReview(topic: topic, subject: subject, context: store.mainContext)
        let cards = try store.mainContext.fetch(FetchDescriptor<StudyCard>())
        for card in cards where card.cardStyle == .multipleChoice {
            #expect(CardGeneratorService.validatedChoices(back: card.back, choices: card.choices)?.count == 4)
            #expect(BiologyStudyService.explanation(for: card)?.isEmpty == false)
        }
        #expect(cards.allSatisfy { $0.totalReviewCount == 0 && $0.proficiency == .novice })
    }

    @MainActor @Test func levelChangesGateEveryReviewEntryWithoutDeletingCards() throws {
        let store = try container()
        let context = store.mainContext
        let subject = Subject(name: "Biology", level: "HL", accentColorHex: "10B981")
        context.insert(subject)
        let topic = try #require(BiologyCatalog.topics.first { $0.code == "D2.3" })
        try BiologyStudyService.addToReview(topic: topic, subject: subject, context: context)
        let cards = try context.fetch(FetchDescriptor<StudyCard>())
        let hl = try #require(cards.first { $0.syllabusReference == "D2.3#d2" })
        #expect(BiologyStudyService.isEligible(hl))
        subject.level = "SL"
        try context.save()
        let day = try ReviewDailyLimitPolicy.day(in: context, now: Date().addingTimeInterval(10))
        #expect(!day.backlog.contains { $0.id == hl.id })
        #expect(day.limited([hl]).isEmpty)
        #expect(!day.canReview(hl))
        #expect(!ReviewQueueManager().eligibleCards(context: context).contains { $0.id == hl.id })
        #expect(subject.dueCardsCount == topic.questions(at: .sl).count)
        #expect(try context.fetchCount(FetchDescriptor<StudyCard>()) == cards.count)
        subject.level = "HL"
        #expect(BiologyStudyService.isEligible(hl))
    }

    @MainActor @Test func legacyCardsRemainEligibleAndUnmodified() throws {
        let store = try container()
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        store.mainContext.insert(subject)
        let card = StudyCard(topicName: "Legacy topic", front: "My question", back: "My answer", subject: subject)
        card.totalReviewCount = 11
        store.mainContext.insert(card)
        #expect(SyllabusSeeder.synchronizeCurriculum(context: store.mainContext))
        #expect(BiologyStudyService.isEligible(card))
        #expect(card.totalReviewCount == 11 && card.topicName == "Legacy topic")
        #expect(try store.mainContext.fetchCount(FetchDescriptor<StudyCard>()) == 1)
    }

    @MainActor @Test func recordedMasterySurvivesLevelSwitchAndCatalogRename() throws {
        let store = try container()
        let context = store.mainContext
        let subject = Subject(name: "Biology", level: "HL", accentColorHex: "10B981")
        context.insert(subject)
        #expect(SyllabusSeeder.synchronizeCurriculum(context: context))
        let node = try #require(context.fetch(FetchDescriptor<CurriculumNode>()).first { $0.topicName.hasPrefix("A2.3") })
        node.recordedProficiency = .proficient
        node.masteryNote = "Teacher checked"
        node.masteryUpdatedAt = Date()
        let id = node.id
        let legacy = CurriculumNode(subjectName: "Biology", level: "HL", unitName: "Retired unit",
                                    topicName: "Retired topic", subtopicName: "My prior work", catalogVersion: "old",
                                    sourceTitle: "Earlier catalog", sourceURLString: BiologyCatalog.sourceURL)
        legacy.recordedProficiency = .developing
        context.insert(legacy)
        subject.level = "SL"
        #expect(SyllabusSeeder.synchronizeCurriculum(context: context))
        subject.level = "HL"
        #expect(SyllabusSeeder.synchronizeCurriculum(context: context))
        let fresh = try ModelContext(store).fetch(FetchDescriptor<CurriculumNode>())
        #expect(fresh.first { $0.id == id }?.recordedProficiency == .proficient)
        #expect(fresh.first { $0.id == id }?.masteryNote == "Teacher checked")
        #expect(fresh.contains { $0.id == legacy.id })
    }

    @MainActor @Test func duplicateNodesKeepTheLatestRecordedEvidence() throws {
        let store = try container()
        let context = store.mainContext
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        context.insert(subject)
        for (offset, level) in [(0, ProficiencyLevel.mastered), (1, ProficiencyLevel.developing)] {
            let node = CurriculumNode(subjectName: "Biology", level: "SL", unitName: "Legacy", topicName: "Legacy",
                                      subtopicName: "Example", catalogVersion: "old", sourceTitle: "Test", sourceURLString: BiologyCatalog.sourceURL)
            node.recordedProficiency = level
            node.masteryUpdatedAt = Date(timeIntervalSince1970: 1_700_000_000 + Double(offset))
            context.insert(node)
        }
        #expect(SyllabusSeeder.synchronizeCurriculum(context: context))
        let legacy = try context.fetch(FetchDescriptor<CurriculumNode>()).filter { $0.topicName == "Legacy" }
        #expect(legacy.count == 1)
        #expect(legacy.first?.recordedProficiency == .developing)
    }

    @Test func mistakeBookmarksPersistWithoutInventingMastery() throws {
        let suite = "biology-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let subject = UUID()
        BiologyPracticeBookmarks.save(["B4.2#m1", "invented#bad"], subjectID: subject, defaults: defaults)
        #expect(BiologyPracticeBookmarks.load(subjectID: subject, defaults: defaults) == ["B4.2#m1"])
        BiologyPracticeBookmarks.save([], subjectID: subject, defaults: defaults)
        #expect(BiologyPracticeBookmarks.load(subjectID: subject, defaults: defaults).isEmpty)
        #expect(BiologyPracticeBookmarks.load(subjectID: UUID(), defaults: defaults).isEmpty)
    }
}
