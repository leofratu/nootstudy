import Testing
import Foundation
import SwiftData
@testable import IBVault

@Suite("Academic Progress Evidence")
struct AcademicProgressTests {
    @Test("Approved mapped scores use the calibrated recall and assessment weights")
    func approvedMappingBlendsEvidence() {
        let card = StudyCard(topicName: "Cells", subtopic: "Cell theory", front: "Q", back: "A")
        card.proficiency = .mastered
        let assessment = AcademicAssessment(
            sourceKey: "cells-test",
            sourceFileName: "assessments.xlsx",
            subjectName: "Biology",
            courseLevel: "HL",
            sourceClassLabel: "IB Biology HL",
            assessmentDate: Date(),
            title: "Cell theory test",
            assessmentType: "Test",
            category: "Summative",
            status: "Graded",
            percentage: 50
        )
        let mapping = AcademicAssessmentMapping(
            assessmentID: assessment.id,
            subjectName: "Biology",
            courseLevel: "HL",
            curriculumNodeKey: "biology.cells.cell-theory",
            unitName: "Cell biology",
            topicName: "Cells",
            subtopicName: "Cell theory",
            status: .approved,
            confidence: 0.92
        )

        let evidence = ProgressEvidenceService.score(
            subjectName: "Biology",
            courseLevel: "HL",
            topicName: "Cells",
            subtopicName: "Cell theory",
            cards: [card],
            assessments: [assessment],
            mappings: [mapping]
        )

        #expect(evidence.recallMastery == 1)
        #expect(evidence.assessmentEvidence == 0.5)
        #expect(abs((evidence.blendedMastery ?? 0) - 0.821_428_571_4) < 0.000_001)
        #expect(evidence.approvedMappingCount == 1)
    }

    @Test("Pending and rejected mappings never affect subunit evidence")
    func unapprovedMappingsAreIgnored() {
        let assessment = AcademicAssessment(
            sourceKey: "cells-quiz",
            sourceFileName: "assessments.xlsx",
            subjectName: "Biology",
            courseLevel: "HL",
            sourceClassLabel: "IB Biology HL",
            assessmentDate: Date(),
            title: "Cell quiz",
            assessmentType: "Quiz",
            category: "Formative",
            status: "Graded",
            percentage: 30
        )
        let mapping = AcademicAssessmentMapping(
            assessmentID: assessment.id,
            subjectName: "Biology",
            courseLevel: "HL",
            curriculumNodeKey: "biology.cells.cell-theory",
            unitName: "Cell biology",
            topicName: "Cells",
            subtopicName: "Cell theory",
            status: .proposed
        )

        let evidence = ProgressEvidenceService.score(
            subjectName: "Biology",
            courseLevel: "HL",
            topicName: "Cells",
            subtopicName: "Cell theory",
            cards: [],
            assessments: [assessment],
            mappings: [mapping]
        )

        #expect(evidence.assessmentEvidence == nil)
        #expect(evidence.blendedMastery == nil)
        #expect(evidence.approvedMappingCount == 0)
    }

    @Test("Subject evidence ignores reports from other courses")
    func reportsAreScopedToTheirSubjectAndLevel() {
        let biology = AcademicAssessment(
            sourceKey: "biology-test",
            sourceFileName: "assessments.xlsx",
            subjectName: "Biology",
            courseLevel: "HL",
            sourceClassLabel: "IB Biology HL",
            assessmentDate: Date(),
            title: "Biology test",
            assessmentType: "Test",
            category: "Summative",
            status: "Graded",
            percentage: 80
        )
        let biologyReport = AcademicReportSnapshot(
            sourceFileName: "biology-report.pdf",
            reportDate: Date(),
            subjectName: "Biology",
            courseLevel: "HL",
            gradeRaw: "6"
        )
        let economicsReport = AcademicReportSnapshot(
            sourceFileName: "economics-report.pdf",
            reportDate: Date(),
            subjectName: "Economics",
            courseLevel: "HL",
            gradeRaw: "1"
        )

        let evidence = ProgressEvidenceService.score(
            subjectName: "Biology",
            courseLevel: "HL",
            cards: [],
            assessments: [biology],
            mappings: [],
            reports: [biologyReport, economicsReport]
        )

        #expect(evidence.assessmentEvidence == (0.8 + 6.0 / 7.0) / 2.0)
        #expect(evidence.scoredAssessmentCount == 2)
    }

    @Test("Completed scoped work uses the exact subunit check-in and time evidence")
    func scopedWorkAddsEngagementEvidence() {
        let session = StudySession(
            subjectName: "Biology",
            topicsCovered: "Cells",
            subtopicsCovered: "Cell theory",
            startDate: Date().addingTimeInterval(-3600),
            endDate: Date(),
            cardsReviewed: 12,
            correctCount: 9,
            xpEarned: 20,
            subunitEvidence: [
                StudySessionSubunitEvidence(
                    topicName: "Cells",
                    subtopicName: "Cell theory",
                    minutes: 60,
                    confidenceRating: 4,
                    cardsReviewed: 12,
                    correctCount: 9
                )
            ]
        )

        let evidence = ProgressEvidenceService.score(
            subjectName: "Biology",
            courseLevel: "HL",
            topicName: "Cells",
            subtopicName: "Cell theory",
            cards: [],
            assessments: [],
            mappings: [],
            workSessions: [session]
        )
        let unrelated = ProgressEvidenceService.score(
            subjectName: "Biology",
            courseLevel: "HL",
            topicName: "Genetics",
            subtopicName: "Inheritance",
            cards: [],
            assessments: [],
            mappings: [],
            workSessions: [session]
        )

        #expect(evidence.completedWorkSessionCount == 1)
        #expect(evidence.completedWorkMinutes == 60)
        #expect(abs((evidence.workMastery ?? 0) - 0.56025) < 0.000_001)
        #expect(abs((evidence.blendedMastery ?? 0) - 0.558_333_333_3) < 0.000_001)
        #expect((evidence.blendedMastery ?? 1) <= 0.65)
        #expect(unrelated.workMastery == nil)
    }

    @Test("Subunit evidence never leaks to a sibling subunit")
    func subunitEvidenceStaysScoped() {
        let session = StudySession(
            subjectName: "Biology",
            topicsCovered: "Cells",
            subtopicsCovered: "Cell theory, Cell membrane",
            startDate: Date().addingTimeInterval(-1800),
            cardsReviewed: 5,
            correctCount: 4,
            xpEarned: 10,
            subunitEvidence: [
                StudySessionSubunitEvidence(
                    topicName: "Cells",
                    subtopicName: "Cell theory",
                    minutes: 30,
                    confidenceRating: 5,
                    cardsReviewed: 5,
                    correctCount: 4
                )
            ]
        )

        let covered = ProgressEvidenceService.score(
            subjectName: "Biology",
            courseLevel: "HL",
            topicName: "Cells",
            subtopicName: "Cell theory",
            cards: [],
            assessments: [],
            mappings: [],
            workSessions: [session]
        )
        let sibling = ProgressEvidenceService.score(
            subjectName: "Biology",
            courseLevel: "HL",
            topicName: "Cells",
            subtopicName: "Cell membrane",
            cards: [],
            assessments: [],
            mappings: [],
            workSessions: [session]
        )

        #expect(covered.blendedMastery != nil)
        #expect((covered.blendedMastery ?? 1) <= 0.65)
        #expect(sibling.blendedMastery == nil)
        #expect(sibling.workMastery == nil)
    }
}
