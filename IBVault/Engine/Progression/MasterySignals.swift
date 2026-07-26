import Foundation

/// Pure functions computing the four mastery signals. No SwiftData, no SwiftUI.
enum MasterySignals {

    // Tuning constants. Changing these changes progression pace for every user.

    /// Trailing window, in days, over which retention is computed.
    static let retentionWindowDays = 90.0
    /// Review count below which the window is too sparse to trust; retention
    /// falls back to `neutralRetention` instead.
    static let retentionMinimumSample = 20
    /// Retention value returned when the sample is smaller than
    /// `retentionMinimumSample`.
    static let neutralRetention = 0.5
    /// Interval, in days, at which a card counts as fully stable.
    static let stabilityTargetDays = 21.0
    /// Floor of the freshness ramp; freshness never drops below this.
    static let freshnessFloor = 0.75
    /// Days since last review below which freshness is still 1.0.
    static let freshnessFullDays = 7.0
    /// Days since last review at which freshness bottoms out at
    /// `freshnessFloor`; freshness ramps linearly from 1.0 to the floor
    /// between `freshnessFullDays` and `freshnessFloorDays`.
    static let freshnessFloorDays = 60.0

    /// Fraction of cards that have been successfully recalled at least twice.
    static func coverage(cards: [CardSnapshot]) -> Double {
        guard !cards.isEmpty else { return 0 }
        let learned = cards.filter { $0.repetitions >= 2 }.count
        return Double(learned) / Double(cards.count)
    }
}
