import Testing
import Foundation
import SwiftData
@testable import IBVault

@Suite("BackupService Restore Safety", .serialized)
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
            AcademicImport.self,
            AcademicAssessment.self,
            AcademicAssessmentMapping.self,
            AcademicReportSnapshot.self,
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

    @MainActor
    @Test("Export writes decodable subjects.json and profile.json into a fresh backup dir")
    func exportBackupWritesValidFiles() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let subject = Subject(name: "Biology", level: "HL", accentColorHex: "#10B981")
        context.insert(subject)
        let card = StudyCard(topicName: "Cells", subtopic: "Cell theory", front: "What is a cell?", back: "Basic unit of life.", subject: subject)
        card.proficiency = .developing
        context.insert(card)
        let profile = UserProfile()
        profile.studentName = "Exporter"
        profile.targetIBScore = 40
        context.insert(profile)
        try context.save()

        let exportedDir = try BackupService.exportBackup(container: container)
        defer { try? FileManager.default.removeItem(at: exportedDir) }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let subjects = try decoder.decode(
            [SubjectBackup].self,
            from: Data(contentsOf: exportedDir.appendingPathComponent("subjects.json"))
        )
        let profileBackup = try decoder.decode(
            ProfileBackup.self,
            from: Data(contentsOf: exportedDir.appendingPathComponent("profile.json"))
        )
        let meta = try decoder.decode(
            BackupMeta.self,
            from: Data(contentsOf: exportedDir.appendingPathComponent("backup_meta.json"))
        )

        #expect(subjects.map(\.name) == ["Biology"])
        #expect(subjects.first?.level == "HL")
        #expect(subjects.first?.cards.count == 1)
        #expect(subjects.first?.cards.first?.front == "What is a cell?")
        #expect(subjects.first?.cards.first?.proficiencyRaw == ProficiencyLevel.developing.rawValue)
        #expect(profileBackup.studentName == "Exporter")
        #expect(profileBackup.targetIBScore == 40)
        #expect(meta.fileCount >= 2)
    }

    @MainActor
    @Test("A backup produced by exportBackup restores into a fresh store and round-trips")
    func exportedBackupRestoresRoundTrip() throws {
        defer { ADHDMedicationSettings.clearFromDefaults() }

        let source = try makeContainer()
        let sourceContext = source.mainContext

        let subject = Subject(name: "Biology", level: "HL", accentColorHex: "#10B981")
        sourceContext.insert(subject)
        let card = StudyCard(topicName: "Cells", subtopic: "Cell theory", front: "Who proposed the cell theory?", back: "Schleiden and Schwann", subject: subject)
        card.proficiency = .developing
        card.interval = 5
        sourceContext.insert(card)
        let profile = UserProfile()
        profile.studentName = "Round Trip"
        profile.currentStreak = 4
        profile.targetIBScore = 38
        sourceContext.insert(profile)
        let memory = ARIAMemory(category: .weakTopics, content: "Confuses mitosis and meiosis", subjectName: "Biology")
        sourceContext.insert(memory)
        let assessment = AcademicAssessment(
            sourceKey: "biology-test-1",
            sourceFileName: "assessments.xlsx",
            subjectName: "Biology",
            courseLevel: "HL",
            sourceClassLabel: "IB Biology HL",
            assessmentDate: Date(),
            title: "Cell biology test",
            assessmentType: "Test",
            category: "Summative",
            status: "Graded",
            percentage: 82
        )
        sourceContext.insert(assessment)
        sourceContext.insert(AcademicAssessmentMapping(
            assessmentID: assessment.id,
            subjectName: "Biology",
            courseLevel: "HL",
            curriculumNodeKey: "biology.cells.cell-theory",
            unitName: "Cell biology",
            topicName: "Cells",
            subtopicName: "Cell theory",
            status: .approved,
            confidence: 0.9
        ))
        try sourceContext.save()

        let exportedDir = try BackupService.exportBackup(container: source)
        defer { try? FileManager.default.removeItem(at: exportedDir) }

        let target = try makeContainer()
        let targetContext = target.mainContext
        try BackupService.restoreFrom(directory: exportedDir, context: targetContext)

        let subjects = try targetContext.fetch(FetchDescriptor<Subject>())
        let cards = try targetContext.fetch(FetchDescriptor<StudyCard>())
        let profiles = try targetContext.fetch(FetchDescriptor<UserProfile>())
        let memories = try targetContext.fetch(FetchDescriptor<ARIAMemory>())
        let assessments = try targetContext.fetch(FetchDescriptor<AcademicAssessment>())
        let mappings = try targetContext.fetch(FetchDescriptor<AcademicAssessmentMapping>())

        #expect(subjects.count == 1)
        #expect(subjects.first?.name == "Biology")
        #expect(subjects.first?.level == "HL")
        #expect(subjects.first?.cards.count == 1)
        #expect(cards.count == 1)
        #expect(cards.first?.subject?.name == "Biology")
        #expect(cards.first?.front == "Who proposed the cell theory?")
        #expect(cards.first?.proficiency == .developing)
        #expect(cards.first?.interval == 5)
        #expect(profiles.count == 1)
        #expect(profiles.first?.studentName == "Round Trip")
        #expect(profiles.first?.currentStreak == 4)
        #expect(memories.count == 1)
        #expect(memories.first?.content == "Confuses mitosis and meiosis")
        #expect(assessments.first?.normalizedScore == 0.82)
        #expect(mappings.first?.status == .approved)
    }

    @MainActor
    @Test("Restore from an empty backup directory throws before clearing live data")
    func emptyBackupDirectoryThrowsBeforeClearing() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let subject = Subject(name: "Chemistry", level: "SL", accentColorHex: "#3B82F6")
        context.insert(subject)
        let profile = UserProfile()
        profile.studentName = "Keeper"
        context.insert(profile)
        try context.save()

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ibvault_empty_backup_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(throws: BackupError.self) {
            try BackupService.restoreFrom(directory: dir, context: context)
        }

        let subjects = try context.fetch(FetchDescriptor<Subject>())
        let profiles = try context.fetch(FetchDescriptor<UserProfile>())
        #expect(subjects.count == 1)
        #expect(subjects.first?.name == "Chemistry")
        #expect(profiles.first?.studentName == "Keeper")
    }
}
