import Foundation

// MARK: - DTO shapes as per spec (camelCase JSON)

nonisolated struct CardDTO: Codable, Sendable {
    let id: UUID
    let subjectName: String
    let topicName: String
    let subtopic: String
    let front: String
    let back: String
    let hint: String?
    let difficulty: String?
    let cognitiveSkill: String?
    let cardStyle: String?
    let choices: [String]
    let proficiency: String
    let nextReviewDate: Date
    let totalReviewCount: Int
    let successfulReviewCount: Int
    let createdDate: Date
}

nonisolated struct ReviewDTO: Codable, Sendable {
    let id: UUID
    let cardID: UUID
    let subjectName: String
    let topicName: String
    let quality: Int
    let timestamp: Date
    let durationSeconds: Double
}

nonisolated struct SessionDTO: Codable, Sendable {
    let id: UUID
    let subjectName: String
    let topicsCovered: [String]
    let startDate: Date
    let endDate: Date
    let cardsReviewed: Int
    let correctCount: Int
    let xpEarned: Int
    let notes: String?
}

nonisolated struct GradeDTO: Codable, Sendable {
    let id: UUID
    let subjectName: String
    let component: String
    let score: Int
    let predictedGrade: Int?
    let date: Date
    let assessmentTitle: String?
    let feedback: String?
}

nonisolated struct PlanDTO: Codable, Sendable {
    let id: UUID
    let subjectName: String
    let topicNames: [String]
    let scheduledDate: Date
    let scheduledEndDate: Date
    let durationMinutes: Int
    let isCompleted: Bool
    let notes: String?
    let planMarkdown: String?
}

nonisolated struct ActivityDTO: Codable, Sendable {
    let id: UUID
    let externalID: String
    let source: String
    let kind: String
    let subjectName: String?
    let topicName: String?
    let minutes: Double
    let cardsReviewed: Int
    let correctCount: Int
    let occurredAt: Date
    let details: String?
    let status: String
    let importedAt: Date
    let mergedStudySessionID: UUID?
}

nonisolated struct SubjectDTO: Codable, Sendable {
    let name: String
    let level: String
    let examDate: Date?
    let cardCount: Int
    let dueCount: Int
    let mastery: Double
    let rank: String?
}

nonisolated struct MemoryDTO: Codable, Sendable {
    let id: UUID
    let category: String
    let content: String
    let timestamp: Date
    let subjectName: String?
}

nonisolated struct AchievementDTO: Codable, Sendable {
    let id: String
    let title: String
    let unlocked: Bool
}

// MARK: - Mapping helpers

nonisolated enum BridgeDTOFactory: Sendable {
    static func cardDTO(from card: StudyCard) -> CardDTO {
        CardDTO(
            id: card.id,
            subjectName: card.subject?.name ?? "",
            topicName: card.topicName,
            subtopic: card.subtopic,
            front: card.front,
            back: card.back,
            hint: card.hint,
            difficulty: card.difficultyRaw,
            cognitiveSkill: card.cognitiveSkillRaw,
            cardStyle: card.cardStyleRaw,
            choices: card.choices,
            proficiency: card.proficiencyRaw,
            nextReviewDate: card.nextReviewDate,
            totalReviewCount: card.totalReviewCount,
            successfulReviewCount: card.successfulReviewCount,
            createdDate: card.createdDate
        )
    }

    static func reviewDTO(from review: ReviewSession) -> ReviewDTO {
        ReviewDTO(
            id: review.id,
            cardID: review.cardID,
            subjectName: review.subjectName,
            topicName: review.topicName,
            quality: review.qualityRating,
            timestamp: review.timestamp,
            durationSeconds: review.sessionDuration
        )
    }

    static func sessionDTO(from session: StudySession) -> SessionDTO {
        SessionDTO(
            id: session.id,
            subjectName: session.subjectName,
            topicsCovered: session.selectedTopicNames,
            startDate: session.startDate,
            endDate: session.endDate,
            cardsReviewed: session.cardsReviewed,
            correctCount: session.correctCount,
            xpEarned: session.xpEarned,
            notes: session.notes
        )
    }

    static func gradeDTO(from grade: Grade) -> GradeDTO {
        GradeDTO(
            id: grade.id,
            subjectName: grade.subject?.name ?? "",
            component: grade.component,
            score: grade.score,
            predictedGrade: grade.predictedGrade,
            date: grade.date,
            assessmentTitle: grade.assessmentTitle,
            feedback: grade.teacherFeedback
        )
    }

    static func planDTO(from plan: StudyPlan) -> PlanDTO {
        PlanDTO(
            id: plan.id,
            subjectName: plan.subjectName,
            topicNames: plan.selectedTopicNames,
            scheduledDate: plan.scheduledDate,
            scheduledEndDate: plan.scheduledEndDate,
            durationMinutes: plan.durationMinutes,
            isCompleted: plan.isCompleted,
            notes: plan.notes.isEmpty ? nil : plan.notes,
            planMarkdown: plan.planMarkdown.isEmpty ? nil : plan.planMarkdown
        )
    }

    static func subjectDTO(from subject: Subject, mastery: Double) -> SubjectDTO {
        SubjectDTO(
            name: subject.name,
            level: subject.level,
            examDate: subject.examDate,
            cardCount: subject.cards.count,
            dueCount: subject.dueCardsCount,
            mastery: mastery,
            rank: nil
        )
    }

    static func memoryDTO(from memory: ARIAMemory) -> MemoryDTO {
        MemoryDTO(
            id: memory.id,
            category: memory.categoryRaw,
            content: memory.content,
            timestamp: memory.timestamp,
            subjectName: memory.subjectName
        )
    }
}
