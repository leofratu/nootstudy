import Testing
import Foundation
import SwiftData
@testable import IBVault

@Suite("ExternalActivity Tests", .serialized)
struct ExternalActivityTests {

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: ExternalActivity.self, StudySession.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test("Idempotent import by source+externalID")
    func idempotentImport() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let dto = ExternalActivityImportDTO(externalID: "ext-1", source: "strava", kind: "run", subjectName: "Biology", topicName: "Cells", minutes: 30, cardsReviewed: 5, correctCount: 3, occurredAt: Date(), details: nil)
        let r1 = ExternalActivityService.importActivities([dto], context: ctx)
        #expect(r1.accepted == 1 && r1.duplicates == 0)
        let r2 = ExternalActivityService.importActivities([dto], context: ctx)
        #expect(r2.accepted == 0 && r2.duplicates == 1)
        let all = ExternalActivityService.listAll(context: ctx)
        #expect(all.count == 1)
    }

    @MainActor
    @Test("Merge creates one session and re-merge is no-op")
    func mergeCreatesSession() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let dto = ExternalActivityImportDTO(externalID: "ext-2", source: "duolingo", kind: "study", subjectName: "Biology", topicName: "Genetics", minutes: 20, cardsReviewed: 10, correctCount: 7, occurredAt: Date().addingTimeInterval(-3600), details: "external work")
        _ = ExternalActivityService.importActivities([dto], context: ctx)
        let pending = ExternalActivityService.listPending(context: ctx)
        #expect(pending.count == 1)
        let id = pending.first!.id
        let merged1 = ExternalActivityService.merge(ids: [id], context: ctx)
        #expect(merged1.count == 1)
        let sessionID = merged1.first!.studySessionID
        let merged2 = ExternalActivityService.merge(ids: [id], context: ctx)
        #expect(merged2.count == 1)
        #expect(merged2.first!.studySessionID == sessionID)
        let sessions = try ctx.fetch(FetchDescriptor<StudySession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.id == sessionID)
        let pendingAfter = ExternalActivityService.listPending(context: ctx)
        #expect(pendingAfter.isEmpty)
    }
}
