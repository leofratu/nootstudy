import Foundation

/// Pure functions computing the four mastery signals. No SwiftData, no SwiftUI.
enum MasterySignals {

    // Tuning constants. Changing these changes progression pace for every user.
    static let retentionWindowDays = 90.0
    static let retentionMinimumSample = 20
    static let neutralRetention = 0.5
    static let stabilityTargetDays = 21.0
    static let freshnessFloor = 0.75
    static let freshnessFullDays = 7.0
    static let freshnessFloorDays = 60.0

    /// Fraction of cards that have been successfully recalled at least twice.
    static func coverage(cards: [CardSnapshot]) -> Double {
        guard !cards.isEmpty else { return 0 }
        let learned = cards.filter { $0.repetitions >= 2 }.count
        return Double(learned) / Double(cards.count)
    }
}
