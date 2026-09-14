import Foundation
import SwiftData

nonisolated struct CardTopicSelection: Hashable, Identifiable, Sendable {
    let topic: String
    var subtopic: String = ""
    var id: String { topic + "\u{1F}" + subtopic }
    var label: String { subtopic.isEmpty ? topic : subtopic }
}

nonisolated struct CardBatchJob: Equatable, Sendable {
    let scope: CardTopicSelection
    let style: CardStyle
    let count: Int
}

nonisolated enum CardBatchError: Error, LocalizedError {
    case emptySelection
    case tooManySelections
    case invalidCount(Int)
    case invalidDraft
    var errorDescription: String? {
        switch self {
        case .emptySelection: "Choose at least one topic and one card format."
        case .tooManySelections: "Choose fewer topics or formats; a batch can contain up to 50 cards."
        case .invalidCount(let minimum): "Choose between \(minimum) and 50 cards to cover every selected topic and format."
        case .invalidDraft: "Every card needs a question and answer. Multiple-choice cards need 3–4 different options and one correct answer; cloze cards need one matching blank."
        }
    }
}

/// Value drafts have no SwiftData relationships. Previewing or cancelling a
/// batch must never autosave generated cards into the learner's library.
nonisolated struct CardDraft: Identifiable, Sendable {
    var id = UUID()
    var topic: String
    var subtopic: String
    var front: String
    var back: String
    var style: CardStyle
    var choices: [String]
    var difficulty: CardDifficulty
    var skill: CardCognitiveSkill
    var hint: String?
    var source: String?
    var sourceTitle: String?
    var sourceURLString: String?
    var syllabusReference: String?
    var topicName: String { topic }

    var isValid: Bool {
        guard !front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch style {
        case .basic: return true
        case .cloze: return CardGeneratorService.isValidCloze(front: front, back: back)
        case .multipleChoice: return CardGeneratorService.validatedChoices(back: back, choices: choices) != nil
        }
    }

    init(card: StudyCard) {
        topic = card.topicName
        subtopic = card.subtopic
        front = card.front
        back = card.back
        style = card.cardStyle
        choices = card.choices
        difficulty = card.difficulty
        skill = card.cognitiveSkill
        hint = card.hint
        source = card.generationSource
        sourceTitle = card.sourceTitle
        sourceURLString = card.sourceURLString
        syllabusReference = card.syllabusReference
    }

    func makeCard(subject: Subject? = nil) -> StudyCard {
        let card = StudyCard(topicName: topic, subtopic: subtopic, front: front, back: back,
                  subject: subject, isAIGenerated: true, generationSource: source,
                  hint: hint, difficulty: difficulty, cognitiveSkill: skill,
                  cardStyle: style, choices: choices, sourceTitle: sourceTitle,
                  sourceURLString: sourceURLString, syllabusReference: syllabusReference,
                  generationPromptVersion: CardGeneratorService.promptVersion)
        card.id = id
        return card
    }
}

enum CardBatchService {
    typealias Generator = @MainActor (Subject, CardBatchJob, CardGenerationOptions, ModelContext) async throws -> [StudyCard]
    nonisolated static func plan(scopes: [CardTopicSelection], styles: [CardStyle], count: Int) throws -> [CardBatchJob] {
        // Selecting a whole topic subsumes its selected subtopics.
        let wholeTopics = Set(scopes.filter { $0.subtopic.isEmpty }.map(\.topic))
        let uniqueScopes = Set(scopes.filter { $0.subtopic.isEmpty || !wholeTopics.contains($0.topic) })
            .sorted { $0.id < $1.id }
        let uniqueStyles = CardStyle.allCases.filter { styles.contains($0) }
        let minimum = uniqueScopes.count * uniqueStyles.count
        guard minimum > 0 else { throw CardBatchError.emptySelection }
        guard minimum <= 50 else { throw CardBatchError.tooManySelections }
        guard count >= minimum, count <= 50 else { throw CardBatchError.invalidCount(minimum) }
        return uniqueScopes.flatMap { scope in uniqueStyles.map { (scope, $0) } }
            .enumerated().map { index, pair in
                CardBatchJob(scope: pair.0, style: pair.1,
                             count: count / minimum + (index < count % minimum ? 1 : 0))
            }
    }

    struct Result {
        var drafts: [CardDraft] = []
        var issues: [String] = []
    }

    @MainActor
    static func generate(subject: Subject, jobs: [CardBatchJob], options: CardGenerationOptions,
                         context: ModelContext,
                         generateCards: Generator? = nil,
                         onProgress: (Int, Int, String) -> Void) async throws -> Result {
        // Use a detached subject so model construction cannot mutate a live
        // inverse relationship before the user saves their drafts.
        let detached = Subject(name: subject.name, level: subject.level, accentColorHex: subject.accentColorHex)
        var result = Result()
        var known = Set(subject.cards.map { fingerprint(front: $0.front, style: $0.cardStyle) })
        for (index, job) in jobs.enumerated() {
            try Task.checkCancellation()
            onProgress(index, jobs.count, job.scope.label)
            var settings = options
            settings.count = job.count
            settings.style = job.style
            do {
                let cards: [StudyCard]
                if let generateCards {
                    cards = try await generateCards(detached, job, settings, context)
                } else {
                    cards = try await CardGeneratorService.generateCards(
                        subject: detached, topicName: job.scope.topic, subtopic: job.scope.subtopic,
                        context: context, options: settings, allowsLocalFallback: false)
                }
                try Task.checkCancellation()
                var added = 0
                for card in cards {
                    let draft = CardDraft(card: card)
                    if draft.isValid, known.insert(fingerprint(front: draft.front, style: draft.style)).inserted {
                        result.drafts.append(draft)
                        added += 1
                    }
                }
                if added < job.count {
                    result.issues.append("\(job.scope.label) · \(job.style.label): \(added) of \(job.count) new cards. Duplicate or invalid cards were skipped.")
                }
            } catch {
                if Task.isCancelled || error is CancellationError { throw CancellationError() }
                result.issues.append("\(job.scope.label): \(error.localizedDescription)")
            }
        }
        onProgress(jobs.count, jobs.count, "Ready to preview")
        return result
    }

    nonisolated static func fingerprint(front: String, style: CardStyle) -> String {
        style.rawValue + ":" + front.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    @MainActor
    static func save(_ drafts: [CardDraft], subject: Subject, context: ModelContext) throws -> Int {
        guard !drafts.isEmpty, drafts.allSatisfy(\.isValid) else { throw CardBatchError.invalidDraft }
        var known = Set(subject.cards.map { fingerprint(front: $0.front, style: $0.cardStyle) })
        let fresh = drafts.filter { known.insert(fingerprint(front: $0.front, style: $0.style)).inserted }
        let cards = fresh.map { $0.makeCard(subject: subject) }
        cards.forEach(context.insert)
        do { try context.save() }
        catch {
            cards.forEach(context.delete)
            throw error
        }
        return cards.count
    }
}
