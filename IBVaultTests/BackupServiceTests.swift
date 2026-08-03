import Testing
import Foundation
import SwiftData
@testable import IBVault

@Suite("BackupService Restore Safety")
struct BackupServiceTests {

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for:
            UserProfile.self,
            Subject.self,
            StudyCard.self,
            Grade.self,
            ReviewSession.self,
            ARIAMemory.self,
            ARIAChatSession.self,
            ChatMessage.self,
            StudyActivity.self,
            StudySession.self,
            StudyPlan.self,
            Achievement.self,
            UnitState.self,
            CurriculumNode.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @MainActor
    private func writeFile(_ name: String, content: Data, into dir: URL) throws {
        let url = dir.appendingPathComponent(name)
        try content.write(to: url)
    }

    @MainActor
    @Test("Restore aborts and preserves live data when a backup file is corrupt")
    func restoreAbortsWithoutClearingOnCorruptFile() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let subject = Subject(name: "Biology", level: "HL", accentColorHex: "#10B981")
        context.insert(subject)
        let profile = UserProfile()
        profile.studentName = "Survives"
        context.insert(profile)
        try context.save()

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ibvault_backup_test_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeFile("profile.json", content: Data(#"{"totalXP": "not-an-int"}"#.utf8), into: dir)

        #expect(throws: BackupError.self) {
            try BackupService.restoreFrom(directory: dir, context: context)
        }

        let subjects = try context.fetch(FetchDescriptor<Subject>())
        let profiles = try context.fetch(FetchDescriptor<UserProfile>())
        #expect(subjects.count == 1)
        #expect(subjects.first?.name == "Biology")
        #expect(profiles.first?.studentName == "Survives")
    }

    @MainActor
    @Test("Restore replaces live data atomically for a valid backup")
    func restoreAppliesValidBackup() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let stale = Subject(name: "Physics", level: "SL", accentColorHex: "#0000FF")
        context.insert(stale)
        try context.save()

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ibvault_backup_test_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let iso = ISO8601DateFormatter().string(from: Date())
        let subjectsJSON = """
        [{"name": "Economics", "level": "HL", "accentColorHex": "#F59E0B", "examDate": null, "cards": []}]
        """
        let profileJSON = """
        {"totalXP": 120, "currentStreak": 3, "longestStreak": 5, "streakFreezes": 1, "dailyGoal": 25,
         "achievedRankRaw": 0, "achievedTierRaw": 3, "studentName": "Restored", "studyIntensityRaw": "Average",
         "ibYearRaw": "DP2 (Year 2)", "targetIBScore": 38, "notificationHour": 9, "notificationMinute": 0}
        """
        let metaJSON = """
        {"date": "\(iso)", "fileCount": 2, "version": "1.0"}
        """

        try writeFile("subjects.json", content: Data(subjectsJSON.utf8), into: dir)
        try writeFile("profile.json", content: Data(profileJSON.utf8), into: dir)
        try writeFile("backup_meta.json", content: Data(metaJSON.utf8), into: dir)

        try BackupService.restoreFrom(directory: dir, context: context)

        let subjects = try context.fetch(FetchDescriptor<Subject>())
        let profiles = try context.fetch(FetchDescriptor<UserProfile>())
        #expect(subjects.map(\.name) == ["Economics"])
        #expect(subjects.first?.level == "HL")
        #expect(profiles.first?.studentName == "Restored")
        #expect(profiles.first?.targetIBScore == 38)
    }
}
