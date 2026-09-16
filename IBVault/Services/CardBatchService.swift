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
        id = card.id
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
        var reusedCards: [StudyCard] = []
        var issues: [String] = []
    }

    @MainActor
    static func generate(subject: Subject, jobs: [CardBatchJob], options: CardGenerationOptions,
                         context: ModelContext,
                         reuseExisting: Bool = true,
                         generateCards: Generator? = nil,
                         onProgress: (Int, Int, String) -> Void) async throws -> Result {
        // Use a detached subject so model construction cannot mutate a live
        // inverse relationship before the user saves their drafts.
        let detached = Subject(name: subject.name, level: subject.level, accentColorHex: subject.accentColorHex)
        var result = Result()
        var known = subject.cards.map(CardDuplicatePolicy.signature)
        var coveredFronts = subject.cards.map(\.front)
        var included = Set<UUID>()
        for (index, job) in jobs.enumerated() {
            try Task.checkCancellation()
            onProgress(index, jobs.count, job.scope.label)
            let reusable = reuseExisting ? StudyLibraryService.cards(in: subject.cards, scopes: [job.scope], styles: [job.style])
                .filter { !included.contains($0.id) && CardDraft(card: $0).isValid } : []
            let reused = Array(reusable.prefix(job.count))
            result.reusedCards.append(contentsOf: reused)
            included.formUnion(reused.map(\.id))
            let missing = job.count - reused.count
            guard missing > 0 else { continue }
            let missingJob = CardBatchJob(scope: job.scope, style: job.style, count: missing)
            var settings = options
            settings.count = missing
            settings.style = job.style
            do {
                let cards: [StudyCard]
                if let generateCards {
                    cards = try await generateCards(detached, missingJob, settings, context)
                } else {
                    cards = try await CardGeneratorService.generateCards(
                        subject: detached, topicName: job.scope.topic, subtopic: job.scope.subtopic,
                        context: context, options: settings, allowsLocalFallback: false,
                        excludingFronts: coveredFronts, libraryCards: subject.cards)
                }
                try Task.checkCancellation()
                var added = 0
                for card in cards {
                    guard added < missing else { break }
                    let draft = CardDraft(card: card)
                    let signature = CardDuplicatePolicy.signature(card)
                    if let existing = subject.cards.first(where: { $0.id == card.id })
                        ?? CardDuplicatePolicy.existingMatch(for: draft, in: subject.cards) {
                        if included.insert(existing.id).inserted {
                            result.reusedCards.append(existing)
                            added += 1
                        }
                        continue
                    }
                    if draft.isValid, !known.contains(where: { signature.matches($0) }) {
                        result.drafts.append(draft)
                        known.append(signature)
                        coveredFronts.append(draft.front)
                        added += 1
                    }
                }
                if added < missing {
                    result.issues.append("\(job.scope.label) · \(job.style.label): \(added + reused.count) of \(job.count) cards available. Repeated or invalid cards were skipped.")
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
        style.rawValue + ":" + CardDuplicatePolicy.normalize(front)
    }

    @MainActor
    static func save(_ drafts: [CardDraft], subject: Subject, context: ModelContext) throws -> Int {
        guard !drafts.isEmpty, drafts.allSatisfy(\.isValid) else { throw CardBatchError.invalidDraft }
        var known = subject.cards.map(CardDuplicatePolicy.signature)
        let fresh = drafts.filter { draft in
            let signature = CardDuplicatePolicy.Signature(front: draft.front, back: draft.back, style: draft.style)
            guard !known.contains(where: { signature.matches($0) }) else { return false }
            known.append(signature)
            return true
        }
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
