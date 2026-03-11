import Foundation
import SwiftData

@Model
final class Grade {
    var id: UUID
    var component: String // "Paper 1", "Paper 2", "IA", "EE", "TOK", "Overall"
    var score: Int // 1-7
    var predictedGrade: Int? // 1-7
    var date: Date
    var teacherFeedback: String
    var subject: Subject?

    init(component: String, score: Int, predictedGrade: Int? = nil, teacherFeedback: String = "", subject: Subject? = nil) {
        self.id = UUID()
        self.component = component
        self.score = score
        self.predictedGrade = predictedGrade
        self.date = Date()
        self.teacherFeedback = teacherFeedback
        self.subject = subject
    }
}
