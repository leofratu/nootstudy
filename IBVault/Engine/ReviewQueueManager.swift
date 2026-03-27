import Foundation
import SwiftData

@Observable
final class ReviewQueueManager: @unchecked Sendable {
    private(set) var dueCards: [StudyCard] = []
    private(set) var totalDueCount: Int = 0
    
    private let lock = NSLock()
    
    func loadDueCards(context: ModelContext) {
        lock.lock()
        defer { lock.unlock() }
        
        let now = Date()
        let predicate = #Predicate<StudyCard> { $0.nextReviewDate <= now }
        var descriptor = FetchDescriptor<StudyCard>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.nextReviewDate, order: .forward)]
        
        do {
            let studiedScopes = self.studiedScopes(in: context)
            guard !studiedScopes.isEmpty else {
                dueCards = []
                totalDueCount = 0
                return
            }
            
            dueCards = filterCardsToScopes(
                try context.fetch(descriptor),
                matching: studiedScopes
            )
            totalDueCount = dueCards.count
        } catch {
            dueCards = []
            totalDueCount = 0
        }
    }
    
    func dueCardsForSubject(_ subject: Subject, context: ModelContext) -> [StudyCard] {
        let now = Date()
        let studiedScopes = self.studiedScopes(in: context).filter { $0.subjectName == subject.name }
        
        return filterCardsToScopes(subject.cards, matching: studiedScopes)
            .filter { $0.nextReviewDate <= now }
            .sorted { $0.nextReviewDate < $1.nextReviewDate }
    }
    
    func overdueCards(context: ModelContext) -> [StudyCard] {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        return dueCards.filter { $0.nextReviewDate < yesterday }
    }
    
    func dueCountPerSubject() -> [String: Int] {
        var counts: [String: Int] = [:]
        for card in dueCards {
            let name = card.subject?.name ?? "Unknown"
            counts[name, default: 0] += 1
        }
        return counts
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
            return filterCardsToScopes(
                try context.fetch(descriptor),
                matching: studiedScopes(in: context)
            )
        } catch {
            return []
        }
    }
    
    func refreshDueCards(context: ModelContext) {
        loadDueCards(context: context)
    }
    
    private func studiedScopes(in context: ModelContext) -> [StudyScope] {
        let sessions = (try? context.fetch(FetchDescriptor<StudySession>())) ?? []
        return StudySession.uniqueStudyScopes(from: sessions)
    }
    
    private func filterCardsToScopes(_ cards: [StudyCard], matching scopes: [StudyScope]) -> [StudyCard] {
        guard !scopes.isEmpty else { return [] }
        return cards.filter { card in
            scopes.contains { $0.matches(card) }
        }
    }
}