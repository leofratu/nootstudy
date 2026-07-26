import Foundation
import Observation

/// Something worth celebrating. The only vocabulary the UI uses for moments.
enum ProgressionEvent: Equatable, Sendable {
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
    private(set) var pending: [ProgressionEvent] = []

    init() {}

    func enqueue(_ events: [ProgressionEvent]) {
        guard !events.isEmpty else { return }
        pending.append(contentsOf: events)
        pending.sort { $0.priority > $1.priority }
    }

    func consumeNext() -> ProgressionEvent? {
        guard !pending.isEmpty else { return nil }
        return pending.removeFirst()
    }

    func clear() {
        pending.removeAll()
    }
}
