import Testing
import Foundation
import SwiftData
@testable import IBVault

@Suite("ReviewQueueManager Tests")
struct ReviewQueueManagerTests {
    
    @MainActor
    @Test("dueCount should return correct count of due cards for a given subject")
    func testDueCountForSubject() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: StudyCard.self, Subject.self, StudySession.self, UserProfile.self, configurations: config)
        let context = container.mainContext
        
        let subject1 = Subject(name: "Mathematics", level: "HL", accentColorHex: "#FF0000")
        let subject2 = Subject(name: "Physics", level: "HL", accentColorHex: "#0000FF")
        context.insert(subject1)
        context.insert(subject2)
        
        let now = Date()
        let past = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let future = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        
        let card1 = StudyCard(topicName: "Calculus", front: "Front 1", back: "Back 1", subject: subject1)
        card1.nextReviewDate = past
        
        let card2 = StudyCard(topicName: "Algebra", front: "Front 2", back: "Back 2", subject: subject1)
        card2.nextReviewDate = future
        
        let card3 = StudyCard(topicName: "Mechanics", front: "Front 3", back: "Back 3", subject: subject2)
        card3.nextReviewDate = past
        
        context.insert(card1)
        context.insert(card2)
        context.insert(card3)
        
        let manager = ReviewQueueManager()
        manager.refreshDueCardsSynchronously(context: context)
        
        #expect(manager.dueCount(for: subject1) == 1)
        #expect(manager.dueCount(for: subject2) == 1)
        #expect(manager.dueCards.count == 2)
    }

    @MainActor
    @Test("dueCardsForSubject falls back to all subject cards when no study scope exists")
    func testDueCardsForSubjectWithoutStudyScopes() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: StudyCard.self, Subject.self, StudySession.self, UserProfile.self, configurations: config)
        let context = container.mainContext

        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "#10B981")
        context.insert(subject)

        let past = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let future = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let dueCard = StudyCard(topicName: "Cells", front: "Front", back: "Back", subject: subject)
        dueCard.nextReviewDate = past
        let futureCard = StudyCard(topicName: "Genetics", front: "Front", back: "Back", subject: subject)
        futureCard.nextReviewDate = future

        context.insert(dueCard)
        context.insert(futureCard)

        let manager = ReviewQueueManager()
        let dueCards = manager.dueCardsForSubject(subject, context: context)

        #expect(dueCards.map(\.id) == [dueCard.id])
    }

    @MainActor
    @Test("eligibleCardsCount should return exact count of study cards when studied scopes are empty")
    func testEligibleCardsCountWithoutStudySessions() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: StudyCard.self, Subject.self, StudySession.self, UserProfile.self, configurations: config)
        let context = container.mainContext
        
        let card1 = StudyCard(topicName: "Calculus", front: "Front 1", back: "Back 1")
        let card2 = StudyCard(topicName: "Algebra", front: "Front 2", back: "Back 2")
        context.insert(card1)
        context.insert(card2)
        
        let manager = ReviewQueueManager()
        manager.refreshDueCardsSynchronously(context: context)
        let eligibleCount = manager.eligibleCardsCount()
        
        #expect(eligibleCount == 2)
    }

    @MainActor
    @Test("A successful refresh clears the error flag and caches all due counts")
    func testSuccessfulRefreshCachesCounts() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: StudyCard.self, Subject.self, StudySession.self, UserProfile.self, configurations: config)
        let context = container.mainContext

        let subject1 = Subject(name: "Biology", level: "SL", accentColorHex: "#10B981")
        let subject2 = Subject(name: "Physics", level: "HL", accentColorHex: "#3B82F6")
        context.insert(subject1)
        context.insert(subject2)

        let now = Date()
        let past = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let future = Calendar.current.date(byAdding: .day, value: 1, to: now)!

        let due1 = StudyCard(topicName: "Cells", front: "F", back: "B", subject: subject1)
        due1.nextReviewDate = past
        let due2a = StudyCard(topicName: "Mechanics", front: "F", back: "B", subject: subject2)
        due2a.nextReviewDate = past
        let due2b = StudyCard(topicName: "Waves", front: "F", back: "B", subject: subject2)
        due2b.nextReviewDate = past
        let notDue = StudyCard(topicName: "Optics", front: "F", back: "B", subject: subject2)
        notDue.nextReviewDate = future
        context.insert(due1)
        context.insert(due2a)
        context.insert(due2b)
        context.insert(notDue)
        try context.save()

        let manager = ReviewQueueManager()
        manager.refreshDueCardsSynchronously(context: context)

        // A successful refresh never leaves a stale error flag.
        #expect(manager.lastRefreshError == nil)
        #expect(manager.dueCards.count == 3)
        #expect(manager.totalDueCount == 3)
        // The eligible-card cache counts the whole pool, including not-yet-due.
        #expect(manager.eligibleCardCount == 4)
        #expect(manager.dueCount(for: subject1) == 1)
        #expect(manager.dueCount(for: subject2) == 2)
        #expect(manager.dueCountPerSubject()[subject2.id.uuidString] == 2)
    }

    @MainActor
    @Test("All due cards remain available regardless of the profile daily goal")
    func allDueCardsRemainAvailable() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: StudyCard.self,
            Subject.self,
            StudySession.self,
            ReviewSession.self,
            UserProfile.self,
            configurations: config
        )
        let context = container.mainContext
        let profile = UserProfile()
        profile.dailyGoal = 18
        context.insert(profile)

        let past = Date().addingTimeInterval(-3600)
        for index in 0..<56 {
            let card = StudyCard(topicName: "Topic", front: "Question \(index)", back: "Answer \(index)")
            card.nextReviewDate = past
            context.insert(card)
        }
        try context.save()

        let manager = ReviewQueueManager()
        manager.refreshDueCardsSynchronously(context: context)

        #expect(manager.totalDueBacklogCount == 56)
        #expect(manager.dueCards.count == 56)
        #expect(manager.deferredDueCount == 0)
    }
}

@Suite("Daily Review Limit Policy")
struct ReviewDailyLimitPolicyTests {
    @Test("Daily maximum adapts to study intensity and respects a lower personal goal")
    func adaptsDailyMaximum() {
        #expect(ReviewDailyLimitPolicy.maximumCards(for: .belowAverage) == 15)
        #expect(ReviewDailyLimitPolicy.maximumCards(for: .average) == 20)
        #expect(ReviewDailyLimitPolicy.maximumCards(for: .aboveAverage) == 25)
        #expect(ReviewDailyLimitPolicy.maximumCards(for: .intensive) == 30)
        #expect(ReviewDailyLimitPolicy.maximumCards(for: .intensive, dailyGoal: 10) == 10)
        #expect(ReviewDailyLimitPolicy.maximumCards(for: .belowAverage, dailyGoal: 30) == 15)
    }

    @Test("Daily queue caps unique cards and excludes cards already reviewed today")
    func capsDailyQueue() {
        let cards = (0..<45).map { index in
            StudyCard(topicName: "Topic", front: "Question \(index)", back: "Answer \(index)")
        }
        let alreadyReviewed = Set(cards.prefix(7).map(\.id))

        let limited = ReviewDailyLimitPolicy.limitedCards(cards, reviewedCardIDs: alreadyReviewed)

        #expect(limited.count == 23)
        #expect(limited.allSatisfy { !alreadyReviewed.contains($0.id) })
        #expect(ReviewDailyLimitPolicy.allowance(reviewedCardIDs: alreadyReviewed) == 23)
    }
}

@Suite("Review Queue Recovery")
struct ReviewQueueRecoveryTests {
    @MainActor
    @Test("refresh exposes all due cards")
    func refreshExposesAllDueCards() throws {
        let container = try ModelContainer(for: StudyCard.self, Subject.self, StudySession.self, UserProfile.self, configurations: .init(isStoredInMemoryOnly: true))
        let context = container.mainContext
        for index in 0..<3 {
            let card = StudyCard(topicName: "Topic", front: "Q\(index)", back: "A\(index)")
            card.nextReviewDate = Date.distantPast
            context.insert(card)
        }
        let manager = ReviewQueueManager()
        manager.refreshDueCardsSynchronously(context: context)
        #expect(manager.totalDueBacklogCount == 3)
    }

    @Test("daily allowance never hides backlog")
    func dailyAllowancePreservesBacklog() {
        #expect(ReviewDailyLimitPolicy.allowance(reviewedCardIDs: Set(), maximum: 30) == 30)
        #expect(ReviewDailyLimitPolicy.allowance(reviewedCardIDs: Set(repeating: UUID(), count: 0), maximum: 30) == 30)
    }

    @Test("intensity caps remain bounded")
    func intensityCapsRemainBounded() {
        #expect(ReviewDailyLimitPolicy.maximumCards(for: .intensive) == 30)
        #expect(ReviewDailyLimitPolicy.maximumCards(for: .belowAverage, dailyGoal: 100) == 15)
    }

    @Test("limited cards preserve source order")
    func limitedCardsPreserveSourceOrder() {
        let cards = (0..<3).map { StudyCard(topicName: "Topic", front: "Q\($0)", back: "A\($0)") }
        let limited = ReviewDailyLimitPolicy.limitedCards(cards, reviewedCardIDs: [], maximum: 2)
        #expect(limited.map(\.front) == ["Q0", "Q1"])
    }

    @Test("zero allowance returns no cards")
    func zeroAllowanceReturnsNoCards() {
        let card = StudyCard(topicName: "Topic", front: "Q", back: "A")
        #expect(ReviewDailyLimitPolicy.limitedCards([card], reviewedCardIDs: [], maximum: 0).isEmpty)
    }
}
