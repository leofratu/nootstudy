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

    @Test("Batch subject scoring matches per-subject scoring, including same-name subjects at different levels")
    func batchScoringMatchesIndividualScoring() {
        let biologyHL = Subject(name: "Biology", level: "HL", accentColorHex: "#10B981")
        let biologySL = Subject(name: "Biology", level: "SL", accentColorHex: "#0EA5E9")
        let economics = Subject(name: "Economics", level: "HL", accentColorHex: "#F0AD2E")

        let bioAssessment = AcademicAssessment(
            sourceKey: "bio-hl",
            sourceFileName: "assessments.xlsx",
            subjectName: "Biology",
            courseLevel: "HL",
            sourceClassLabel: "IB Biology HL",
            assessmentDate: Date(),
            title: "Cells test",
            assessmentType: "Test",
            category: "Summative",
            status: "Graded",
            percentage: 72
        )
        let economicsAssessment = AcademicAssessment(
            sourceKey: "econ-hl",
            sourceFileName: "assessments.xlsx",
            subjectName: "Economics",
            courseLevel: "HL",
            sourceClassLabel: "IB Economics HL",
            assessmentDate: Date(),
            title: "Micro test",
            assessmentType: "Test",
            category: "Summative",
            status: "Graded",
            percentage: 65
        )
        let bioReport = AcademicReportSnapshot(
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
            gradeRaw: "5"
        )
        let bioSession = StudySession(
            subjectName: "Biology",
            topicsCovered: "Cells",
            startDate: Date().addingTimeInterval(-3600),
            cardsReviewed: 8,
            correctCount: 7,
            xpEarned: 12
        )
        let economicsSession = StudySession(
            subjectName: "Economics",
            topicsCovered: "Demand",
            startDate: Date().addingTimeInterval(-1800),
            cardsReviewed: 5,
            correctCount: 3,
            xpEarned: 8
        )

        let subjects = [biologyHL, biologySL, economics]
        let assessments = [bioAssessment, economicsAssessment]
        let reports = [bioReport, economicsReport]
        let sessions = [bioSession, economicsSession]

        let batch = ProgressEvidenceService.scoreBySubject(
            subjects: subjects,
            assessments: assessments,
            mappings: [],
            reports: reports,
            workSessions: sessions
        )

        for subject in subjects {
            let expected = ProgressEvidenceService.score(
                subjectName: subject.name,
                courseLevel: subject.level,
                cards: subject.cards,
                assessments: assessments,
                mappings: [],
                reports: reports,
                workSessions: sessions
            )
            #expect(batch[subject.id] == expected)
        }
    }

    private func reviewedCard(accuracy: Int = 5, lastReviewed: Date = Date()) -> StudyCard {
        let card = StudyCard(topicName: "Cells", subtopic: "Theory", front: "Q", back: "A")
        card.proficiency = .mastered
        card.totalReviewCount = 5
        card.successfulReviewCount = accuracy
        card.consecutiveCorrect = accuracy
        card.lastReviewedDate = lastReviewed
        return card
    }

    private func loggedSession(minutes: Double) -> StudySession {
        StudySession(
            subjectName: "Biology",
            topicsCovered: "Cells",
            startDate: Date().addingTimeInterval(-minutes * 60),
            endDate: Date(),
            cardsReviewed: 0,
            correctCount: 0,
            xpEarned: 0
        )
    }

    @Test("Logged sessions raise mastery on top of cards and never lower it")
    func studyTimeRaisesMastery() {
        let cards = [reviewedCard(accuracy: 4)]
        let before = ProgressEvidenceService.score(
            subjectName: "Biology", courseLevel: "HL", cards: cards, assessments: [], mappings: []
        )
        let after = ProgressEvidenceService.score(
            subjectName: "Biology", courseLevel: "HL", cards: cards, assessments: [], mappings: [],
            workSessions: [loggedSession(minutes: 240)]
        )
        #expect(abs((before.blendedMastery ?? 0) - 0.8) < 0.000_001)
        #expect(abs((after.blendedMastery ?? 0) - 0.82) < 0.000_001)
    }

    @Test("Prior grades and logged sessions both count with no cards reviewed")
    func gradesAndSessionsCountWithoutCards() {
        let report = AcademicReportSnapshot(
            sourceFileName: "report.pdf",
            reportDate: nil,
            subjectName: "Biology",
            courseLevel: "HL",
            gradeRaw: "5"
        )
        let gradeOnly = ProgressEvidenceService.score(
            subjectName: "Biology", courseLevel: "HL", cards: [], assessments: [], mappings: [], reports: [report]
        )
        let withSession = ProgressEvidenceService.score(
            subjectName: "Biology", courseLevel: "HL", cards: [], assessments: [], mappings: [], reports: [report],
            workSessions: [loggedSession(minutes: 60)]
        )
        #expect(abs((gradeOnly.blendedMastery ?? 0) - 5.0 / 7.0) < 0.000_001)
        #expect((withSession.blendedMastery ?? 0) > (gradeOnly.blendedMastery ?? 0))
    }

    @Test("One strong card does not stand in for a whole unreviewed deck")
    func unreviewedCardsLimitRecall() {
        let unreviewed = (0..<9).map { _ in StudyCard(topicName: "Cells", front: "Q", back: "A") }
        let evidence = ProgressEvidenceService.score(
            subjectName: "Biology", courseLevel: "HL", cards: [reviewedCard()] + unreviewed,
            assessments: [], mappings: []
        )
        #expect(abs((evidence.blendedMastery ?? 0) - 0.1) < 0.000_001)
    }

    @Test("Unreviewed cards leave a real grade in charge instead of zeroing it")
    func unreviewedCardsDeferToGrade() {
        let report = AcademicReportSnapshot(
            sourceFileName: "report.pdf",
            reportDate: nil,
            subjectName: "Biology",
            courseLevel: "HL",
            gradeRaw: "7"
        )
        let unreviewed = (0..<9).map { _ in StudyCard(topicName: "Cells", front: "Q", back: "A") }
        let evidence = ProgressEvidenceService.score(
            subjectName: "Biology", courseLevel: "HL", cards: unreviewed,
            assessments: [], mappings: [], reports: [report]
        )
        #expect(evidence.blendedMastery == 1)
    }

    @Test("Recall fades when a subject is neglected")
    func neglectFadesRecall() {
        let now = Date()
        let evidence = ProgressEvidenceService.score(
            subjectName: "Biology", courseLevel: "HL",
            cards: [reviewedCard(lastReviewed: now.addingTimeInterval(-90 * 86_400))],
            assessments: [], mappings: [], now: now
        )
        #expect(abs((evidence.blendedMastery ?? 0) - MasterySignals.freshnessFloor) < 0.000_001)
    }
}
