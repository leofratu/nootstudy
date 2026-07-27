import Testing
import SwiftData
@testable import IBVault

@Suite("Adaptive Card Generator Tests")
struct CardGeneratorServiceTests {
    @Test("A new topic starts with a balanced baseline")
    func newTopicProfile() {
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        let profile = CardGeneratorService.adaptiveProfile(
            for: subject,
            topicName: "Cells and Cell Structure",
            subtopic: "Prokaryotic cell structure"
        )

        #expect(profile.difficulty == .standard)
        #expect(profile.skillMix == [.recall, .explain, .apply])
    }

    @Test("Low recall generates foundation cards")
    func strugglingTopicProfile() {
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        let card = StudyCard(topicName: "Genetics", subtopic: "Genes, alleles and the genome", front: "Q", back: "A", subject: subject)
        card.totalReviewCount = 10
        card.successfulReviewCount = 3
        card.proficiency = .novice
        subject.cards.append(card)

        let profile = CardGeneratorService.adaptiveProfile(for: subject, topicName: "Genetics", subtopic: "Genes, alleles and the genome")
        #expect(profile.difficulty == .foundation)
    }

    @Test("Strong recall generates transfer-heavy stretch cards")
    func strongTopicProfile() {
        let subject = Subject(name: "Economics", level: "HL", accentColorHex: "F59E0B")
        let card = StudyCard(topicName: "Demand", subtopic: "The law of demand", front: "Q", back: "A", subject: subject)
        card.totalReviewCount = 10
        card.successfulReviewCount = 9
        card.proficiency = .mastered
        subject.cards.append(card)

        let profile = CardGeneratorService.adaptiveProfile(for: subject, topicName: "Demand", subtopic: "The law of demand")
        #expect(profile.difficulty == .stretch)
        #expect(profile.skillMix.contains(.evaluate))
    }

    @Test("Generated JSON preserves metadata and normalizes math delimiters")
    func parsesRichCardPayload() throws {
        let subject = Subject(name: "Mathematics AA", level: "SL", accentColorHex: "3B82F6")
        let response = #"[{"front":"Differentiate \\(x^2\\)","back":"\\[2x\\]","hint":"Use the power rule","difficulty":"Exam","skill":"Apply"}]"#

        let cards = try CardGeneratorService.parseFlashcards(
            from: response,
            subject: subject,
            topicName: "Differentiation",
            subtopic: "Power rule"
        )

        #expect(cards.count == 1)
        #expect(cards[0].front == "Differentiate $x^2$")
        #expect(cards[0].back == "$$2x$$")
        #expect(cards[0].difficulty == .exam)
        #expect(cards[0].cognitiveSkill == .apply)
        #expect(cards[0].sourceURL != nil)
        #expect(cards[0].generationPromptVersion == CardGeneratorService.promptVersion)
    }

    @MainActor
    @Test("Inserting a generated card preserves one inverse subject relationship")
    func generatedCardRelationshipIsNotDuplicated() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Subject.self,
            StudyCard.self,
            StudySession.self,
            UserProfile.self,
            configurations: configuration
        )
        let context = container.mainContext
        let subject = Subject(name: "Biology", level: "HL", accentColorHex: "10B981")
        context.insert(subject)

        let card = StudyCard(
            topicName: "Genetics",
            subtopic: "Gene expression",
            front: "What is transcription?",
            back: "The synthesis of RNA from a DNA template.",
            subject: subject
        )
        context.insert(card)
        try context.save()

        #expect(subject.cards.count == 1)
        #expect(subject.cards.first?.id == card.id)
    }
}

@Suite("Local Codex Event Tests")
struct LocalCodexEventTests {
    @Test("Completed agent messages become learner-visible output")
    func parsesAgentMessage() {
        let line = #"{"type":"item.completed","item":{"type":"agent_message","text":"  Use $F = ma$.  "}}"#
        let update = AIProviderService.parseCodexEvent(line)

        #expect(update?.message == "Use $F = ma$.")
        #expect(update?.status == nil)
        #expect(update?.error == nil)
    }

    @Test("Web search events expose research progress")
    func parsesWebSearchStatus() {
        let line = #"{"type":"item.started","item":{"type":"web_search"}}"#
        let update = AIProviderService.parseCodexEvent(line)

        #expect(update?.status == "Researching supporting sources")
        #expect(update?.message == nil)
    }

    @Test("Failed turns preserve the CLI error detail")
    func parsesFailure() {
        let line = #"{"type":"turn.failed","error":{"message":"Saved login was rejected"}}"#
        let update = AIProviderService.parseCodexEvent(line)

        #expect(update?.error == "Saved login was rejected")
    }
}

@Suite("AI Configuration Tests")
struct AIConfigurationTests {
    @Test("Local Codex exposes only supported GPT-5.6 effort levels")
    func codexEffortLevels() {
        let efforts = AIConfiguration.supportedReasoningEfforts(for: .codexCLI)

        #expect(efforts == [.low, .medium, .high, .xhigh, .max, .ultra])
        #expect(AIConfiguration.normalizedReasoningEffort(.none, for: .codexCLI) == .low)
        #expect(AIConfiguration.normalizedReasoningEffort(.ultra, for: .junali) == .max)
        #expect(AIConfiguration.supportedReasoningEfforts(for: .gemini).isEmpty)
    }

    @Test("Known model slugs receive human-readable names")
    func modelDisplayNames() {
        #expect(AIConfiguration.modelDisplayName("gpt-5.6-sol", for: .codexCLI) == "GPT-5.6 Sol")
        #expect(AIConfiguration.modelDisplayName("custom-model", for: .junali) == "custom-model")
    }
}
