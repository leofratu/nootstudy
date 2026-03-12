import Foundation
import SwiftData

@Model
final class Grade {
    var id: UUID
    var component: String // "Paper 1", "Paper 2", "IA", "EE", "TOK", "Overall"
    var score: Int // 1-7
    var predictedGrade: Int? // 1-7
    var date: Date
    var teacherFeedback: String
    var assessmentTitle: String?
    var assessmentCategory: String?
    var achievedPoints: Double?
    var maxPoints: Double?
    var weightPercent: Double?
    var sourceName: String?
    var termName: String?
    var subject: Subject?

    var normalizedScore: Double {
        if let achievedPoints, let maxPoints, maxPoints > 0 {
            return min(max(achievedPoints / maxPoints, 0), 1)
        }
        return min(max(Double(score) / 7.0, 0), 1)
    }

    var resolvedIBScore: Int {
        if (1...7).contains(score) {
            return score
        }
        return Self.ibScore(fromNormalized: normalizedScore)
    }

    var effectiveWeight: Double {
        if let weightPercent, weightPercent > 0 {
            return weightPercent
        }
        return 1
    }

    var hasDetailedBreakdown: Bool {
        (assessmentTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ||
        achievedPoints != nil ||
        maxPoints != nil ||
        weightPercent != nil ||
        sourceName != nil
    }

    var displayTitle: String {
        let trimmedTitle = assessmentTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedTitle.isEmpty ? component : trimmedTitle
    }

    var scoreSummary: String {
        if let achievedPoints, let maxPoints, maxPoints > 0 {
            let pointsText = Self.formatNumber(achievedPoints) + "/" + Self.formatNumber(maxPoints)
            return "\(pointsText) • IB \(resolvedIBScore)"
        }
        return "IB \(resolvedIBScore)"
    }

    init(
        component: String,
        score: Int,
        predictedGrade: Int? = nil,
        teacherFeedback: String = "",
        assessmentTitle: String = "",
        assessmentCategory: String? = nil,
        achievedPoints: Double? = nil,
        maxPoints: Double? = nil,
        weightPercent: Double? = nil,
        sourceName: String? = nil,
        termName: String? = nil,
        subject: Subject? = nil
    ) {
        self.id = UUID()
        self.component = component
        if let achievedPoints, let maxPoints, maxPoints > 0 {
            let normalized = min(max(achievedPoints / maxPoints, 0), 1)
            self.score = Self.ibScore(fromNormalized: normalized)
        } else {
            self.score = min(max(score, 1), 7)
        }
        self.predictedGrade = predictedGrade
        self.date = Date()
        self.teacherFeedback = teacherFeedback
        let trimmedAssessmentTitle = assessmentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.assessmentTitle = trimmedAssessmentTitle.isEmpty ? nil : trimmedAssessmentTitle
        self.assessmentCategory = assessmentCategory
        self.achievedPoints = achievedPoints
        self.maxPoints = maxPoints
        self.weightPercent = weightPercent
        self.sourceName = sourceName
        self.termName = termName
        self.subject = subject
    }

    static func ibScore(fromNormalized normalized: Double) -> Int {
        let clamped = min(max(normalized, 0), 1)
        switch clamped {
        case ..<0.20: return 1
        case ..<0.35: return 2
        case ..<0.50: return 3
        case ..<0.62: return 4
        case ..<0.75: return 5
        case ..<0.88: return 6
        default: return 7
        }
    }

    private static func formatNumber(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(rounded - value) < 0.0001 {
            return String(Int(rounded))
        }
        return String(format: "%.1f", value)
    }
}
