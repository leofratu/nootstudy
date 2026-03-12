import Foundation
import SwiftData

struct CardGeneratorService {
    private static let fallbackModels = ["gemini-2.0-flash", "gemini-2.0-flash-lite"]

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

        let systemPrompt = """
        You are an IB curriculum expert flashcard generator. Generate cards that precisely match the IB \(subject.level) \(subject.name) syllabus for the DP 2027 curriculum. Cards must be exam-relevant and test understanding, not just recall. Return ONLY valid JSON array.
        """

        let modelsToTry = [GeminiService.selectedModel] + fallbackModels.filter { $0 != GeminiService.selectedModel }
        var collectedCards: [StudyCard] = []
        var lastError: Error?

        for model in modelsToTry {
            for _ in 0..<2 {
                let remaining = count - collectedCards.count
                guard remaining > 0 else {
                    return Array(collectedCards.prefix(count))
                }

                let prompt = generationPrompt(
                    subject: subject,
                    topicName: topicName,
                    subtopic: subtopic,
                    count: remaining,
                    excludingFronts: collectedCards.map(\.front)
                )

                do {
                    let response = try await GeminiService.generateContent(
                        messages: [GeminiMessage(role: "user", text: prompt)],
                        systemInstruction: systemPrompt,
                        apiKey: apiKey,
                        modelOverride: model,
                        timeout: model == GeminiService.selectedModel ? 120 : 90
                    )
                    let parsed = try parseFlashcards(from: response, subject: subject, topicName: topicName, subtopic: subtopic)
                    let merged = mergeUnique(existing: collectedCards, incoming: parsed)
                    let addedCount = merged.count - collectedCards.count
                    collectedCards = merged

                    if collectedCards.count >= count {
                        return Array(collectedCards.prefix(count))
                    }

                    if addedCount == 0 {
                        break
                    }
                } catch {
                    lastError = error
                    break
                }
            }
        }

        if !collectedCards.isEmpty {
            return collectedCards
        }
        throw lastError ?? CardGeneratorError.noCardsGenerated
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

        if let data = cleaned.data(using: .utf8),
           let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
            let cards = cardsFromJSONArray(jsonArray, subject: subject, topicName: topicName, subtopic: subtopic)
            if !cards.isEmpty {
                return cards
            }
        }

        let textPairs = parseFrontBackBlocks(from: response)
        let cards = cardsFromPairs(textPairs, subject: subject, topicName: topicName, subtopic: subtopic)
        guard !cards.isEmpty else { throw CardGeneratorError.invalidFormat }
        return cards
    }

    private static func cardsFromJSONArray(
        _ jsonArray: [[String: String]],
        subject: Subject,
        topicName: String,
        subtopic: String
    ) -> [StudyCard] {
        cardsFromPairs(
            jsonArray.compactMap { item in
                guard let front = item["front"], let back = item["back"] else { return nil }
                return (front, back)
            },
            subject: subject,
            topicName: topicName,
            subtopic: subtopic
        )
    }

    private static func cardsFromPairs(
        _ pairs: [(String, String)],
        subject: Subject,
        topicName: String,
        subtopic: String
    ) -> [StudyCard] {
        var cards: [StudyCard] = []
        for (frontRaw, backRaw) in pairs {
            let front = frontRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            let back = backRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !front.isEmpty, !back.isEmpty else { continue }
            cards.append(StudyCard(
                topicName: topicName,
                subtopic: subtopic,
                front: front,
                back: back,
                subject: subject,
                isCustom: false,
                isAIGenerated: true,
                generationSource: "ARIA" as String?
            ))
        }
        return deduplicated(cards)
    }

    private static func generationPrompt(
        subject: Subject,
        topicName: String,
        subtopic: String,
        count: Int,
        excludingFronts: [String]
    ) -> String {
        let unitPart = SyllabusSeeder.unitName(for: subject.name, topicName: topicName).map { "\nUnit: \($0)" } ?? ""
        let subtopicPart = subtopic.isEmpty ? "" : "\nSubtopic: \(subtopic)"
        let exclusionLines = excludingFronts.isEmpty
            ? ""
            : "\nAlready generated question fronts to avoid repeating:\n" + excludingFronts.prefix(20).map { "- \($0)" }.joined(separator: "\n")

        return """
        Generate exactly \(count) high-quality IB flashcards for:
        Subject: \(subject.name) \(subject.level)
        Topic: \(topicName)\(unitPart)\(subtopicPart)

        REQUIREMENTS:
        - Each card must test a SPECIFIC concept, fact, definition, or application
        - Every card must stay anchored to the named IB unit/topic and avoid unrelated syllabus areas
        - Questions should match IB exam style and difficulty
        - Answers should be concise but comprehensive (2-4 sentences)
        - Include a mix of: definitions, explanations, applications, and analysis questions
        - For science/math: include formulas, calculations, and diagram descriptions where relevant
        - For humanities: include real-world examples and evaluation points
        - Every card must be materially distinct from the others\(excludingFronts.isEmpty ? "" : " and must not repeat the excluded question fronts")
        \(exclusionLines)

        RESPOND IN EXACTLY THIS JSON FORMAT (no markdown, no code fences, just raw JSON):
        [
          {"front": "question text here", "back": "answer text here"},
          {"front": "question text here", "back": "answer text here"}
        ]
        """
    }

    private static func parseFrontBackBlocks(from response: String) -> [(String, String)] {
        let normalized = response.replacingOccurrences(of: "\r\n", with: "\n")
        let pattern = #"FRONT:\s*(.*?)\nBACK:\s*(.*?)(?=\n\s*FRONT:|\z)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return []
        }
        let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        return regex.matches(in: normalized, options: [], range: nsRange).compactMap { match in
            guard
                let frontRange = Range(match.range(at: 1), in: normalized),
                let backRange = Range(match.range(at: 2), in: normalized)
            else { return nil }
            return (String(normalized[frontRange]), String(normalized[backRange]))
        }
    }

    private static func deduplicated(_ cards: [StudyCard]) -> [StudyCard] {
        var seen = Set<String>()
        return cards.filter { card in
            let key = "\(card.front.lowercased())::\(card.back.lowercased())"
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private static func mergeUnique(existing: [StudyCard], incoming: [StudyCard]) -> [StudyCard] {
        deduplicated(existing + incoming)
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
