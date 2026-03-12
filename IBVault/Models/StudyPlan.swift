import Foundation
import SwiftData

enum StudyPlanKind: String, Codable {
    case studySession
    case followUpReview
}

@Model
final class StudyPlan {
    var id: UUID
    var subjectName: String
    var topicName: String
    var subtopicName: String
    var planMarkdown: String
    var createdDate: Date
    var scheduledDate: Date
    var scheduledEndDate: Date
    var isCompleted: Bool
    var notes: String
    var durationMinutes: Int
    var kindRaw: String
    var reviewIntervalDays: Int?

    var kind: StudyPlanKind {
        get { StudyPlanKind(rawValue: kindRaw) ?? .studySession }
        set { kindRaw = newValue.rawValue }
    }

    var isFollowUpReview: Bool {
        kind == .followUpReview
    }

    var scheduleLabel: String {
        if isFollowUpReview {
            if let reviewIntervalDays {
                return "Review • Day \(reviewIntervalDays)"
            }
            return "Review"
        }
        return topicName
    }

    var scheduledTimeFormatted: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "E d MMM, HH:mm"
        return fmt.string(from: scheduledDate)
    }

    var scheduledEndTimeFormatted: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: scheduledEndDate)
    }

    var isUpcoming: Bool {
        !isCompleted && scheduledDate > Date()
    }

    var isActive: Bool {
        !isCompleted && scheduledDate <= Date() && scheduledEndDate >= Date()
    }

    var isPast: Bool {
        isCompleted || scheduledEndDate < Date()
    }

    init(
        subjectName: String,
        topicName: String,
        subtopicName: String = "",
        planMarkdown: String = "",
        scheduledDate: Date,
        durationMinutes: Int = 60,
        notes: String = "",
        kind: StudyPlanKind = .studySession,
        reviewIntervalDays: Int? = nil
    ) {
        self.id = UUID()
        self.subjectName = subjectName
        self.topicName = topicName
        self.subtopicName = subtopicName
        self.planMarkdown = planMarkdown
        self.createdDate = Date()
        self.scheduledDate = scheduledDate
        self.scheduledEndDate = Calendar.current.date(byAdding: .minute, value: durationMinutes, to: scheduledDate) ?? scheduledDate
        self.isCompleted = false
        self.notes = notes
        self.durationMinutes = durationMinutes
        self.kindRaw = kind.rawValue
        self.reviewIntervalDays = reviewIntervalDays
    }
}

extension StudyPlan: Identifiable {}
