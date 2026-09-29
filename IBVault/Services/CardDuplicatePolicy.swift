import Foundation

/// Collapses only exact prompts or strongly overlapping question/answer pairs.
/// Originals remain in storage so their review history is never discarded.
nonisolated enum CardDuplicatePolicy {
    struct Signature {
        let question: String
        let questionWords: Set<String>
        let answerWords: [String]
        let answerPairs: Set<String>
        let protectedWords: [String]
        let style: CardStyle

        init(front: String, back: String, style: CardStyle) {
            question = normalize(front)
            let stopWords: Set<String> = ["what", "is", "a", "an", "the", "of", "in", "and", "to", "it",
                                         "define", "state", "explain", "describe", "give", "how", "used"]
            questionWords = Set(question.split(separator: " ").map(String.init)).subtracting(stopWords)
            answerWords = normalize(back).split(separator: " ").map(String.init)
            answerPairs = Set(zip(answerWords, answerWords.dropFirst()).map { $0 + " " + $1 })
            let contrasts: Set<String> = ["not", "no", "never", "without", "non", "above", "below",
                                         "increase", "decrease", "positive", "negative", "less", "greater"]
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
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+−-=<>/%^")).inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func signature(_ card: StudyCard) -> Signature {
        Signature(front: card.front, back: card.back, style: card.cardStyle)
    }

    static func library(_ cards: [StudyCard]) -> Library {
        var groups: [String: [(card: StudyCard, signature: Signature)]] = [:]
        var exactQuestions: [String: [String: Int]] = [:]
        var questionIndex: [String: [String: Set<Int>]] = [:]
        var aliases: [UUID: UUID] = [:]
        var unique: [StudyCard] = []
        // Keep the copy with the strongest review history; prefer a stable
        // original when neither copy has been studied.
        let preferred = cards.sorted {
            if $0.totalReviewCount != $1.totalReviewCount { return $0.totalReviewCount > $1.totalReviewCount }
            if $0.lastReviewedDate != $1.lastReviewedDate {
                return ($0.lastReviewedDate ?? .distantPast) > ($1.lastReviewedDate ?? .distantPast)
            }
            if $0.createdDate != $1.createdDate { return $0.createdDate < $1.createdDate }
            return $0.id.uuidString < $1.id.uuidString
        }
        for card in preferred {
            let signature = signature(card)
            var scope = (card.subject?.id.uuidString ?? "unassigned") + "|" + card.cardStyle.rawValue
            // Very short prompts need their topic to disambiguate context.
            if signature.question.count < 12 || card.subject == nil {
                scope += "|" + normalize(card.topicName) + "|" + normalize(card.subtopic)
            }
            // A fuzzy match requires at least two shared question words.
            // Use postings to avoid comparing every card in a subject, while
            // retaining the same preferred-original ordering and match rules.
            var sharedCounts: [Int: Int] = [:]
            if signature.answerWords.count >= 12 {
                for word in signature.questionWords {
                    for index in questionIndex[scope]?[word] ?? [] {
                        sharedCounts[index, default: 0] += 1
                    }
                }
            }
            var candidates = Set(sharedCounts.compactMap { $0.value >= 2 ? $0.key : nil })
            if let exact = exactQuestions[scope]?[signature.question] { candidates.insert(exact) }
            let match = candidates.sorted().first { index in
                guard let existing = groups[scope]?[index] else { return false }
                return signature.matches(existing.signature)
            }
            if let match {
                aliases[card.id] = groups[scope]?[match].card.id
            } else {
                let index = groups[scope]?.count ?? 0
                groups[scope, default: []].append((card, signature))
                exactQuestions[scope, default: [:]][signature.question] = index
                if signature.answerWords.count >= 12 {
                    for word in signature.questionWords {
                        questionIndex[scope, default: [:]][word, default: []].insert(index)
                    }
                }
                aliases[card.id] = card.id
                unique.append(card)
            }
        }
        return Library(cards: unique, canonicalIDs: aliases)
    }

    static func existingMatch(for draft: CardDraft, in cards: [StudyCard]) -> StudyCard? {
        existingMatch(for: draft, in: library(cards))
    }

    static func existingMatch(for draft: CardDraft, in library: Library) -> StudyCard? {
        let signature = Signature(front: draft.front, back: draft.back, style: draft.style)
        return library.cards.first { signature.matches(Self.signature($0)) }
    }
}
