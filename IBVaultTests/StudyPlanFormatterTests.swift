import Testing
import Foundation
@testable import IBVault

@Suite("Study Plan Formatter Tests")
struct StudyPlanFormatterTests {

    @Test("scheduledTimeFormatted always returns a non-empty formatted string")
    func scheduledTimeFormattedIsNonEmpty() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let plan = StudyPlan(
            subjectName: "Biology",
            topicName: "Genetics",
            subtopicName: "Gene expression",
            scheduledDate: date,
            durationMinutes: 60
        )

        #expect(!plan.scheduledTimeFormatted.isEmpty)
        #expect(!plan.scheduledEndTimeFormatted.isEmpty)
        #expect(plan.scheduledTimeFormatted != plan.scheduledEndTimeFormatted)
    }

    @Test("Formatted times are deterministic for the same date")
    func formattedTimesAreDeterministic() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = StudyPlan(subjectName: "Economics", topicName: "Demand", scheduledDate: date, durationMinutes: 45)
        let second = StudyPlan(subjectName: "Economics", topicName: "Demand", scheduledDate: date, durationMinutes: 45)

        #expect(first.scheduledTimeFormatted == second.scheduledTimeFormatted)
        #expect(first.scheduledEndTimeFormatted == second.scheduledEndTimeFormatted)
    }

    @Test("A plan whose scheduled date is in the past is not active or upcoming")
    func pastPlanIsNotActive() {
        let past = Date(timeIntervalSince1970: 1_500_000_000)
        let plan = StudyPlan(subjectName: "Biology", topicName: "Cells", scheduledDate: past, durationMinutes: 60)

        #expect(!plan.isUpcoming)
        #expect(!plan.isActive)
        #expect(plan.isPast)
    }

    @Test("A plan scheduled in the future is upcoming and not yet active")
    func upcomingPlanState() {
        let future = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let plan = StudyPlan(subjectName: "Biology", topicName: "Genetics", scheduledDate: future, durationMinutes: 60)

        #expect(plan.isUpcoming)
        #expect(!plan.isActive)
        #expect(!plan.isPast)
    }

    @Test("A plan inside its scheduled window is active")
    func activePlanState() {
        let start = Calendar.current.date(byAdding: .minute, value: -30, to: Date())!
        // A 120-minute plan started 30 minutes ago is still running.
        let plan = StudyPlan(subjectName: "Biology", topicName: "Genetics", scheduledDate: start, durationMinutes: 120)

        #expect(!plan.isUpcoming)
        #expect(plan.isActive)
        #expect(!plan.isPast)
    }

    @Test("A completed plan is past even while its window is still open")
    func completedPlanIsPast() {
        let future = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let plan = StudyPlan(subjectName: "Biology", topicName: "Genetics", scheduledDate: future, durationMinutes: 60)
        plan.isCompleted = true

        #expect(!plan.isUpcoming)
        #expect(!plan.isActive)
        #expect(plan.isPast)
    }

    @Test("An empty review schedule falls back to the default offsets")
    func emptyReviewScheduleFallsBack() {
        let plan = StudyPlan(
            subjectName: "Biology",
            topicName: "Genetics",
            scheduledDate: Date(),
            reviewScheduleOffsets: []
        )

        #expect(plan.reviewScheduleOffsets == [1, 3, 7])
        #expect(plan.revisitCount == 3)
    }

    @Test("Review schedule offsets drop non-positive values and deduplicate")
    func reviewScheduleFiltersAndDedupes() {
        let plan = StudyPlan(
            subjectName: "Biology",
            topicName: "Genetics",
            scheduledDate: Date(),
            reviewScheduleOffsets: [2, 2, 5, 0, -3, 1]
        )

        #expect(plan.reviewScheduleOffsets == [2, 5, 1])
        #expect(plan.revisitCount == 3)
    }
}
