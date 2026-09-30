import Foundation
import SwiftData
import Testing
@testable import IBVault

@Suite("Biology stable mastery mappings", .serialized)
@MainActor
struct BiologyMasteryMappingTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: Subject.self, StudyCard.self, Grade.self, CurriculumNode.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func recordedHLMasteryIsVisibleUnderBothDisplayNames() throws {
        let subject = Subject(name: "Biology", level: "HL", accentColorHex: "10B981")
        let topic = try #require(BiologyCatalog.topics.first { $0.code == "C1.2" })
        let section = try #require(topic.sections.first { $0.key == "glycolysis" })
        let node = CurriculumNode(subjectName: "Biology", level: "HL", unitName: "C",
                                  topicName: topic.name, subtopicName: section.curriculumTitle,
                                  catalogVersion: "test", sourceTitle: "Test", sourceURLString: "")
        node.recordedProficiency = .mastered
        for title in [section.title, section.curriculumTitle] {
            #expect(CurriculumProgressService.topicMastery(subject: subject, topicName: topic.name,
                                                           subtopics: [title], nodes: [node]) == 1)
        }
        let old = CurriculumNode(subjectName: "Biology", level: "HL", unitName: "C",
                                 topicName: topic.name, subtopicName: section.title,
                                 catalogVersion: "old", sourceTitle: "Test", sourceURLString: "")
        old.recordedProficiency = .developing
        old.masteryUpdatedAt = Date(timeIntervalSince1970: 10)
        node.masteryUpdatedAt = Date(timeIntervalSince1970: 20)
        #expect(CurriculumProgressService.topicMastery(subject: subject, topicName: topic.name,
                                                       subtopics: [section.title], nodes: [old, node]) == 1)
        node.recordedProficiency = nil
        #expect(CurriculumProgressService.topicMastery(subject: subject, topicName: topic.name,
                                                       subtopics: [section.curriculumTitle], nodes: [node, old]) == 0.33)
    }

    @Test func importedHistoryFollowsAQuestionMovedToItsCorrectSection() throws {
        let store = try container()
        let context = store.mainContext
        let subject = Subject(name: "Biology", level: "HL", accentColorHex: "10B981")
        context.insert(subject)
        let topic = try #require(BiologyCatalog.topics.first { $0.code == "C1.2" })
        let oldSection = try #require(topic.sections.first { $0.key == "pathways" })
        let correctedSection = try #require(topic.sections.first { $0.key == "fermentation" })
        let card = StudyCard(topicName: topic.name, subtopic: oldSection.title,
                             front: "Earlier imported question", back: "Earlier answer", subject: subject,
                             generationSource: BiologyCatalog.sourceID, syllabusReference: "C1.2#w1")
        card.proficiency = .mastered
        card.totalReviewCount = 12
        card.successfulReviewCount = 12
        context.insert(card)
        try context.save()
        #expect(BiologyStudyService.sectionKey(for: card, in: topic) == "fermentation")
        #expect(CurriculumProgressService.topicMastery(subject: subject, topicName: topic.name,
                                                       subtopics: [correctedSection.curriculumTitle], nodes: []) == 1)
        #expect(CurriculumProgressService.topicMastery(subject: subject, topicName: topic.name,
                                                       subtopics: [oldSection.title], nodes: []) == 0)
        subject.level = "SL"
        #expect(CurriculumProgressService.topicMastery(subject: subject, topicName: topic.name,
                                                       subtopics: [oldSection.title], nodes: []) == 0)
        #expect(card.totalReviewCount == 12 && card.subtopic == oldSection.title)
    }

    @Test func newlyImportedHLResourcesUseTheCanonicalSubtopicName() throws {
        let store = try container()
        let context = store.mainContext
        let subject = Subject(name: "Biology", level: "HL", accentColorHex: "10B981")
        context.insert(subject)
        let topic = try #require(BiologyCatalog.topics.first { $0.code == "C1.3" })
        try BiologyStudyService.addToReview(topic: topic, subject: subject, context: context,
                                           questionKeys: ["m-rubisco-rubp"])
        let card = try #require(context.fetch(FetchDescriptor<StudyCard>()).first)
        let section = try #require(topic.sections.first { $0.key == "fixation" })
        #expect(card.subtopic == section.curriculumTitle)
        #expect(card.subtopic.hasPrefix("HL: "))
        #expect(card.totalReviewCount == 0 && card.proficiency == .novice)
    }
}
