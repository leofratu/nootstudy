import Foundation
import SwiftData

nonisolated struct ProficiencyConfig: Sendable {
    // Levels follow what the memory research measures: repeated successful
    // retrieval, spread over time, leaving memory that lasts. Stability comes
    // from FSRS and is the number of days until recall is predicted to fall to
    // 90%. The studies justify which signals count; the exact cutoffs are this
    // app's choices and are not values validated by those studies.
    static let evidenceSummary = "Levels combine successful recall, spacing and predicted memory stability. The research supports these signals; the exact cutoffs are this app's own, and a level is not an exam grade or a guarantee of retention."
    static let researchURLs = [
        URL(string: "https://doi.org/10.1016/j.jml.2006.09.004")!,
        URL(string: "https://doi.org/10.1037/0033-2909.132.3.354")!
    ]
    // Rawson & Dunlosky (2011): gains from further successful relearning shrink
    // quickly after about three to four spaced successes.
    var masteryRepetitionsThreshold: Int = 4
    // Cepeda et al. (2008): lasting retention over months needs gaps of weeks.
    var masteryIntervalThreshold: Int = 21
    var masterySuccessRateThreshold: Double = 0.85

    // Karpicke & Roediger (2008): one recall is fragile, and repeated retrieval
    // is what separates long-term retention from short-term performance.
    var proficientRepetitionsThreshold: Int = 3
    var proficientIntervalThreshold: Int = 7
    var proficientSuccessRateThreshold: Double = 0.65
    
    var developingConsecutiveThreshold: Int = 2
    var developingReviewCountThreshold: Int = 2
    
    static let `default` = ProficiencyConfig()
}

/// One published study behind a mastery level, shown in the level guide.
nonisolated struct MasteryCitation: Identifiable, Sendable {
    let citation: String
    let finding: String
    let doi: String
    var id: String { doi }
    var url: URL? { URL(string: "https://doi.org/\(doi)") }
}

nonisolated struct MasteryLevelGuide: Identifiable, Sendable {
    let level: ProficiencyLevel
    let requirement: String
    let meaning: String
    var id: String { level.rawValue }

    static func all(config: ProficiencyConfig = .default) -> [MasteryLevelGuide] {
        [
            MasteryLevelGuide(
                level: .novice,
                requirement: "Studied, but not yet recalled reliably",
                meaning: "The idea is still being formed. Re-reading feels familiar, but recall is what counts next."
            ),
            MasteryLevelGuide(
                level: .developing,
                requirement: "At least \(config.developingConsecutiveThreshold) reviews with a successful recall",
                meaning: "You can retrieve it, though it may fade within days without another attempt."
            ),
            MasteryLevelGuide(
                level: .proficient,
                requirement: "\(config.proficientRepetitionsThreshold)+ successful recalls, predicted to hold for \(config.proficientIntervalThreshold)+ days, \(Int(config.proficientSuccessRateThreshold * 100))%+ accuracy",
                meaning: "Spaced recall has started to stick. Memory now survives a week without review."
            ),
            MasteryLevelGuide(
                level: .mastered,
                requirement: "\(config.masteryRepetitionsThreshold)+ successful recalls, predicted to hold for \(config.masteryIntervalThreshold)+ days, \(Int(config.masterySuccessRateThreshold * 100))%+ accuracy",
                meaning: "Further reviews add little, so they are spaced weeks apart. A forgotten review moves the card back down."
            )
        ]
    }

    static let citations = [
        MasteryCitation(
            citation: "Karpicke & Roediger (2007), Journal of Memory and Language",
            finding: "Repeated retrieval during learning, more than repeated study, drives long-term retention.",
            doi: "10.1016/j.jml.2006.09.004"
        ),
        MasteryCitation(
            citation: "Karpicke & Roediger (2008), Science",
            finding: "Continuing to recall items after first success greatly improved retention a week later.",
            doi: "10.1126/science.1152408"
        ),
        MasteryCitation(
            citation: "Rawson & Dunlosky (2011), Journal of Experimental Psychology: General",
            finding: "Successive relearning across sessions yields durable, efficient learning, with diminishing returns after a few successes.",
            doi: "10.1037/a0023956"
        ),
        MasteryCitation(
            citation: "Cepeda et al. (2006), Psychological Bulletin",
            finding: "A synthesis of distributed-practice research: spreading practice out improves retention.",
            doi: "10.1037/0033-2909.132.3.354"
        ),
        MasteryCitation(
            citation: "Cepeda et al. (2008), Psychological Science",
            finding: "The best gap between reviews grows with how long you need to remember, reaching weeks for retention over months.",
            doi: "10.1111/j.1467-9280.2008.02209.x"
        ),
        MasteryCitation(
            citation: "Ye, Su & Cao (2022), KDD",
            finding: "The memory-stability modelling approach behind FSRS, the scheduler used to predict how long a card will hold.",
            doi: "10.1145/3534678.3539081"
        )
    ]
}

nonisolated enum ProficiencyTracker {
    /// Days the memory is predicted to hold at 90% recall. FSRS stability when
    /// the card has it; otherwise the scheduled interval, which FSRS sets to the
    /// same value at this app's 90% target.
    static func holdDays(for card: StudyCard) -> Double {
        if let stability = card.fsrsStability, stability.isFinite, stability > 0 { return stability }
        return Double(max(card.interval, 0))
    }

    static func updateProficiency(for card: StudyCard, config: ProficiencyConfig = .default) {
        let successRate = card.effectivenessRate
        let reviewCount = card.totalReviewCount
        let holdDays = holdDays(for: card)
        
        let level: ProficiencyLevel
        
        if card.repetitions >= config.masteryRepetitionsThreshold &&
            card.successfulReviewCount >= config.masteryRepetitionsThreshold &&
            holdDays >= Double(config.masteryIntervalThreshold) &&
            successRate >= config.masterySuccessRateThreshold {
            level = .mastered
        } else if card.repetitions >= config.proficientRepetitionsThreshold &&
                    card.successfulReviewCount >= config.proficientRepetitionsThreshold &&
                    holdDays >= Double(config.proficientIntervalThreshold) &&
                    successRate >= config.proficientSuccessRateThreshold {
            level = .proficient
        } else if card.successfulReviewCount > 0 &&
                    (card.consecutiveCorrect >= config.developingConsecutiveThreshold ||
                     reviewCount >= config.developingReviewCountThreshold) {
            level = .developing
        } else {
            level = .novice
        }
        
        card.proficiency = level
    }
    
    static func masteryPercentage(for subject: Subject) -> Double {
        calculateMastery(for: subject.cards)
    }
    
    static func masteryPercentage(for subject: Subject, topicName: String) -> Double {
        let topicCards = subject.cards.filter { $0.topicName == topicName }
        return calculateMastery(for: topicCards)
    }
    
    static func masteryPercentage(for subject: Subject, topicName: String, subtopic: String) -> Double {
        let subtopicCards = subject.cards.filter {
            $0.topicName == topicName && $0.subtopic == subtopic
        }
        return calculateMastery(for: subtopicCards)
    }

    static func masteryPercentage(for cards: [StudyCard]) -> Double {
        calculateMastery(for: cards)
    }

    static func masteryValue(for level: ProficiencyLevel) -> Double {
        switch level {
        case .novice: return 0
        case .developing: return 0.33
        case .proficient: return 0.66
        case .mastered: return 1
        }
    }

    /// Give successful early recalls credit between proficiency milestones.
    /// Legacy imports without counters retain their explicitly stored level.
    static func masteryValue(for card: StudyCard) -> Double {
        guard card.totalReviewCount > 0 else { return masteryValue(for: card.proficiency) }
        let accuracy = min(max(card.effectivenessRate, 0), 1)
        let correct = Double(max(0, card.consecutiveCorrect))
        let interval = holdDays(for: card)
        switch card.proficiency {
        case .novice:
            return 0.33 * min(correct / 2, 1) * accuracy
        case .developing:
            return (0.33 + 0.33 * min(min(correct / 3, interval / 7), 1)) * accuracy
        case .proficient:
            return (0.66 + 0.34 * min(min(correct / 4, interval / 21), 1)) * accuracy
        case .mastered:
            return accuracy
        }
    }
    
    static func weakTopics(for subject: Subject) -> [StudyCard] {
        subject.cards
            .filter { $0.proficiency == .novice || $0.proficiency == .developing }
            .sorted {
                if $0.consecutiveCorrect != $1.consecutiveCorrect {
                    return $0.consecutiveCorrect < $1.consecutiveCorrect
                }
                if $0.topicName != $1.topicName {
                    return $0.topicName < $1.topicName
                }
                return $0.id.uuidString < $1.id.uuidString
            }
    }
    
    static func effectiveAICards(for subject: Subject) -> [StudyCard] {
        subject.cards.filter { ($0.isAIGenerated ?? false) && $0.isEffective }
    }
    
    static func strugglingAICards(for subject: Subject) -> [StudyCard] {
        subject.cards.filter { ($0.isAIGenerated ?? false) && $0.isStruggling }
    }
    
    static func topicEffectiveness(
        for subject: Subject,
        topicName: String
    ) -> (effective: Int, struggling: Int, total: Int) {
        let topicCards = subject.cards.filter {
            $0.topicName == topicName && ($0.isAIGenerated ?? false)
        }
        let effective = topicCards.filter { $0.isEffective }.count
        let struggling = topicCards.filter { $0.isStruggling }.count
        return (effective, struggling, topicCards.count)
    }
    
    static func overallAIEffectiveness(for subject: Subject) -> Double {
        let aiCards = subject.cards.filter {
            ($0.isAIGenerated ?? false) && $0.totalReviewCount >= 3
        }
        guard !aiCards.isEmpty else { return 0 }
        let effectiveCount = aiCards.filter { $0.isEffective }.count
        return Double(effectiveCount) / Double(aiCards.count)
    }
    
    static func retentionRate(from sessions: [ReviewSession]) -> Double {
        guard !sessions.isEmpty else { return 0 }
        let correct = sessions.filter { $0.wasCorrect }.count
        return Double(correct) / Double(sessions.count)
    }
    
    private static func calculateMastery(for cards: [StudyCard]) -> Double {
        guard !cards.isEmpty else { return 0 }
        
        let score = cards.reduce(0.0) { sum, card in
            sum + masteryValue(for: card)
        }
        
        return score / Double(cards.count)
    }
}
