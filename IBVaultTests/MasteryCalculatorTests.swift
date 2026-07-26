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
}
