import Foundation
import SwiftData

@MainActor
@Observable
final class ReviewQueueManager {
    // MARK: - Published State
    private(set) var dueCards: [StudyCard] = []
    private(set) var totalDueCount: Int = 0

    // O(1) per-subject due count cache: keyed by subject UUID string
    private(set) var dueCountCache: [String: Int] = [:]

    private var isRefreshing = false

    private struct ScopeIndex {
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
            applyDueCardsSnapshot(filtered)
        } catch {
            applyDueCardsSnapshot([])
        }
    }

    // MARK: - O(1) Due Count Lookup
    func dueCount(for subject: Subject) -> Int {
        dueCountCache[subject.id.uuidString] ?? 0
    }

    // MARK: - Subject-scoped due cards (for ReviewSession)
    func dueCardsForSubject(_ subject: Subject, context: ModelContext) -> [StudyCard] {
        let now = Date()
        let studiedScopes = fetchStudiedScopes(in: context).filter { $0.subjectName == subject.name }
        let scopeIndex = ScopeIndex(scopes: studiedScopes)

        if scopeIndex.isEmpty {
            return subject.cards
                .filter { $0.nextReviewDate <= now }
                .sorted { $0.nextReviewDate < $1.nextReviewDate }
        }

        return filterCardsToScopes(subject.cards, matching: scopeIndex)
            .filter { $0.nextReviewDate <= now }
            .sorted { $0.nextReviewDate < $1.nextReviewDate }
    }

    func overdueCards(context: ModelContext) -> [StudyCard] {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        return dueCards.filter { $0.nextReviewDate < yesterday }
    }

    func dueCountPerSubject() -> [String: Int] {
        dueCountCache
    }

    func upcomingCards(context: ModelContext, days: Int = 7) -> [StudyCard] {
        let now = Date()
        let future = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        let predicate = #Predicate<StudyCard> {
            $0.nextReviewDate > now && $0.nextReviewDate <= future
        }
        var descriptor = FetchDescriptor<StudyCard>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.nextReviewDate)]

        do {
            let scopeIndex = ScopeIndex(scopes: fetchStudiedScopes(in: context))
            let fetched = try context.fetch(descriptor)
            if scopeIndex.isEmpty { return fetched }
            return filterCardsToScopes(fetched, matching: scopeIndex)
        } catch {
            return []
        }
    }

    func eligibleCardsCount(context: ModelContext) -> Int {
        let studied = fetchStudiedScopes(in: context)
        if studied.isEmpty {
            return (try? context.fetchCount(FetchDescriptor<StudyCard>())) ?? 0
        }
        return eligibleCards(context: context).count
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

    @MainActor
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

    private func filterCardsToScopes(_ cards: [StudyCard], matching scopes: [StudyScope]) -> [StudyCard] {
        guard !scopes.isEmpty else { return [] }
        return filterCardsToScopes(cards, matching: ScopeIndex(scopes: scopes))
    }

    private func filterCardsToScopes(_ cards: [StudyCard], matching scopeIndex: ScopeIndex) -> [StudyCard] {
        guard !scopeIndex.isEmpty else { return [] }
        return cards.filter { scopeIndex.matches($0) }
    }

    // Keep old name so callers continue to compile
    private func studiedScopes(in context: ModelContext) -> [StudyScope] {
        fetchStudiedScopes(in: context)
    }
}
