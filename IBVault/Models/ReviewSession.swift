import Foundation
import SwiftData

@Model
nonisolated final class ReviewSession {
    var id: UUID
    var timestamp: Date
    var cardID: UUID
    var subjectName: String
    var topicName: String
    var qualityRating: Int // 0-5 mapped from RecallQuality
    var fsrsRatingRaw: Int?
    var schedulerVersion: Int?
    var sessionDuration: TimeInterval
    var wasCorrect: Bool
    var studySessionID: UUID?

    init(
        cardID: UUID,
        subjectName: String,
        topicName: String,
        qualityRating: Int,
        sessionDuration: TimeInterval = 0,
        studySessionID: UUID? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.cardID = cardID
        self.subjectName = subjectName
        self.topicName = topicName
        self.qualityRating = qualityRating
        self.fsrsRatingRaw = nil
        self.schedulerVersion = nil
        self.sessionDuration = sessionDuration
        self.wasCorrect = qualityRating >= 3
        self.studySessionID = studySessionID
    }
}
