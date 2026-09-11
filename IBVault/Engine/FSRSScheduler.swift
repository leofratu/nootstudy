import Foundation
import FSRS
import SwiftData

nonisolated struct FSRSReviewPreview: Sendable, Equatable {
    let quality: RecallQuality
    let dueDate: Date
    let scheduledDays: Double

    var intervalLabel: String {
        if scheduledDays < 1 { return "<1 day" }
        if scheduledDays < 2 { return "1 day" }
        return "\(Int(scheduledDays.rounded())) days"
    }
}

@MainActor
enum FSRSScheduler {
    nonisolated static let schedulerVersion = 6
    nonisolated static let desiredRetention = 0.90

    nonisolated static func xp(for quality: RecallQuality) -> Int {
        switch quality {
        case .again: return 2
        case .hard: return 5
        case .good: return 10
        case .easy: return 15
        }
    }

    static func previews(for card: StudyCard, now: Date = Date()) -> [FSRSReviewPreview] {
        RecallQuality.allCases.compactMap { quality in
            guard let next = try? nextCard(for: card, quality: quality, now: now) else { return nil }
            return FSRSReviewPreview(quality: quality, dueDate: next.due, scheduledDays: next.scheduledDays)
        }
    }

    static func applyReview(to card: StudyCard, quality: RecallQuality, now: Date = Date()) throws {
        try applyReviewSync(to: card, quality: quality, now: now)
    }

    /// Nonisolated entry for background contexts (e.g. local bridge) that must not hop to MainActor synchronously.
    nonisolated static func applyReviewSync(to card: StudyCard, quality: RecallQuality, now: Date = Date()) throws {
        let next = try nextCard(for: card, quality: quality, now: now)
        applySync(next, to: card)
        card.totalReviewCount += 1
        if quality == .good || quality == .easy {
            card.successfulReviewCount += 1
            card.consecutiveCorrect += 1
        } else {
            card.consecutiveCorrect = 0
        }
        ProficiencyTracker.updateProficiency(for: card)
    }

    nonisolated static func configureSync(_ session: ReviewSession, quality: RecallQuality) {
        session.fsrsRatingRaw = rating(for: quality).rawValue
        session.schedulerVersion = schedulerVersion
    }

    static func configure(_ session: ReviewSession, quality: RecallQuality) {
        session.fsrsRatingRaw = rating(for: quality).rawValue
        session.schedulerVersion = schedulerVersion
    }

    static func migrate(cards: [StudyCard], reviewSessions: [ReviewSession]) {
        let sessionsByCard = Dictionary(grouping: reviewSessions, by: \.cardID)
        for card in cards where card.fsrsSchedulerVersion != schedulerVersion {
            let history = (sessionsByCard[card.id] ?? []).sorted { $0.timestamp < $1.timestamp }
            if history.isEmpty {
                apply(legacyConversion(for: card), to: card)
            } else {
                var replay = Card(due: card.createdDate)
                for session in history {
                    guard let next = try? scheduler.next(card: replay, now: session.timestamp, grade: rating(forStoredQuality: session.qualityRating)) else { continue }
                    replay = next.card
                }
                apply(replay, to: card)
            }
        }
    }

    nonisolated private static var scheduler: FSRS {
        FSRS(parameters: FSRSParameters(
            requestRetention: desiredRetention,
            w: FSRSDefaults.defaultWv6,
            enableFuzz: false,
            enableShortTerm: true
        ))
    }

    nonisolated private static func nextCard(for card: StudyCard, quality: RecallQuality, now: Date) throws -> Card {
        try scheduler.next(card: fsrsCard(for: card), now: now, grade: rating(for: quality)).card
    }

    nonisolated private static func fsrsCard(for card: StudyCard) -> Card {
        guard let stateRaw = card.fsrsStateRaw, let state = CardState(rawValue: stateRaw) else {
            return legacyConversion(for: card)
        }
        return Card(
            due: card.nextReviewDate,
            stability: card.fsrsStability ?? 0,
            difficulty: card.fsrsDifficulty ?? 0,
            elapsedDays: card.fsrsElapsedDays ?? 0,
            scheduledDays: card.fsrsScheduledDays ?? 0,
            reps: card.fsrsRepetitions ?? card.repetitions,
            lapses: card.fsrsLapses ?? 0,
            state: state,
            lastReview: card.fsrsLastReviewDate
        )
    }

    nonisolated private static func legacyConversion(for card: StudyCard) -> Card {
        guard card.repetitions > 0 || card.totalReviewCount > 0 else {
            return Card(due: card.nextReviewDate)
        }
        let stability = max(1, Double(max(card.interval, 1)))
        let difficulty = min(max(11 - card.easeFactor * 2, 1), 10)
        return Card(
            due: card.nextReviewDate,
            stability: stability,
            difficulty: difficulty,
            elapsedDays: max(0, Date().timeIntervalSince(card.lastReviewedDate ?? card.createdDate) / 86_400),
            scheduledDays: max(1, Double(card.interval)),
            reps: max(card.repetitions, card.totalReviewCount),
            lapses: max(0, card.totalReviewCount - card.successfulReviewCount),
            state: .review,
            lastReview: card.lastReviewedDate
        )
    }

    private static func apply(_ fsrsCard: Card, to card: StudyCard) {
        applySync(fsrsCard, to: card)
    }

    nonisolated private static func applySync(_ fsrsCard: Card, to card: StudyCard) {
        card.fsrsStability = fsrsCard.stability
        card.fsrsDifficulty = fsrsCard.difficulty
        card.fsrsElapsedDays = fsrsCard.elapsedDays
        card.fsrsScheduledDays = fsrsCard.scheduledDays
        card.fsrsRepetitions = fsrsCard.reps
        card.fsrsLapses = fsrsCard.lapses
        card.fsrsStateRaw = fsrsCard.state.rawValue
        card.fsrsLastReviewDate = fsrsCard.lastReview
        card.fsrsSchedulerVersion = schedulerVersion
        card.nextReviewDate = fsrsCard.due
        card.lastReviewedDate = fsrsCard.lastReview

        // Legacy read models still derive proficiency from these fields.
        card.interval = max(0, Int(fsrsCard.scheduledDays.rounded()))
        card.repetitions = fsrsCard.reps
        card.easeFactor = max(1.3, 3.2 - fsrsCard.difficulty / 5)
    }

    nonisolated private static func rating(for quality: RecallQuality) -> Rating {
        switch quality {
        case .again: return .again
        case .hard: return .hard
        case .good: return .good
        case .easy: return .easy
        }
    }

    private static func rating(forStoredQuality quality: Int) -> Rating {
        switch quality {
        case ..<1: return .again
        case 1...2: return .hard
        case 3...4: return .good
        default: return .easy
        }
    }
}
