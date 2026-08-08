import Foundation
import SwiftData

nonisolated struct StudySessionSubunitEvidence: Codable, Equatable, Sendable {
    let topicName: String
    let subtopicName: String
    let minutes: Double
    let confidenceRating: Int
    let cardsReviewed: Int
    let correctCount: Int

    var normalizedConfidence: Double {
        min(max(Double(confidenceRating - 1) / 4, 0), 1)
    }

    var accuracy: Double? {
        guard cardsReviewed > 0 else { return nil }
        return min(max(Double(correctCount) / Double(cardsReviewed), 0), 1)
    }
}

@Model
nonisolated final class StudySession {
    var id: UUID
    var subjectName: String
    var topicsCovered: String  // comma-separated
    var subtopicsCovered: String?  // comma-separated
    var startDate: Date
    var endDate: Date
    var cardsReviewed: Int
    var correctCount: Int
    var xpEarned: Int
    var sourcePlanID: UUID?
    var notes: String?
    var evidenceVersion: Int?
    var subunitEvidenceJSON: String?
    var reviewedCardIDsRaw: String?

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

    var subunitEvidence: [StudySessionSubunitEvidence] {
        get {
            guard let subunitEvidenceJSON,
                  let data = subunitEvidenceJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([StudySessionSubunitEvidence].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            evidenceVersion = 1
            guard !newValue.isEmpty,
                  let data = try? JSONEncoder().encode(newValue),
                  let encoded = String(data: data, encoding: .utf8) else {
                subunitEvidenceJSON = nil
                return
            }
            subunitEvidenceJSON = encoded
        }
    }

    var reviewedCardIDs: [UUID] {
        get {
            StudyScope.parseList(reviewedCardIDsRaw ?? "").compactMap(UUID.init(uuidString:))
        }
        set {
            reviewedCardIDsRaw = newValue.map(\.uuidString).joined(separator: ",")
        }
    }

    init(
        id: UUID = UUID(),
        subjectName: String,
        topicsCovered: String,
        subtopicsCovered: String = "",
        startDate: Date,
        endDate: Date = Date(),
        cardsReviewed: Int,
        correctCount: Int,
        xpEarned: Int,
        sourcePlanID: UUID? = nil,
        notes: String = "",
        subunitEvidence: [StudySessionSubunitEvidence] = [],
        reviewedCardIDs: [UUID] = []
    ) {
        self.id = id
        self.subjectName = subjectName
        self.topicsCovered = topicsCovered
        self.subtopicsCovered = subtopicsCovered.isEmpty ? nil : subtopicsCovered
        self.startDate = startDate
        self.endDate = endDate
        self.cardsReviewed = cardsReviewed
        self.correctCount = correctCount
        self.xpEarned = xpEarned
        self.sourcePlanID = sourcePlanID
        self.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        self.evidenceVersion = subunitEvidence.isEmpty ? nil : 1
        self.subunitEvidenceJSON = nil
        self.reviewedCardIDsRaw = nil
        self.subunitEvidence = subunitEvidence
        self.reviewedCardIDs = reviewedCardIDs
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

nonisolated extension StudySession: Identifiable {}
