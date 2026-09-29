import Foundation

/// Stable identifiers for generated card formats. Raw values are persisted on
/// `StudyCard.cardStyleRaw`, so they must never be localized or renumbered.
nonisolated enum CardStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case basic = "basic"
    case cloze = "cloze"
    case multipleChoice = "multiple_choice"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .basic: return "Basic"
        case .cloze: return "Cloze"
        case .multipleChoice: return "Multiple Choice"
        }
    }

    var summary: String {
        switch self {
        case .basic: return "Prompt on the front, self-contained answer on the back."
        case .cloze: return "Fill-in-the-blank deletions marked as {{c1::answer}}."
        case .multipleChoice: return "One correct option with plausible distractors."
        }
    }
}

/// Writing voice for generated cards. Raw values are persisted only inside
/// generation metadata, not on the card model.
nonisolated enum CardTone: String, Codable, CaseIterable, Identifiable, Sendable {
    case balanced = "balanced"
    case exam = "exam"
    case concise = "concise"
    case socratic = "socratic"
    case applied = "applied"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .balanced: return "Balanced"
        case .exam: return "Exam"
        case .concise: return "Concise"
        case .socratic: return "Socratic"
        case .applied: return "Applied"
        }
    }

    var summary: String {
        switch self {
        case .balanced: return "One idea per card. A short definition, then a separate why or example question."
        case .concise: return "Quick recall with a single-sentence answer."
        case .exam: return "Precise terminology and only the marking points needed for one question."
        case .socratic: return "One focused reasoning question with a short explanation."
        case .applied: return "One practical situation and a brief answer."
        }
    }

    var promptInstructions: String {
        switch self {
        case .balanced:
            return "Aim for 15–40 words per answer, at most two short sentences. Break a broad concept into two or three independent cards: a definition, a why/how question, and optionally an example. These cards count toward the requested total. Start with definitions when recall is included in the requested skills; respect explicitly selected skills. Never combine definition, mechanism, example and evaluation on one back."
        case .concise:
            return "Aim for 5–20 words in a single sentence. Ask for one fact or definition. Split additional learning points into separate cards within the requested total."
        case .exam:
            return "Use at most three short marking points, normally under 60 words total. Ask one focused exam question, never a multi-part essay."
        case .socratic:
            return "Ask one why/how question; answer in at most two short sentences, normally under 45 words. Do not include a chain of follow-up questions."
        case .applied:
            return "Ask about one concrete situation; answer in at most two short sentences, normally under 45 words. Keep the scenario brief."
        }
    }

    /// Reject an overlong generated answer rather than truncating its meaning.
    var maximumAnswerWords: Int {
        switch self {
        case .balanced: 60
        case .concise: 30
        case .exam: 90
        case .socratic, .applied: 65
        }
    }
}

/// User-facing generation settings for the Card Studio. Persisted raw values
/// remain compatible; new sets default to six balanced cards.
nonisolated struct CardGenerationOptions: Codable, Equatable, Sendable {
    var count: Int
    var difficulty: CardDifficulty
    var style: CardStyle
    var tone: CardTone
    var cognitiveSkills: [CardCognitiveSkill]
    /// When true, the generation prompt tells the model the app performs
    /// curriculum lookup, duplicate detection, and scheduling with its internal
    /// tools, and the app enforces those steps deterministically after parsing.
    var useInternalTools: Bool

    init(
        count: Int = 6,
        difficulty: CardDifficulty = .exam,
        style: CardStyle = .basic,
        tone: CardTone = .balanced,
        cognitiveSkills: [CardCognitiveSkill] = [],
        useInternalTools: Bool = false
    ) {
        self.count = count
        self.difficulty = difficulty
        self.style = style
        self.tone = tone
        self.cognitiveSkills = cognitiveSkills
        self.useInternalTools = useInternalTools
    }

    static let `default` = CardGenerationOptions()

    static var preferred: CardGenerationOptions { preferences(in: .standard) }

    static func preferences(in defaults: UserDefaults) -> CardGenerationOptions {
        let count = defaults.object(forKey: "cardDefaultCount") as? Int ?? 6
        return CardGenerationOptions(
            count: min(max(count, 1), 50),
            difficulty: CardDifficulty(rawValue: defaults.string(forKey: "cardDefaultDifficulty") ?? "") ?? .exam,
            style: CardStyle(rawValue: defaults.string(forKey: "cardDefaultStyle") ?? "") ?? .basic,
            tone: CardTone(rawValue: defaults.string(forKey: "cardDefaultTone") ?? "") ?? .balanced
        )
    }

    func savePreferences(in defaults: UserDefaults = .standard) {
        defaults.set(min(max(count, 1), 50), forKey: "cardDefaultCount")
        defaults.set(difficulty.rawValue, forKey: "cardDefaultDifficulty")
        defaults.set(style.rawValue, forKey: "cardDefaultStyle")
        defaults.set(tone.rawValue, forKey: "cardDefaultTone")
    }

    /// Effective skills used when the caller did not pick an explicit mix.
    func resolvedSkills(fallback: [CardCognitiveSkill]) -> [CardCognitiveSkill] {
        cognitiveSkills.isEmpty ? fallback : cognitiveSkills
    }
}
