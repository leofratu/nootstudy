import Foundation
import os
import SwiftData

nonisolated enum ReviewDailyLimitPolicy: Sendable {
    static let maximumCards = 40

    static func maximumCards(for intensity: StudyIntensity) -> Int {
        min(intensity.dailyCardSuggestion, maximumCards)
    }

    static func maximumCards(for intensity: StudyIntensity, dailyGoal: Int) -> Int {
        // Intensity supplies a suggestion; an explicitly saved goal is the
        // actual allowance, still bounded by the app-wide daily maximum.
        min(max(dailyGoal, 1), maximumCards)
    }

    static func allowance(reviewedCardIDs: Set<UUID>, maximum: Int = maximumCards) -> Int {
        max(0, min(maximumCards, maximum) - reviewedCardIDs.count)
    }

    static func limitedCards(_ cards: [StudyCard], reviewedCardIDs: Set<UUID>, maximum: Int = maximumCards) -> [StudyCard] {
        let remaining = allowance(reviewedCardIDs: reviewedCardIDs, maximum: maximum)
        guard remaining > 0 else { return [] }
        var seen = reviewedCardIDs
        var result: [StudyCard] = []
        for card in cards where seen.insert(card.id).inserted {
            result.append(card)
            if result.count == remaining { break }
        }
        return result
    }

    struct Day {
        let library: CardDuplicatePolicy.Library
        let reviewedIDs: Set<UUID>
        let reviewedCanonicalIDs: Set<UUID>
        let maximum: Int
        let now: Date

        var remaining: Int { allowance(reviewedCardIDs: reviewedIDs, maximum: maximum) }

        var backlog: [StudyCard] {
            library.cards.filter { $0.nextReviewDate <= now && !reviewedCanonicalIDs.contains($0.id) }
                .sorted {
                    if $0.nextReviewDate != $1.nextReviewDate { return $0.nextReviewDate < $1.nextReviewDate }
                    if $0.easeFactor != $1.easeFactor { return $0.easeFactor < $1.easeFactor }
                    return $0.id.uuidString < $1.id.uuidString
                }
        }

        func limited(_ candidates: [StudyCard]) -> [StudyCard] {
            let limit = remaining
            guard limit > 0 else { return [] }
            var seen = reviewedCanonicalIDs
            var unique: [StudyCard] = []
            for card in candidates {
                let canonicalID = library.canonicalIDs[card.id] ?? card.id
                guard canonicalID == card.id && seen.insert(canonicalID).inserted else { continue }
                unique.append(card)
                if unique.count == limit { break }
            }
            return unique
        }

        func canReview(_ card: StudyCard) -> Bool {
            remaining > 0 && !reviewedCanonicalIDs.contains(library.canonicalIDs[card.id] ?? card.id)
        }
    }

    @MainActor
    static func day(in context: ModelContext, now: Date = IBLocalClock.now,
                    calendar: Calendar = IBLocalClock.calendar) throws -> Day {
        let all = try context.fetch(FetchDescriptor<StudyCard>())
        let library = CardDuplicatePolicy.library(all)
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
    private(set) var newCardCount = 0
    private(set) var lastRefreshError: String?
    private var isRefreshing = false
    private var hasLoaded = false
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    /// Reuse the shared snapshot on page entry; saves and day changes refresh it.
    func ensureLoaded(context: ModelContext) {
        guard !hasLoaded else { return }
        refreshDueCards(context: context)
    }

    func scheduleRefresh(context: ModelContext) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(120)) }
            catch { return }
            guard let self else { return }
            self.refreshTask = nil
            self.refreshDueCards(context: context)
        }
    }

    func refreshDueCards(context: ModelContext) {
        let state = PerformanceSignposts.signposter.beginInterval("reviewQueue.refresh")
        defer { PerformanceSignposts.signposter.endInterval("reviewQueue.refresh", state) }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        refreshDueCardsSynchronously(context: context)
    }

    func loadDueCards(context: ModelContext) { refreshDueCards(context: context) }

    @discardableResult
    func refreshDueCardsSynchronously(context: ModelContext) -> ReviewDailyLimitPolicy.Day? {
        refreshTask?.cancel()
        refreshTask = nil
        do {
            let day = try ReviewDailyLimitPolicy.day(in: context)
            apply(day)
            return day
        } catch {
            // Do not offer more reviews when the allowance cannot be checked.
            dueCards = []
            totalDueCount = 0
            dueCountCache = [:]
            remainingDailyAllowance = 0
            lastRefreshError = "Could not load today's review allowance: \(error.localizedDescription)"
            hasLoaded = false
            return nil
        }
    }

    /// Called immediately after a review is inserted on the main actor. Reuse
    /// the allowance just checked, avoiding a second full-store fetch/dedup.
    func recordReview(of card: StudyCard, checkedDay day: ReviewDailyLimitPolicy.Day) {
        var reviewed = day.reviewedIDs
        reviewed.insert(card.id)
        var canonical = day.reviewedCanonicalIDs
        canonical.insert(day.library.canonicalIDs[card.id] ?? card.id)
        apply(.init(library: day.library, reviewedIDs: reviewed, reviewedCanonicalIDs: canonical,
                    maximum: day.maximum, now: day.now))
    }

    private func apply(_ day: ReviewDailyLimitPolicy.Day) {
        let backlog = day.backlog
        let available = day.limited(backlog)
        reviewedTodayCount = day.reviewedIDs.count
        dailyMaximum = day.maximum
        remainingDailyAllowance = day.remaining
        backlogDueCount = backlog.count
        totalDueBacklogCount = backlog.count
        deferredDueCount = backlog.count - available.count
        eligibleCardCount = day.library.cards.count
        newCardCount = day.library.cards.lazy.filter { $0.totalReviewCount == 0 }.count
        duplicateCardCount = day.library.canonicalIDs.count - day.library.cards.count
        dueCards = available
        totalDueCount = available.count
        var cache: [String: Int] = [:]
        for card in available {
            if let id = card.subject?.id.uuidString { cache[id, default: 0] += 1 }
        }
        dueCountCache = cache
        lastRefreshError = nil
        hasLoaded = true
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
        return CardDuplicatePolicy.library(cards).cards
    }

    /// Retained for existing tests; snapshots now recompute when data changes.
    func resetFingerprintForTesting() {}
}
