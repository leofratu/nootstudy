import Testing
import Foundation
import SwiftData
@testable import IBVault

@Suite("ReviewScheduler Tests")
struct ReviewSchedulerTests {

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Subject.self,
            StudyCard.self,
            StudySession.self,
            UserProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @MainActor
    @Test("analyze does not crash on an empty store and reports zero load")
    func analyzeEmptyStoreDoesNotCrash() throws {
        let container = try makeContainer()
        let scheduler = ReviewScheduler()

        scheduler.analyze(context: container.mainContext)

        #expect(scheduler.schedules.isEmpty)
        #expect(scheduler.totalDueToday == 0)
        #expect(scheduler.totalOverdue == 0)
        #expect(scheduler.recommendedStudyOrder.isEmpty)
    }

    @MainActor
    @Test("analyze tolerates a subject with no cards")
    func analyzeSubjectWithNoCards() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(Subject(name: "Biology", level: "HL", accentColorHex: "#10B981"))
        try context.save()

        let scheduler = ReviewScheduler()
        scheduler.analyze(context: context)

        // No due cards, so no schedule row and no NaN anywhere.
        #expect(scheduler.schedules.isEmpty)
        #expect(scheduler.totalDueToday == 0)
        #expect(scheduler.totalOverdue == 0)
    }

    @MainActor
    @Test("cardsDueToday orders by review date first, then ease factor")
    func cardsDueTodayOrdersByDateThenEaseFactor() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let subject = Subject(name: "Biology", level: "HL", accentColorHex: "#10B981")
        context.insert(subject)

        let now = Date()
        let earlier = Calendar.current.date(byAdding: .day, value: -2, to: now)!
        let later = Calendar.current.date(byAdding: .day, value: -1, to: now)!

        // Same later date: ease factor decides (2.5 before 1.1 is WRONG, so
        // expectation proves ease ordering is applied).
        let highEase = StudyCard(topicName: "Metabolism", front: "High ease", back: "a", subject: subject)
        highEase.nextReviewDate = later
        highEase.easeFactor = 2.5
        let lowEase = StudyCard(topicName: "Cells", front: "Low ease", back: "b", subject: subject)
        lowEase.nextReviewDate = later
        lowEase.easeFactor = 1.1

        let earlierCard = StudyCard(topicName: "Genetics", front: "Earlier", back: "c", subject: subject)
        earlierCard.nextReviewDate = earlier
        earlierCard.easeFactor = 3.0

        let notDue = StudyCard(topicName: "Ecology", front: "Future", back: "d", subject: subject)
        notDue.nextReviewDate = now.addingTimeInterval(86_400)

        context.insert(highEase)
        context.insert(lowEase)
        context.insert(earlierCard)
        context.insert(notDue)
        try context.save()

        let scheduler = ReviewScheduler()
        let due = scheduler.cardsDueToday(for: subject, context: context)

        // Earlier date first, then the later-date pair ordered by ease factor.
        let expectedIDs: [UUID] = [earlierCard.id, lowEase.id, highEase.id]
        #expect(due.map(\.id) == expectedIDs)
        #expect(!due.contains(where: { $0.id == notDue.id }))
    }

    @MainActor
    @Test("cardsDueToday ordering is a consistent total order across many cards")
    func cardsDueTodayIsATotalOrder() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let subject = Subject(name: "Physics", level: "SL", accentColorHex: "#0000FF")
        context.insert(subject)

        // Deterministic matrix of review dates and ease factors, no Date() jitter.
        let base = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
        var cards: [StudyCard] = []
        for i in 0..<12 {
            let card = StudyCard(topicName: "Unit", front: "F\(i)", back: "B\(i)", subject: subject)
            card.nextReviewDate = base.addingTimeInterval(Double(i % 4) * 3600)
            card.easeFactor = 1.0 + Double((i * 7) % 10) / 5.0
            context.insert(card)
            cards.append(card)
        }
        try context.save()

        let scheduler = ReviewScheduler()
        let due = scheduler.cardsDueToday(for: subject, context: context)
        #expect(due.count == cards.count)

        let shouldPrecede: (StudyCard, StudyCard) -> Bool = { lhs, rhs in
            if lhs.nextReviewDate != rhs.nextReviewDate {
                return lhs.nextReviewDate < rhs.nextReviewDate
            }
            return lhs.easeFactor < rhs.easeFactor
        }

        // Adjacent pairs are correctly ordered...
        for i in 0..<(due.count - 1) {
            #expect(shouldPrecede(due[i], due[i + 1]),
                    "adjacent pair \(i) out of order: \(due[i].nextReviewDate)/\(due[i].easeFactor)")
        }
        // ...and the produced order is transitive (a valid total order for the
        // comparator), so sorting can never leave an inconsistent permutation.
        for i in 0..<due.count {
            for j in (i + 1)..<due.count {
                #expect(shouldPrecede(due[i], due[j]),
                        "pair (\(i), \(j)) violates the comparator's total order")
            }
        }
    }
}
