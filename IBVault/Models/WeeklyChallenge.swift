import Foundation
import SwiftData

nonisolated enum WeeklyChallengeRule: String, Codable, CaseIterable, Sendable {
    case reviewCards
    case studyMinutes
    case coverSubjects

    var title: String {
        switch self {
        case .reviewCards: return "Review Cards"
        case .studyMinutes: return "Study Minutes"
        case .coverSubjects: return "Cover Subjects"
        }
    }
}

@Model
nonisolated final class WeeklyChallenge {
    var id: UUID
    var ruleRaw: String
    var target: Int
    var progress: Int
    /// ISO week identifier, e.g. "2026-W31". One challenge per week.
    var weekIdentifier: String

    var rule: WeeklyChallengeRule {
        get { WeeklyChallengeRule(rawValue: ruleRaw) ?? .reviewCards }
        set { ruleRaw = newValue.rawValue }
    }

    var isComplete: Bool { progress >= target }

    var fractionComplete: Double {
        guard target > 0 else { return 0 }
        return min(Double(progress) / Double(target), 1.0)
    }

    static func weekIdentifier(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = components.yearForWeekOfYear ?? 0
        let week = components.weekOfYear ?? 0
        return String(format: "%04d-W%02d", year, week)
    }

    init(rule: WeeklyChallengeRule, target: Int, weekIdentifier: String) {
        self.id = UUID()
        self.ruleRaw = rule.rawValue
        self.target = target
        self.progress = 0
        self.weekIdentifier = weekIdentifier
    }
}
