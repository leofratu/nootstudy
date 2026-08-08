import Testing
import Foundation
@testable import IBVault

@Suite("Study Plan Formatter Tests")
struct StudyPlanFormatterTests {

    @Test("Planning starts round up to the next local quarter hour")
    func planningStartRoundsForward() throws {
        let calendar = IBLocalClock.calendar
        let base = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 5,
            hour: 13,
            minute: 48,
            second: 42
        )))
        let rounded = IBLocalClock.nextQuarterHour(after: base)

        #expect(calendar.component(.hour, from: rounded) == 14)
        #expect(calendar.component(.minute, from: rounded) == 0)
        #expect(calendar.component(.second, from: rounded) == 0)
    }

    @Test("An exact quarter hour is preserved")
    func planningStartKeepsExactQuarter() throws {
        let calendar = IBLocalClock.calendar
        let base = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 5,
            hour: 14,
            minute: 15,
            second: 0
        )))

        #expect(IBLocalClock.nextQuarterHour(after: base) == base)
    }

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

    @Test("An empty review schedule does not create calendar review chains")
    func emptyReviewScheduleStaysEmpty() {
        let plan = StudyPlan(
            subjectName: "Biology",
            topicName: "Genetics",
            scheduledDate: Date(),
            reviewScheduleOffsets: []
        )

        #expect(plan.reviewScheduleOffsets.isEmpty)
        #expect(plan.revisitCount == 0)
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

    @Test("AI plan JSON without task IDs decodes and fills a thirty minute session")
    func planDraftDecodesAndNormalizes() throws {
        let response = """
        Here is the plan:
        {"overview":"Explain cell membranes","objectives":["Recall transport"],"tasks":[{"title":"Retrieve","minutes":10,"activityType":"active-recall","topicName":"Cells","subtopicName":"Cell membrane","instructions":"Write what you know.","successCriterion":"Explain it without notes.","flashcardTarget":3}]}
        """

        let plan = try StudyPlanDraft.decode(from: response).normalized(
            durationMinutes: 30,
            topicNames: ["Cells"],
            subtopicNames: ["Cell membrane"]
        )

        #expect(plan.tasks.count == 4)
        #expect(plan.tasks.reduce(0) { $0 + $1.minutes } == 30)
        #expect(plan.tasks.allSatisfy { $0.minutes > 0 })
        #expect(plan.tasks.allSatisfy { $0.topicName == "Cells" })
        #expect(plan.tasks.first?.title == "Orient with a trusted source")
        #expect(plan.tasks.last?.title == "Exit ticket and next gap")
    }

    @Test("Economics sessions introduce a trusted resource before testing")
    func economicsPlanStartsWithResource() {
        let draft = StudyPlanDraft(overview: "Understand demand", objectives: [], tasks: [])
        let plan = draft.normalized(
            durationMinutes: 60,
            topicNames: ["Demand and supply"],
            subtopicNames: ["Demand"],
            subjectName: "Economics"
        )

        #expect(plan.tasks.first?.activityType == "introduction")
        #expect(plan.tasks.first?.instructions.contains("EcoNinja") == true)
        #expect(plan.tasks[2].activityType == "active-recall")
        #expect(plan.tasks[3].activityType == "break")
        #expect(plan.tasks[3].minutes == 15)
        #expect(plan.tasks[4].activityType == "feedback")
    }

    @Test("Longer sessions receive proportionate task depth with an exact time budget")
    func planDepthScalesWithDuration() {
        let draft = StudyPlanDraft(overview: "Practise mechanics", objectives: [], tasks: [])

        let sixty = draft.normalized(durationMinutes: 60, topicNames: ["Mechanics"], subtopicNames: [])
        let ninety = draft.normalized(durationMinutes: 90, topicNames: ["Mechanics"], subtopicNames: [])
        let oneTwenty = draft.normalized(durationMinutes: 120, topicNames: ["Mechanics"], subtopicNames: [])

        #expect(sixty.tasks.count == 7)
        #expect(ninety.tasks.count == 9)
        #expect(oneTwenty.tasks.count == 12)
        #expect(sixty.tasks.reduce(0) { $0 + $1.minutes } == 60)
        #expect(ninety.tasks.reduce(0) { $0 + $1.minutes } == 90)
        #expect(oneTwenty.tasks.reduce(0) { $0 + $1.minutes } == 120)
    }
}

@Suite("Flashcard Batch Allocator Tests")
struct FlashcardBatchAllocatorTests {
    @Test("Requested cards are distributed exactly across selected topics")
    func distributesExactBatch() {
        #expect(FlashcardBatchAllocator.counts(total: 10, topicCount: 3) == [4, 3, 3])
        #expect(FlashcardBatchAllocator.counts(total: 5, topicCount: 2) == [3, 2])
        #expect(FlashcardBatchAllocator.counts(total: 10, topicCount: 0).isEmpty)
    }
}

@Suite("Calendar Timeline Layout Tests")
struct CalendarTimelineLayoutTests {
    @Test("Minute offsets and duration heights use one consistent hour scale")
    func timelineGeometryIsContinuous() {
        let hourHeight: CGFloat = 72

        #expect(CalendarTimelineLayout.offset(hour: 9, minute: 0, firstHour: 8, hourHeight: hourHeight) == 72)
        #expect(CalendarTimelineLayout.offset(hour: 9, minute: 30, firstHour: 8, hourHeight: hourHeight) == 108)
        #expect(CalendarTimelineLayout.blockHeight(durationMinutes: 90, hourHeight: hourHeight) == 108)
        #expect(CalendarTimelineLayout.blockHeight(durationMinutes: 15, hourHeight: hourHeight) == 48)
    }
}
