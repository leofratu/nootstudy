import Foundation
import SwiftData

/// Maps SwiftData models into the value types the engine consumes.
nonisolated enum SnapshotBuilder: Sendable {

    static func snapshot(for subject: Subject, reviews: [ReviewSession]) -> SubjectSnapshot {
        SubjectSnapshot(
            name: subject.name,
            level: SubjectLevel(rawLevel: subject.level),
            cards: subject.cards.map {
                CardSnapshot(repetitions: $0.repetitions, intervalDays: $0.interval)
            },
            reviews: reviews
                .filter { $0.subjectName == subject.name }
                .map { ReviewSnapshot(timestamp: $0.timestamp, qualityRating: $0.qualityRating) }
        )
    }

    static func snapshots(for subjects: [Subject], reviews: [ReviewSession]) -> [SubjectSnapshot] {
        subjects.map { snapshot(for: $0, reviews: reviews) }
    }
}
