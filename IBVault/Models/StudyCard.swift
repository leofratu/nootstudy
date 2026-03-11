import Foundation
import SwiftData

enum ProficiencyLevel: String, Codable, CaseIterable {
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

enum RecallQuality: Int, Codable, CaseIterable {
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
    var createdDate: Date
    var lastReviewedDate: Date?

    // Relationship
    var subject: Subject?

    var proficiency: ProficiencyLevel {
        get { ProficiencyLevel(rawValue: proficiencyRaw) ?? .novice }
        set { proficiencyRaw = newValue.rawValue }
    }

    var isDue: Bool {
        nextReviewDate <= Date()
    }

    var daysUntilDue: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: nextReviewDate).day ?? 0
    }

    init(
        topicName: String,
        subtopic: String = "",
        front: String,
        back: String,
        subject: Subject? = nil,
        isCustom: Bool = false
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
        self.createdDate = Date()
        self.subject = subject
    }
}
