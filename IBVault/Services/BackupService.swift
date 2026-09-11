import Foundation
import SwiftData

nonisolated struct BackupService {
    private static let folderName = "IBVault Backups"
    private static let automaticBackupInterval: TimeInterval = 60 * 60 * 24

    nonisolated static var backupDirectory: URL {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return FileManager.default.temporaryDirectory.appendingPathComponent(folderName)
        }
        let dir = docs.appendingPathComponent(folderName)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        excludeFromBackupIfNeeded(dir)
        return dir
    }

    /// Backups contain full chat transcripts and medical (ADHD) settings in
    /// plaintext, so they must never be synced to iCloud or Time Machine.
    ///
    /// Runs once on a background queue and never touches the main thread.
    /// Reading `resourceValues(forKeys: [.isExcludedFromBackupKey])` calls
    /// `CSBackupIsItemExcluded` → `getxattr`, which can block indefinitely on
    /// some volumes/environments and previously hung app launch under the test
    /// host. Setting the value directly avoids that read.
    nonisolated(unsafe) private static var hasConfiguredBackupExclusion = false

    private static func excludeFromBackupIfNeeded(_ directory: URL) {
        guard !hasConfiguredBackupExclusion else { return }
        hasConfiguredBackupExclusion = true
        DispatchQueue.global(qos: .utility).async {
            var mutable = directory
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? mutable.setResourceValues(resourceValues)
        }
    }

    nonisolated(unsafe) private static var cachedLatestBackupDate: Date?
    nonisolated(unsafe) private static var cachedLatestBackupDateIsValid = false

    nonisolated static var latestBackupDate: Date? {
        if cachedLatestBackupDateIsValid {
            return cachedLatestBackupDate
        }
        // Never do file IO on the main thread; return cached value (nil on first launch)
        if Thread.isMainThread {
            return cachedLatestBackupDate
        }
        let metaURL = backupDirectory.appendingPathComponent("backup_meta.json")
        guard let data = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(BackupMeta.self, from: data) else {
            cachedLatestBackupDate = nil
            cachedLatestBackupDateIsValid = true
            return nil
        }
        cachedLatestBackupDate = meta.date
        cachedLatestBackupDateIsValid = true
        return meta.date
    }

    static func resetCacheForTesting() {
        cachedLatestBackupDate = nil
        cachedLatestBackupDateIsValid = false
        hasConfiguredBackupExclusion = false
    }

    @discardableResult
    nonisolated static func autoBackupIfNeeded(context: ModelContext) throws -> URL? {
        // Cheap early-out without file IO when interval not elapsed.
        if let cached = cachedLatestBackupDate, cachedLatestBackupDateIsValid,
           Date().timeIntervalSince(cached) < automaticBackupInterval {
            return nil
        }
        if Thread.isMainThread {
            // Never block main with file IO; schedule background check and return early.
            let container = context.container
            Task.detached(priority: .utility) {
                let bgContext = ModelContext(container)
                _ = try? BackupService.autoBackupIfNeeded(context: bgContext)
            }
            return nil
        }
        if let latestBackupDate,
           Date().timeIntervalSince(latestBackupDate) < automaticBackupInterval {
            return nil
        }
        let url = try exportBackup(context: context)
        cachedLatestBackupDate = Date()
        cachedLatestBackupDateIsValid = true
        return url
    }

    // MARK: - Export All Data

    /// Exports against a scratch context derived from the caller's store, so a
    /// background caller never touches a context it did not create.
    nonisolated static func exportBackup(context: ModelContext) throws -> URL {
        try exportBackup(container: context.container)
    }

    /// Exports using a fresh scratch context created from the container. The
    /// container is `Sendable` (safe to share across threads), so a background
    /// queue can drive the export without touching any context from the main
    /// actor. Reads the committed store state.
    nonisolated static func exportBackup(container: ModelContainer) throws -> URL {
        let scratch = ModelContext(container)
        return try performExport(using: scratch)
    }

    private static func performExport(using context: ModelContext) throws -> URL {
        let dir = backupDirectory
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let backupDir = dir.appendingPathComponent("backup_\(timestamp.replacingOccurrences(of: ":", with: "-"))")
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        var writtenFiles: [String] = []

        let profiles = try fetchAll(UserProfile.self, context: context)
        if let profile = profiles.first {
            try write(ProfileBackup(from: profile), named: "profile.json", into: backupDir, encoder: encoder)
            writtenFiles.append("profile.json")
        }

        let subjects = try fetchAll(Subject.self, context: context)
        try write(subjects.map(SubjectBackup.init), named: "subjects.json", into: backupDir, encoder: encoder)
        writtenFiles.append("subjects.json")

        let grades = try fetchAll(Grade.self, context: context)
        try write(grades.map(GradeBackup.init), named: "grades.json", into: backupDir, encoder: encoder)
        writtenFiles.append("grades.json")

        let sessions = try fetchAll(ReviewSession.self, context: context)
        try write(sessions.map(SessionBackup.init), named: "review_sessions.json", into: backupDir, encoder: encoder)
        writtenFiles.append("review_sessions.json")

        let memories = try fetchAll(ARIAMemory.self, context: context)
        try write(memories.map(MemoryBackup.init), named: "aria_memory.json", into: backupDir, encoder: encoder)
        writtenFiles.append("aria_memory.json")

        let chatSessions = try fetchAll(ARIAChatSession.self, context: context)
        try write(chatSessions.map(ChatSessionBackup.init), named: "aria_chat_sessions.json", into: backupDir, encoder: encoder)
        writtenFiles.append("aria_chat_sessions.json")

        let chats = try fetchAll(ChatMessage.self, context: context)
        try write(chats.map(ChatBackup.init), named: "chat_history.json", into: backupDir, encoder: encoder)
        writtenFiles.append("chat_history.json")

        let activities = try fetchAll(StudyActivity.self, context: context)
        try write(activities.map(ActivityBackup.init), named: "study_activity.json", into: backupDir, encoder: encoder)
        writtenFiles.append("study_activity.json")

        let studySessions = try fetchAll(StudySession.self, context: context)
        try write(studySessions.map(StudySessionBackup.init), named: "study_sessions.json", into: backupDir, encoder: encoder)
        writtenFiles.append("study_sessions.json")

        let studyPlans = try fetchAll(StudyPlan.self, context: context)
        try write(studyPlans.map(StudyPlanBackup.init), named: "study_plans.json", into: backupDir, encoder: encoder)
        writtenFiles.append("study_plans.json")

        let achievements = try fetchAll(Achievement.self, context: context)
        try write(achievements.map(AchievementBackup.init), named: "achievements.json", into: backupDir, encoder: encoder)
        writtenFiles.append("achievements.json")

        let unitStates = try fetchAll(UnitState.self, context: context)
        try write(unitStates.map(UnitStateBackup.init), named: "unit_states.json", into: backupDir, encoder: encoder)
        writtenFiles.append("unit_states.json")

        let curriculumNodes = try fetchAll(CurriculumNode.self, context: context)
        try write(curriculumNodes.map(CurriculumNodeBackup.init), named: "curriculum_progress.json", into: backupDir, encoder: encoder)
        writtenFiles.append("curriculum_progress.json")

        let academicImports = try fetchAll(AcademicImport.self, context: context)
        try write(academicImports.map(AcademicImportBackup.init), named: "academic_imports.json", into: backupDir, encoder: encoder)
        writtenFiles.append("academic_imports.json")

        let academicAssessments = try fetchAll(AcademicAssessment.self, context: context)
        try write(academicAssessments.map(AcademicAssessmentBackup.init), named: "academic_assessments.json", into: backupDir, encoder: encoder)
        writtenFiles.append("academic_assessments.json")

        let academicMappings = try fetchAll(AcademicAssessmentMapping.self, context: context)
        try write(academicMappings.map(AcademicAssessmentMappingBackup.init), named: "academic_mappings.json", into: backupDir, encoder: encoder)
        writtenFiles.append("academic_mappings.json")

        let academicReports = try fetchAll(AcademicReportSnapshot.self, context: context)
        try write(academicReports.map(AcademicReportSnapshotBackup.init), named: "academic_reports.json", into: backupDir, encoder: encoder)
        writtenFiles.append("academic_reports.json")
        
        let adhdSettings = ADHDMedicationSettings.loadFromDefaults()
        try write(ADHDMedicationBackup(from: adhdSettings), named: "adhd_medication.json", into: backupDir, encoder: encoder)
        writtenFiles.append("adhd_medication.json")

        let meta = BackupMeta(date: Date(), fileCount: writtenFiles.count, version: appVersion())
        let metaData = try encoder.encode(meta)
        try metaData.write(to: backupDir.appendingPathComponent("backup_meta.json"))
        try metaData.write(to: dir.appendingPathComponent("backup_meta.json"))

        return backupDir
    }

    // MARK: - Restore

    static func restoreFromLatest(context: ModelContext) throws {
        let dir = backupDirectory
        let contents = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
        // Only completed exports are restorable. A `backup_` directory left by
        // an interrupted export can still decode the files it contains, which
        // would pass the hasAnyDataset guard and then clear every dataset the
        // partial export does not carry. The meta file is written last, so its
        // presence marks a finished backup.
        let backupDirs = contents
            .filter { $0.hasDirectoryPath && $0.lastPathComponent.hasPrefix("backup_") }
            .filter {
                let metaURL = $0.appendingPathComponent("backup_meta.json")
                guard let data = try? Data(contentsOf: metaURL) else { return false }
                return (try? JSONDecoder().decode(BackupMeta.self, from: data)) != nil
            }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        guard let latest = backupDirs.first else { throw BackupError.noBackupFound }
        try restoreFrom(directory: latest, context: context)
    }

    /// Recovers historical evidence without replacing the live subjects/cards.
    /// Older full exports contain mastery and session history that predates the
    /// current store; those records are safe to merge by UUID.
    static func mergeHistoricalEvidence(from directory: URL, container: ModelContainer) throws {
        if UserDefaults.standard.bool(forKey: "IBVaultHistoricalEvidenceMerged.v1") {
            return
        }
        let context = ModelContext(container)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let subjectsByName = Dictionary((try context.fetch(FetchDescriptor<Subject>())).map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let grades = try decodeOrNil([GradeBackup].self, fileName: "grades.json", from: directory, decoder: decoder) ?? []
        let reviews = try decodeOrNil([SessionBackup].self, fileName: "review_sessions.json", from: directory, decoder: decoder) ?? []
        let studySessions = try decodeOrNil([StudySessionBackup].self, fileName: "study_sessions.json", from: directory, decoder: decoder) ?? []
        let curriculum = try decodeOrNil([CurriculumNodeBackup].self, fileName: "curriculum_progress.json", from: directory, decoder: decoder) ?? []
        let reports = try decodeOrNil([AcademicReportSnapshotBackup].self, fileName: "academic_reports.json", from: directory, decoder: decoder) ?? []

        let existingGrades = Set((try context.fetch(FetchDescriptor<Grade>())).map(\.id))
        for backup in grades where !existingGrades.contains(backup.id) { context.insert(backup.toModel(subjectsByName: subjectsByName)) }
        let existingReviews = Set((try context.fetch(FetchDescriptor<ReviewSession>())).map(\.id))
        for backup in reviews where !existingReviews.contains(backup.id) { context.insert(backup.toModel()) }
        let existingStudySessions = Set((try context.fetch(FetchDescriptor<StudySession>())).map(\.id))
        for backup in studySessions where !existingStudySessions.contains(backup.id) { context.insert(backup.toModel()) }
        let existingNodes = Set((try context.fetch(FetchDescriptor<CurriculumNode>())).map(\.id))
        for backup in curriculum where !existingNodes.contains(backup.id) { context.insert(backup.toModel()) }
        let existingReports = Set((try context.fetch(FetchDescriptor<AcademicReportSnapshot>())).map(\.id))
        for backup in reports where !existingReports.contains(backup.id) { context.insert(backup.toModel()) }
        try context.save()
    }

    static func mergeHistoricalEvidence(from directory: URL, context: ModelContext) throws {
        // Cheap early-out when already merged; avoids any file IO.
        if UserDefaults.standard.bool(forKey: "IBVaultHistoricalEvidenceMerged.v1") {
            return
        }
        // Never do file IO on the main thread synchronously.
        if Thread.isMainThread {
            let container = context.container
            Task.detached(priority: .utility) {
                try? BackupService.mergeHistoricalEvidence(from: directory, container: container)
            }
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let subjectsByName = Dictionary((try context.fetch(FetchDescriptor<Subject>())).map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let grades = try decodeOrNil([GradeBackup].self, fileName: "grades.json", from: directory, decoder: decoder) ?? []
        let reviews = try decodeOrNil([SessionBackup].self, fileName: "review_sessions.json", from: directory, decoder: decoder) ?? []
        let studySessions = try decodeOrNil([StudySessionBackup].self, fileName: "study_sessions.json", from: directory, decoder: decoder) ?? []
        let curriculum = try decodeOrNil([CurriculumNodeBackup].self, fileName: "curriculum_progress.json", from: directory, decoder: decoder) ?? []
        let reports = try decodeOrNil([AcademicReportSnapshotBackup].self, fileName: "academic_reports.json", from: directory, decoder: decoder) ?? []

        let existingGrades = Set((try context.fetch(FetchDescriptor<Grade>())).map(\.id))
        for backup in grades where !existingGrades.contains(backup.id) { context.insert(backup.toModel(subjectsByName: subjectsByName)) }
        let existingReviews = Set((try context.fetch(FetchDescriptor<ReviewSession>())).map(\.id))
        for backup in reviews where !existingReviews.contains(backup.id) { context.insert(backup.toModel()) }
        let existingStudySessions = Set((try context.fetch(FetchDescriptor<StudySession>())).map(\.id))
        for backup in studySessions where !existingStudySessions.contains(backup.id) { context.insert(backup.toModel()) }
        let existingNodes = Set((try context.fetch(FetchDescriptor<CurriculumNode>())).map(\.id))
        for backup in curriculum where !existingNodes.contains(backup.id) { context.insert(backup.toModel()) }
        let existingReports = Set((try context.fetch(FetchDescriptor<AcademicReportSnapshot>())).map(\.id))
        for backup in reports where !existingReports.contains(backup.id) { context.insert(backup.toModel()) }
        try context.save()
    }

    static func restoreFrom(directory: URL, context: ModelContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Phase 1: Decode and validate every file BEFORE touching live data.
        // A restore must never destroy existing data because one file is missing
        // or corrupt. Missing files are fine (added by a later feature); a file
        // that exists but cannot be decoded aborts the whole restore.
        let profile = try decodeOrNil(ProfileBackup.self, fileName: "profile.json", from: directory, decoder: decoder)
        let subjectBackups = try decodeOrNil([SubjectBackup].self, fileName: "subjects.json", from: directory, decoder: decoder)
        let gradeBackups = try decodeOrNil([GradeBackup].self, fileName: "grades.json", from: directory, decoder: decoder)
        let sessionBackups = try decodeOrNil([SessionBackup].self, fileName: "review_sessions.json", from: directory, decoder: decoder)
        let memoryBackups = try decodeOrNil([MemoryBackup].self, fileName: "aria_memory.json", from: directory, decoder: decoder)
        let chatSessionBackups = try decodeOrNil([ChatSessionBackup].self, fileName: "aria_chat_sessions.json", from: directory, decoder: decoder)
        let chatBackups = try decodeOrNil([ChatBackup].self, fileName: "chat_history.json", from: directory, decoder: decoder)
        let activityBackups = try decodeOrNil([ActivityBackup].self, fileName: "study_activity.json", from: directory, decoder: decoder)
        let studySessionBackups = try decodeOrNil([StudySessionBackup].self, fileName: "study_sessions.json", from: directory, decoder: decoder)
        let studyPlanBackups = try decodeOrNil([StudyPlanBackup].self, fileName: "study_plans.json", from: directory, decoder: decoder)
        let achievementBackups = try decodeOrNil([AchievementBackup].self, fileName: "achievements.json", from: directory, decoder: decoder)
        let unitStateBackups = try decodeOrNil([UnitStateBackup].self, fileName: "unit_states.json", from: directory, decoder: decoder)
        let curriculumNodeBackups = try decodeOrNil([CurriculumNodeBackup].self, fileName: "curriculum_progress.json", from: directory, decoder: decoder)
        let academicImportBackups = try decodeOrNil([AcademicImportBackup].self, fileName: "academic_imports.json", from: directory, decoder: decoder)
        let academicAssessmentBackups = try decodeOrNil([AcademicAssessmentBackup].self, fileName: "academic_assessments.json", from: directory, decoder: decoder)
        let academicMappingBackups = try decodeOrNil([AcademicAssessmentMappingBackup].self, fileName: "academic_mappings.json", from: directory, decoder: decoder)
        let academicReportBackups = try decodeOrNil([AcademicReportSnapshotBackup].self, fileName: "academic_reports.json", from: directory, decoder: decoder)
        let adhdBackup = try decodeOrNil(ADHDMedicationBackup.self, fileName: "adhd_medication.json", from: directory, decoder: decoder)

        // A backup directory that decodes to zero datasets is not a real
        // backup (e.g. an export interrupted before its first file was
        // written). Proceeding would wipe every live row and insert nothing,
        // so abort before any clearAll() touches the store.
        let hasAnyDataset = profile != nil
            || subjectBackups != nil
            || gradeBackups != nil
            || sessionBackups != nil
            || memoryBackups != nil
            || chatSessionBackups != nil
            || chatBackups != nil
            || activityBackups != nil
            || studySessionBackups != nil
            || studyPlanBackups != nil
            || achievementBackups != nil
            || unitStateBackups != nil
            || curriculumNodeBackups != nil
            || academicImportBackups != nil
            || academicAssessmentBackups != nil
            || academicMappingBackups != nil
            || academicReportBackups != nil
            || adhdBackup != nil
        guard hasAnyDataset else { throw BackupError.noBackupFound }

        // Duplicate subject names are legal in live data; collapse them instead
        // of trapping in Dictionary(uniqueKeysWithValues:).
        let subjectModels = (subjectBackups ?? []).map { $0.toModel() }
        let subjectsByName = Dictionary(
            subjectModels.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Phase 2: Every file decoded. Now it is safe to replace live data.
        try clearAll(UserProfile.self, context: context)
        try clearAll(Subject.self, context: context)
        try clearAll(Grade.self, context: context)
        try clearAll(ReviewSession.self, context: context)
        try clearAll(ARIAMemory.self, context: context)
        try clearAll(ARIAChatSession.self, context: context)
        try clearAll(ChatMessage.self, context: context)
        try clearAll(StudyActivity.self, context: context)
        try clearAll(StudySession.self, context: context)
        try clearAll(StudyPlan.self, context: context)
        try clearAll(Achievement.self, context: context)
        try clearAll(UnitState.self, context: context)
        try clearAll(CurriculumNode.self, context: context)
        try clearAll(AcademicImport.self, context: context)
        try clearAll(AcademicAssessment.self, context: context)
        try clearAll(AcademicAssessmentMapping.self, context: context)
        try clearAll(AcademicReportSnapshot.self, context: context)

        if let backup = profile {
            context.insert(backup.toModel())
        }

        for subject in subjectModels {
            context.insert(subject)
        }

        if let backups = gradeBackups {
            for backup in backups {
                context.insert(backup.toModel(subjectsByName: subjectsByName))
            }
        }

        if let backups = sessionBackups {
            for backup in backups {
                context.insert(backup.toModel())
            }
        }

        if let backups = memoryBackups {
            for backup in backups {
                context.insert(backup.toModel())
            }
        }

        if let backups = chatSessionBackups {
            for backup in backups {
                context.insert(backup.toModel())
            }
        }

        if let backups = chatBackups {
            for backup in backups {
                context.insert(backup.toModel())
            }
        }

        if let backups = activityBackups {
            for backup in backups {
                context.insert(backup.toModel())
            }
        }

        if let backups = studySessionBackups {
            for backup in backups {
                context.insert(backup.toModel())
            }
        }

        if let backups = studyPlanBackups {
            for backup in backups {
                context.insert(backup.toModel())
            }
        }

        if let backups = achievementBackups {
            for backup in backups {
                context.insert(backup.toModel())
            }
        }

        if let backups = unitStateBackups {
            for backup in backups {
                context.insert(backup.toModel())
            }
        }

        if let backups = curriculumNodeBackups {
            for backup in backups {
                context.insert(backup.toModel())
            }
        }

        if let backups = academicImportBackups {
            for backup in backups { context.insert(backup.toModel()) }
        }
        if let backups = academicAssessmentBackups {
            for backup in backups { context.insert(backup.toModel()) }
        }
        if let backups = academicMappingBackups {
            for backup in backups { context.insert(backup.toModel()) }
        }
        if let backups = academicReportBackups {
            for backup in backups { context.insert(backup.toModel()) }
        }

        if let backup = adhdBackup {
            let adhdSettings = backup.toSettings()
            adhdSettings.saveToDefaults()
        }

        try context.save()
        SyllabusSeeder.synchronizeCurriculum(context: context)
    }

    // MARK: - List Backups

    nonisolated static func listBackups() -> [(name: String, date: Date, url: URL)] {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles) else { return [] }
        return contents.filter { $0.hasDirectoryPath && $0.lastPathComponent.hasPrefix("backup_") }
            .compactMap { url in
                let metaURL = url.appendingPathComponent("backup_meta.json")
                if let data = try? Data(contentsOf: metaURL),
                   let meta = try? JSONDecoder().decode(BackupMeta.self, from: data) {
                    return (name: url.lastPathComponent, date: meta.date, url: url)
                }
                return nil
            }
            .sorted { $0.date > $1.date }
    }

    nonisolated static func deleteBackup(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    private static func clearAll<Model: PersistentModel>(_ type: Model.Type, context: ModelContext) throws {
        let existing = try fetchAll(type, context: context)
        existing.forEach { context.delete($0) }
    }

    /// Fetch every row of a dataset, surfacing a fetch failure instead of
    /// silently omitting the dataset. `performExport` writes whole datasets to
    /// disk, so a failed fetch must abort the export rather than produce a
    /// backup that silently lacks data.
    private static func fetchAll<Model: PersistentModel>(_ type: Model.Type, context: ModelContext) throws -> [Model] {
        do {
            return try context.fetch(FetchDescriptor<Model>())
        } catch {
            throw BackupError.fetchFailed(dataset: String(describing: Model.self))
        }
    }

    private static func write<Value: Encodable>(_ value: Value, named fileName: String, into directory: URL, encoder: JSONEncoder) throws {
        let data = try encoder.encode(value)
        try data.write(to: directory.appendingPathComponent(fileName))
    }

    /// Returns nil when the file does not exist (that dataset was never backed
    /// up) and throws `.corruptedBackup` when the file exists but cannot be
    /// decoded, so a partial or damaged backup never silently drops data.
    private static func decodeOrNil<Value: Decodable>(_ type: Value.Type, fileName: String, from directory: URL, decoder: JSONDecoder) throws -> Value? {
        let fileURL = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        guard let data = try? Data(contentsOf: fileURL),
              let value = try? decoder.decode(type, from: data) else {
            throw BackupError.corruptedBackup(fileName: fileName)
        }
        return value
    }

    private static func appVersion() -> String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
    }
}

// MARK: - Errors
enum BackupError: Error, LocalizedError, Sendable {
    case noBackupFound
    case corruptedBackup(fileName: String)
    case fetchFailed(dataset: String)

    var errorDescription: String? {
        switch self {
        case .noBackupFound:
            return "No backup found to restore"
        case .corruptedBackup(let fileName):
            return "Backup data is corrupted: \(fileName) could not be read."
        case .fetchFailed(let dataset):
            return "Backup could not read the \(dataset) dataset from the store."
        }
    }
}

// MARK: - Backup Meta
nonisolated struct BackupMeta: Codable {
    let date: Date
    let fileCount: Int
    let version: String
}

// MARK: - Backup Models (Codable mirrors of SwiftData models)

nonisolated struct ProfileBackup: Codable {
    let totalXP: Int; let currentStreak: Int; let longestStreak: Int
    let streakFreezes: Int; let dailyGoal: Int
    let achievedRankRaw: Int; let achievedTierRaw: Int
    let studentName: String; let studyIntensityRaw: String; let ibYearRaw: String
    let targetIBScore: Int; let notificationHour: Int; let notificationMinute: Int

    init(from p: UserProfile) {
        totalXP = p.totalXP; currentStreak = p.currentStreak; longestStreak = p.longestStreak
        streakFreezes = p.streakFreezes; dailyGoal = p.dailyGoal
        achievedRankRaw = p.achievedRankRaw; achievedTierRaw = p.achievedTierRaw
        studentName = p.studentName; studyIntensityRaw = p.studyIntensityRaw; ibYearRaw = p.ibYearRaw
        targetIBScore = p.targetIBScore; notificationHour = p.notificationHour; notificationMinute = p.notificationMinute
    }

    func toModel() -> UserProfile {
        let p = UserProfile()
        p.totalXP = totalXP; p.currentStreak = currentStreak; p.longestStreak = longestStreak
        p.streakFreezes = streakFreezes; p.dailyGoal = dailyGoal
        p.achievedRankRaw = achievedRankRaw; p.achievedTierRaw = achievedTierRaw
        p.studentName = studentName; p.studyIntensityRaw = studyIntensityRaw; p.ibYearRaw = ibYearRaw
        p.targetIBScore = targetIBScore; p.notificationHour = notificationHour; p.notificationMinute = notificationMinute
        p.onboardingCompleted = true
        return p
    }
}

nonisolated struct SubjectBackup: Codable {
    let name: String; let level: String; let accentColorHex: String; let examDate: Date?
    let cards: [CardBackup]

    init(from s: Subject) {
        name = s.name; level = s.level; accentColorHex = s.accentColorHex; examDate = s.examDate
        cards = s.cards.map { CardBackup(from: $0) }
    }

    func toModel() -> Subject {
        let s = Subject(name: name, level: level, accentColorHex: accentColorHex, examDate: examDate)
        for cb in cards {
            let card = cb.toModel()
            card.subject = s
            s.cards.append(card)
        }
        return s
    }
}

nonisolated struct CardBackup: Codable {
    let id: UUID; let topicName: String; let subtopic: String; let front: String; let back: String
    let easeFactor: Double; let interval: Int; let repetitions: Int
    let nextReviewDate: Date; let proficiencyRaw: String; let consecutiveCorrect: Int
    let isCustom: Bool; let isAIGenerated: Bool?; let createdDate: Date
    let lastReviewedDate: Date?; let generationSource: String?
    let totalReviewCount: Int; let successfulReviewCount: Int
    let hint: String?; let difficultyRaw: String?; let cognitiveSkillRaw: String?
    let sourceTitle: String?; let sourceURLString: String?; let syllabusReference: String?
    let adaptationReason: String?; let generationPromptVersion: Int?
    let sourceStudyPlanID: UUID?; let sourceStudySessionID: UUID?
    let fsrsStability: Double?; let fsrsDifficulty: Double?; let fsrsElapsedDays: Double?; let fsrsScheduledDays: Double?
    let fsrsRepetitions: Int?; let fsrsLapses: Int?; let fsrsStateRaw: Int?; let fsrsLastReviewDate: Date?; let fsrsSchedulerVersion: Int?
    let cardStyleRaw: String?
    let choicesJSON: String?

    init(from c: StudyCard) {
        id = c.id; topicName = c.topicName; subtopic = c.subtopic; front = c.front; back = c.back
        easeFactor = c.easeFactor; interval = c.interval; repetitions = c.repetitions
        nextReviewDate = c.nextReviewDate; proficiencyRaw = c.proficiencyRaw
        consecutiveCorrect = c.consecutiveCorrect; isCustom = c.isCustom
        isAIGenerated = c.isAIGenerated; createdDate = c.createdDate
        lastReviewedDate = c.lastReviewedDate; generationSource = c.generationSource
        totalReviewCount = c.totalReviewCount; successfulReviewCount = c.successfulReviewCount
        hint = c.hint; difficultyRaw = c.difficultyRaw; cognitiveSkillRaw = c.cognitiveSkillRaw
        sourceTitle = c.sourceTitle; sourceURLString = c.sourceURLString; syllabusReference = c.syllabusReference
        adaptationReason = c.adaptationReason; generationPromptVersion = c.generationPromptVersion
        sourceStudyPlanID = c.sourceStudyPlanID; sourceStudySessionID = c.sourceStudySessionID
        fsrsStability = c.fsrsStability; fsrsDifficulty = c.fsrsDifficulty; fsrsElapsedDays = c.fsrsElapsedDays
        fsrsScheduledDays = c.fsrsScheduledDays; fsrsRepetitions = c.fsrsRepetitions; fsrsLapses = c.fsrsLapses
        fsrsStateRaw = c.fsrsStateRaw; fsrsLastReviewDate = c.fsrsLastReviewDate; fsrsSchedulerVersion = c.fsrsSchedulerVersion
        cardStyleRaw = c.cardStyleRaw
        choicesJSON = c.choicesJSON
    }

    func toModel() -> StudyCard {
        let c = StudyCard(
            topicName: topicName,
            subtopic: subtopic,
            front: front,
            back: back,
            isCustom: isCustom,
            isAIGenerated: isAIGenerated,
            generationSource: generationSource
        )
        c.id = id
        c.easeFactor = easeFactor; c.interval = interval; c.repetitions = repetitions
        c.nextReviewDate = nextReviewDate; c.proficiencyRaw = proficiencyRaw
        c.consecutiveCorrect = consecutiveCorrect
        c.createdDate = createdDate; c.lastReviewedDate = lastReviewedDate
        c.totalReviewCount = totalReviewCount; c.successfulReviewCount = successfulReviewCount
        c.hint = hint; c.difficultyRaw = difficultyRaw; c.cognitiveSkillRaw = cognitiveSkillRaw
        c.sourceTitle = sourceTitle; c.sourceURLString = sourceURLString; c.syllabusReference = syllabusReference
        c.adaptationReason = adaptationReason; c.generationPromptVersion = generationPromptVersion
        c.sourceStudyPlanID = sourceStudyPlanID; c.sourceStudySessionID = sourceStudySessionID
        c.fsrsStability = fsrsStability; c.fsrsDifficulty = fsrsDifficulty; c.fsrsElapsedDays = fsrsElapsedDays
        c.fsrsScheduledDays = fsrsScheduledDays; c.fsrsRepetitions = fsrsRepetitions; c.fsrsLapses = fsrsLapses
        c.fsrsStateRaw = fsrsStateRaw; c.fsrsLastReviewDate = fsrsLastReviewDate; c.fsrsSchedulerVersion = fsrsSchedulerVersion
        c.cardStyleRaw = cardStyleRaw
        c.choicesJSON = choicesJSON
        return c
    }
}

nonisolated struct UnitStateBackup: Codable {
    let subjectName: String
    let unitName: String
    let isTaught: Bool

    init(from state: UnitState) {
        subjectName = state.subjectName
        unitName = state.unitName
        isTaught = state.isTaught
    }

    func toModel() -> UnitState {
        UnitState(subjectName: subjectName, unitName: unitName, isTaught: isTaught)
    }
}

nonisolated struct CurriculumNodeBackup: Codable {
    let id: UUID
    let subjectName: String
    let level: String
    let unitName: String
    let topicName: String
    let subtopicName: String
    let catalogVersion: String
    let sourceTitle: String
    let sourceURLString: String
    let updatedAt: Date
    let recordedMasteryRaw: String?
    let masteryUpdatedAt: Date?
    let masterySource: String?
    let masteryNote: String?

    init(from node: CurriculumNode) {
        id = node.id
        subjectName = node.subjectName
        level = node.level
        unitName = node.unitName
        topicName = node.topicName
        subtopicName = node.subtopicName
        catalogVersion = node.catalogVersion
        sourceTitle = node.sourceTitle
        sourceURLString = node.sourceURLString
        updatedAt = node.updatedAt
        recordedMasteryRaw = node.recordedMasteryRaw
        masteryUpdatedAt = node.masteryUpdatedAt
        masterySource = node.masterySource
        masteryNote = node.masteryNote
    }

    func toModel() -> CurriculumNode {
        let node = CurriculumNode(
            subjectName: subjectName,
            level: level,
            unitName: unitName,
            topicName: topicName,
            subtopicName: subtopicName,
            catalogVersion: catalogVersion,
            sourceTitle: sourceTitle,
            sourceURLString: sourceURLString
        )
        node.id = id
        node.updatedAt = updatedAt
        node.recordedMasteryRaw = recordedMasteryRaw
        node.masteryUpdatedAt = masteryUpdatedAt
        node.masterySource = masterySource
        node.masteryNote = masteryNote
        return node
    }
}

nonisolated struct AcademicImportBackup: Codable {
    let id: UUID; let sourceFolderName: String; let sourceFingerprint: String; let importedAt: Date
    let assessmentCount: Int; let curriculumUnitCount: Int; let reportCount: Int; let warningCount: Int

    init(from record: AcademicImport) {
        id = record.id; sourceFolderName = record.sourceFolderName; sourceFingerprint = record.sourceFingerprint
        importedAt = record.importedAt; assessmentCount = record.assessmentCount; curriculumUnitCount = record.curriculumUnitCount
        reportCount = record.reportCount; warningCount = record.warningCount
    }

    func toModel() -> AcademicImport {
        let record = AcademicImport(sourceFolderName: sourceFolderName, sourceFingerprint: sourceFingerprint, assessmentCount: assessmentCount, curriculumUnitCount: curriculumUnitCount, reportCount: reportCount, warningCount: warningCount)
        record.id = id; record.importedAt = importedAt
        return record
    }
}

nonisolated struct AcademicAssessmentBackup: Codable {
    let id: UUID; let importID: UUID?; let sourceKey: String; let sourceFileName: String; let sourceURLString: String?
    let subjectName: String; let courseLevel: String; let sourceClassLabel: String; let assessmentDate: Date?
    let title: String; let assessmentType: String; let category: String; let status: String
    let achievedPoints: Double?; let possiblePoints: Double?; let percentage: Double?; let ibScore: Int?; let details: String

    init(from assessment: AcademicAssessment) {
        id = assessment.id; importID = assessment.importID; sourceKey = assessment.sourceKey; sourceFileName = assessment.sourceFileName; sourceURLString = assessment.sourceURLString
        subjectName = assessment.subjectName; courseLevel = assessment.courseLevel; sourceClassLabel = assessment.sourceClassLabel; assessmentDate = assessment.assessmentDate
        title = assessment.title; assessmentType = assessment.assessmentType; category = assessment.category; status = assessment.status
        achievedPoints = assessment.achievedPoints; possiblePoints = assessment.possiblePoints; percentage = assessment.percentage; ibScore = assessment.ibScore; details = assessment.details
    }

    func toModel() -> AcademicAssessment {
        let assessment = AcademicAssessment(importID: importID, sourceKey: sourceKey, sourceFileName: sourceFileName, sourceURLString: sourceURLString, subjectName: subjectName, courseLevel: courseLevel, sourceClassLabel: sourceClassLabel, assessmentDate: assessmentDate, title: title, assessmentType: assessmentType, category: category, status: status, achievedPoints: achievedPoints, possiblePoints: possiblePoints, percentage: percentage, ibScore: ibScore, details: details)
        assessment.id = id
        return assessment
    }
}

nonisolated struct AcademicAssessmentMappingBackup: Codable {
    let id: UUID; let assessmentID: UUID; let subjectName: String; let courseLevel: String; let curriculumNodeKey: String
    let unitName: String; let topicName: String; let subtopicName: String; let statusRaw: String; let confidence: Double
    let rationale: String; let proposedBy: String; let updatedAt: Date

    init(from mapping: AcademicAssessmentMapping) {
        id = mapping.id; assessmentID = mapping.assessmentID; subjectName = mapping.subjectName; courseLevel = mapping.courseLevel; curriculumNodeKey = mapping.curriculumNodeKey
        unitName = mapping.unitName; topicName = mapping.topicName; subtopicName = mapping.subtopicName; statusRaw = mapping.statusRaw; confidence = mapping.confidence
        rationale = mapping.rationale; proposedBy = mapping.proposedBy; updatedAt = mapping.updatedAt
    }

    func toModel() -> AcademicAssessmentMapping {
        let mapping = AcademicAssessmentMapping(assessmentID: assessmentID, subjectName: subjectName, courseLevel: courseLevel, curriculumNodeKey: curriculumNodeKey, unitName: unitName, topicName: topicName, subtopicName: subtopicName, status: AcademicMappingStatus(rawValue: statusRaw) ?? .unmapped, confidence: confidence, rationale: rationale, proposedBy: proposedBy)
        mapping.id = id; mapping.updatedAt = updatedAt
        return mapping
    }
}

nonisolated struct AcademicReportSnapshotBackup: Codable {
    let id: UUID; let importID: UUID?; let sourceFileName: String; let reportDate: Date?; let subjectName: String; let courseLevel: String
    let gradeRaw: String; let predictedGradeRaw: String; let effort: String; let teacherComment: String

    init(from report: AcademicReportSnapshot) {
        id = report.id; importID = report.importID; sourceFileName = report.sourceFileName; reportDate = report.reportDate; subjectName = report.subjectName; courseLevel = report.courseLevel
        gradeRaw = report.gradeRaw; predictedGradeRaw = report.predictedGradeRaw; effort = report.effort; teacherComment = report.teacherComment
    }

    func toModel() -> AcademicReportSnapshot {
        let report = AcademicReportSnapshot(importID: importID, sourceFileName: sourceFileName, reportDate: reportDate, subjectName: subjectName, courseLevel: courseLevel, gradeRaw: gradeRaw, predictedGradeRaw: predictedGradeRaw, effort: effort, teacherComment: teacherComment)
        report.id = id
        return report
    }
}

nonisolated struct GradeBackup: Codable {
    let id: UUID; let component: String; let score: Int; let predictedGrade: Int?
    let date: Date; let teacherFeedback: String; let subjectName: String
    let assessmentTitle: String?
    let assessmentCategory: String?
    let achievedPoints: Double?
    let maxPoints: Double?
    let weightPercent: Double?
    let sourceName: String?
    let termName: String?

    init(from g: Grade) {
        id = g.id; component = g.component; score = g.score; predictedGrade = g.predictedGrade
        date = g.date; teacherFeedback = g.teacherFeedback; subjectName = g.subject?.name ?? ""
        assessmentTitle = g.assessmentTitle
        assessmentCategory = g.assessmentCategory
        achievedPoints = g.achievedPoints
        maxPoints = g.maxPoints
        weightPercent = g.weightPercent
        sourceName = g.sourceName
        termName = g.termName
    }

    func toModel(subjectsByName: [String: Subject]) -> Grade {
        let grade = Grade(
            component: component,
            score: score,
            predictedGrade: predictedGrade,
            teacherFeedback: teacherFeedback,
            assessmentTitle: assessmentTitle ?? "",
            assessmentCategory: assessmentCategory,
            achievedPoints: achievedPoints,
            maxPoints: maxPoints,
            weightPercent: weightPercent,
            sourceName: sourceName,
            termName: termName,
            subject: subjectsByName[subjectName]
        )
        grade.id = id
        grade.date = date
        return grade
    }
}

nonisolated struct SessionBackup: Codable {
    let id: UUID; let timestamp: Date; let cardID: UUID; let subjectName: String; let topicName: String
    let qualityRating: Int; let sessionDuration: TimeInterval; let wasCorrect: Bool
    let fsrsRatingRaw: Int?; let schedulerVersion: Int?
    let studySessionID: UUID?

    init(from s: ReviewSession) {
        id = s.id; timestamp = s.timestamp; cardID = s.cardID; subjectName = s.subjectName; topicName = s.topicName
        qualityRating = s.qualityRating; sessionDuration = s.sessionDuration; wasCorrect = s.wasCorrect
        fsrsRatingRaw = s.fsrsRatingRaw; schedulerVersion = s.schedulerVersion
        studySessionID = s.studySessionID
    }

    func toModel() -> ReviewSession {
        let session = ReviewSession(
            cardID: cardID,
            subjectName: subjectName,
            topicName: topicName,
            qualityRating: qualityRating,
            sessionDuration: sessionDuration,
            studySessionID: studySessionID
        )
        session.id = id
        session.timestamp = timestamp
        session.wasCorrect = wasCorrect
        session.fsrsRatingRaw = fsrsRatingRaw
        session.schedulerVersion = schedulerVersion
        return session
    }
}

nonisolated struct MemoryBackup: Codable {
    let id: UUID; let categoryRaw: String; let content: String; let timestamp: Date
    let isCompacted: Bool; let isArchived: Bool; let importanceRaw: Int
    let subjectName: String?; let topicName: String?; let importanceScore: Double
    let accessCount: Int; let lastAccessed: Date?; let relatedMemoryIDs: [UUID]; let tags: [String]

    init(from m: ARIAMemory) {
        id = m.id; categoryRaw = m.categoryRaw; content = m.content; timestamp = m.timestamp
        isCompacted = m.isCompacted; isArchived = m.isArchived; importanceRaw = m.importanceRaw
        subjectName = m.subjectName; topicName = m.topicName; importanceScore = m.importanceScore
        accessCount = m.accessCount; lastAccessed = m.lastAccessed; relatedMemoryIDs = m.relatedMemoryIDs; tags = m.tags
    }

    func toModel() -> ARIAMemory {
        let memory = ARIAMemory(
            category: MemoryCategory(rawValue: categoryRaw) ?? .conversationHistory,
            content: content,
            isCompacted: isCompacted,
            importance: MemoryImportance(rawValue: importanceRaw) ?? .medium,
            subjectName: subjectName,
            topicName: topicName,
            tags: tags
        )
        memory.id = id
        memory.timestamp = timestamp
        memory.isArchived = isArchived
        memory.importanceRaw = importanceRaw
        memory.importanceScore = importanceScore
        memory.accessCount = accessCount
        memory.lastAccessed = lastAccessed
        memory.relatedMemoryIDs = relatedMemoryIDs
        return memory
    }
}

nonisolated struct ChatBackup: Codable {
    let id: UUID; let role: String; let content: String; let timestamp: Date; let sessionID: UUID?

    init(from c: ChatMessage) {
        id = c.id; role = c.role; content = c.content; timestamp = c.timestamp; sessionID = c.sessionID
    }

    func toModel() -> ChatMessage {
        let message = ChatMessage(restoredRole: role, content: content, sessionID: sessionID)
        message.id = id
        message.timestamp = timestamp
        return message
    }
}

nonisolated struct ChatSessionBackup: Codable {
    let id: UUID; let title: String; let createdAt: Date; let updatedAt: Date
    let lastMessagePreview: String; let isArchived: Bool

    init(from session: ARIAChatSession) {
        id = session.id; title = session.title; createdAt = session.createdAt; updatedAt = session.updatedAt
        lastMessagePreview = session.lastMessagePreview; isArchived = session.isArchived
    }

    func toModel() -> ARIAChatSession {
        let session = ARIAChatSession(title: title, lastMessagePreview: lastMessagePreview, isArchived: isArchived)
        session.id = id
        session.createdAt = createdAt
        session.updatedAt = updatedAt
        return session
    }
}

nonisolated struct ActivityBackup: Codable {
    let id: UUID; let date: Date; let cardsReviewed: Int; let minutesStudied: Double; let xpEarned: Int

    init(from a: StudyActivity) {
        id = a.id; date = a.date; cardsReviewed = a.cardsReviewed; minutesStudied = a.minutesStudied; xpEarned = a.xpEarned
    }

    func toModel() -> StudyActivity {
        let activity = StudyActivity(date: date, cardsReviewed: cardsReviewed, minutesStudied: minutesStudied, xpEarned: xpEarned)
        activity.id = id
        return activity
    }
}

nonisolated struct StudySessionBackup: Codable {
    let id: UUID; let subjectName: String; let topicsCovered: String
    let subtopicsCovered: String?
    let startDate: Date; let endDate: Date; let cardsReviewed: Int; let correctCount: Int; let xpEarned: Int
    let sourcePlanID: UUID?; let notes: String?; let evidenceVersion: Int?; let subunitEvidenceJSON: String?; let reviewedCardIDsRaw: String?

    init(from session: StudySession) {
        id = session.id; subjectName = session.subjectName; topicsCovered = session.topicsCovered
        subtopicsCovered = session.subtopicsCovered
        startDate = session.startDate; endDate = session.endDate; cardsReviewed = session.cardsReviewed
        correctCount = session.correctCount; xpEarned = session.xpEarned
        sourcePlanID = session.sourcePlanID; notes = session.notes; evidenceVersion = session.evidenceVersion
        subunitEvidenceJSON = session.subunitEvidenceJSON; reviewedCardIDsRaw = session.reviewedCardIDsRaw
    }

    func toModel() -> StudySession {
        let session = StudySession(
            subjectName: subjectName,
            topicsCovered: topicsCovered,
            subtopicsCovered: subtopicsCovered ?? "",
            startDate: startDate,
            endDate: endDate,
            cardsReviewed: cardsReviewed,
            correctCount: correctCount,
            xpEarned: xpEarned,
            sourcePlanID: sourcePlanID,
            notes: notes ?? ""
        )
        session.id = id
        session.evidenceVersion = evidenceVersion
        session.subunitEvidenceJSON = subunitEvidenceJSON
        session.reviewedCardIDsRaw = reviewedCardIDsRaw
        return session
    }
}

nonisolated struct StudyPlanBackup: Codable {
    let id: UUID; let subjectName: String; let topicName: String; let subtopicName: String
    let planMarkdown: String; let createdDate: Date; let scheduledDate: Date; let scheduledEndDate: Date
    let isCompleted: Bool; let notes: String; let durationMinutes: Int; let kindRaw: String; let reviewIntervalDays: Int?
    let reviewScheduleOffsetsRaw: String?
    let prepareFlashcards: Bool?
    let planTasksJSON: String?

    init(from plan: StudyPlan) {
        id = plan.id; subjectName = plan.subjectName; topicName = plan.topicName; subtopicName = plan.subtopicName
        planMarkdown = plan.planMarkdown; createdDate = plan.createdDate; scheduledDate = plan.scheduledDate
        scheduledEndDate = plan.scheduledEndDate; isCompleted = plan.isCompleted; notes = plan.notes
        durationMinutes = plan.durationMinutes; kindRaw = plan.kindRaw; reviewIntervalDays = plan.reviewIntervalDays
        reviewScheduleOffsetsRaw = plan.reviewScheduleOffsetsRaw
        prepareFlashcards = plan.prepareFlashcards
        planTasksJSON = plan.planTasksJSON
    }

    func toModel() -> StudyPlan {
        let plan = StudyPlan(
            subjectName: subjectName,
            topicName: topicName,
            subtopicName: subtopicName,
            planMarkdown: planMarkdown,
            scheduledDate: scheduledDate,
            durationMinutes: durationMinutes,
            notes: notes,
            kind: StudyPlanKind(rawValue: kindRaw) ?? .studySession,
            reviewIntervalDays: reviewIntervalDays,
            reviewScheduleOffsets: reviewScheduleOffsetsRaw?
                .components(separatedBy: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? [1, 3, 7]
        )
        plan.id = id
        plan.createdDate = createdDate
        plan.scheduledEndDate = scheduledEndDate
        plan.isCompleted = isCompleted
        plan.prepareFlashcards = prepareFlashcards ?? false
        plan.planTasksJSON = planTasksJSON
        return plan
    }
}

nonisolated struct AchievementBackup: Codable {
    let id: String; let title: String; let desc: String; let icon: String
    let unlocked: Bool; let unlockDate: Date?; let category: String
    /// Optional so backups written before progression rules existed still decode.
    let ruleRaw: String?; let tier: Int?

    init(from a: Achievement) {
        id = a.id; title = a.title; desc = a.desc; icon = a.icon
        unlocked = a.unlocked; unlockDate = a.unlockDate; category = a.category
        ruleRaw = a.ruleRaw; tier = a.tier
    }

    func toModel() -> Achievement {
        let definition = Achievement.definitions.first { $0.id == id }
        // A missing or empty rule would make the achievement permanently unevaluable,
        // so fall back to the shipped definition for this id.
        let resolvedRule: String = {
            if let ruleRaw, !ruleRaw.isEmpty { return ruleRaw }
            return definition?.rule.rawValue ?? ""
        }()
        let resolvedTier = tier ?? definition?.tier ?? 1
        let a = Achievement(
            id: id,
            title: title,
            desc: desc,
            icon: icon,
            category: category,
            ruleRaw: resolvedRule,
            tier: resolvedTier
        )
        a.unlocked = unlocked; a.unlockDate = unlockDate; return a
    }
}

nonisolated struct ADHDMedicationBackup: Codable {
    let medicationTypeRaw: String
    let doseMg: Int
    let dailyDoses: Int
    let firstDoseHour: Int
    let firstDoseMinute: Int
    let doseIntervalMinutes: Int
    let isEnabled: Bool
    
    init(from settings: ADHDMedicationSettings) {
        self.medicationTypeRaw = settings.medicationType.rawValue
        self.doseMg = settings.doseMg
        self.dailyDoses = settings.dailyDoses
        self.firstDoseHour = settings.firstDoseHour
        self.firstDoseMinute = settings.firstDoseMinute
        self.doseIntervalMinutes = settings.doseIntervalMinutes
        self.isEnabled = settings.isEnabled
    }
    
    func toSettings() -> ADHDMedicationSettings {
        ADHDMedicationSettings(
            medicationType: ADHDMedicationType(rawValue: medicationTypeRaw) ?? .none,
            doseMg: doseMg,
            dailyDoses: dailyDoses,
            firstDoseHour: firstDoseHour,
            firstDoseMinute: firstDoseMinute,
            doseIntervalMinutes: doseIntervalMinutes,
            isEnabled: isEnabled
        )
    }
}
