import Foundation
import SwiftData

@Model
nonisolated final class ExternalActivity {
    var id: UUID
    var externalID: String
    var source: String
    var kindRaw: String
    var subjectName: String?
    var topicName: String?
    var minutes: Double
    var cardsReviewed: Int
    var correctCount: Int
    var occurredAt: Date
    var details: String?
    var importedAt: Date
    var statusRaw: String
    var mergedStudySessionID: UUID?

    var kind: String {
        get { kindRaw }
        set { kindRaw = newValue }
    }

    var status: String {
        get { statusRaw }
        set { statusRaw = newValue }
    }

    init(
        id: UUID = UUID(),
        externalID: String,
        source: String,
        kindRaw: String,
        subjectName: String? = nil,
        topicName: String? = nil,
        minutes: Double,
        cardsReviewed: Int,
        correctCount: Int,
        occurredAt: Date,
        details: String? = nil,
        importedAt: Date = Date(),
        statusRaw: String = "pending",
        mergedStudySessionID: UUID? = nil
    ) {
        self.id = id
        self.externalID = externalID
        self.source = source
        self.kindRaw = kindRaw
        self.subjectName = subjectName
        self.topicName = topicName
        self.minutes = minutes
        self.cardsReviewed = cardsReviewed
        self.correctCount = correctCount
        self.occurredAt = occurredAt
        self.details = details
        self.importedAt = importedAt
        self.statusRaw = statusRaw
        self.mergedStudySessionID = mergedStudySessionID
    }
}

nonisolated extension ExternalActivity: Identifiable {}
