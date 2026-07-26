import Foundation

/// Composes the mastery signals into a single 0...1 score per subject.
enum MasteryCalculator {

    static let coverageWeight = 0.40
    static let retentionWeight = 0.35
    static let stabilityWeight = 0.25

    /// Mastery for one subject. Returns 0 when no work has been recorded — the
    /// neutral retention value must never grant mastery to an untouched subject.
    static func mastery(for snapshot: SubjectSnapshot, now: Date) -> Double {
        guard !snapshot.reviews.isEmpty else { return 0 }

        let raw = coverageWeight * MasterySignals.coverage(cards: snapshot.cards)
            + retentionWeight * MasterySignals.retention(reviews: snapshot.reviews, now: now)
            + stabilityWeight * MasterySignals.stability(cards: snapshot.cards)

        let decayed = raw * MasterySignals.freshness(lastReviewDate: snapshot.lastReviewDate, now: now)
        return min(max(decayed, 0.0), 1.0)
    }
}
