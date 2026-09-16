import Foundation

/// Collapses only exact prompts or strongly overlapping question/answer pairs.
/// Originals remain in storage so their review history is never discarded.
nonisolated enum CardDuplicatePolicy {
    private static let stopWords: Set<String> = ["what", "is", "a", "an", "the", "of", "in", "and", "to", "it",
                                                "define", "state", "explain", "describe", "give", "how", "used"]
    private static let contrasts: Set<String> = ["not", "no", "never", "without", "non", "above", "below",
                                                "increase", "decrease", "positive", "negative", "less", "greater"]

    struct Signature {
        let question: String
        let questionWords: Set<String>
        let answerWords: [String]
        let answerPairs: Set<String>
        let protectedWords: [String]
        let style: CardStyle

        init(front: String, back: String, style: CardStyle) {
            question = normalize(front)
            questionWords = Set(question.split(separator: " ").map(String.init)).subtracting(stopWords)
            answerWords = normalize(back).split(separator: " ").map(String.init)
            answerPairs = Set(zip(answerWords, answerWords.dropFirst()).map { $0 + " " + $1 })
            protectedWords = answerWords.filter { word in
                contrasts.contains(word) || word.contains(where: \.isNumber)
                    || word.contains(where: { "+−-=<>/%^".contains($0) })
            }
            self.style = style
        }

        func matches(_ other: Signature) -> Bool {
            guard style == other.style else { return false }
            if question == other.question { return true }
            // Short/common answers and numeric or opposite statements are not
            // enough evidence to treat two different prompts as duplicates.
            guard answerWords.count >= 12, other.answerWords.count >= 12,
                  protectedWords == other.protectedWords else { return false }
            let sharedQuestions = questionWords.intersection(other.questionWords).count
            guard sharedQuestions >= 2,
                  Double(sharedQuestions) / Double(max(1, min(questionWords.count, other.questionWords.count))) >= 0.5 else { return false }
            let sharedAnswers = answerPairs.intersection(other.answerPairs).count
            return Double(2 * sharedAnswers) / Double(max(1, answerPairs.count + other.answerPairs.count)) >= 0.9
        }
    }

    struct Library {
        let cards: [StudyCard]
        let canonicalIDs: [UUID: UUID]
    }

    static func normalize(_ text: String) -> String {
        // Most prompts use ASCII. Avoid Foundation's Unicode transformations
        // for these while preserving the same word and operator boundaries.
        if text.utf8.allSatisfy({ $0 < 128 }) {
            var result: [UInt8] = []
            result.reserveCapacity(text.utf8.count)
            var needsSpace = false
            for byte in text.utf8 {
                let lowered = (65...90).contains(byte) ? byte + 32 : byte
                switch lowered {
                case 97...122, 48...57, 43, 45, 61, 60, 62, 47, 37, 94:
                    if needsSpace && !result.isEmpty { result.append(32) }
                    result.append(lowered)
                    needsSpace = false
                default:
                    needsSpace = true
                }
            }
            return String(decoding: result, as: UTF8.self)
        }
        return text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+−-=<>/%^")).inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func signature(_ card: StudyCard) -> Signature {
        Signature(front: card.front, back: card.back, style: card.cardStyle)
    }

    static func library(_ cards: [StudyCard]) -> Library {
        var groups: [String: [(id: UUID, rank: Int, signature: Signature)]] = [:]
        var exactPrompts: [String: [String: (id: UUID, rank: Int)]] = [:]
        var aliases: [UUID: UUID] = [:]
        var unique: [StudyCard] = []
        // Keep the copy with the strongest review history; prefer a stable
        // original when neither copy has been studied.
        // Snapshot sort keys once: reading SwiftData properties inside every
        // comparison makes a large library refresh noticeably slower.
        let preferred = cards.map { card in
            (card: card, count: card.totalReviewCount, reviewed: card.lastReviewedDate ?? .distantPast,
             created: card.createdDate, id: card.id)
        }.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            if $0.reviewed != $1.reviewed { return $0.reviewed > $1.reviewed }
            if $0.created != $1.created { return $0.created < $1.created }
            return $0.id.uuidString < $1.id.uuidString
        }
        for (rank, item) in preferred.enumerated() {
            let card = item.card
            let signature = signature(card)
            let subjectID = card.subject?.id
            var scope = (subjectID?.uuidString ?? "unassigned") + "|" + signature.style.rawValue
            // Very short prompts need their topic to disambiguate context.
            if signature.question.count < 12 || subjectID == nil {
                scope += "|" + normalize(card.topicName) + "|" + normalize(card.subtopic)
            }
            let exact = exactPrompts[scope]?[signature.question]
            // Short answers can only match an exact prompt. Long-answer
            // candidates retain preference order for conservative fuzzy reuse.
            let near = signature.answerWords.count >= 12
                ? groups[scope]?.first(where: { signature.matches($0.signature) }) : nil
            let existingID: UUID?
            if let exact, let near { existingID = exact.rank < near.rank ? exact.id : near.id }
            else { existingID = exact?.id ?? near?.id }
            if let existingID {
                aliases[item.id] = existingID
            } else {
                if signature.answerWords.count >= 12 { groups[scope, default: []].append((item.id, rank, signature)) }
                exactPrompts[scope, default: [:]][signature.question] = (item.id, rank)
                aliases[item.id] = item.id
                unique.append(card)
            }
        }
        return Library(cards: unique, canonicalIDs: aliases)
    }

    static func existingMatch(for draft: CardDraft, in cards: [StudyCard]) -> StudyCard? {
        let signature = Signature(front: draft.front, back: draft.back, style: draft.style)
        return library(cards).cards.first { signature.matches(Self.signature($0)) }
    }
}
