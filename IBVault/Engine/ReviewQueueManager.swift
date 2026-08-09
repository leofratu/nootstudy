import Foundation
import SwiftData

nonisolated enum ReviewDailyLimitPolicy: Sendable {
    static let maximumCards = 30

    static func maximumCards(for intensity: StudyIntensity) -> Int {
        min(intensity.dailyCardSuggestion, maximumCards)
    }

    static func maximumCards(for intensity: StudyIntensity, dailyGoal: Int) -> Int {
        min(max(dailyGoal, 1), maximumCards(for: intensity))
    }

    static func allowance(reviewedCardIDs: Set<UUID>, maximum: Int = maximumCards) -> Int {
        max(0, maximum - reviewedCardIDs.count)
    }

    static func limitedCards(_ cards: [StudyCard], reviewedCardIDs: Set<UUID>, maximum: Int = maximumCards) -> [StudyCard] {
        let remaining = allowance(reviewedCardIDs: reviewedCardIDs, maximum: maximum)
        return Array(cards.filter { !reviewedCardIDs.contains($0.id) }.prefix(remaining))
    }
}

@MainActor
@Observable
final class ReviewQueueManager {
    // MARK: - Published State
    private(set) var dueCards: [StudyCard] = []
    private(set) var totalDueCount: Int = 0
    private(set) var backlogDueCount: Int = 0
    private(set) var deferredDueCount: Int = 0
    private(set) var reviewedTodayCount: Int = 0
    private(set) var remainingDailyAllowance: Int = ReviewDailyLimitPolicy.maximumCards

    // O(1) per-subject due count cache: keyed by subject UUID string
    private(set) var dueCountCache: [String: Int] = [:]

    // O(1) eligible-card count refreshed alongside the due snapshot
    private(set) var eligibleCardCount: Int = 0

    // Set when a store refresh fails. Keeps a broken store from being reported
    // as "0 due": the last good snapshot stays in place instead of being cleared.
    private(set) var lastRefreshError: String?

    private var isRefreshing = false

    private struct ScopeIndex: Sendable {
        let scopesBySubject: [String: [StudyScope]]

        init(scopes: [StudyScope]) {
            scopesBySubject = Dictionary(grouping: scopes, by: \.subjectName)
        }

        var isEmpty: Bool {
            scopesBySubject.isEmpty
        }

        func matches(_ card: StudyCard) -> Bool {
            guard let subjectName = card.subject?.name,
                  let scopes = scopesBySubject[subjectName] else { return false }
            return scopes.contains { $0.matches(card) }
        }
    }

    // MARK: - Refresh
    func refreshDueCards(context: ModelContext) {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        refreshDueCardsSynchronously(context: context)
    }

    // Convenience alias
    func loadDueCards(context: ModelContext) {
        refreshDueCards(context: context)
    }

    func refreshDueCardsSynchronously(context: ModelContext) {
        let now = Date()
        let predicate = #Predicate<StudyCard> { $0.nextReviewDate <= now }
        var descriptor = FetchDescriptor<StudyCard>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.nextReviewDate, order: .forward)]

        do {
            let studiedScopes = fetchStudiedScopes(in: context)
            let fetched = try context.fetch(descriptor)
            let scopeIndex = ScopeIndex(scopes: studiedScopes)
            let filtered = scopeIndex.isEmpty ? fetched : filterCardsToScopes(fetched, matching: scopeIndex)
            let reviewedIDs = reviewedCardIDsToday(in: context)
            let dailyMaximum = dailyMaximum(in: context)
            let available = ReviewDailyLimitPolicy.limitedCards(
                filtered,
                reviewedCardIDs: reviewedIDs,
                maximum: dailyMaximum
            )
            lastRefreshError = nil
            reviewedTodayCount = reviewedIDs.count
            remainingDailyAllowance = ReviewDailyLimitPolicy.allowance(
                reviewedCardIDs: reviewedIDs,
                maximum: dailyMaximum
            )
            backlogDueCount = filtered.filter { !reviewedIDs.contains($0.id) }.count
            deferredDueCount = max(0, backlogDueCount - available.count)
            applyDueCardsSnapshot(available)

            // Cache the eligible pool count here (once per refresh) instead of
            // letting views run a full unfiltered fetch inside their body.
            if studiedScopes.isEmpty {
                eligibleCardCount = (try? context.fetchCount(FetchDescriptor<StudyCard>())) ?? 0
            } else {
                let all = (try? context.fetch(FetchDescriptor<StudyCard>())) ?? []
                eligibleCardCount = filterCardsToScopes(all, matching: scopeIndex).count
            }
        } catch {
            // Do not clear the queue: the previous snapshot is a better answer
            // than a fabricated "0 due". Views may ignore the error, but the
            // reported counts stay honest.
            lastRefreshError = "Review queue refresh failed: \(error.localizedDescription)"
        }
    }

    // MARK: - O(1) Due Count Lookup
    func dueCount(for subject: Subject) -> Int {
        dueCountCache[subject.id.uuidString] ?? 0
    }

    // MARK: - Subject-scoped due cards (for ReviewSession)
    func dueCardsForSubject(_ subject: Subject, context: ModelContext) -> [StudyCard] {
        let now = Date()
        let reviewedIDs = reviewedCardIDsToday(in: context)
        let dailyMaximum = dailyMaximum(in: context)
        let studiedScopes = fetchStudiedScopes(in: context).filter { $0.subjectName == subject.name }
        let scopeIndex = ScopeIndex(scopes: studiedScopes)

        if scopeIndex.isEmpty {
            let due = subject.cards
                .filter { $0.nextReviewDate <= now }
                .sorted { $0.nextReviewDate < $1.nextReviewDate }
            return ReviewDailyLimitPolicy.limitedCards(
                due,
                reviewedCardIDs: reviewedIDs,
                maximum: dailyMaximum
            )
        }

        let due = filterCardsToScopes(subject.cards, matching: scopeIndex)
            .filter { $0.nextReviewDate <= now }
            .sorted { $0.nextReviewDate < $1.nextReviewDate }
        return ReviewDailyLimitPolicy.limitedCards(
            due,
            reviewedCardIDs: reviewedIDs,
            maximum: dailyMaximum
        )
    }

    func dueCountPerSubject() -> [String: Int] {
        dueCountCache
    }

    /// O(1) eligible-card count computed during `refreshDueCardsSynchronously`,
    /// so views never run a full unfiltered fetch inside their body.
    func eligibleCardsCount() -> Int {
        eligibleCardCount
    }

    func eligibleCards(context: ModelContext) -> [StudyCard] {
        let studied = fetchStudiedScopes(in: context)
        let all = (try? context.fetch(FetchDescriptor<StudyCard>())) ?? []
        if studied.isEmpty { return all }
        return filterCardsToScopes(all, matching: ScopeIndex(scopes: studied))
    }

    // MARK: - Private helpers
    private func fetchStudiedScopes(in context: ModelContext) -> [StudyScope] {
        let sessions = (try? context.fetch(FetchDescriptor<StudySession>())) ?? []
        return StudySession.uniqueStudyScopes(from: sessions)
    }

    private func reviewedCardIDsToday(in context: ModelContext) -> Set<UUID> {
        let start = IBLocalClock.calendar.startOfDay(for: IBLocalClock.now)
        let predicate = #Predicate<ReviewSession> { $0.timestamp >= start }
        let reviews = (try? context.fetch(FetchDescriptor<ReviewSession>(predicate: predicate))) ?? []
        return Set(reviews.lazy.map(\.cardID))
    }

    private func dailyMaximum(in context: ModelContext) -> Int {
        let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
        guard let profile else {
            return ReviewDailyLimitPolicy.maximumCards(for: .average)
        }
        return ReviewDailyLimitPolicy.maximumCards(
            for: profile.studyIntensity,
            dailyGoal: profile.dailyGoal
        )
    }

    private func applyDueCardsSnapshot(_ cards: [StudyCard]) {
        var cache: [String: Int] = [:]
        for card in cards {
            if let subjectID = card.subject?.id.uuidString {
                cache[subjectID, default: 0] += 1
            }
        }

        dueCards = cards
        totalDueCount = cards.count
        dueCountCache = cache
    }

    private func filterCardsToScopes(_ cards: [StudyCard], matching scopeIndex: ScopeIndex) -> [StudyCard] {
        guard !scopeIndex.isEmpty else { return [] }
        return cards.filter { scopeIndex.matches($0) }
    }
}
