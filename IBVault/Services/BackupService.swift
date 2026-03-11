import Foundation
import SwiftData

struct BackupService {
    private static let folderName = "IBVault Backups"

    static var backupDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent(folderName)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static var latestBackupDate: Date? {
        let metaURL = backupDirectory.appendingPathComponent("backup_meta.json")
        guard let data = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(BackupMeta.self, from: data) else { return nil }
        return meta.date
    }

    // MARK: - Export All Data

    static func exportBackup(context: ModelContext) throws -> URL {
        let dir = backupDirectory
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let backupDir = dir.appendingPathComponent("backup_\(timestamp.replacingOccurrences(of: ":", with: "-"))")
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // 1. Profile
        if let profiles = try? context.fetch(FetchDescriptor<UserProfile>()),
           let profile = profiles.first {
            let profileData = ProfileBackup(from: profile)
            let data = try encoder.encode(profileData)
            try data.write(to: backupDir.appendingPathComponent("profile.json"))
        }

        // 2. Subjects + Cards
        if let subjects = try? context.fetch(FetchDescriptor<Subject>()) {
            let subjectBackups = subjects.map { SubjectBackup(from: $0) }
            let data = try encoder.encode(subjectBackups)
            try data.write(to: backupDir.appendingPathComponent("subjects.json"))
        }

        // 3. Grades
        if let grades = try? context.fetch(FetchDescriptor<Grade>()) {
            let gradeBackups = grades.map { GradeBackup(from: $0) }
            let data = try encoder.encode(gradeBackups)
            try data.write(to: backupDir.appendingPathComponent("grades.json"))
        }

        // 4. Review Sessions
        if let sessions = try? context.fetch(FetchDescriptor<ReviewSession>()) {
            let sessionBackups = sessions.map { SessionBackup(from: $0) }
            let data = try encoder.encode(sessionBackups)
            try data.write(to: backupDir.appendingPathComponent("review_sessions.json"))
        }

        // 5. ARIA Memory
        if let memories = try? context.fetch(FetchDescriptor<ARIAMemory>()) {
            let memBackups = memories.map { MemoryBackup(from: $0) }
            let data = try encoder.encode(memBackups)
            try data.write(to: backupDir.appendingPathComponent("aria_memory.json"))
        }

        // 6. Chat History
        if let chats = try? context.fetch(FetchDescriptor<ChatMessage>()) {
            let chatBackups = chats.map { ChatBackup(from: $0) }
            let data = try encoder.encode(chatBackups)
            try data.write(to: backupDir.appendingPathComponent("chat_history.json"))
        }

        // 7. Study Activity
        if let activities = try? context.fetch(FetchDescriptor<StudyActivity>()) {
            let actBackups = activities.map { ActivityBackup(from: $0) }
            let data = try encoder.encode(actBackups)
            try data.write(to: backupDir.appendingPathComponent("study_activity.json"))
        }

        // 8. Achievements
        if let achievements = try? context.fetch(FetchDescriptor<Achievement>()) {
            let achBackups = achievements.map { AchievementBackup(from: $0) }
            let data = try encoder.encode(achBackups)
            try data.write(to: backupDir.appendingPathComponent("achievements.json"))
        }

        // Meta
        let meta = BackupMeta(date: Date(), fileCount: 8, version: "1.0")
        let metaData = try encoder.encode(meta)
        try metaData.write(to: backupDir.appendingPathComponent("backup_meta.json"))
        // Also save to root for quick "last backup" check
        try metaData.write(to: dir.appendingPathComponent("backup_meta.json"))

        return backupDir
    }

    // MARK: - Restore

    static func restoreFromLatest(context: ModelContext) throws {
        let dir = backupDirectory
        let contents = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
        let backupDirs = contents.filter { $0.hasDirectoryPath && $0.lastPathComponent.hasPrefix("backup_") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        guard let latest = backupDirs.first else { throw BackupError.noBackupFound }
        try restoreFrom(directory: latest, context: context)
    }

    static func restoreFrom(directory: URL, context: ModelContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // 1. Profile
        let profileURL = directory.appendingPathComponent("profile.json")
        if let data = try? Data(contentsOf: profileURL),
           let backup = try? decoder.decode(ProfileBackup.self, from: data) {
            // Clear existing
            if let existing = try? context.fetch(FetchDescriptor<UserProfile>()) {
                existing.forEach { context.delete($0) }
            }
            let profile = backup.toModel()
            context.insert(profile)
        }

        // 2. Subjects + Cards
        let subjectsURL = directory.appendingPathComponent("subjects.json")
        if let data = try? Data(contentsOf: subjectsURL),
           let backups = try? decoder.decode([SubjectBackup].self, from: data) {
            // Clear existing
            if let existing = try? context.fetch(FetchDescriptor<Subject>()) {
                existing.forEach { context.delete($0) }
            }
            for backup in backups {
                let subject = backup.toModel()
                context.insert(subject)
            }
        }

        // 3. Grades
        let gradesURL = directory.appendingPathComponent("grades.json")
        if let data = try? Data(contentsOf: gradesURL),
           let backups = try? decoder.decode([GradeBackup].self, from: data) {
            if let existing = try? context.fetch(FetchDescriptor<Grade>()) {
                existing.forEach { context.delete($0) }
            }
            for backup in backups {
                context.insert(backup.toModel())
            }
        }

        // 4. Study Activity
        let actURL = directory.appendingPathComponent("study_activity.json")
        if let data = try? Data(contentsOf: actURL),
           let backups = try? decoder.decode([ActivityBackup].self, from: data) {
            if let existing = try? context.fetch(FetchDescriptor<StudyActivity>()) {
                existing.forEach { context.delete($0) }
            }
            for backup in backups { context.insert(backup.toModel()) }
        }

        // 5. ARIA Memory
        let memURL = directory.appendingPathComponent("aria_memory.json")
        if let data = try? Data(contentsOf: memURL),
           let backups = try? decoder.decode([MemoryBackup].self, from: data) {
            if let existing = try? context.fetch(FetchDescriptor<ARIAMemory>()) {
                existing.forEach { context.delete($0) }
            }
            for backup in backups { context.insert(backup.toModel()) }
        }

        // 6. Achievements
        let achURL = directory.appendingPathComponent("achievements.json")
        if let data = try? Data(contentsOf: achURL),
           let backups = try? decoder.decode([AchievementBackup].self, from: data) {
            if let existing = try? context.fetch(FetchDescriptor<Achievement>()) {
                existing.forEach { context.delete($0) }
            }
            for backup in backups { context.insert(backup.toModel()) }
        }

        try context.save()
    }

    // MARK: - List Backups

    static func listBackups() -> [(name: String, date: Date, url: URL)] {
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

    static func deleteBackup(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}

// MARK: - Errors
enum BackupError: Error, LocalizedError {
    case noBackupFound
    case corruptedBackup
    var errorDescription: String? {
        switch self {
        case .noBackupFound: return "No backup found to restore"
        case .corruptedBackup: return "Backup data is corrupted"
        }
    }
}

// MARK: - Backup Meta
struct BackupMeta: Codable {
    let date: Date
    let fileCount: Int
    let version: String
}

// MARK: - Backup Models (Codable mirrors of SwiftData models)

struct ProfileBackup: Codable {
    let totalXP: Int; let currentStreak: Int; let longestStreak: Int
    let streakFreezes: Int; let rankRaw: String; let dailyGoal: Int
    let studentName: String; let studyIntensityRaw: String; let ibYearRaw: String
    let targetIBScore: Int; let notificationHour: Int; let notificationMinute: Int

    init(from p: UserProfile) {
        totalXP = p.totalXP; currentStreak = p.currentStreak; longestStreak = p.longestStreak
        streakFreezes = p.streakFreezes; rankRaw = p.rankRaw; dailyGoal = p.dailyGoal
        studentName = p.studentName; studyIntensityRaw = p.studyIntensityRaw; ibYearRaw = p.ibYearRaw
        targetIBScore = p.targetIBScore; notificationHour = p.notificationHour; notificationMinute = p.notificationMinute
    }

    func toModel() -> UserProfile {
        let p = UserProfile()
        p.totalXP = totalXP; p.currentStreak = currentStreak; p.longestStreak = longestStreak
        p.streakFreezes = streakFreezes; p.rankRaw = rankRaw; p.dailyGoal = dailyGoal
        p.studentName = studentName; p.studyIntensityRaw = studyIntensityRaw; p.ibYearRaw = ibYearRaw
        p.targetIBScore = targetIBScore; p.notificationHour = notificationHour; p.notificationMinute = notificationMinute
        p.onboardingCompleted = true
        return p
    }
}

struct SubjectBackup: Codable {
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

struct CardBackup: Codable {
    let topicName: String; let subtopic: String; let front: String; let back: String
    let easeFactor: Double; let interval: Int; let repetitions: Int
    let nextReviewDate: Date; let proficiencyRaw: String; let consecutiveCorrect: Int
    let isCustom: Bool

    init(from c: StudyCard) {
        topicName = c.topicName; subtopic = c.subtopic; front = c.front; back = c.back
        easeFactor = c.easeFactor; interval = c.interval; repetitions = c.repetitions
        nextReviewDate = c.nextReviewDate; proficiencyRaw = c.proficiencyRaw
        consecutiveCorrect = c.consecutiveCorrect; isCustom = c.isCustom
    }

    func toModel() -> StudyCard {
        let c = StudyCard(topicName: topicName, subtopic: subtopic, front: front, back: back, isCustom: isCustom)
        c.easeFactor = easeFactor; c.interval = interval; c.repetitions = repetitions
        c.nextReviewDate = nextReviewDate; c.proficiencyRaw = proficiencyRaw
        c.consecutiveCorrect = consecutiveCorrect
        return c
    }
}

struct GradeBackup: Codable {
    let component: String; let score: Int; let predictedGrade: Int?
    let date: Date; let teacherFeedback: String; let subjectName: String

    init(from g: Grade) {
        component = g.component; score = g.score; predictedGrade = g.predictedGrade
        date = g.date; teacherFeedback = g.teacherFeedback; subjectName = g.subject?.name ?? ""
    }

    func toModel() -> Grade { Grade(component: component, score: score, predictedGrade: predictedGrade, teacherFeedback: teacherFeedback) }
}

struct SessionBackup: Codable {
    let timestamp: Date; let subjectName: String; let topicName: String
    let qualityRating: Int; let sessionDuration: TimeInterval

    init(from s: ReviewSession) {
        timestamp = s.timestamp; subjectName = s.subjectName; topicName = s.topicName
        qualityRating = s.qualityRating; sessionDuration = s.sessionDuration
    }
}

struct MemoryBackup: Codable {
    let categoryRaw: String; let content: String; let timestamp: Date; let isCompacted: Bool

    init(from m: ARIAMemory) {
        categoryRaw = m.categoryRaw; content = m.content; timestamp = m.timestamp; isCompacted = m.isCompacted
    }
    func toModel() -> ARIAMemory {
        ARIAMemory(category: MemoryCategory(rawValue: categoryRaw) ?? .conversationHistory, content: content, isCompacted: isCompacted)
    }
}

struct ChatBackup: Codable {
    let role: String; let content: String; let timestamp: Date
    init(from c: ChatMessage) { role = c.role; content = c.content; timestamp = c.timestamp }
}

struct ActivityBackup: Codable {
    let date: Date; let cardsReviewed: Int; let minutesStudied: Double; let xpEarned: Int
    init(from a: StudyActivity) { date = a.date; cardsReviewed = a.cardsReviewed; minutesStudied = a.minutesStudied; xpEarned = a.xpEarned }
    func toModel() -> StudyActivity { StudyActivity(date: date, cardsReviewed: cardsReviewed, minutesStudied: minutesStudied, xpEarned: xpEarned) }
}

struct AchievementBackup: Codable {
    let id: String; let title: String; let desc: String; let icon: String
    let unlocked: Bool; let unlockDate: Date?; let category: String
    init(from a: Achievement) { id = a.id; title = a.title; desc = a.desc; icon = a.icon; unlocked = a.unlocked; unlockDate = a.unlockDate; category = a.category }
    func toModel() -> Achievement {
        let a = Achievement(id: id, title: title, desc: desc, icon: icon, category: category)
        a.unlocked = unlocked; a.unlockDate = unlockDate; return a
    }
}
