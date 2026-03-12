import Foundation
import SwiftData

struct CardGeneratorService {

    /// Generate flashcards for a specific topic using ARIA/Gemini
    static func generateCards(
        subject: Subject,
        topicName: String,
        subtopic: String = "",
        count: Int = 10,
        context: ModelContext
    ) async throws -> [StudyCard] {
        guard let apiKey = KeychainService.loadAPIKey(), !apiKey.isEmpty else {
            throw GeminiError.noAPIKey
        }

        let subtopicPart = subtopic.isEmpty ? "" : ", Subtopic: \(subtopic)"
        let prompt = """
        Generate exactly \(count) high-quality IB flashcards for:
        Subject: \(subject.name) \(subject.level)
        Topic: \(topicName)\(subtopicPart)

        REQUIREMENTS:
        - Each card must test a SPECIFIC concept, fact, definition, or application
        - Questions should match IB exam style and difficulty
        - Answers should be concise but comprehensive (2-4 sentences)
        - Include a mix of: definitions, explanations, applications, and analysis questions
        - For science/math: include formulas, calculations, and diagram descriptions where relevant
        - For humanities: include real-world examples and evaluation points

        RESPOND IN EXACTLY THIS JSON FORMAT (no markdown, no code fences, just raw JSON):
        [
          {"front": "question text here", "back": "answer text here"},
          {"front": "question text here", "back": "answer text here"}
        ]
        """

        let systemPrompt = """
        You are an IB curriculum expert flashcard generator. Generate cards that precisely match the IB \(subject.level) \(subject.name) syllabus for the DP 2027 curriculum. Cards must be exam-relevant and test understanding, not just recall. Return ONLY valid JSON array.
        """

        let response = try await GeminiService.generateContent(
            messages: [GeminiMessage(role: "user", text: prompt)],
            systemInstruction: systemPrompt,
            apiKey: apiKey
        )

        let cards = try parseFlashcards(from: response, subject: subject, topicName: topicName, subtopic: subtopic)
        return cards
    }

    /// Parse ARIA's response into StudyCard objects
    static func parseFlashcards(
        from response: String,
        subject: Subject,
        topicName: String,
        subtopic: String
    ) throws -> [StudyCard] {
        // Clean response — strip markdown code fences if present
        var cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Find the JSON array
        guard let startIdx = cleaned.firstIndex(of: "["),
              let endIdx = cleaned.lastIndex(of: "]") else {
            throw CardGeneratorError.invalidFormat
        }
        cleaned = String(cleaned[startIdx...endIdx])

        guard let data = cleaned.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
            throw CardGeneratorError.invalidFormat
        }

        var cards: [StudyCard] = []
        for item in jsonArray {
            guard let front = item["front"], let back = item["back"],
                  !front.isEmpty, !back.isEmpty else { continue }

            let card = StudyCard(
                topicName: topicName,
                subtopic: subtopic,
                front: front,
                back: back,
                subject: subject,
                isCustom: false,
                isAIGenerated: true,
                generationSource: "ARIA" as String?
            )
            cards.append(card)
        }

        guard !cards.isEmpty else { throw CardGeneratorError.noCardsGenerated }
        return cards
    }
}

enum CardGeneratorError: Error, LocalizedError {
    case invalidFormat
    case noCardsGenerated

    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "ARIA returned an unexpected format. Try again."
        case .noCardsGenerated: return "No cards could be parsed from ARIA's response."
        }
    }
}
