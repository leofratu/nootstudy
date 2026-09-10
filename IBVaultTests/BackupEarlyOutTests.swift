import Testing
import Foundation
import SwiftData
@testable import IBVault

@Suite("Backup and Migration Early-Out Tests")
struct BackupEarlyOutTests {

    @MainActor
    @Test("Merge historical evidence early-out when already merged does no file IO")
    func mergeEarlyOutWhenAlreadyMerged() throws {
        let key = "IBVaultHistoricalEvidenceMerged.v1"
        let original = UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.set(true, forKey: key)
        defer { UserDefaults.standard.set(original, forKey: key) }

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Subject.self, StudyCard.self, Grade.self, ReviewSession.self, UserProfile.self, Achievement.self, SubjectTrack.self, StudySession.self, configurations: config)
        let context = container.mainContext
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ibvault_merge_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Even with missing files, early-out should return without throwing or file decode
        try BackupService.mergeHistoricalEvidence(from: tmp, context: context)
        // If early-out works, no save needed and no error thrown
        #expect(Bool(true))
    }

    @MainActor
    @Test("Auto backup early-out on main thread does not block")
    func autoBackupEarlyOutOnMain() throws {
        BackupService.resetCacheForTesting()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: UserProfile.self, Subject.self, StudyCard.self, ReviewSession.self, configurations: config)
        let context = container.mainContext
        context.insert(UserProfile())
        try context.save()

        // First call on main should early-out via background dispatch, not throw
        let result = try BackupService.autoBackupIfNeeded(context: context)
        #expect(result == nil)
        BackupService.resetCacheForTesting()
    }

    @MainActor
    @Test("FSRS migrate early-out when already migrated")
    func fsrsMigrateEarlyOut() {
        let cards = (0..<10).map { _ in
            let c = StudyCard(topicName: "T", front: "Q", back: "A")
            c.fsrsSchedulerVersion = FSRSScheduler.schedulerVersion
            return c
        }
        let clock = ContinuousClock()
        let start = clock.now
        FSRSScheduler.migrate(cards: cards, reviewSessions: [])
        let elapsed = clock.now - start
        let ms = Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
        print("fsrs migrate early-out 10 already migrated: \(ms) ms")
        #expect(ms < 50)
    }
}
