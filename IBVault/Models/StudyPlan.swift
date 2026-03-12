import Foundation
import SwiftData

struct StudyScope: Equatable {
    let subjectName: String
    let unitNames: [String]
    let topicNames: [String]
    let subtopicNames: [String]

    var hasFilters: Bool {
        !topicNames.isEmpty || !subtopicNames.isEmpty || !unitNames.isEmpty
    }

    var title: String {
        if !topicNames.isEmpty {
            return topicNames.joined(separator: ", ")
        }
        if !unitNames.isEmpty {
            return unitNames.joined(separator: ", ")
        }
        return subjectName
    }

    var summary: String {
        var parts: [String] = []
        if !unitNames.isEmpty {
            parts.append(unitNames.joined(separator: ", "))
        }
        if !topicNames.isEmpty {
            parts.append(topicNames.joined(separator: ", "))
        }
        if !subtopicNames.isEmpty {
            parts.append(subtopicNames.joined(separator: ", "))
        }
        return parts.joined(separator: " • ")
    }

    func matches(_ card: StudyCard) -> Bool {
        if !subjectName.isEmpty, let cardSubjectName = card.subject?.name, cardSubjectName != subjectName {
            return false
        }

        if !topicNames.isEmpty, !topicNames.contains(card.topicName) {
            return false
        }

        guard !subtopicNames.isEmpty else { return true }
        let normalizedCardSubtopic = card.subtopic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCardSubtopic.isEmpty, normalizedCardSubtopic != card.topicName else {
            return true
        }

        return subtopicNames.contains(normalizedCardSubtopic)
    }

    static func parseList(_ rawValue: String) -> [String] {
        rawValue
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

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

    var selectedTopicNames: [String] {
        StudyScope.parseList(topicName)
    }

    var selectedSubtopicNames: [String] {
        StudyScope.parseList(subtopicName)
    }

    var selectedUnitNames: [String] {
        SyllabusSeeder.unitNames(for: subjectName, topicNames: selectedTopicNames)
    }

    var studyScope: StudyScope {
        StudyScope(
            subjectName: subjectName,
            unitNames: selectedUnitNames,
            topicNames: selectedTopicNames,
            subtopicNames: selectedSubtopicNames
        )
    }

    var selectionSummary: String {
        let summary = studyScope.summary
        return summary.isEmpty ? topicName : summary
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
