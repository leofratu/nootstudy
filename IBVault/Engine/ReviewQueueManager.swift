import Foundation
import SwiftData

@Observable
class ReviewQueueManager {
    var dueCards: [StudyCard] = []
    var totalDueCount: Int = 0

    private func studiedScopes(in context: ModelContext) -> [StudyScope] {
        let sessions = (try? context.fetch(FetchDescriptor<StudySession>())) ?? []
        return StudySession.uniqueStudyScopes(from: sessions)
    }

    private func cards(_ cards: [StudyCard], matching scopes: [StudyScope]) -> [StudyCard] {
        guard !scopes.isEmpty else { return [] }
        return cards.filter { card in
            scopes.contains { $0.matches(card) }
        }
    }

    func loadDueCards(context: ModelContext) {
        let now = Date()
        let predicate = #Predicate<StudyCard> { card in
            card.nextReviewDate <= now
        }
        var descriptor = FetchDescriptor<StudyCard>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.nextReviewDate, order: .forward)]

        do {
            let studiedScopes = studiedScopes(in: context)
            guard !studiedScopes.isEmpty else {
                dueCards = []
                totalDueCount = 0
                return
            }

            dueCards = cards(try context.fetch(descriptor), matching: studiedScopes)
            totalDueCount = dueCards.count
        } catch {
            print("Failed to fetch due cards: \(error)")
            dueCards = []
            totalDueCount = 0
        }
    }

    func dueCardsForSubject(_ subject: Subject, context: ModelContext) -> [StudyCard] {
        let now = Date()
        let studiedScopes = studiedScopes(in: context).filter { $0.subjectName == subject.name }
        return cards(subject.cards, matching: studiedScopes)
            .filter { $0.nextReviewDate <= now }
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
            return cards(try context.fetch(descriptor), matching: studiedScopes(in: context))
        } catch {
            return []
        }
    }
}
