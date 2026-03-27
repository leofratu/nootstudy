import Testing
import Foundation

@testable import IBVault

@Suite("SM2Engine Tests")
struct SM2EngineTests {
    
    @Test("Initial card state should have correct defaults")
    func testInitialCardState() {
        let card = createTestCard()
        
        #expect(card.easeFactor == 2.5)
        #expect(card.interval == 0)
        #expect(card.repetitions == 0)
        #expect(card.consecutiveCorrect == 0)
        #expect(card.totalReviewCount == 0)
    }
    
    @Test("Again quality should reset repetitions")
    func testAgainResetsRepetitions() {
        var card = createTestCard()
        card.repetitions = 5
        card.interval = 10
        
        let result = SM2Engine.calculateNextReview(card: card, quality: .again)
        
        #expect(result.repetitions == 0)
        #expect(result.interval == 1)
    }
    
    @Test("Hard quality should reset repetitions")
    func testHardResetsRepetitions() {
        var card = createTestCard()
        card.repetitions = 5
        card.interval = 10
        
        let result = SM2Engine.calculateNextReview(card: card, quality: .hard)
        
        #expect(result.repetitions == 0)
        #expect(result.interval == 1)
    }
    
    @Test("First successful recall should set interval to 1")
    func testFirstSuccessInterval() {
        let card = createTestCard()
        
        let result = SM2Engine.calculateNextReview(card: card, quality: .good)
        
        #expect(result.interval == 1)
        #expect(result.repetitions == 1)
    }
    
    @Test("Second successful recall should set interval to 6")
    func testSecondSuccessInterval() {
        var card = createTestCard()
        card.repetitions = 1
        
        let result = SM2Engine.calculateNextReview(card: card, quality: .good)
        
        #expect(result.interval == 6)
        #expect(result.repetitions == 2)
    }
    
    @Test("Third successful recall should use ease factor")
    func testThirdSuccessInterval() {
        var card = createTestCard()
        card.repetitions = 2
        card.interval = 6
        card.easeFactor = 2.5
        
        let result = SM2Engine.calculateNextReview(card: card, quality: .good)
        
        let expectedInterval = Int(round(6.0 * 2.5))
        #expect(result.interval == expectedInterval)
        #expect(result.repetitions == 3)
    }
    
    @Test("Easy quality should increase ease factor")
    func testEasyIncreasesEaseFactor() {
        let card = createTestCard()
        
        let result = SM2Engine.calculateNextReview(card: card, quality: .easy)
        
        #expect(result.easeFactor > 2.5)
    }
    
    @Test("Again quality should decrease ease factor")
    func testAgainDecreasesEaseFactor() {
        var card = createTestCard()
        card.easeFactor = 2.5
        
        let result = SM2Engine.calculateNextReview(card: card, quality: .again)
        
        #expect(result.easeFactor < 2.5)
    }
    
    @Test("Ease factor should not go below minimum")
    func testMinimumEaseFactor() {
        var card = createTestCard()
        card.easeFactor = 1.4
        
        let result = SM2Engine.calculateNextReview(card: card, quality: .again)
        
        #expect(result.easeFactor >= 1.3)
    }
    
    @Test("XP for review should return correct values")
    func testXPForReview() {
        #expect(SM2Engine.xpForReview(.again) == 2)
        #expect(SM2Engine.xpForReview(.hard) == 5)
        #expect(SM2Engine.xpForReview(.good) == 10)
        #expect(SM2Engine.xpForReview(.easy) == 15)
    }
    
    @Test("Apply review should update card properties")
    func testApplyReview() {
        let card = createTestCard()
        
        SM2Engine.applyReview(to: card, quality: .good)
        
        #expect(card.totalReviewCount == 1)
        #expect(card.successfulReviewCount == 1)
        #expect(card.consecutiveCorrect == 1)
        #expect(card.repetitions == 1)
    }
    
    @Test("Apply review with again should reset consecutive correct")
    func testApplyReviewAgainResetsConsecutive() {
        let card = createTestCard()
        card.consecutiveCorrect = 5
        
        SM2Engine.applyReview(to: card, quality: .again)
        
        #expect(card.consecutiveCorrect == 0)
        #expect(card.successfulReviewCount == 0)
    }
    
    private func createTestCard() -> StudyCard {
        StudyCard(
            topicName: "Test Topic",
            subtopic: "Test Subtopic",
            front: "Test Front",
            back: "Test Back"
        )
    }
}