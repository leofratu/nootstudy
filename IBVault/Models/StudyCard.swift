import Foundation
import SwiftData

enum ProficiencyLevel: String, Codable, CaseIterable, Sendable {
    case novice = "Novice"
    case developing = "Developing"
    case proficient = "Proficient"
    case mastered = "Mastered"

    var sortOrder: Int {
        switch self {
        case .novice: return 0
        case .developing: return 1
        case .proficient: return 2
        case .mastered: return 3
        }
    }

    var emoji: String {
        switch self {
        case .novice: return "🔴"
        case .developing: return "🟡"
        case .proficient: return "🟢"
        case .mastered: return "⭐"
        }
    }
}

enum RecallQuality: Int, Codable, CaseIterable, Sendable {
    case again = 0
    case hard = 2
    case good = 3
    case easy = 5

    var label: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }
}

enum CardDifficulty: String, Codable, CaseIterable, Identifiable, Sendable {
    case foundation = "Foundation"
    case standard = "Standard"
    case exam = "Exam"
    case stretch = "Stretch"

    var id: String { rawValue }
}

enum CardCognitiveSkill: String, Codable, CaseIterable, Identifiable, Sendable {
    case recall = "Recall"
    case explain = "Explain"
    case apply = "Apply"
    case analyze = "Analyze"
    case evaluate = "Evaluate"

    var id: String { rawValue }
}

@Model
final class StudyCard {
    var id: UUID
    var topicName: String
    var subtopic: String
    var front: String
    var back: String

    // SM-2 Fields
    var easeFactor: Double
    var interval: Int  // days
    var repetitions: Int
    var nextReviewDate: Date

    // Proficiency
    var proficiencyRaw: String
    var consecutiveCorrect: Int

    // Metadata
    var isCustom: Bool
    var isAIGenerated: Bool?
    var createdDate: Date
    var lastReviewedDate: Date?
    var generationSource: String?
    var totalReviewCount: Int
    var successfulReviewCount: Int
    var hint: String?
    var difficultyRaw: String?
    var cognitiveSkillRaw: String?
    var sourceTitle: String?
    var sourceURLString: String?
    var syllabusReference: String?
    var adaptationReason: String?
    var generationPromptVersion: Int?

    // Relationship
    var subject: Subject?

    var effectivenessRate: Double {
        guard totalReviewCount > 0 else { return 0 }
        return Double(successfulReviewCount) / Double(totalReviewCount)
    }

    var isEffective: Bool {
        totalReviewCount >= 3 && effectivenessRate >= 0.6
    }

    var isStruggling: Bool {
        totalReviewCount >= 3 && effectivenessRate < 0.4
    }

    var proficiency: ProficiencyLevel {
        get { ProficiencyLevel(rawValue: proficiencyRaw) ?? .novice }
        set { proficiencyRaw = newValue.rawValue }
    }

    var isDue: Bool {
        nextReviewDate <= Date()
    }

    var difficulty: CardDifficulty {
        get { difficultyRaw.flatMap(CardDifficulty.init(rawValue:)) ?? .standard }
        set { difficultyRaw = newValue.rawValue }
    }

    var cognitiveSkill: CardCognitiveSkill {
        get { cognitiveSkillRaw.flatMap(CardCognitiveSkill.init(rawValue:)) ?? .recall }
        set { cognitiveSkillRaw = newValue.rawValue }
    }

    var sourceURL: URL? {
        guard let sourceURLString, !sourceURLString.isEmpty else { return nil }
        return URL(string: sourceURLString)
    }

    var daysUntilDue: Int {
        let calendar = Calendar.current
        let fromDay = calendar.startOfDay(for: Date())
        let toDay = calendar.startOfDay(for: nextReviewDate)
        let days = calendar.dateComponents([.day], from: fromDay, to: toDay).day ?? 0
        return max(0, days)
    }

    init(
        topicName: String,
        subtopic: String = "",
        front: String,
        back: String,
        subject: Subject? = nil,
        isCustom: Bool = false,
        isAIGenerated: Bool? = true,
        generationSource: String? = "ARIA",
        hint: String? = nil,
        difficulty: CardDifficulty = .standard,
        cognitiveSkill: CardCognitiveSkill = .recall,
        sourceTitle: String? = nil,
        sourceURLString: String? = nil,
        syllabusReference: String? = nil,
        adaptationReason: String? = nil,
        generationPromptVersion: Int? = nil
    ) {
        self.id = UUID()
        self.topicName = topicName
        self.subtopic = subtopic
        self.front = front
        self.back = back
        self.easeFactor = 2.5
        self.interval = 0
        self.repetitions = 0
        self.nextReviewDate = Date()
        self.proficiencyRaw = ProficiencyLevel.novice.rawValue
        self.consecutiveCorrect = 0
        self.isCustom = isCustom
        self.isAIGenerated = isAIGenerated
        self.createdDate = Date()
        self.subject = subject
        self.generationSource = generationSource
        self.totalReviewCount = 0
        self.successfulReviewCount = 0
        self.hint = hint
        self.difficultyRaw = difficulty.rawValue
        self.cognitiveSkillRaw = cognitiveSkill.rawValue
        self.sourceTitle = sourceTitle
        self.sourceURLString = sourceURLString
        self.syllabusReference = syllabusReference
        self.adaptationReason = adaptationReason
        self.generationPromptVersion = generationPromptVersion
    }
}
