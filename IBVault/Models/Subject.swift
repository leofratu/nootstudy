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
        ProficiencyTracker.masteryPercentage(for: self)
    }

    var weightedGradeAverage: Double? {
        guard !grades.isEmpty else { return nil }
        let totalWeight = grades.reduce(0.0) { $0 + $1.effectiveWeight }
        guard totalWeight > 0 else { return nil }
        let weightedSum = grades.reduce(0.0) { partial, grade in
            partial + (Double(grade.resolvedIBScore) * grade.effectiveWeight)
        }
        return weightedSum / totalWeight
    }

    var latestResolvedGrade: Int? {
        grades.sorted { $0.date > $1.date }.first?.resolvedIBScore
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

    static func overallGradeAverage(for subjects: [Subject]) -> Double? {
        let weightedPairs = subjects.flatMap { subject in
            subject.grades.map { (grade: $0, weight: $0.effectiveWeight) }
        }
        let totalWeight = weightedPairs.reduce(0.0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        let weightedSum = weightedPairs.reduce(0.0) { partial, pair in
            partial + (Double(pair.grade.resolvedIBScore) * pair.weight)
        }
        return weightedSum / totalWeight
    }
}
