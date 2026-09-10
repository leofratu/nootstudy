import Foundation
import SwiftData

enum ExternalActivityService: Sendable {

    struct ImportResult: Sendable {
        let accepted: Int
        let duplicates: Int
    }

    struct MergeResult: Sendable {
        let id: UUID
        let studySessionID: UUID
    }

    /// Idempotent import by (source, externalID)
    nonisolated static func importActivities(_ dtos: [ExternalActivityImportDTO], context: ModelContext) -> ImportResult {
        let existing = (try? context.fetch(FetchDescriptor<ExternalActivity>())) ?? []
        var existingKeys = Set(existing.map { "\($0.source)|\($0.externalID)" })
        var accepted = 0
        var duplicates = 0
        for dto in dtos {
            let key = "\(dto.source)|\(dto.externalID)"
            if existingKeys.contains(key) {
                duplicates += 1
                continue
            }
            let activity = ExternalActivity(
                externalID: dto.externalID,
                source: dto.source,
                kindRaw: dto.kind,
                subjectName: dto.subjectName,
                topicName: dto.topicName,
                minutes: dto.minutes,
                cardsReviewed: dto.cardsReviewed,
                correctCount: dto.correctCount,
                occurredAt: dto.occurredAt,
                details: dto.details,
                importedAt: Date(),
                statusRaw: "pending"
            )
            context.insert(activity)
            existingKeys.insert(key)
            accepted += 1
        }
        if accepted > 0 {
            try? context.save()
        }
        return ImportResult(accepted: accepted, duplicates: duplicates)
    }

    nonisolated static func listPending(context: ModelContext) -> [ExternalActivity] {
        let all = (try? context.fetch(FetchDescriptor<ExternalActivity>())) ?? []
        return all.filter { $0.statusRaw == "pending" }
    }

    nonisolated static func listAll(context: ModelContext) -> [ExternalActivity] {
        (try? context.fetch(FetchDescriptor<ExternalActivity>())) ?? []
    }

    /// Merge into a StudySession (create with source marker in notes, dedupe)
    nonisolated static func merge(ids: [UUID], context: ModelContext) -> [MergeResult] {
        let all = (try? context.fetch(FetchDescriptor<ExternalActivity>())) ?? []
        var results: [MergeResult] = []
        for id in ids {
            guard let activity = all.first(where: { $0.id == id }) else { continue }
            if activity.statusRaw == "merged", let sessionID = activity.mergedStudySessionID {
                results.append(MergeResult(id: activity.id, studySessionID: sessionID))
                continue
            }
            let session = StudySession(
                subjectName: activity.subjectName ?? "General",
                topicsCovered: activity.topicName ?? "",
                subtopicsCovered: "",
                startDate: activity.occurredAt,
                endDate: activity.occurredAt.addingTimeInterval(activity.minutes * 60),
                cardsReviewed: activity.cardsReviewed,
                correctCount: activity.correctCount,
                xpEarned: max(activity.cardsReviewed * 2, 0),
                notes: "[External: \(activity.source) \(activity.externalID)] \(activity.details ?? "")".trimmingCharacters(in: .whitespacesAndNewlines)
            )
            context.insert(session)
            activity.statusRaw = "merged"
            activity.mergedStudySessionID = session.id
            results.append(MergeResult(id: activity.id, studySessionID: session.id))
        }
        if !results.isEmpty {
            try? context.save()
        }
        return results
    }

    nonisolated static func delete(id: UUID, context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<ExternalActivity>())) ?? []
        if let activity = all.first(where: { $0.id == id }) {
            context.delete(activity)
            try? context.save()
        }
    }
}

struct ExternalActivityImportDTO: Codable, Sendable {
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
}
