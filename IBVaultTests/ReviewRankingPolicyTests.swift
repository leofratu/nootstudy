import Testing
import Foundation
@testable import IBVault

@Suite("Review Ranking Policy Tests")
struct ReviewRankingPolicyTests {
    @Test("Overdue cards outrank equal due cards")
    func overdueCardsIncreasePriority() {
        let now = Date()

        let normal = ReviewRankingPolicy.priority(
            for: ReviewRankingInput(dueCount: 5, overdueCount: 0, mastery: 0.5, examDate: nil),
            now: now
        )
        let overdue = ReviewRankingPolicy.priority(
            for: ReviewRankingInput(dueCount: 5, overdueCount: 3, mastery: 0.5, examDate: nil),
            now: now
        )

        #expect(overdue > normal)
    }

    @Test("Lower mastery increases priority")
    func lowerMasteryIncreasesPriority() {
        let now = Date()

        let highMastery = ReviewRankingPolicy.priority(
            for: ReviewRankingInput(dueCount: 3, overdueCount: 0, mastery: 0.9, examDate: nil),
            now: now
        )
        let lowMastery = ReviewRankingPolicy.priority(
            for: ReviewRankingInput(dueCount: 3, overdueCount: 0, mastery: 0.2, examDate: nil),
            now: now
        )

        #expect(lowMastery > highMastery)
    }

    @Test("Past exams do not inflate priority")
    func pastExamDoesNotIncreasePriority() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let pastExam = calendar.date(byAdding: .day, value: -3, to: now)

        let withoutExam = ReviewRankingPolicy.priority(
            for: ReviewRankingInput(dueCount: 2, overdueCount: 1, mastery: 0.5, examDate: nil),
            now: now,
            calendar: calendar
        )
        let withPastExam = ReviewRankingPolicy.priority(
            for: ReviewRankingInput(dueCount: 2, overdueCount: 1, mastery: 0.5, examDate: pastExam),
            now: now,
            calendar: calendar
        )

        #expect(withPastExam == withoutExam)
    }
}
