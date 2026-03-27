import Foundation
import SwiftData

struct ReviewScheduleConfig {
    var optimalStudyHours: ClosedRange<Int> = 16...21
    var minutesPerCard: Double = 0.5
    var minimumRecommendedMinutes: Int = 15
    var overdueWeightMultiplier: Double = 20.0
    var dueWeightMultiplier: Double = 10.0
    var examUrgencyWeight: Double = 0.5
    var lowMasteryWeight: Double = 30.0
    var examUrgencyDaysThreshold: Int = 30
    
    static let `default` = ReviewScheduleConfig()
}

struct SubjectReviewSchedule: Identifiable, Sendable {
    let id = UUID()
    let subject: Subject
    let dueCards: Int
    let overdueCards: Int
    let recommendedMinutes: Int
    let priority: Double
    let nextOptimalReview: Date?
    
    enum UrgencyLevel: String, Sendable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
        case critical = "Critical"
        
        var color: String {
            switch self {
            case .low: return "gray"
            case .medium: return "orange"
            case .high: return "red"
            case .critical: return "purple"
            }
        }
    }
    
    var urgencyLevel: UrgencyLevel {
        if overdueCards > 10 { return .critical }
        if dueCards > 20 { return .high }
        if dueCards > 5 { return .medium }
        return .low
    }
}

@Observable
final class ReviewScheduler: @unchecked Sendable {
    var schedules: [SubjectReviewSchedule] = []
    var totalDueToday: Int = 0
    var totalOverdue: Int = 0
    var recommendedStudyOrder: [Subject] = []
    
    private let lock = NSLock()
    
    func analyze(context: ModelContext, config: ReviewScheduleConfig = .default) {
        lock.lock()
        defer { lock.unlock() }
        
        let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        let scopes = studiedScopes(in: context)
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        
        schedules = subjects.compactMap { subject -> SubjectReviewSchedule? in
            let reviewableCards = scopedCards(for: subject, scopes: scopes)
            let dueCards = reviewableCards.filter { $0.nextReviewDate <= now }.count
            let overdueCards = reviewableCards.filter { $0.nextReviewDate < yesterday }.count
            
            guard dueCards > 0 || overdueCards > 0 else { return nil }
            
            let priority = calculatePriority(
                dueCount: dueCards,
                overdueCount: overdueCards,
                subject: subject,
                now: now,
                config: config
            )
            
            let recommendedMinutes = max(
                config.minimumRecommendedMinutes,
                Int(Double(dueCards) * config.minutesPerCard)
            )
            
            let nextOptimal = findNextOptimalSlot(from: now, config: config)
            
            return SubjectReviewSchedule(
                subject: subject,
                dueCards: dueCards,
                overdueCards: overdueCards,
                recommendedMinutes: recommendedMinutes,
                priority: priority,
                nextOptimalReview: nextOptimal
            )
        }
        .sorted { $0.priority > $1.priority }
        
        totalDueToday = schedules.reduce(0) { $0 + $1.dueCards }
        totalOverdue = schedules.reduce(0) { $0 + $1.overdueCards }
        recommendedStudyOrder = schedules.map { $0.subject }
    }
    
    func cardsDueToday(for subject: Subject, context: ModelContext) -> [StudyCard] {
        let now = Date()
        return scopedCards(for: subject, scopes: studiedScopes(in: context))
            .filter { $0.nextReviewDate <= now }
            .sorted { card1, card2 in
                if card1.nextReviewDate < card2.nextReviewDate { return true }
                if card1.easeFactor < card2.easeFactor { return true }
                return false
            }
    }
    
    func upcomingCards(for subject: Subject, context: ModelContext, days: Int = 7) -> [StudyCard] {
        let now = Date()
        let future = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        
        return scopedCards(for: subject, scopes: studiedScopes(in: context))
            .filter { $0.nextReviewDate > now && $0.nextReviewDate <= future }
            .sorted { $0.nextReviewDate < $1.nextReviewDate }
    }
    
    func allocateStudyTime(dailyGoalMinutes: Int) -> [(subject: Subject, minutes: Int)] {
        guard !schedules.isEmpty else { return [] }
        
        let totalPriority = schedules.reduce(0.0) { $0 + $1.priority }
        var allocations: [(subject: Subject, minutes: Int)] = []
        var remainingMinutes = dailyGoalMinutes
        
        for schedule in schedules {
            let proportion = schedule.priority / totalPriority
            let minutes = min(remainingMinutes, Int(Double(dailyGoalMinutes) * proportion))
            if minutes > 0 {
                allocations.append((schedule.subject, minutes))
                remainingMinutes -= minutes
            }
        }
        
        return allocations
    }
    
    func generateWeeklySchedule(context: ModelContext) -> [(date: Date, subjects: [Subject])] {
        let calendar = Calendar.current
        var schedule: [(date: Date, subjects: [Subject])] = []
        let scopes = studiedScopes(in: context)
        
        for dayOffset in 0..<7 {
            let date = calendar.date(byAdding: .day, value: dayOffset, to: Date())!
            let dayStart = calendar.startOfDay(for: date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            
            let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
            let subjectsForDay = subjects.filter { subject in
                hasDueOrOverdueCards(
                    subject: subject,
                    scopes: scopes,
                    dayStart: dayStart,
                    dayEnd: dayEnd
                )
            }
            .sorted { s1, s2 in
                let due1 = scopedCards(for: s1, scopes: scopes).filter { $0.nextReviewDate < dayEnd }.count
                let due2 = scopedCards(for: s2, scopes: scopes).filter { $0.nextReviewDate < dayEnd }.count
                return due1 > due2
            }
            
            if !subjectsForDay.isEmpty {
                schedule.append((date, subjectsForDay))
            }
        }
        
        return schedule
    }
    
    private func studiedScopes(in context: ModelContext) -> [StudyScope] {
        let sessions = (try? context.fetch(FetchDescriptor<StudySession>())) ?? []
        return StudySession.uniqueStudyScopes(from: sessions)
    }
    
    private func scopedCards(for subject: Subject, scopes: [StudyScope]) -> [StudyCard] {
        let subjectScopes = scopes.filter { $0.subjectName == subject.name }
        guard !subjectScopes.isEmpty else { return [] }
        return subject.cards.filter { card in
            subjectScopes.contains { $0.matches(card) }
        }
    }
    
    private func calculatePriority(
        dueCount: Int,
        overdueCount: Int,
        subject: Subject,
        now: Date,
        config: ReviewScheduleConfig
    ) -> Double {
        var priority: Double = 0
        
        priority += Double(overdueCount) * config.overdueWeightMultiplier
        priority += Double(dueCount) * config.dueWeightMultiplier
        
        if let examDate = subject.examDate {
            let daysUntil = Calendar.current.dateComponents([.day], from: now, to: examDate).day ?? 999
            if daysUntil <= config.examUrgencyDaysThreshold {
                priority += Double(config.examUrgencyDaysThreshold - daysUntil) * config.examUrgencyWeight
            }
        }
        
        let mastery = ProficiencyTracker.masteryPercentage(for: subject)
        priority += (1.0 - mastery) * config.lowMasteryWeight
        
        return priority
    }
    
    private func findNextOptimalSlot(from date: Date, config: ReviewScheduleConfig) -> Date? {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        
        if config.optimalStudyHours.contains(hour) {
            return date
        }
        
        let targetHour = hour < config.optimalStudyHours.lowerBound
            ? config.optimalStudyHours.lowerBound
            : config.optimalStudyHours.lowerBound
        
        if hour < config.optimalStudyHours.lowerBound {
            return calendar.date(bySettingHour: targetHour, minute: 0, second: 0, of: date)
        } else {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: date)!
            return calendar.date(bySettingHour: targetHour, minute: 0, second: 0, of: nextDay)
        }
    }
    
    private func hasDueOrOverdueCards(
        subject: Subject,
        scopes: [StudyScope],
        dayStart: Date,
        dayEnd: Date
    ) -> Bool {
        let reviewableCards = scopedCards(for: subject, scopes: scopes)
        return reviewableCards.contains { card in
            (card.nextReviewDate >= dayStart && card.nextReviewDate < dayEnd) ||
            card.nextReviewDate < dayStart
        }
    }
}