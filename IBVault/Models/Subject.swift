import Foundation
import SwiftData

@Model
final class Subject {
    var id: UUID
    var name: String
    var level: String  // "HL" or "SL"
    var accentColorHex: String
    var examDate: Date?
    @Relationship(deleteRule: .cascade, inverse: \StudyCard.subject) var cards: [StudyCard]
    @Relationship(deleteRule: .cascade, inverse: \Grade.subject) var grades: [Grade]

    var dueCardsCount: Int {
        let now = Date()
        return cards.filter { $0.nextReviewDate <= now }.count
    }

    var masteryProgress: Double {
        guard !cards.isEmpty else { return 0 }
        let masteredCount = cards.filter { $0.proficiency == .mastered }.count
        return Double(masteredCount) / Double(cards.count)
    }

    var overallProficiencyBreakdown: [ProficiencyLevel: Int] {
        var breakdown: [ProficiencyLevel: Int] = [:]
        for card in cards {
            breakdown[card.proficiency, default: 0] += 1
        }
        return breakdown
    }

    var accentColor: String { accentColorHex }

    init(name: String, level: String, accentColorHex: String, examDate: Date? = nil) {
        self.id = UUID()
        self.name = name
        self.level = level
        self.accentColorHex = accentColorHex
        self.examDate = examDate
        self.cards = []
        self.grades = []
    }
}
