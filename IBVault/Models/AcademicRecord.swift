import Foundation
import SwiftData

nonisolated enum AcademicMappingStatus: String, Codable, CaseIterable, Sendable {
    case unmapped = "Unmapped"
    case proposed = "Proposed"
    case approved = "Approved"
    case rejected = "Rejected"
}

nonisolated enum AcademicImportSource: String, Codable, Sendable {
    case manageBacWorkbook = "ManageBac workbook"
    case reportPDF = "School report PDF"
    case markdownSummary = "School record summary"
}

@Model
nonisolated final class AcademicImport {
    var id: UUID
    var sourceFolderName: String
    var sourceFingerprint: String
    var importedAt: Date
    var assessmentCount: Int
    var curriculumUnitCount: Int
    var reportCount: Int
    var warningCount: Int

    init(
        sourceFolderName: String,
        sourceFingerprint: String,
        assessmentCount: Int = 0,
        curriculumUnitCount: Int = 0,
        reportCount: Int = 0,
        warningCount: Int = 0
    ) {
        self.id = UUID()
        self.sourceFolderName = sourceFolderName
        self.sourceFingerprint = sourceFingerprint
        self.importedAt = Date()
        self.assessmentCount = assessmentCount
        self.curriculumUnitCount = curriculumUnitCount
        self.reportCount = reportCount
        self.warningCount = warningCount
    }
}

@Model
nonisolated final class AcademicAssessment {
    var id: UUID
    var importID: UUID?
    var sourceKey: String
    var sourceFileName: String
    var sourceURLString: String?
    var subjectName: String
    var courseLevel: String
    var sourceClassLabel: String
    var assessmentDate: Date?
    var title: String
    var assessmentType: String
    var category: String
    var status: String
    var achievedPoints: Double?
    var possiblePoints: Double?
    var percentage: Double?
    var ibScore: Int?
    var details: String

    init(
        importID: UUID? = nil,
        sourceKey: String,
        sourceFileName: String,
        sourceURLString: String? = nil,
        subjectName: String,
        courseLevel: String,
        sourceClassLabel: String,
        assessmentDate: Date?,
        title: String,
        assessmentType: String,
        category: String,
        status: String,
        achievedPoints: Double? = nil,
        possiblePoints: Double? = nil,
        percentage: Double? = nil,
        ibScore: Int? = nil,
        details: String = ""
    ) {
        self.id = UUID()
        self.importID = importID
        self.sourceKey = sourceKey
        self.sourceFileName = sourceFileName
        self.sourceURLString = sourceURLString
        self.subjectName = subjectName
        self.courseLevel = courseLevel
        self.sourceClassLabel = sourceClassLabel
        self.assessmentDate = assessmentDate
        self.title = title
        self.assessmentType = assessmentType
        self.category = category
        self.status = status
        self.achievedPoints = achievedPoints
        self.possiblePoints = possiblePoints
        self.percentage = percentage
        self.ibScore = ibScore
        self.details = details
    }

    var normalizedScore: Double? {
        if let percentage {
            return min(max(percentage > 1 ? percentage / 100 : percentage, 0), 1)
        }
        if let achievedPoints, let possiblePoints, possiblePoints > 0 {
            return min(max(achievedPoints / possiblePoints, 0), 1)
        }
        if let ibScore, (1...7).contains(ibScore) {
            return Double(ibScore) / 7.0
        }
        return nil
    }

    var isScored: Bool { normalizedScore != nil }
}

@Model
nonisolated final class AcademicAssessmentMapping {
    var id: UUID
    var assessmentID: UUID
    var subjectName: String
    var courseLevel: String
    var curriculumNodeKey: String
    var unitName: String
    var topicName: String
    var subtopicName: String
    var statusRaw: String
    var confidence: Double
    var rationale: String
    var proposedBy: String
    var updatedAt: Date

    init(
        assessmentID: UUID,
        subjectName: String,
        courseLevel: String,
        curriculumNodeKey: String,
        unitName: String,
        topicName: String,
        subtopicName: String,
        status: AcademicMappingStatus = .proposed,
        confidence: Double = 0,
        rationale: String = "",
        proposedBy: String = "ARIA"
    ) {
        self.id = UUID()
        self.assessmentID = assessmentID
        self.subjectName = subjectName
        self.courseLevel = courseLevel
        self.curriculumNodeKey = curriculumNodeKey
        self.unitName = unitName
        self.topicName = topicName
        self.subtopicName = subtopicName
        self.statusRaw = status.rawValue
        self.confidence = min(max(confidence, 0), 1)
        self.rationale = rationale
        self.proposedBy = proposedBy
        self.updatedAt = Date()
    }

    var status: AcademicMappingStatus {
        get { AcademicMappingStatus(rawValue: statusRaw) ?? .unmapped }
        set { statusRaw = newValue.rawValue; updatedAt = Date() }
    }
}

@Model
nonisolated final class AcademicReportSnapshot {
    var id: UUID
    var importID: UUID?
    var sourceFileName: String
    var reportDate: Date?
    var subjectName: String
    var courseLevel: String
    var gradeRaw: String
    var predictedGradeRaw: String
    var effort: String
    var teacherComment: String

    init(
        importID: UUID? = nil,
        sourceFileName: String,
        reportDate: Date?,
        subjectName: String,
        courseLevel: String,
        gradeRaw: String = "",
        predictedGradeRaw: String = "",
        effort: String = "",
        teacherComment: String = ""
    ) {
        self.id = UUID()
        self.importID = importID
        self.sourceFileName = sourceFileName
        self.reportDate = reportDate
        self.subjectName = subjectName
        self.courseLevel = courseLevel
        self.gradeRaw = gradeRaw
        self.predictedGradeRaw = predictedGradeRaw
        self.effort = effort
        self.teacherComment = teacherComment
    }

    var normalizedGrade: Double? {
        guard let value = Int(gradeRaw.trimmingCharacters(in: .whitespacesAndNewlines)), (1...7).contains(value) else {
            return nil
        }
        return Double(value) / 7.0
    }
}

nonisolated struct AcademicImportPreview: Sendable {
    let sourceFolderName: String
    let sourceFingerprint: String
    let assessments: [AcademicAssessmentDraft]
    let reportSnapshots: [AcademicReportDraft]
    let curriculumUnits: [AcademicCurriculumUnitDraft]
    let warnings: [String]
    let sourceFiles: [String]
}

nonisolated struct AcademicAssessmentDraft: Sendable, Hashable {
    let sourceKey: String
    let sourceFileName: String
    let sourceURLString: String?
    let subjectName: String
    let courseLevel: String
    let sourceClassLabel: String
    let assessmentDate: Date?
    let title: String
    let assessmentType: String
    let category: String
    let status: String
    let achievedPoints: Double?
    let possiblePoints: Double?
    let percentage: Double?
    let ibScore: Int?
    let details: String
}

nonisolated struct AcademicReportDraft: Sendable, Hashable {
    let sourceFileName: String
    let reportDate: Date?
    let subjectName: String
    let courseLevel: String
    let gradeRaw: String
    let predictedGradeRaw: String
    let effort: String
    let teacherComment: String
}

nonisolated struct AcademicCurriculumUnitDraft: Sendable, Hashable {
    let sourceClassLabel: String
    let unitName: String
    let scheduledStart: String
    let durationWeeks: Double?
    let status: String
    let lessonsListed: Int?
    let tasksLinked: Int?
    let sourceURLString: String?
}

nonisolated struct ProgressEvidence: Sendable, Equatable {
    let recallMastery: Double?
    let assessmentEvidence: Double?
    let workMastery: Double?
    let blendedMastery: Double?
    let scoredAssessmentCount: Int
    let approvedMappingCount: Int
    let completedWorkSessionCount: Int
    let completedWorkMinutes: Int
    let dueCardCount: Int
    let lastAssessmentDate: Date?

    var hasEvidence: Bool {
        assessmentEvidence != nil || recallMastery != nil || workMastery != nil
    }
    var isAtRisk: Bool {
        if let blendedMastery { return blendedMastery < 0.5 || dueCardCount > 8 }
        return dueCardCount > 8
    }
}
