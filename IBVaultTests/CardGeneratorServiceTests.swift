import Testing
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
}
