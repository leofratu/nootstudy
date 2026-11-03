import Foundation

/// Composes retrieval evidence into an estimate, not a validated grade or a
/// probability of passing an exam. Repeated retrieval and distributed practice
/// inform the signals; weights and cutoffs are product heuristics.
/// Research: https://doi.org/10.1016/j.jml.2006.09.004
/// https://doi.org/10.1037/0033-2909.132.3.354
nonisolated enum MasteryCalculator: Sendable {

    static let coverageWeight = 0.40
    static let retentionWeight = 0.35
    static let stabilityWeight = 0.25

    /// Mastery for one subject. Returns 0 when no work has been recorded — the
    /// neutral retention value must never grant mastery to an untouched subject.
    static func mastery(for snapshot: SubjectSnapshot, now: Date) -> Double {
        let observed = snapshot.reviews.filter { $0.timestamp <= now }
        guard observed.contains(where: \.isSuccessful) else { return 0 }

        let raw = coverageWeight * MasterySignals.coverage(cards: snapshot.cards)
            + retentionWeight * MasterySignals.retention(reviews: observed, now: now)
            + stabilityWeight * MasterySignals.stability(cards: snapshot.cards)

        // Sparse samples must not inherit the full neutral retention credit.
        let evidence = min(Double(observed.count) / Double(MasterySignals.retentionMinimumSample), 1)
        let decayed = raw * evidence * MasterySignals.freshness(lastReviewDate: observed.map(\.timestamp).max(), now: now)
        return min(max(decayed, 0.0), 1.0)
    }

    /// The headline composite: mean subject mastery weighted by teaching hours.
    static func globalMastery(for snapshots: [SubjectSnapshot], now: Date) -> Double {
        let totalWeight = snapshots.reduce(0.0) { $0 + $1.level.masteryWeight }
        guard totalWeight > 0 else { return 0 }
        let weightedSum = snapshots.reduce(0.0) { partial, snapshot in
            partial + mastery(for: snapshot, now: now) * snapshot.level.masteryWeight
        }
        return min(max(weightedSum / totalWeight, 0.0), 1.0)
    }
}
