import Foundation
import SwiftData

@Model
final class StudySession {
    var id: UUID
    var subjectName: String
    var topicsCovered: String  // comma-separated
    var subtopicsCovered: String?  // comma-separated
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
            subtopicNames: StudyScope.parseList(subtopicsCovered ?? "")
        )
    }

    var hasMeaningfulScope: Bool {
        !subjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (!selectedTopicNames.isEmpty || !StudyScope.parseList(subtopicsCovered ?? "").isEmpty)
    }

    var scopeSummary: String {
        let summary = studyScope.summary
        return summary.isEmpty ? subjectName : summary
    }

    init(subjectName: String, topicsCovered: String, subtopicsCovered: String = "", startDate: Date, endDate: Date = Date(), cardsReviewed: Int, correctCount: Int, xpEarned: Int) {
        self.id = UUID()
        self.subjectName = subjectName
        self.topicsCovered = topicsCovered
        self.subtopicsCovered = subtopicsCovered.isEmpty ? nil : subtopicsCovered
        self.startDate = startDate
        self.endDate = endDate
        self.cardsReviewed = cardsReviewed
        self.correctCount = correctCount
        self.xpEarned = xpEarned
    }

    static func uniqueStudyScopes(from sessions: [StudySession]) -> [StudyScope] {
        var seen = Set<String>()
        var scopes: [StudyScope] = []

        for session in sessions where session.hasMeaningfulScope {
            let scope = session.studyScope
            let key = [
                scope.subjectName,
                scope.topicNames.joined(separator: "|"),
                scope.subtopicNames.joined(separator: "|")
            ].joined(separator: "::").lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            scopes.append(scope)
        }

        return scopes
    }

    static func cardIsWithinStudiedScopes(_ card: StudyCard, sessions: [StudySession]) -> Bool {
        uniqueStudyScopes(from: sessions).contains { $0.matches(card) }
    }
}

extension StudySession: Identifiable {}
