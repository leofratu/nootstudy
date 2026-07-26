import Testing
import Foundation
@testable import IBVault

@Suite("Mastery Signals Tests")
struct MasterySignalsTests {

    @Test("Coverage is the fraction of cards with at least two repetitions")
    func coverageCountsLearnedCards() {
        let cards = [
            CardSnapshot(repetitions: 0, intervalDays: 0),
            CardSnapshot(repetitions: 1, intervalDays: 1),
            CardSnapshot(repetitions: 2, intervalDays: 6),
            CardSnapshot(repetitions: 5, intervalDays: 30),
        ]
        #expect(MasterySignals.coverage(cards: cards) == 0.5)
    }

    @Test("Coverage of an empty card set is zero, not a division by zero")
    func coverageOfEmptyIsZero() {
        #expect(MasterySignals.coverage(cards: []) == 0)
    }

    @Test("Coverage of a fully learned card set is one")
    func coverageOfFullyLearnedSetIsOne() {
        let cards = [
            CardSnapshot(repetitions: 2, intervalDays: 6),
            CardSnapshot(repetitions: 9, intervalDays: 60),
        ]
        #expect(MasterySignals.coverage(cards: cards) == 1.0)
    }

    @Test("Retention counts reviews graded good or better within the window")
    func retentionCountsSuccessfulRecentReviews() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // 30 reviews, 24 successful, all within the last few days.
        let reviews = (0..<30).map { index in
            ReviewSnapshot(
                timestamp: now.addingTimeInterval(-Double(index) * 3600),
                qualityRating: index < 24 ? 3 : 0
            )
        }
        let value = MasterySignals.retention(reviews: reviews, now: now)
        #expect(abs(value - 0.8) < 0.0001)
    }

    @Test("Retention below the minimum sample returns neutral, not a wild value")
    func retentionBelowSampleFloorIsNeutral() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let reviews = (0..<5).map { index in
            ReviewSnapshot(timestamp: now.addingTimeInterval(-Double(index) * 3600), qualityRating: 5)
        }
        #expect(MasterySignals.retention(reviews: reviews, now: now) == 0.5)
    }

    @Test("Retention ignores reviews older than the ninety day window")
    func retentionIgnoresStaleReviews() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let oldDay = -91.0 * 86_400
        // 25 ancient perfect reviews plus 20 recent failures.
        let stale = (0..<25).map { index in
            ReviewSnapshot(timestamp: now.addingTimeInterval(oldDay - Double(index) * 3600), qualityRating: 5)
        }
        let recent = (0..<20).map { index in
            ReviewSnapshot(timestamp: now.addingTimeInterval(-Double(index) * 3600), qualityRating: 0)
        }
        #expect(MasterySignals.retention(reviews: stale + recent, now: now) == 0.0)
    }

    @Test("Stability averages intervals normalised against the target, capped at one")
    func stabilityNormalisesAgainstTarget() {
        let cards = [
            CardSnapshot(repetitions: 1, intervalDays: 21),   // 1.0
            CardSnapshot(repetitions: 1, intervalDays: 42),   // capped to 1.0
            CardSnapshot(repetitions: 1, intervalDays: 0),    // 0.0
        ]
        let value = MasterySignals.stability(cards: cards)
        #expect(abs(value - (2.0 / 3.0)) < 0.0001)
    }

    @Test("Stability ignores cards that have never been reviewed")
    func stabilityIgnoresUnseenCards() {
        let cards = [
            CardSnapshot(repetitions: 0, intervalDays: 0),
            CardSnapshot(repetitions: 0, intervalDays: 0),
            CardSnapshot(repetitions: 3, intervalDays: 21),
        ]
        #expect(MasterySignals.stability(cards: cards) == 1.0)
    }

    @Test("Stability with no seen cards is zero")
    func stabilityWithNoSeenCardsIsZero() {
        #expect(MasterySignals.stability(cards: [CardSnapshot(repetitions: 0, intervalDays: 0)]) == 0)
    }

    @Test("Freshness is full within the first week and floors after sixty days")
    func freshnessBoundaries() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

        #expect(MasterySignals.freshness(lastReviewDate: now, now: now) == 1.0)
        #expect(MasterySignals.freshness(lastReviewDate: daysAgo(7), now: now) == 1.0)
        #expect(MasterySignals.freshness(lastReviewDate: daysAgo(60), now: now) == 0.75)
        #expect(MasterySignals.freshness(lastReviewDate: daysAgo(365), now: now) == 0.75)
    }

    @Test("Freshness decays linearly between the full and floor boundaries")
    func freshnessDecaysLinearly() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // Midpoint between 7 and 60 days is 33.5, expecting halfway 1.0 -> 0.75.
        let midpoint = now.addingTimeInterval(-33.5 * 86_400)
        let value = MasterySignals.freshness(lastReviewDate: midpoint, now: now)
        #expect(abs(value - 0.875) < 0.0001)
    }

    @Test("Freshness with no review history is the floor")
    func freshnessWithoutHistoryIsFloor() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(MasterySignals.freshness(lastReviewDate: nil, now: now) == 0.75)
    }
}
