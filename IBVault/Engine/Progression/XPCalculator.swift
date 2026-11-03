import Foundation

/// The single source of XP. Views and services record work; only this type
/// decides what that work is worth.
nonisolated enum XPCalculator: Sendable {

    // A focused hour now earns 180 XP at average intensity, comparable to
    // a useful retrieval set. Previously time-based sessions earned only 60.
    static let xpPerStudyMinute = 3.0

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
}
