import Foundation

/// The single source of XP. Views and services record work; only this type
/// decides what that work is worth.
enum XPCalculator {

    static let xpPerStudyMinute = 1.0

    /// XP for a completed review session.
    static func xp(forQualities qualities: [RecallQuality], intensity: StudyIntensity) -> Int {
        guard !qualities.isEmpty else { return 0 }
        let base = qualities.reduce(0) { $0 + SM2Engine.xpForReview($1) }
        return Int(Double(base) * intensity.xpMultiplier)
    }

    /// XP for logged study time.
    static func xp(forStudyMinutes minutes: Double, intensity: StudyIntensity) -> Int {
        guard minutes > 0 else { return 0 }
        return Int(minutes * xpPerStudyMinute * intensity.xpMultiplier)
    }
}
