import Foundation
import SwiftData

@Model
final class ReviewSession {
    var id: UUID
    var timestamp: Date
    var cardID: UUID
    var subjectName: String
    var topicName: String
    var qualityRating: Int // 0-5 mapped from RecallQuality
    var sessionDuration: TimeInterval
    var wasCorrect: Bool

    init(cardID: UUID, subjectName: String, topicName: String, qualityRating: Int, sessionDuration: TimeInterval = 0) {
        self.id = UUID()
        self.timestamp = Date()
        self.cardID = cardID
        self.subjectName = subjectName
        self.topicName = topicName
        self.qualityRating = qualityRating
        self.sessionDuration = sessionDuration
        self.wasCorrect = qualityRating >= 3
    }
}
