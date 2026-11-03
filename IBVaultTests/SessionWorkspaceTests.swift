import Foundation
import Testing
@testable import IBVault

@Suite("Active study workspace")
struct SessionWorkspaceTests {
    @Test("Time-only study days appear in the contribution heatmap")
    func timeOnlyActivity() {
        #expect(StudyActivity.intensity(cardsReviewed: 0, minutesStudied: 0) == 0)
        #expect(StudyActivity.intensity(cardsReviewed: 0, minutesStudied: 25) == 1)
        #expect(StudyActivity.intensity(cardsReviewed: 0, minutesStudied: 30) == 2)
        #expect(StudyActivity.intensity(cardsReviewed: 0, minutesStudied: 60) == 3)
        #expect(StudyActivity.intensity(cardsReviewed: 0, minutesStudied: 120) == 4)
        #expect(StudyActivity.intensity(cardsReviewed: 30, minutesStudied: 0) == 4)
    }

    @Test func extendingKeepsStartAndExistingProgress() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let plan = StudyPlan(subjectName: "Biology", topicName: "D1.2 Protein synthesis",
                             scheduledDate: start, durationMinutes: 60, notes: "Already studied translation")
        let originalID = plan.id
        let adjustment = try StudySessionDuration.extending(plan, by: 30)
        plan.durationMinutes = adjustment.minutes
        plan.scheduledEndDate = adjustment.endDate

        #expect(plan.id == originalID)
        #expect(plan.scheduledDate == start)
        #expect(plan.durationMinutes == 90)
        #expect(plan.scheduledEndDate == start.addingTimeInterval(90 * 60))
        #expect(plan.notes == "Already studied translation")
        #expect(!plan.isCompleted)
    }

    @Test func extensionRejectsInvalidOrCompletedSessions() {
        let plan = StudyPlan(subjectName: "Biology", topicName: "D1.2 Protein synthesis",
                             scheduledDate: Date(), durationMinutes: 60)
        for minutes in [-30, 0, 1440, Int.max] {
            #expect(throws: StudySessionDuration.AdjustmentError.self) {
                try StudySessionDuration.extending(plan, by: minutes)
            }
        }
        plan.isCompleted = true
        #expect(throws: StudySessionDuration.AdjustmentError.self) {
            try StudySessionDuration.extending(plan, by: 15)
        }
    }

    @Test func generatedExamKeepsAnswersSeparateAndCountsOnlyQuestionMarks() throws {
        let response = #"""
        ```json
        {"question":"1. Define diffusion. [2 marks]\n2. Explain movement down a gradient. [4]","markScheme":"Q1: net movement [2 marks]. Q2: gradient and particles [4 marks].","maximumMarks":6}
        ```
        """#
        let paper = try PracticeExamPaper.parse(response)
        #expect(paper.maximumMarks == 6)
        #expect(!paper.question.contains("net movement"))
        #expect(paper.markScheme.contains("net movement"))
        #expect(IBExamRubric.totalMarks(in: paper.question) == 6)
    }

    @Test func rejectsMissingQuestionsSchemesAndInconsistentMarks() throws {
        let valid = PracticeExamPaper(question: "Define diffusion. [2 marks]", markScheme: "Net movement down a concentration gradient.", maximumMarks: 2)
        for paper in [
            PracticeExamPaper(question: " ", markScheme: valid.markScheme, maximumMarks: 2),
            PracticeExamPaper(question: valid.question, markScheme: " ", maximumMarks: 2),
            PracticeExamPaper(question: valid.question, markScheme: valid.markScheme, maximumMarks: 20),
            PracticeExamPaper(question: "Define diffusion.", markScheme: valid.markScheme, maximumMarks: 20),
            PracticeExamPaper(question: "Invalid [999999999999999999999999 marks]", markScheme: valid.markScheme, maximumMarks: 20)
        ] {
            let response = String(decoding: try JSONEncoder().encode(paper), as: UTF8.self)
            #expect(throws: PracticeExamPaper.GenerationError.self) { try PracticeExamPaper.parse(response) }
        }
    }
}
