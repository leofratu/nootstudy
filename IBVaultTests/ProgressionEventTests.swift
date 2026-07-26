import Testing
import Foundation
@testable import IBVault

@Suite("Progression Event Tests")
struct ProgressionEventTests {

    @Test("A rank up outranks every other event")
    func rankUpHasHighestPriority() {
        let rankUp = ProgressionEvent.rankUp(from: RankStep(ordinal: 3), to: RankStep(ordinal: 6))
        #expect(rankUp.priority > ProgressionEvent.dailyGoalMet.priority)
        #expect(rankUp.priority > ProgressionEvent.streakMilestone(days: 30).priority)
    }

    @Test("Events sort highest priority first")
    func eventsSortByPriority() {
        let center = ProgressionEventCenter()
        center.enqueue([
            .dailyGoalMet,
            .rankUp(from: RankStep(ordinal: 0), to: RankStep(ordinal: 3)),
            .streakMilestone(days: 7),
        ])
        #expect(center.pending.first == .rankUp(from: RankStep(ordinal: 0), to: RankStep(ordinal: 3)))
        #expect(center.pending.count == 3)
    }

    @Test("Consuming returns events one at a time and drains the queue")
    func consumingDrainsQueue() {
        let center = ProgressionEventCenter()
        center.enqueue([.dailyGoalMet, .weeklyChallengeComplete])
        #expect(center.consumeNext() != nil)
        #expect(center.pending.count == 1)
        #expect(center.consumeNext() != nil)
        #expect(center.consumeNext() == nil)
        #expect(center.pending.isEmpty)
    }

    @Test("Enqueuing nothing leaves the queue untouched")
    func enqueuingEmptyIsNoop() {
        let center = ProgressionEventCenter()
        center.enqueue([])
        #expect(center.pending.isEmpty)
    }
}
