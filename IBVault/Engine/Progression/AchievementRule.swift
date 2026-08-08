import Foundation

/// The facts an achievement rule may be evaluated against.
struct AchievementContext: Sendable {
    let totalCardsReviewed: Int
    let currentStreak: Int
    let totalXP: Int
    let globalMastery: Double
    let distinctSubjectsToday: Int
    let lastReviewHour: Int?
}

/// A rule, serialised onto `Achievement.ruleRaw` so the model stays storable.
nonisolated enum AchievementRule: Equatable, Sendable {
    case cardsReviewed(Int)
    case streakDays(Int)
    case totalXP(Int)
    case globalMastery(Double)
    case subjectsInOneDay(Int)
    case studiedAfterHour(Int)
    case studiedBeforeHour(Int)

    var rawValue: String {
        switch self {
        case .cardsReviewed(let n): return "cardsReviewed:\(n)"
        case .streakDays(let n): return "streakDays:\(n)"
        case .totalXP(let n): return "totalXP:\(n)"
        case .globalMastery(let v): return "globalMastery:\(v)"
        case .subjectsInOneDay(let n): return "subjectsInOneDay:\(n)"
        case .studiedAfterHour(let n): return "studiedAfterHour:\(n)"
        case .studiedBeforeHour(let n): return "studiedBeforeHour:\(n)"
        }
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let name = String(parts[0])
        let argument = String(parts[1])
        switch name {
        case "cardsReviewed": guard let n = Int(argument) else { return nil }; self = .cardsReviewed(n)
        case "streakDays": guard let n = Int(argument) else { return nil }; self = .streakDays(n)
        case "totalXP": guard let n = Int(argument) else { return nil }; self = .totalXP(n)
        case "globalMastery": guard let v = Double(argument) else { return nil }; self = .globalMastery(v)
        case "subjectsInOneDay": guard let n = Int(argument) else { return nil }; self = .subjectsInOneDay(n)
        case "studiedAfterHour": guard let n = Int(argument) else { return nil }; self = .studiedAfterHour(n)
        case "studiedBeforeHour": guard let n = Int(argument) else { return nil }; self = .studiedBeforeHour(n)
        default: return nil
        }
    }

    func isSatisfied(by context: AchievementContext) -> Bool {
        switch self {
        case .cardsReviewed(let n): return context.totalCardsReviewed >= n
        case .streakDays(let n): return context.currentStreak >= n
        case .totalXP(let n): return context.totalXP >= n
        case .globalMastery(let v): return context.globalMastery >= v
        case .subjectsInOneDay(let n): return context.distinctSubjectsToday >= n
        case .studiedAfterHour(let n):
            guard let hour = context.lastReviewHour else { return false }
            return hour >= n
        case .studiedBeforeHour(let n):
            guard let hour = context.lastReviewHour else { return false }
            return hour < n
        }
    }
}

nonisolated enum AchievementEvaluator {
    /// Unlocks every newly satisfied achievement and returns only those that
    /// changed, so callers can celebrate without re-announcing old unlocks.
    @discardableResult
    static func evaluate(achievements: [Achievement], context: AchievementContext) -> [Achievement] {
        var newlyUnlocked: [Achievement] = []
        for achievement in achievements where !achievement.unlocked {
            guard let rule = AchievementRule(rawValue: achievement.ruleRaw),
                  rule.isSatisfied(by: context) else { continue }
            achievement.unlocked = true
            achievement.unlockDate = Date()
            newlyUnlocked.append(achievement)
        }
        return newlyUnlocked
    }
}
