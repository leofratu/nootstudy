import Testing
import Foundation
import SwiftData
@testable import IBVault

@Suite("CardGenerationOptions Tests")
struct CardGenerationOptionsTests {

    @Test("Cloze valid front preserves cloze style")
    func clozeValidPreservesStyle() throws {
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        let response = #"[{"front":"The {{c1::mitochondrion}} is the powerhouse.","back":"mitochondrion","cardStyle":"cloze"}]"#
        let cards = try CardGeneratorService.parseFlashcards(
            from: response,
            subject: subject,
            topicName: "Cells",
            subtopic: ""
        )
        #expect(cards.count == 1)
        #expect(cards[0].cardStyle == .cloze)
        #expect(cards[0].front.contains("{{c1::mitochondrion}}"))
        #expect(cards[0].choices.isEmpty)
    }

    @Test("Cloze invalid front repairs to basic")
    func clozeInvalidRepairsToBasic() throws {
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        // Missing cloze markup -> should repair
        let response = #"[{"front":"What is the powerhouse of the cell?","back":"mitochondrion","cardStyle":"cloze"}]"#
        let cards = try CardGeneratorService.parseFlashcards(
            from: response,
            subject: subject,
            topicName: "Cells",
            subtopic: ""
        )
        #expect(cards.count == 1)
        #expect(cards[0].cardStyle == .basic)
        #expect(cards[0].choices.isEmpty)
    }

    @Test("Cloze deletion mismatch repairs to basic")
    func clozeMismatchRepairsToBasic() throws {
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        let response = #"[{"front":"The {{c1::chloroplast}} is the powerhouse.","back":"mitochondrion","cardStyle":"cloze"}]"#
        let cards = try CardGeneratorService.parseFlashcards(
            from: response,
            subject: subject,
            topicName: "Cells",
            subtopic: ""
        )
        #expect(cards.count == 1)
        #expect(cards[0].cardStyle == .basic)
    }

    @Test("Multiple choice valid stores choices")
    func mcqValidStoresChoices() throws {
        let subject = Subject(name: "Economics", level: "HL", accentColorHex: "F59E0B")
        let response = #"[{"front":"Which cost is forgone?","back":"Opportunity cost","cardStyle":"multiple_choice","choices":["Opportunity cost","Sunk cost","Fixed cost","Variable cost"]}]"#
        let cards = try CardGeneratorService.parseFlashcards(
            from: response,
            subject: subject,
            topicName: "Choice",
            subtopic: ""
        )
        #expect(cards.count == 1)
        #expect(cards[0].cardStyle == .multipleChoice)
        #expect(cards[0].choices.count == 4)
        #expect(cards[0].choices.contains("Opportunity cost"))
    }

    @Test("Multiple choice valid is case-insensitive trimmed match")
    func mcqCaseInsensitiveMatch() throws {
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        let response = #"[{"front":"What is ATP?","back":"adenosine triphosphate","cardStyle":"multiple_choice","choices":["Adenosine Triphosphate ","ADP","AMP","GTP"]}]"#
        let cards = try CardGeneratorService.parseFlashcards(
            from: response,
            subject: subject,
            topicName: "Cells",
            subtopic: ""
        )
        #expect(cards.count == 1)
        #expect(cards[0].cardStyle == .multipleChoice)
    }

    @Test("Multiple choice duplicate choices repair to basic")
    func mcqDuplicateRepairsToBasic() throws {
        let subject = Subject(name: "Economics", level: "HL", accentColorHex: "F59E0B")
        let response = #"[{"front":"Which cost is forgone?","back":"Opportunity cost","cardStyle":"multiple_choice","choices":["Opportunity cost","Opportunity Cost","Fixed cost","Variable cost"]}]"#
        let cards = try CardGeneratorService.parseFlashcards(
            from: response,
            subject: subject,
            topicName: "Choice",
            subtopic: ""
        )
        #expect(cards.count == 1)
        #expect(cards[0].cardStyle == .basic)
        #expect(cards[0].choices.isEmpty)
    }

    @Test("Multiple choice missing back in choices repairs to basic")
    func mcqMissingBackRepairsToBasic() throws {
        let subject = Subject(name: "Economics", level: "HL", accentColorHex: "F59E0B")
        let response = #"[{"front":"Which cost is forgone?","back":"Opportunity cost","cardStyle":"multiple_choice","choices":["Sunk cost","Fixed cost","Variable cost"]}]"#
        let cards = try CardGeneratorService.parseFlashcards(
            from: response,
            subject: subject,
            topicName: "Choice",
            subtopic: ""
        )
        #expect(cards.count == 1)
        #expect(cards[0].cardStyle == .basic)
        #expect(cards[0].choices.isEmpty)
    }

    @Test("Multiple choice too few choices repairs to basic")
    func mcqTooFewRepairsToBasic() throws {
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        let response = #"[{"front":"What is ATP?","back":"ATP","cardStyle":"multiple_choice","choices":["ATP","ADP"]}]"#
        let cards = try CardGeneratorService.parseFlashcards(
            from: response,
            subject: subject,
            topicName: "Cells",
            subtopic: ""
        )
        #expect(cards.count == 1)
        #expect(cards[0].cardStyle == .basic)
    }

    @Test("Choices uniqueness is case-insensitive trimmed")
    func choicesUniquenessCaseInsensitive() {
        let valid = CardGeneratorService.validatedChoices(back: "Answer", choices: ["Answer", "answer ", "Other", "More"])
        #expect(valid == nil)
        let valid2 = CardGeneratorService.validatedChoices(back: "Answer", choices: ["Answer", "Other", "More", "Extra"])
        #expect(valid2 != nil)
        #expect(valid2?.count == 4)
    }

    @Test("Dedup by normalized front collapses duplicates")
    func dedupNormalizedFront() throws {
        let subject = Subject(name: "Economics", level: "HL", accentColorHex: "F59E0B")
        let response = #"[{"front":"What is CAC?","back":"CAC is acquisition cost per customer."},{"front":"What is   CAC? ","back":"Different answer but same normalized front."}]"#
        let cards = try CardGeneratorService.parseFlashcards(
            from: response,
            subject: subject,
            topicName: "Metrics",
            subtopic: ""
        )
        #expect(cards.count == 1)
    }

    @Test("Options override count and difficulty")
    func optionsOverride() throws {
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        let response = #"[{"front":"Q1","back":"A1"},{"front":"Q2","back":"A2"},{"front":"Q3","back":"A3"}]"#
        let options = CardGenerationOptions(count: 2, difficulty: .stretch, style: .basic, tone: .concise, cognitiveSkills: [.apply], useInternalTools: false)
        let profile = CardGeneratorService.adaptiveProfile(for: subject, topicName: "Cells", subtopic: "")
        let cards = try CardGeneratorService.parseFlashcards(
            from: response,
            subject: subject,
            topicName: "Cells",
            subtopic: "",
            profile: profile,
            options: options
        )
        // parseFlashcards returns all parsed cards; count limiting is done at generateCards level, but difficulty should be clamped
        #expect(cards.count == 3)
        #expect(cards.allSatisfy { $0.difficulty == .stretch })
    }

    @Test("useInternalTools clamps difficulty and sets syllabusReference")
    func useInternalToolsClampsAndReferences() throws {
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        let response = #"[{"front":"Q1","back":"A1","difficulty":"Foundation"},{"front":"Q2","back":"A2","difficulty":"Stretch"}]"#
        let options = CardGenerationOptions(difficulty: .exam, style: .basic, useInternalTools: true)
        let profile = CardGeneratorService.AdaptiveProfile(difficulty: .standard, skillMix: [.recall], reason: "test")
        let cards = try CardGeneratorService.parseFlashcards(
            from: response,
            subject: subject,
            topicName: "Cells",
            subtopic: "Cell theory",
            profile: profile,
            options: options
        )
        #expect(cards.count == 2)
        #expect(cards.allSatisfy { $0.difficulty == .exam })
        #expect(cards.allSatisfy { $0.syllabusReference != nil && !$0.syllabusReference!.isEmpty })
    }

    @MainActor
    @Test("Local starter cards emit cloze and mcq when requested")
    func localStarterClozeAndMCQ() {
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        let profile = CardGeneratorService.adaptiveProfile(for: subject, topicName: "Cells", subtopic: "")
        let clozeOptions = CardGenerationOptions(style: .cloze, useInternalTools: false)
        let clozeCards = CardGeneratorService.localStarterCards(
            subject: subject,
            topicName: "Cells",
            subtopic: "",
            count: 2,
            profile: profile,
            options: clozeOptions
        )
        #expect(clozeCards.allSatisfy { $0.cardStyle == .cloze })
        #expect(clozeCards.allSatisfy { $0.front.contains("{{c1::") && $0.front.contains($0.back) })

        let mcqOptions = CardGenerationOptions(style: .multipleChoice, useInternalTools: false)
        let mcqCards = CardGeneratorService.localStarterCards(
            subject: subject,
            topicName: "Cells",
            subtopic: "",
            count: 2,
            profile: profile,
            options: mcqOptions
        )
        #expect(mcqCards.allSatisfy { $0.cardStyle == .multipleChoice })
        #expect(mcqCards.allSatisfy { $0.choices.count >= 3 && $0.choices.count <= 4 })
        #expect(mcqCards.allSatisfy { card in card.choices.contains { $0.lowercased() == card.back.lowercased() } })
    }

    @Test("isValidCloze checks deletion equals back")
    func isValidClozeCheck() {
        #expect(CardGeneratorService.isValidCloze(front: "The {{c1::answer}} is correct.", back: "answer"))
        #expect(!CardGeneratorService.isValidCloze(front: "The {{c1::wrong}} is correct.", back: "answer"))
        #expect(!CardGeneratorService.isValidCloze(front: "No cloze here", back: "answer"))
        #expect(!CardGeneratorService.isValidCloze(front: "The {{c1::answer}} and {{c1::other}}", back: "answer"))
    }

    @MainActor
    @Test("Backup round-trip preserves cardStyle and choices")
    func backupRoundTripPreservesStyleAndChoices() throws {
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        let card = StudyCard(topicName: "Cells", subtopic: "Theory", front: "Which organelle?", back: "Mitochondrion", subject: subject, cardStyle: .multipleChoice, choices: ["Mitochondrion", "Chloroplast", "Nucleus", "Ribosome"])
        card.difficulty = .exam
        // Simulate backup encode/decode
        let backup = CardBackup(from: card)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedBackup = try decoder.decode(CardBackup.self, from: data)
        let restored = decodedBackup.toModel()
        #expect(restored.cardStyle == .multipleChoice)
        #expect(restored.choices == ["Mitochondrion", "Chloroplast", "Nucleus", "Ribosome"])
        #expect(restored.front == "Which organelle?")
        #expect(restored.back == "Mitochondrion")
    }

    @Test("Backup decodes old payload without new fields")
    func backupBackwardCompatibility() throws {
        let json = """
        {"id":"\(UUID().uuidString)","topicName":"Cells","subtopic":"","front":"Q","back":"A","easeFactor":2.5,"interval":0,"repetitions":0,"nextReviewDate":"2026-01-01T00:00:00Z","proficiencyRaw":"Novice","consecutiveCorrect":0,"isCustom":false,"createdDate":"2026-01-01T00:00:00Z","totalReviewCount":0,"successfulReviewCount":0}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(CardBackup.self, from: Data(json.utf8))
        #expect(backup.cardStyleRaw == nil)
        #expect(backup.choicesJSON == nil)
        let model = backup.toModel()
        #expect(model.cardStyle == .basic)
        #expect(model.choices.isEmpty)
    }
}
