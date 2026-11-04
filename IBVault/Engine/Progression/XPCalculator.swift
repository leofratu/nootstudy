import Foundation

/// The single source of XP. Views and services record work; only this type
/// decides what that work is worth.
nonisolated enum XPCalculator: Sendable {

    // A focused hour earns 300 XP at average intensity, about what 30 cards
    // rated Good earn, so deep study is not worth less than clicking through a
    // queue. Finishing a real session pays a further flat bonus.
    static let xpPerStudyMinute = 5.0
    static let sessionCompletionBonus = 50.0
    /// Below this a session is a check-in, so it earns no completion bonus.
    static let completionBonusMinimumMinutes = 10.0

    /// XP for a completed review session.
    static func xp(forQualities qualities: [RecallQuality], intensity: StudyIntensity) -> Int {
        guard !qualities.isEmpty else { return 0 }
        let base = qualities.reduce(0) { $0 + FSRSScheduler.xp(for: $1) }
        return Int(Double(base) * intensity.xpMultiplier)
    }

    /// XP for logged study time.
    static func xp(forStudyMinutes minutes: Double, intensity: StudyIntensity) -> Int {
        guard minutes.isFinite, minutes > 0 else { return 0 }
        let earned = minutes * xpPerStudyMinute * intensity.xpMultiplier
        // Inputs can also come from imported activity logs. Avoid trapping
        // when converting an out-of-range Double to Int.
        guard earned < Double(Int.max) else { return 0 }
        return Int(earned)
    }

    /// Bonus for seeing a planned session through to its check-in.
    static func completionBonus(forStudyMinutes minutes: Double, intensity: StudyIntensity) -> Int {
        guard minutes.isFinite, minutes >= completionBonusMinimumMinutes else { return 0 }
        return Int(sessionCompletionBonus * intensity.xpMultiplier)
    }
}
