import Foundation
import SwiftData

@Model
final class CurriculumNode {
    var id: UUID
    var subjectName: String
    var level: String
    var unitName: String
    var topicName: String
    var subtopicName: String
    var catalogVersion: String
    var sourceTitle: String
    var sourceURLString: String
    var updatedAt: Date

    var stableKey: String {
        Self.stableKey(
            subjectName: subjectName,
            level: level,
            unitName: unitName,
            topicName: topicName,
            subtopicName: subtopicName
        )
    }

    init(
        subjectName: String,
        level: String,
        unitName: String,
        topicName: String,
        subtopicName: String,
        catalogVersion: String,
        sourceTitle: String,
        sourceURLString: String
    ) {
        self.id = UUID()
        self.subjectName = subjectName
        self.level = level
        self.unitName = unitName
        self.topicName = topicName
        self.subtopicName = subtopicName
        self.catalogVersion = catalogVersion
        self.sourceTitle = sourceTitle
        self.sourceURLString = sourceURLString
        self.updatedAt = Date()
    }

    static func stableKey(
        subjectName: String,
        level: String,
        unitName: String,
        topicName: String,
        subtopicName: String
    ) -> String {
        [subjectName, level, unitName, topicName, subtopicName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: "|")
    }
}
