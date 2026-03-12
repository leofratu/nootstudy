import Foundation

struct SM2Result {
    let interval: Int
    let easeFactor: Double
    let repetitions: Int
    let nextReviewDate: Date
}

struct SM2Engine {
    /// Calculate next review parameters using SM-2 algorithm
    /// - Parameters:
    ///   - card: The study card being reviewed
    ///   - quality: Recall quality (0-5): Again=0, Hard=2, Good=3, Easy=5
    /// - Returns: Updated SM-2 parameters
    static func calculateNextReview(card: StudyCard, quality: RecallQuality) -> SM2Result {
        let q = Double(quality.rawValue)
        var ef = card.easeFactor
        var reps = card.repetitions
        var interval = card.interval

        // If quality < 3, reset repetitions (failed recall)
        if quality == .again || quality == .hard {
            reps = 0
            interval = 1
        } else {
            // Successful recall
            switch reps {
            case 0:
                interval = 1
            case 1:
                interval = 6
            default:
                interval = Int(round(Double(interval) * ef))
            }
            reps += 1
        }

        // Update ease factor using SM-2 formula
        // EF' = EF + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
        ef = ef + (0.1 - (5.0 - q) * (0.08 + (5.0 - q) * 0.02))
        ef = max(1.3, ef) // Minimum ease factor

        // Calculate next review date
        let nextDate = Calendar.current.date(byAdding: .day, value: interval, to: Date()) ?? Date()

        return SM2Result(
            interval: interval,
            easeFactor: ef,
            repetitions: reps,
            nextReviewDate: nextDate
        )
    }

    /// Apply SM-2 result to a card
    static func applyReview(to card: StudyCard, quality: RecallQuality) {
        let result = calculateNextReview(card: card, quality: quality)
        card.easeFactor = result.easeFactor
        card.interval = result.interval
        card.repetitions = result.repetitions
        card.nextReviewDate = result.nextReviewDate
        card.lastReviewedDate = Date()

        // Track effectiveness for AI-generated cards
        card.totalReviewCount += 1
        if quality == .good || quality == .easy {
            card.successfulReviewCount += 1
            card.consecutiveCorrect += 1
        } else {
            card.consecutiveCorrect = 0
        }

        // Update proficiency based on consecutive correct
        ProficiencyTracker.updateProficiency(for: card)
    }

    /// Calculate XP earned from a review
    static func xpForReview(quality: RecallQuality) -> Int {
        switch quality {
        case .again: return 2
        case .hard: return 5
        case .good: return 10
        case .easy: return 15
        }
    }
}
