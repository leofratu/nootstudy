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

    @Test("Equal-priority events keep their arrival order across enqueues")
    func equalPriorityEventsAreStable() {
        let center = ProgressionEventCenter()
        let alpha = ProgressionEvent.achievementUnlocked(id: "alpha", title: "Alpha")
        let beta = ProgressionEvent.achievementUnlocked(id: "beta", title: "Beta")
        let gamma = ProgressionEvent.achievementUnlocked(id: "gamma", title: "Gamma")
        let rankUp = ProgressionEvent.rankUp(from: RankStep(ordinal: 0), to: RankStep(ordinal: 1))

        center.enqueue([alpha, beta])
        center.enqueue([rankUp])
        center.enqueue([.dailyGoalMet])
        center.enqueue([gamma])

        #expect(center.pending == [rankUp, alpha, beta, gamma, .dailyGoalMet])
    }

    @Test("The queue is capped and sheds the lowest-priority events first")
    func queueCapsByDroppingLowestPriority() {
        let center = ProgressionEventCenter()

        center.enqueue(Array(repeating: .dailyGoalMet, count: ProgressionEventCenter.capacity + 8))
        #expect(center.pending.count == ProgressionEventCenter.capacity)

        // A rank up arriving at a full queue must displace a low-priority
        // event rather than be dropped itself.
        let rankUp = ProgressionEvent.rankUp(from: RankStep(ordinal: 0), to: RankStep(ordinal: 3))
        center.enqueue([rankUp])

        #expect(center.pending.count == ProgressionEventCenter.capacity)
        #expect(center.pending.first == rankUp)
        #expect(center.pending.dropFirst().allSatisfy { $0 == .dailyGoalMet })
    }
}
