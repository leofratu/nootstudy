import Foundation
import Observation

/// Something worth celebrating. The only vocabulary the UI uses for moments.
nonisolated enum ProgressionEvent: Equatable, Sendable {
    case rankUp(from: RankStep, to: RankStep)
    case tierUp(subjectName: String, to: RankStep)
    case achievementUnlocked(id: String, title: String)
    case streakMilestone(days: Int)
    case dailyGoalMet
    case weeklyChallengeComplete

    /// Higher wins when several land at once.
    var priority: Int {
        switch self {
        case .rankUp: return 100
        case .tierUp: return 80
        case .achievementUnlocked: return 60
        case .streakMilestone: return 40
        case .weeklyChallengeComplete: return 30
        case .dailyGoalMet: return 20
        }
    }
}

/// Holds pending events for the UI to present in order.
@Observable
final class ProgressionEventCenter {

    /// Upper bound on `pending`. Nothing drains the queue yet — presentation
    /// lands in a later plan — so an unbounded queue grows for the whole life
    /// of the process. Overflow sheds the least interesting events.
    static let capacity = 32

    /// Pairs an event with when it arrived, so ties break on arrival order.
    private struct Entry {
        let event: ProgressionEvent
        let sequence: Int

        var priority: Int { event.priority }
    }

    private var entries: [Entry] = []
    private var nextSequence = 0

    var pending: [ProgressionEvent] { entries.map(\.event) }

    init() {}

    func enqueue(_ events: [ProgressionEvent]) {
        guard !events.isEmpty else { return }

        for event in events {
            entries.append(Entry(event: event, sequence: nextSequence))
            nextSequence += 1
        }

        // `sort` is not stable, so ordering by priority alone let
        // equal-priority events shuffle on every enqueue. The insertion
        // sequence pins them in arrival order.
        entries.sort { lhs, rhs in
            lhs.priority == rhs.priority
                ? lhs.sequence < rhs.sequence
                : lhs.priority > rhs.priority
        }

        // Sorted highest priority first, so the overflow at the tail is
        // exactly the lowest-priority events.
        if entries.count > Self.capacity {
            entries.removeLast(entries.count - Self.capacity)
        }
    }

    func consumeNext() -> ProgressionEvent? {
        guard !entries.isEmpty else { return nil }
        return entries.removeFirst().event
    }

    func clear() {
        entries.removeAll()
    }
}
