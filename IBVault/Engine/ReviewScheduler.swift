import Foundation
import SwiftData
import SwiftUI

struct SubjectReviewSchedule: Identifiable {
    let id = UUID()
    let subject: Subject
    let dueCards: Int
    let overdueCards: Int
    let recommendedMinutes: Int
    let priority: Double
    let nextOptimalReview: Date?
    
    var urgencyLevel: UrgencyLevel {
        if overdueCards > 10 { return .critical }
        if dueCards > 20 { return .high }
        if dueCards > 5 { return .medium }
        return .low
    }
    
    enum UrgencyLevel {
        case low, medium, high, critical
        
        var color: String {
            switch self {
            case .low: return "gray"
            case .medium: return "orange"
            case .high: return "red"
            case .critical: return "purple"
            }
        }
    }
}

@Observable
class ReviewScheduler {
    var schedules: [SubjectReviewSchedule] = []
    var totalDueToday: Int = 0
    var totalOverdue: Int = 0
    var recommendedStudyOrder: [Subject] = []
    
    func analyze(context: ModelContext) {
        let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        
        schedules = subjects.compactMap { subject -> SubjectReviewSchedule? in
            let dueCards = subject.cards.filter { $0.nextReviewDate <= now }.count
            let overdueCards = subject.cards.filter { $0.nextReviewDate < yesterday }.count
            
            guard dueCards > 0 || overdueCards > 0 else { return nil }
            
            // Calculate priority based on multiple factors
            let priority = calculatePriority(
                dueCount: dueCards,
                overdueCount: overdueCards,
                subject: subject,
                now: now
            )
            
            // Calculate recommended minutes (5 min per 10 cards)
            let recommendedMinutes = max(15, (dueCards * 5) / 2)
            
            // Find next optimal review time
            let nextOptimal = findNextOptimalSlot(for: subject, from: now)
            
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
    
    private func calculatePriority(dueCount: Int, overdueCount: Int, subject: Subject, now: Date) -> Double {
        var priority: Double = 0
        
        // Overdue cards are much more important (2x weight)
        priority += Double(overdueCount) * 20.0
        
        // Due cards
        priority += Double(dueCount) * 10.0
        
        // Exam urgency - if exam is close, boost priority
        if let examDate = subject.examDate {
            let daysUntil = Calendar.current.dateComponents([.day], from: now, to: examDate).day ?? 999
            if daysUntil <= 30 {
                priority += Double(30 - daysUntil) * 0.5
            }
        }
        
        // Mastery penalty - if subject has low mastery, boost priority
        let mastery = ProficiencyTracker.masteryPercentage(for: subject)
        priority += (1.0 - mastery) * 30.0
        
        return priority
    }
    
    private func findNextOptimalSlot(for subject: Subject, from date: Date) -> Date? {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        
        // Best study hours: 4pm - 9pm
        if hour >= 16 && hour <= 21 {
            return date
        }
        
        // Find next optimal slot
        if hour < 16 {
            return calendar.date(bySettingHour: 16, minute: 0, second: 0, of: date)
        } else {
            return calendar.date(byAdding: .day, value: 1, to: calendar.date(bySettingHour: 16, minute: 0, second: 0, of: date)!)
        }
    }
    
    // Get cards due today for a specific subject
    func cardsDueToday(for subject: Subject) -> [StudyCard] {
        let now = Date()
        return subject.cards
            .filter { $0.nextReviewDate <= now }
            .sorted { card1, card2 in
                // Prioritize overdue cards first, then by ease factor (harder cards first)
                if card1.nextReviewDate < card2.nextReviewDate { return true }
                if card1.easeFactor < card2.easeFactor { return true }
                return false
            }
    }
    
    // Get upcoming cards for a subject in the next N days
    func upcomingCards(for subject: Subject, days: Int = 7) -> [StudyCard] {
        let now = Date()
        let future = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        
        return subject.cards
            .filter { $0.nextReviewDate > now && $0.nextReviewDate <= future }
            .sorted { $0.nextReviewDate < $1.nextReviewDate }
    }
    
    // Auto-allocate study time across subjects
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
    
    // Generate a weekly schedule
    func generateWeeklySchedule(context: ModelContext) -> [(date: Date, subjects: [Subject])] {
        let calendar = Calendar.current
        var schedule: [(date: Date, subjects: [Subject])] = []
        
        for dayOffset in 0..<7 {
            let date = calendar.date(byAdding: .day, value: dayOffset, to: Date())!
            let dayStart = calendar.startOfDay(for: date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            
            let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
            let subjectsForDay = subjects.filter { subject in
                let dueOnDay = subject.cards.contains { card in
                    card.nextReviewDate >= dayStart && card.nextReviewDate < dayEnd
                }
                let hasOverdue = subject.cards.contains { card in
                    card.nextReviewDate < dayStart && card.nextReviewDate >= calendar.date(byAdding: .day, value: -1, to: dayStart)!
                }
                return dueOnDay || hasOverdue
            }
            .sorted { s1, s2 in
                let due1 = s1.cards.filter { $0.nextReviewDate < dayEnd }.count
                let due2 = s2.cards.filter { $0.nextReviewDate < dayEnd }.count
                return due1 > due2
            }
            
            if !subjectsForDay.isEmpty {
                schedule.append((date, subjectsForDay))
            }
        }
        
        return schedule
    }
}
