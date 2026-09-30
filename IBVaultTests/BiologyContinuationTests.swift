import Foundation
import SwiftData
import Testing
@testable import IBVault

@Suite("Bioenergetics coverage and queue continuation", .serialized)
@MainActor
struct BiologyContinuationTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: Subject.self, StudyCard.self, Grade.self,
                           ReviewSession.self, UserProfile.self, StudySession.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func bioenergeticsUnderstandingRangesAndLevelsAreExplicit() throws {
        for (code, core, total) in [("C1.2", 6, 17), ("C1.3", 8, 19)] {
            let topic = try #require(BiologyCatalog.topics.first { $0.code == code })
            #expect(Set(topic.sections.flatMap { $0.syllabusPoints ?? [] }) == Set((1...total).map { "\(code).\($0)" }))
            #expect(Set(topic.sections(at: .sl).flatMap { $0.syllabusPoints ?? [] }) == Set((1...core).map { "\(code).\($0)" }))
            for section in topic.sections {
                for point in section.syllabusPoints ?? [] {
                    let number = try #require(Int(point.split(separator: ".").last ?? ""))
                    #expect((section.hlOnly == true) == (number > core))
                }
                let questions = topic.questions.filter { $0.sectionKey == section.key }
                #expect(questions.count >= 2)
                #expect(questions.allSatisfy { ($0.hlOnly == true) == (section.hlOnly == true) })
            }
        }
    }

    @Test func bioenergeticsSearchAndQuestionsRespectLevel() throws {
        let respiration = try #require(BiologyCatalog.topics.first { $0.code == "C1.2" })
        let photosynthesis = try #require(BiologyCatalog.topics.first { $0.code == "C1.3" })
        #expect(!respiration.contains("Krebs", at: .sl))
        #expect(respiration.contains("Krebs", at: .hl))
        #expect(!photosynthesis.contains("Rubisco", at: .sl))
        #expect(photosynthesis.contains("Rubisco", at: .hl))
        #expect(!respiration.questions(at: .sl).contains { $0.key == "w1" })
        #expect(respiration.questions(at: .hl).contains { $0.key == "w1" })
        #expect(respiration.sections(at: .sl).contains { $0.key == "respirometry" })
        #expect(photosynthesis.sections(at: .sl).contains { $0.key == "chromatography" })
    }

    @Test func oldYeastReferenceIsGatedWithoutLosingHistory() throws {
        let store = try container()
        let context = store.mainContext
        let subject = Subject(name: "Biology", level: "HL", accentColorHex: "10B981")
        context.insert(subject)
        let topic = try #require(BiologyCatalog.topics.first { $0.code == "C1.2" })
        #expect(try BiologyStudyService.addToReview(topic: topic, subject: subject,
                                                   context: context, questionKeys: ["w1"]) == 1)
        let card = try #require(context.fetch(FetchDescriptor<StudyCard>()).first)
        let id = card.id
        let due = Date(timeIntervalSince1970: 2_000_000_000)
        card.totalReviewCount = 9
        card.successfulReviewCount = 8
        card.nextReviewDate = due
        card.fsrsStability = 12.5
        try context.save()
        #expect(card.syllabusReference == "C1.2#w1")
        subject.level = "SL"
        try context.save()
        #expect(!BiologyStudyService.isEligible(card))
        #expect(try BiologyStudyService.addToReview(topic: topic, subject: subject,
                                                   context: context, questionKeys: ["w1"]) == 0)
        #expect(try ReviewDailyLimitPolicy.day(in: context).library.cards.isEmpty)
        subject.level = "HL"
        try context.save()
        #expect(try BiologyStudyService.addToReview(topic: topic, subject: subject,
                                                   context: context, questionKeys: ["w1"]) == 0)
        let restored = try #require(ReviewDailyLimitPolicy.day(in: context).library.cards.first)
        #expect(restored.id == id && restored.totalReviewCount == 9)
        #expect(restored.successfulReviewCount == 8 && restored.nextReviewDate == due)
        #expect(restored.fsrsStability == 12.5)
    }

    @Test func expandedMultipleChoiceImportsHaveFourUsableOptions() throws {
        let store = try container()
        let context = store.mainContext
        let subject = Subject(name: "Biology", level: "HL", accentColorHex: "10B981")
        context.insert(subject)
        for code in ["C1.2", "C1.3"] {
            let topic = try #require(BiologyCatalog.topics.first { $0.code == code })
            #expect(try BiologyStudyService.addToReview(topic: topic, subject: subject,
                                                       context: context) == topic.questions.count)
        }
        let cards = try context.fetch(FetchDescriptor<StudyCard>())
        for card in cards where card.cardStyle == .multipleChoice {
            #expect(CardGeneratorService.validatedChoices(back: card.back, choices: card.choices)?.count == 4)
            #expect(BiologyStudyService.explanation(for: card)?.isEmpty == false)
        }
        #expect(cards.allSatisfy { $0.totalReviewCount == 0 && $0.proficiency == .novice })
    }

    @Test func shortAnswersKeepTheSameFuzzyBoundary() {
        let frontA = "Explain electron transfer through the membrane."
        let frontB = "Describe membrane electron transfer."
        let eleven = "one two three four five six seven eight nine ten eleven"
        let shortA = CardDuplicatePolicy.Signature(front: frontA, back: eleven, style: .basic)
        let shortB = CardDuplicatePolicy.Signature(front: frontB, back: eleven, style: .basic)
        #expect(!shortA.matches(shortB))
        #expect(shortA.matches(CardDuplicatePolicy.Signature(front: frontA, back: "Short", style: .basic)))
        let twelve = eleven + " twelve"
        #expect(CardDuplicatePolicy.Signature(front: frontA, back: twelve, style: .basic)
            .matches(CardDuplicatePolicy.Signature(front: frontB, back: twelve, style: .basic)))
    }

    @Test func normalizedScopeIsRecomputedAfterAnEdit() {
        let subject = Subject(name: "Biology", level: "HL", accentColorHex: "10B981")
        let a = StudyCard(topicName: "Énergie", subtopic: "Cell", front: "ATP?", back: "Carrier", subject: subject)
        let b = StudyCard(topicName: "Water", subtopic: "Cell", front: "ATP?", back: "Carrier", subject: subject)
        a.totalReviewCount = 8
        #expect(CardDuplicatePolicy.library([b, a]).cards.count == 2)
        b.topicName = " energie "
        #expect(CardDuplicatePolicy.library([b, a]).canonicalIDs[b.id] == a.id)
        b.subtopic = "Different context"
        #expect(CardDuplicatePolicy.library([b, a]).cards.count == 2)
        b.subject = nil
        #expect(CardDuplicatePolicy.library([b, a]).cards.count == 2)
    }

    @Test func exactAndFuzzyCandidatesStillUseHistoryPreference() {
        let subject = Subject(name: "Biology", level: "HL", accentColorHex: "10B981")
        let answer = "Electrons pass through a sequence of membrane carriers and the released energy supports proton pumping across the inner membrane."
        let earlier = StudyCard(topicName: "Respiration", front: "Explain electron transfer through membrane carriers.", back: answer, subject: subject)
        let exact = StudyCard(topicName: "Respiration", front: "Describe membrane electron transfer.", back: "Electron transfer", subject: subject)
        let repeated = StudyCard(topicName: "Respiration", front: exact.front, back: answer, subject: subject)
        earlier.totalReviewCount = 10
        exact.totalReviewCount = 5
        #expect(CardDuplicatePolicy.library([repeated, exact, earlier]).canonicalIDs[repeated.id] == earlier.id)
        exact.totalReviewCount = 11
        #expect(CardDuplicatePolicy.library([repeated, exact, earlier]).canonicalIDs[repeated.id] == exact.id)
        #expect(earlier.totalReviewCount == 10 && exact.totalReviewCount == 11)
    }

    @Test func queueColdAndWarmReadsRetainNonQueueMetadata() throws {
        let store = try container()
        let writer = store.mainContext
        let subject = Subject(name: "Biology", level: "HL", accentColorHex: "10B981")
        writer.insert(subject)
        let card = StudyCard(topicName: "Custom", front: "A custom question?", back: "Saved answer", subject: subject)
        card.hint = "Keep this learner hint"
        card.sourceTitle = "My source"
        card.fsrsStability = 14.25
        card.totalReviewCount = 7
        writer.insert(card)
        try writer.save()
        let reader = ModelContext(store)
        let cold = try ReviewDailyLimitPolicy.day(in: reader).library.cards
        let warm = try ReviewDailyLimitPolicy.day(in: reader).library.cards
        #expect(Set(cold.map(\.id)) == Set(warm.map(\.id)))
        let restored = try #require(warm.first)
        #expect(restored.id == card.id && restored.hint == "Keep this learner hint")
        #expect(restored.sourceTitle == "My source" && restored.fsrsStability == 14.25)
        #expect(restored.totalReviewCount == 7)
        restored.hint = "Edited hint"
        try reader.save()
        let reopened = try #require(ModelContext(store).fetch(FetchDescriptor<StudyCard>()).first)
        #expect(reopened.hint == "Edited hint" && reopened.fsrsStability == 14.25)
    }

    @Test func queueIncludesPendingInsertEditAndDelete() throws {
        let store = try container()
        let context = store.mainContext
        context.autosaveEnabled = false
        let subject = Subject(name: "Other", level: "SL", accentColorHex: "123456")
        context.insert(subject)
        let now = Date()
        let a = StudyCard(topicName: "A", front: "First question", back: "Answer one", subject: subject)
        a.nextReviewDate = now.addingTimeInterval(-60)
        context.insert(a)
        try context.save()
        #expect(try ReviewDailyLimitPolicy.day(in: context, now: now).backlog.map(\.id) == [a.id])
        a.nextReviewDate = now.addingTimeInterval(3600)
        let b = StudyCard(topicName: "B", front: "Second question", back: "Answer two", subject: subject)
        b.nextReviewDate = now.addingTimeInterval(-60)
        context.insert(b)
        #expect(try ReviewDailyLimitPolicy.day(in: context, now: now).backlog.map(\.id) == [b.id])
        context.delete(a)
        #expect(Set(try ReviewDailyLimitPolicy.day(in: context).library.cards.map(\.id)) == [b.id])
        try context.save()
        #expect(Set(try ReviewDailyLimitPolicy.day(in: context).library.cards.map(\.id)) == [b.id])
    }

    @Test func registeredReadMatchesOrdinaryFetchAfterAnotherContextSaves() throws {
        let store = try container()
        let writer = store.mainContext
        let card = StudyCard(topicName: "Saved", front: "Original prompt", back: "Original answer")
        writer.insert(card)
        try writer.save()
        let reader = ModelContext(store)
        _ = try ReviewDailyLimitPolicy.day(in: reader).library.cards
        card.front = "Changed prompt"
        try writer.save()
        let editedActual = try ReviewDailyLimitPolicy.day(in: reader).library.cards.map(\.front)
        let editedNormal = try reader.fetch(FetchDescriptor<StudyCard>()).map(\.front)
        #expect(editedActual == editedNormal)
        let added = StudyCard(topicName: "New", front: "New prompt", back: "New answer")
        writer.insert(added)
        try writer.save()
        let actual = Dictionary(try ReviewDailyLimitPolicy.day(in: reader).library.cards.map { ($0.id, $0.front) }, uniquingKeysWith: { first, _ in first })
        let normal = Dictionary(try reader.fetch(FetchDescriptor<StudyCard>()).map { ($0.id, $0.front) }, uniquingKeysWith: { first, _ in first })
        #expect(actual == normal)
        #expect(actual[added.id] == "New prompt")
        writer.delete(added)
        try writer.save()
        #expect(!(try ReviewDailyLimitPolicy.day(in: reader).library.cards).contains { $0.id == added.id })
    }
}
