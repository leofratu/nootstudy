import Testing
import Foundation

@testable import IBVault

@Suite("ProficiencyTracker Tests")
struct ProficiencyTrackerTests {
    
    @Test("Empty cards should return zero mastery")
    func testEmptyCardsMastery() {
        let mastery = calculateMasteryForCards([])
        
        #expect(mastery == 0.0)
    }
    
    @Test("All novice cards should return zero mastery")
    func testAllNoviceCardsMastery() {
        let cards = [
            createTestCard(proficiency: .novice),
            createTestCard(proficiency: .novice),
            createTestCard(proficiency: .novice)
        ]
        
        let mastery = calculateMasteryForCards(cards)
        
        #expect(mastery == 0.0)
    }
    
    @Test("All mastered cards should return full mastery")
    func testAllMasteredCardsMastery() {
        let cards = [
            createTestCard(proficiency: .mastered),
            createTestCard(proficiency: .mastered),
            createTestCard(proficiency: .mastered)
        ]
        
        let mastery = calculateMasteryForCards(cards)
        
        #expect(abs(mastery - 1.0) < 0.001)
    }
    
    @Test("Mixed proficiency should return correct average")
    func testMixedProficiencyMastery() {
        let cards = [
            createTestCard(proficiency: .novice),
            createTestCard(proficiency: .developing),
            createTestCard(proficiency: .proficient),
            createTestCard(proficiency: .mastered)
        ]
        
        let mastery = calculateMasteryForCards(cards)
        
        #expect(abs(mastery - 0.4975) < 0.01)
    }
    
    @Test("Card with necessary repetitions and interval should become mastered")
    func testMasteredProficiency() {
        var card = createTestCard(proficiency: .developing)
        card.repetitions = 6
        card.interval = 21
        card.totalReviewCount = 10
        card.successfulReviewCount = 9
        
        ProficiencyTracker.updateProficiency(for: card)
        
        #expect(card.proficiency == .mastered)
    }
    
    @Test("Card with moderate stats should become proficient")
    func testProficientProficiency() {
        var card = createTestCard(proficiency: .novice)
        card.repetitions = 3
        card.interval = 7
        card.totalReviewCount = 5
        card.successfulReviewCount = 4
        
        ProficiencyTracker.updateProficiency(for: card)
        
        #expect(card.proficiency == .proficient)
    }
    
    @Test("Card with consecutive correct should become developing")
    func testDevelopingProficiency() {
        var card = createTestCard(proficiency: .novice)
        card.consecutiveCorrect = 2
        card.totalReviewCount = 2
        
        ProficiencyTracker.updateProficiency(for: card)
        
        #expect(card.proficiency == .developing)
    }
    
    @Test("New card should be novice")
    func testNoviceProficiency() {
        let card = createTestCard(proficiency: .novice)
        
        ProficiencyTracker.updateProficiency(for: card)
        
        #expect(card.proficiency == .novice)
    }
    
    @Test("Effective AI card should have high success rate")
    func testEffectiveAICard() {
        var card = createTestCard()
        card.isAIGenerated = true
        card.totalReviewCount = 5
        card.successfulReviewCount = 4
        
        #expect(card.isEffective == true)
        #expect(card.isStruggling == false)
    }
    
    @Test("Struggling AI card should have low success rate")
    func testStrugglingAICard() {
        var card = createTestCard()
        card.isAIGenerated = true
        card.totalReviewCount = 5
        card.successfulReviewCount = 1
        
        #expect(card.isEffective == false)
        #expect(card.isStruggling == true)
    }
    
    @Test("Card with insufficient reviews should not be effective or struggling")
    func testCardWithFewReviews() {
        var card = createTestCard()
        card.isAIGenerated = true
        card.totalReviewCount = 2
        card.successfulReviewCount = 0
        
        #expect(card.isEffective == false)
        #expect(card.isStruggling == false)
    }
    
    @Test("Retention rate should be calculated correctly")
    func testRetentionRate() {
        let sessions = [
            createTestReviewSession(wasCorrect: true),
            createTestReviewSession(wasCorrect: true),
            createTestReviewSession(wasCorrect: false),
            createTestReviewSession(wasCorrect: true)
        ]
        
        let rate = ProficiencyTracker.retentionRate(from: sessions)
        
        #expect(abs(rate - 0.75) < 0.001)
    }
    
    @Test("Empty sessions should return zero retention rate")
    func testEmptyRetentionRate() {
        let rate = ProficiencyTracker.retentionRate(from: [])
        
        #expect(rate == 0.0)
    }
    
    private func createTestCard(proficiency: ProficiencyLevel = .novice) -> StudyCard {
        let card = StudyCard(
            topicName: "Test Topic",
            subtopic: "Test Subtopic",
            front: "Test Front",
            back: "Test Back"
        )
        card.proficiency = proficiency
        return card
    }
    
    private func createTestReviewSession(wasCorrect: Bool) -> ReviewSession {
        let session = ReviewSession(
            cardID: UUID(),
            subjectName: "Test Subject",
            topicName: "Test Topic",
            qualityRating: wasCorrect ? 3 : 0,
            sessionDuration: 10
        )
        session.wasCorrect = wasCorrect
        return session
    }
    
    private func calculateMasteryForCards(_ cards: [StudyCard]) -> Double {
        let weights: [ProficiencyLevel: Double] = [
            .novice: 0,
            .developing: 0.33,
            .proficient: 0.66,
            .mastered: 1.0
        ]
        
        guard !cards.isEmpty else { return 0 }
        
        let score = cards.reduce(0.0) { sum, card in
            sum + (weights[card.proficiency] ?? 0)
        }
        
        return score / Double(cards.count)
    }
}