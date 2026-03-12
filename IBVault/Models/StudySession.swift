import Foundation
import SwiftData

@Model
final class StudySession {
    var id: UUID
    var subjectName: String
    var topicsCovered: String  // comma-separated
    var startDate: Date
    var endDate: Date
    var cardsReviewed: Int
    var correctCount: Int
    var xpEarned: Int

    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }

    var durationFormatted: String {
        let minutes = Int(duration / 60)
        if minutes < 1 { return "<1 min" }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    var retentionPercent: Int {
        cardsReviewed == 0 ? 0 : correctCount * 100 / cardsReviewed
    }

    var selectedTopicNames: [String] {
        StudyScope.parseList(topicsCovered)
    }

    var studyScope: StudyScope {
        StudyScope(
            subjectName: subjectName,
            unitNames: SyllabusSeeder.unitNames(for: subjectName, topicNames: selectedTopicNames),
            topicNames: selectedTopicNames,
            subtopicNames: []
        )
    }

    var scopeSummary: String {
        let summary = studyScope.summary
        return summary.isEmpty ? subjectName : summary
    }

    init(subjectName: String, topicsCovered: String, startDate: Date, endDate: Date = Date(), cardsReviewed: Int, correctCount: Int, xpEarned: Int) {
        self.id = UUID()
        self.subjectName = subjectName
        self.topicsCovered = topicsCovered
        self.startDate = startDate
        self.endDate = endDate
        self.cardsReviewed = cardsReviewed
        self.correctCount = correctCount
        self.xpEarned = xpEarned
    }
}

extension StudySession: Identifiable {}
