import Testing
import Foundation
@testable import IBVault

@Suite("Mastery Calculator Tests")
struct MasteryCalculatorTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(
        name: String = "Biology",
        level: SubjectLevel = .sl,
        cards: [CardSnapshot],
        reviews: [ReviewSnapshot]
    ) -> SubjectSnapshot {
        SubjectSnapshot(name: name, level: level, cards: cards, reviews: reviews)
    }

    @Test("A subject with no reviews has exactly zero mastery")
    func noReviewsMeansZeroMastery() {
        let subject = snapshot(
            cards: [CardSnapshot(repetitions: 0, intervalDays: 0)],
            reviews: []
        )
        #expect(MasteryCalculator.mastery(for: subject, now: now) == 0)
    }

    @Test("Mastery composes the three signals at 40/35/25 and applies freshness")
    func masteryComposesSignals() {
        // 4 cards, all learned and mature: coverage 1.0, stability 1.0.
        let cards = (0..<4).map { _ in CardSnapshot(repetitions: 3, intervalDays: 21) }
        // 20 reviews all successful and recent: retention 1.0, freshness 1.0.
        let reviews = (0..<20).map { index in
            ReviewSnapshot(timestamp: now.addingTimeInterval(-Double(index) * 3600), qualityRating: 5)
        }
        let value = MasteryCalculator.mastery(for: snapshot(cards: cards, reviews: reviews), now: now)
        #expect(abs(value - 1.0) < 0.0001)
    }

    @Test("Neglect reduces mastery through the freshness factor")
    func neglectReducesMastery() {
        let cards = (0..<4).map { _ in CardSnapshot(repetitions: 3, intervalDays: 21) }
        let reviews = (0..<20).map { index in
            ReviewSnapshot(
                timestamp: now.addingTimeInterval(-90.0 * 86_400 - Double(index) * 3600),
                qualityRating: 5
            )
        }
        // Reviews are outside the retention window, so retention is neutral 0.5,
        // and freshness has floored at 0.75.
        let expected = (0.40 * 1.0 + 0.35 * 0.5 + 0.25 * 1.0) * 0.75
        let value = MasteryCalculator.mastery(for: snapshot(cards: cards, reviews: reviews), now: now)
        #expect(abs(value - expected) < 0.0001)
    }

    /// Builds a snapshot whose mastery evaluates to 1.0: coverage, retention and
    /// stability all maxed, with fully recent reviews so freshness is 1.0.
    private func fullMasterySnapshot(name: String, level: SubjectLevel) -> SubjectSnapshot {
        let cards = (0..<4).map { _ in CardSnapshot(repetitions: 3, intervalDays: 21) }
        let reviews = (0..<20).map { index in
            ReviewSnapshot(timestamp: now.addingTimeInterval(-Double(index) * 3600), qualityRating: 5)
        }
        return SubjectSnapshot(name: name, level: level, cards: cards, reviews: reviews)
    }

    @Test("Global mastery weights HL at 1.5 against SL at 1.0")
    func globalMasteryWeightsHL() {
        let hl = fullMasterySnapshot(name: "Economics", level: .hl)      // mastery 1.0
        let sl = SubjectSnapshot(name: "Biology", level: .sl, cards: [], reviews: [])  // mastery 0
        // (1.0 * 1.5 + 0.0 * 1.0) / 2.5 == 0.6
        let value = MasteryCalculator.globalMastery(for: [hl, sl], now: now)
        #expect(abs(value - 0.6) < 0.0001)
    }

    @Test("Global mastery of no subjects is zero, not a division by zero")
    func globalMasteryOfEmptyIsZero() {
        #expect(MasteryCalculator.globalMastery(for: [], now: now) == 0)
    }

    @Test("Global mastery of all-untouched subjects is zero")
    func globalMasteryOfUntouchedIsZero() {
        let subjects = ["Biology", "Economics"].map {
            SubjectSnapshot(name: $0, level: .sl, cards: [], reviews: [])
        }
        #expect(MasteryCalculator.globalMastery(for: subjects, now: now) == 0)
    }
}
