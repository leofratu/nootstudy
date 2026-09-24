import Foundation
import os
import SwiftData

nonisolated enum ReviewDailyLimitPolicy: Sendable {
    static let maximumCards = 40

    static func maximumCards(for intensity: StudyIntensity) -> Int {
        min(intensity.dailyCardSuggestion, maximumCards)
    }

    static func maximumCards(for intensity: StudyIntensity, dailyGoal: Int) -> Int {
        min(max(dailyGoal, 1), maximumCards(for: intensity))
    }

    static func allowance(reviewedCardIDs: Set<UUID>, maximum: Int = maximumCards) -> Int {
        max(0, min(maximumCards, maximum) - reviewedCardIDs.count)
    }

    static func limitedCards(_ cards: [StudyCard], reviewedCardIDs: Set<UUID>, maximum: Int = maximumCards) -> [StudyCard] {
        let remaining = allowance(reviewedCardIDs: reviewedCardIDs, maximum: maximum)
        var seen = reviewedCardIDs
        return Array(cards.filter { seen.insert($0.id).inserted }.prefix(remaining))
    }

    struct Day {
        let library: CardDuplicatePolicy.Library
        let reviewedIDs: Set<UUID>
        let reviewedCanonicalIDs: Set<UUID>
        let maximum: Int
        let now: Date

        var remaining: Int { allowance(reviewedCardIDs: reviewedIDs, maximum: maximum) }

        var backlog: [StudyCard] {
            library.cards.compactMap { card -> (card: StudyCard, due: Date, ease: Double, id: String)? in
                let due = card.nextReviewDate
                guard due <= now else { return nil }
                let id = card.id
                guard !reviewedCanonicalIDs.contains(id) else { return nil }
                return (card, due, card.easeFactor, id.uuidString)
            }.sorted {
                if $0.due != $1.due { return $0.due < $1.due }
                if $0.ease != $1.ease { return $0.ease < $1.ease }
                return $0.id < $1.id
            }.map(\.card)
        }

        func limited(_ candidates: [StudyCard]) -> [StudyCard] {
            guard remaining > 0 else { return [] }
            var seen = reviewedCanonicalIDs
            var unique: [StudyCard] = []
            for card in candidates where BiologyStudyService.isEligible(card) {
                let id = card.id
                let canonicalID = library.canonicalIDs[id] ?? id
                guard canonicalID == id && seen.insert(canonicalID).inserted else { continue }
                unique.append(card)
                if unique.count == remaining { break }
            }
            return unique
        }

        func canReview(_ card: StudyCard) -> Bool {
            BiologyStudyService.isEligible(card) && remaining > 0 && !reviewedCanonicalIDs.contains(library.canonicalIDs[card.id] ?? card.id)
        }
    }

    @MainActor
    static func day(in context: ModelContext, now: Date = IBLocalClock.now,
                    calendar: Calendar = IBLocalClock.calendar) throws -> Day {
        let all = try context.fetch(FetchDescriptor<StudyCard>())
        let library = CardDuplicatePolicy.library(all.filter(BiologyStudyService.isEligible))
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
        let reviews = try context.fetch(FetchDescriptor<ReviewSession>(
            predicate: #Predicate { $0.timestamp >= start && $0.timestamp < end && $0.timestamp <= now }
        ))
        let reviewedIDs = Set(reviews.map(\.cardID))
        let profile = try context.fetch(FetchDescriptor<UserProfile>()).first
        let maximum = profile.map { maximumCards(for: $0.studyIntensity, dailyGoal: $0.dailyGoal) } ?? maximumCards
        return Day(library: library, reviewedIDs: reviewedIDs,
                   reviewedCanonicalIDs: Set(reviewedIDs.map { library.canonicalIDs[$0] ?? $0 }),
                   maximum: maximum, now: now)
    }
}

@MainActor
@Observable
final class ReviewQueueManager {
    private(set) var dueCards: [StudyCard] = []
    private(set) var totalDueCount = 0
    /// Full backlog, separate from the smaller daily queue.
    private(set) var totalDueBacklogCount = 0
    private(set) var backlogDueCount = 0
    private(set) var deferredDueCount = 0
    private(set) var reviewedTodayCount = 0
    private(set) var dailyMaximum = ReviewDailyLimitPolicy.maximumCards
    private(set) var remainingDailyAllowance = ReviewDailyLimitPolicy.maximumCards
    private(set) var duplicateCardCount = 0
    private(set) var dueCountCache: [String: Int] = [:]
    private(set) var eligibleCardCount = 0
    private(set) var lastRefreshError: String?
    private var isRefreshing = false

    func refreshDueCards(context: ModelContext) {
        let state = PerformanceSignposts.signposter.beginInterval("reviewQueue.refresh")
        defer { PerformanceSignposts.signposter.endInterval("reviewQueue.refresh", state) }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        refreshDueCardsSynchronously(context: context)
    }

    func loadDueCards(context: ModelContext) { refreshDueCards(context: context) }

    func refreshDueCardsSynchronously(context: ModelContext) {
        do {
            let day = try ReviewDailyLimitPolicy.day(in: context)
            let backlog = day.backlog
            let available = day.limited(backlog)
            reviewedTodayCount = day.reviewedIDs.count
            dailyMaximum = day.maximum
            remainingDailyAllowance = day.remaining
            backlogDueCount = backlog.count
            totalDueBacklogCount = backlog.count
            deferredDueCount = backlog.count - available.count
            eligibleCardCount = day.library.cards.count
            duplicateCardCount = day.library.canonicalIDs.count - day.library.cards.count
            dueCards = available
            totalDueCount = available.count
            var cache: [String: Int] = [:]
            for card in available {
                if let id = card.subject?.id.uuidString { cache[id, default: 0] += 1 }
            }
            dueCountCache = cache
            lastRefreshError = nil
        } catch {
            // Do not offer more reviews when the allowance cannot be checked.
            dueCards = []
            totalDueCount = 0
            dueCountCache = [:]
            remainingDailyAllowance = 0
            lastRefreshError = "Could not load today's review allowance: \(error.localizedDescription)"
        }
    }

    func cardsForReview(from candidates: [StudyCard], context: ModelContext) -> [StudyCard] {
        do { return try ReviewDailyLimitPolicy.day(in: context).limited(candidates) }
        catch {
            lastRefreshError = "Could not load today's review allowance: \(error.localizedDescription)"
            return []
        }
    }

    func dueCount(for subject: Subject) -> Int { dueCountCache[subject.id.uuidString] ?? 0 }

    func dueCardsForSubject(_ subject: Subject, context: ModelContext) -> [StudyCard] {
        do {
            let day = try ReviewDailyLimitPolicy.day(in: context)
            return day.limited(day.backlog.filter { $0.subject?.id == subject.id })
        } catch {
            lastRefreshError = "Could not load today's review allowance: \(error.localizedDescription)"
            return []
        }
    }

    func dueCountPerSubject() -> [String: Int] { dueCountCache }
    func eligibleCardsCount() -> Int { eligibleCardCount }

    func eligibleCards(context: ModelContext) -> [StudyCard] {
        guard let cards = try? context.fetch(FetchDescriptor<StudyCard>()) else { return [] }
        return CardDuplicatePolicy.library(cards.filter(BiologyStudyService.isEligible)).cards
    }

    /// Retained for existing tests; snapshots now recompute when data changes.
    func resetFingerprintForTesting() {}
}
