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

    @Test func rejectsOnlyPapersWithNoUsableQuestions() throws {
        let response = String(decoding: try JSONEncoder().encode(
            PracticeExamPaper(question: " ", markScheme: "Net movement.", maximumMarks: 2)), as: UTF8.self)
        #expect(throws: PracticeExamPaper.GenerationError.self) { try PracticeExamPaper.parse(response) }
        #expect(throws: PracticeExamPaper.GenerationError.self) { try PracticeExamPaper.parse("") }
    }

    @Test func printedMarksWinOverAMiscountedDeclaredTotal() throws {
        let paper = try PracticeExamPaper.parse(#"{"question":"1. Define diffusion. [2 marks]\n2. Explain osmosis. [5 marks]","markScheme":"Q1 and Q2.","maximumMarks":24}"#)
        #expect(paper.maximumMarks == 7)
    }

    @Test func aPrintedPaperTotalIsNotCountedTwice() throws {
        let paper = try PracticeExamPaper.parse(#"{"question":"Section A [6 marks]\n1. Define it. [2 marks]\n2. Explain it. [4 marks]","markScheme":"Scheme","maximumMarks":6}"#)
        #expect(paper.maximumMarks == 6)
    }

    @Test func aMissingSchemeOrDeclaredTotalStillGivesASittablePaper() throws {
        let noScheme = try PracticeExamPaper.parse(#"{"question":"1. Define diffusion. [2 marks]","maximumMarks":2}"#)
        #expect(noScheme.markScheme.isEmpty)
        let noMarksPrinted = try PracticeExamPaper.parse(#"{"question":"Define diffusion.","markScheme":"x","maximumMarks":"20"}"#)
        #expect(noMarksPrinted.maximumMarks == 20)
    }

    @Test func unescapedLatexSurvivesInsteadOfBreakingThePaper() throws {
        // How models commonly write maths inside JSON: \\frac is valid JSON that
        // would silently decode to a form feed, and \\sum is invalid outright.
        let response = #"{"question":"1. Find $\frac{d}{dx}\sum x^2$ when $\theta \neq 0$. [4 marks]\n2. Next. [2 marks]","markScheme":"Use $\beta$.","maximumMarks":6}"#
        let paper = try PracticeExamPaper.parse(response)
        #expect(paper.question.contains(#"\frac{d}{dx}"#))
        #expect(paper.question.contains(#"\sum"#))
        #expect(paper.question.contains(#"\theta"#))
        #expect(paper.question.contains(#"\neq"#))
        #expect(paper.question.contains("\n2. Next."))
        #expect(paper.markScheme.contains(#"\beta"#))
        #expect(paper.maximumMarks == 6)
    }

    @Test func correctlyEscapedLatexIsLeftAlone() throws {
        let paper = try PracticeExamPaper.parse(#"{"question":"Find $\\frac{1}{2}$. [1 mark]","markScheme":"x","maximumMarks":1}"#)
        #expect(paper.question == #"Find $\frac{1}{2}$. [1 mark]"#)
    }

    @Test func rawLineBreaksInsideJSONStringsAreTolerated() throws {
        let paper = try PracticeExamPaper.parse("{\"question\":\"1. Define it. [2 marks]\n2. Explain it. [3 marks]\",\"markScheme\":\"x\",\"maximumMarks\":5}")
        #expect(paper.maximumMarks == 5)
    }

    @Test func plainMarkdownPapersAreSplitAtTheMarkScheme() throws {
        let paper = try PracticeExamPaper.parse("## Paper\n1. Define diffusion. **[2 marks]**\n\n## Mark scheme\nQ1: net movement.")
        #expect(paper.maximumMarks == 2)
        #expect(paper.question.contains("Define diffusion"))
        #expect(!paper.question.contains("net movement"))
        #expect(paper.markScheme.contains("net movement"))
    }

    @Test func mathsBracketsAreNotCountedAsMarks() {
        #expect(IBExamRubric.questionMarks(in: "Evaluate $[2]$ and $$[3]$$. (4 marks)") == 4)
    }
}
