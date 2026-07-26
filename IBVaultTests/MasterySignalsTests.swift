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
}
