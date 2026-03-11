import Foundation
import SwiftData

@Observable
class ReviewQueueManager {
    var dueCards: [StudyCard] = []
    var totalDueCount: Int = 0

    func loadDueCards(context: ModelContext) {
        let now = Date()
        let predicate = #Predicate<StudyCard> { card in
            card.nextReviewDate <= now
        }
        var descriptor = FetchDescriptor<StudyCard>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.nextReviewDate, order: .forward)]

        do {
            dueCards = try context.fetch(descriptor)
            totalDueCount = dueCards.count
        } catch {
            print("Failed to fetch due cards: \(error)")
            dueCards = []
            totalDueCount = 0
        }
    }

    func dueCardsForSubject(_ subject: Subject) -> [StudyCard] {
        let now = Date()
        return subject.cards.filter { $0.nextReviewDate <= now }
            .sorted { $0.nextReviewDate < $1.nextReviewDate }
    }

    func overdueCards(context: ModelContext) -> [StudyCard] {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        return dueCards.filter { $0.nextReviewDate < yesterday }
    }

    func dueCountPerSubject(context: ModelContext) -> [String: Int] {
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
        let predicate = #Predicate<StudyCard> { card in
            card.nextReviewDate > now && card.nextReviewDate <= future
        }
        var descriptor = FetchDescriptor<StudyCard>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.nextReviewDate)]

        do {
            return try context.fetch(descriptor)
        } catch {
            return []
        }
    }
}
