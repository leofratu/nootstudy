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
    case exam = "exam"
    case concise = "concise"
    case socratic = "socratic"
    case applied = "applied"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .exam: return "Exam"
        case .concise: return "Concise"
        case .socratic: return "Socratic"
        case .applied: return "Applied"
        }
    }
}

/// User-facing generation settings for the Card Studio. Every field has a
/// backward-compatible default so existing call sites keep current behavior.
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
        count: Int = 10,
        difficulty: CardDifficulty = .exam,
        style: CardStyle = .basic,
        tone: CardTone = .exam,
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

    /// Effective skills used when the caller did not pick an explicit mix.
    func resolvedSkills(fallback: [CardCognitiveSkill]) -> [CardCognitiveSkill] {
        cognitiveSkills.isEmpty ? fallback : cognitiveSkills
    }
}
