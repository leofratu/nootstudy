import Foundation
import SwiftData

struct SM2Result: Sendable {
    let interval: Int
    let easeFactor: Double
    let repetitions: Int
    let nextReviewDate: Date
}

struct SM2Config: Sendable {
    var minimumEaseFactor: Double = 1.3
    var initialEaseFactor: Double = 2.5
    var intervalAfterFailure: Int = 1
    var firstIntervalSuccess: Int = 1
    var secondIntervalSuccess: Int = 6
    
    static let `default` = SM2Config()
}

enum SM2Engine {
    static func calculateNextReview(
        card: StudyCard,
        quality: RecallQuality,
        config: SM2Config = .default
    ) -> SM2Result {
        let q = Double(quality.rawValue)
        var ef = card.easeFactor
        var reps = card.repetitions
        var interval = card.interval
        
        if quality == .again || quality == .hard {
            reps = 0
            interval = config.intervalAfterFailure
        } else {
            interval = computeInterval(for: reps, currentInterval: interval, easeFactor: ef, config: config)
            reps += 1
        }
        
        ef = updateEaseFactor(easeFactor: ef, quality: q, minimum: config.minimumEaseFactor)
        
        let nextDate = Calendar.current.date(byAdding: .day, value: interval, to: Date()) ?? Date()
        
        return SM2Result(
            interval: interval,
            easeFactor: ef,
            repetitions: reps,
            nextReviewDate: nextDate
        )
    }
    
    static func applyReview(to card: StudyCard, quality: RecallQuality, config: SM2Config = .default) {
        let result = calculateNextReview(card: card, quality: quality, config: config)
        
        card.easeFactor = result.easeFactor
        card.interval = result.interval
        card.repetitions = result.repetitions
        card.nextReviewDate = result.nextReviewDate
        card.lastReviewedDate = Date()
        card.totalReviewCount += 1
        
        if quality == .good || quality == .easy {
            card.successfulReviewCount += 1
            card.consecutiveCorrect += 1
        } else {
            card.consecutiveCorrect = 0
        }
        
        ProficiencyTracker.updateProficiency(for: card)
    }
    
    static func xpForReview(_ quality: RecallQuality) -> Int {
        switch quality {
        case .again: return 2
        case .hard: return 5
        case .good: return 10
        case .easy: return 15
        }
    }
    
    private static func computeInterval(
        for repetitions: Int,
        currentInterval: Int,
        easeFactor: Double,
        config: SM2Config
    ) -> Int {
        switch repetitions {
        case 0:
            return config.firstIntervalSuccess
        case 1:
            return config.secondIntervalSuccess
        default:
            // Floor at one day so a degenerate stored ease factor can never
            // schedule a successful card for immediate re-review (interval 0).
            return max(1, Int(round(Double(currentInterval) * easeFactor)))
        }
    }
    
    private static func updateEaseFactor(
        easeFactor: Double,
        quality: Double,
        minimum: Double
    ) -> Double {
        let ef = easeFactor + (0.1 - (5.0 - quality) * (0.08 + (5.0 - quality) * 0.02))
        return max(minimum, ef)
    }
}