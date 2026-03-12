import Foundation
import SwiftData

struct BackupService {
    private static let folderName = "IBVault Backups"
    private static let automaticBackupInterval: TimeInterval = 60 * 60 * 24

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

    @discardableResult
    static func autoBackupIfNeeded(context: ModelContext) throws -> URL? {
        if let latestBackupDate,
           Date().timeIntervalSince(latestBackupDate) < automaticBackupInterval {
            return nil
        }

        return try exportBackup(context: context)
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

        var writtenFiles: [String] = []

        if let profiles = try? context.fetch(FetchDescriptor<UserProfile>()),
           let profile = profiles.first {
            try write(ProfileBackup(from: profile), named: "profile.json", into: backupDir, encoder: encoder)
            writtenFiles.append("profile.json")
        }

        if let subjects = try? context.fetch(FetchDescriptor<Subject>()) {
            try write(subjects.map(SubjectBackup.init), named: "subjects.json", into: backupDir, encoder: encoder)
            writtenFiles.append("subjects.json")
        }

        if let grades = try? context.fetch(FetchDescriptor<Grade>()) {
            try write(grades.map(GradeBackup.init), named: "grades.json", into: backupDir, encoder: encoder)
            writtenFiles.append("grades.json")
        }

        if let sessions = try? context.fetch(FetchDescriptor<ReviewSession>()) {
            try write(sessions.map(SessionBackup.init), named: "review_sessions.json", into: backupDir, encoder: encoder)
            writtenFiles.append("review_sessions.json")
        }

        if let memories = try? context.fetch(FetchDescriptor<ARIAMemory>()) {
            try write(memories.map(MemoryBackup.init), named: "aria_memory.json", into: backupDir, encoder: encoder)
            writtenFiles.append("aria_memory.json")
        }

        if let chatSessions = try? context.fetch(FetchDescriptor<ARIAChatSession>()) {
            try write(chatSessions.map(ChatSessionBackup.init), named: "aria_chat_sessions.json", into: backupDir, encoder: encoder)
            writtenFiles.append("aria_chat_sessions.json")
        }

        if let chats = try? context.fetch(FetchDescriptor<ChatMessage>()) {
            try write(chats.map(ChatBackup.init), named: "chat_history.json", into: backupDir, encoder: encoder)
            writtenFiles.append("chat_history.json")
        }

        if let activities = try? context.fetch(FetchDescriptor<StudyActivity>()) {
            try write(activities.map(ActivityBackup.init), named: "study_activity.json", into: backupDir, encoder: encoder)
            writtenFiles.append("study_activity.json")
        }

        if let studySessions = try? context.fetch(FetchDescriptor<StudySession>()) {
            try write(studySessions.map(StudySessionBackup.init), named: "study_sessions.json", into: backupDir, encoder: encoder)
            writtenFiles.append("study_sessions.json")
        }

        if let studyPlans = try? context.fetch(FetchDescriptor<StudyPlan>()) {
            try write(studyPlans.map(StudyPlanBackup.init), named: "study_plans.json", into: backupDir, encoder: encoder)
            writtenFiles.append("study_plans.json")
        }

        if let achievements = try? context.fetch(FetchDescriptor<Achievement>()) {
            try write(achievements.map(AchievementBackup.init), named: "achievements.json", into: backupDir, encoder: encoder)
            writtenFiles.append("achievements.json")
        }

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
        let backupDirs = contents.filter { $0.hasDirectoryPath && $0.lastPathComponent.hasPrefix("backup_") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        guard let latest = backupDirs.first else { throw BackupError.noBackupFound }
        try restoreFrom(directory: latest, context: context)
    }

    static func restoreFrom(directory: URL, context: ModelContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        clearAll(UserProfile.self, context: context)
        clearAll(Subject.self, context: context)
        clearAll(Grade.self, context: context)
        clearAll(ReviewSession.self, context: context)
        clearAll(ARIAMemory.self, context: context)
        clearAll(ARIAChatSession.self, context: context)
        clearAll(ChatMessage.self, context: context)
        clearAll(StudyActivity.self, context: context)
        clearAll(StudySession.self, context: context)
        clearAll(StudyPlan.self, context: context)
        clearAll(Achievement.self, context: context)

        if let backup = decode(ProfileBackup.self, from: directory.appendingPathComponent("profile.json"), decoder: decoder) {
            context.insert(backup.toModel())
        }

        if let backups = decode([SubjectBackup].self, from: directory.appendingPathComponent("subjects.json"), decoder: decoder) {
            for backup in backups {
                context.insert(backup.toModel())
            }
        }

        let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        let subjectsByName = Dictionary(uniqueKeysWithValues: subjects.map { ($0.name, $0) })

        if let backups = decode([GradeBackup].self, from: directory.appendingPathComponent("grades.json"), decoder: decoder) {
            for backup in backups {
                context.insert(backup.toModel(subjectsByName: subjectsByName))
            }
        }

        if let backups = decode([SessionBackup].self, from: directory.appendingPathComponent("review_sessions.json"), decoder: decoder) {
            for backup in backups {
                context.insert(backup.toModel())
            }
        }

        if let backups = decode([MemoryBackup].self, from: directory.appendingPathComponent("aria_memory.json"), decoder: decoder) {
            for backup in backups {
                context.insert(backup.toModel())
            }
        }

        if let backups = decode([ChatSessionBackup].self, from: directory.appendingPathComponent("aria_chat_sessions.json"), decoder: decoder) {
            for backup in backups {
                context.insert(backup.toModel())
            }
        }

        if let backups = decode([ChatBackup].self, from: directory.appendingPathComponent("chat_history.json"), decoder: decoder) {
            for backup in backups {
                context.insert(backup.toModel())
            }
        }

        if let backups = decode([ActivityBackup].self, from: directory.appendingPathComponent("study_activity.json"), decoder: decoder) {
            for backup in backups {
                context.insert(backup.toModel())
            }
        }

        if let backups = decode([StudySessionBackup].self, from: directory.appendingPathComponent("study_sessions.json"), decoder: decoder) {
            for backup in backups {
                context.insert(backup.toModel())
            }
        }

        if let backups = decode([StudyPlanBackup].self, from: directory.appendingPathComponent("study_plans.json"), decoder: decoder) {
            for backup in backups {
                context.insert(backup.toModel())
            }
        }

        if let backups = decode([AchievementBackup].self, from: directory.appendingPathComponent("achievements.json"), decoder: decoder) {
            for backup in backups {
                context.insert(backup.toModel())
            }
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

    private static func clearAll<Model: PersistentModel>(_ type: Model.Type, context: ModelContext) {
        if let existing = try? context.fetch(FetchDescriptor<Model>()) {
            existing.forEach { context.delete($0) }
        }
    }

    private static func write<Value: Encodable>(_ value: Value, named fileName: String, into directory: URL, encoder: JSONEncoder) throws {
        let data = try encoder.encode(value)
        try data.write(to: directory.appendingPathComponent(fileName))
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from fileURL: URL, decoder: JSONDecoder) -> Value? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private static func appVersion() -> String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
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
    let id: UUID; let topicName: String; let subtopic: String; let front: String; let back: String
    let easeFactor: Double; let interval: Int; let repetitions: Int
    let nextReviewDate: Date; let proficiencyRaw: String; let consecutiveCorrect: Int
    let isCustom: Bool; let isAIGenerated: Bool?; let createdDate: Date
    let lastReviewedDate: Date?; let generationSource: String?
    let totalReviewCount: Int; let successfulReviewCount: Int

    init(from c: StudyCard) {
        id = c.id; topicName = c.topicName; subtopic = c.subtopic; front = c.front; back = c.back
        easeFactor = c.easeFactor; interval = c.interval; repetitions = c.repetitions
        nextReviewDate = c.nextReviewDate; proficiencyRaw = c.proficiencyRaw
        consecutiveCorrect = c.consecutiveCorrect; isCustom = c.isCustom
        isAIGenerated = c.isAIGenerated; createdDate = c.createdDate
        lastReviewedDate = c.lastReviewedDate; generationSource = c.generationSource
        totalReviewCount = c.totalReviewCount; successfulReviewCount = c.successfulReviewCount
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
        return c
    }
}

struct GradeBackup: Codable {
    let id: UUID; let component: String; let score: Int; let predictedGrade: Int?
    let date: Date; let teacherFeedback: String; let subjectName: String
    let assessmentTitle: String
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
            assessmentTitle: assessmentTitle,
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

struct SessionBackup: Codable {
    let id: UUID; let timestamp: Date; let cardID: UUID; let subjectName: String; let topicName: String
    let qualityRating: Int; let sessionDuration: TimeInterval; let wasCorrect: Bool

    init(from s: ReviewSession) {
        id = s.id; timestamp = s.timestamp; cardID = s.cardID; subjectName = s.subjectName; topicName = s.topicName
        qualityRating = s.qualityRating; sessionDuration = s.sessionDuration; wasCorrect = s.wasCorrect
    }

    func toModel() -> ReviewSession {
        let session = ReviewSession(
            cardID: cardID,
            subjectName: subjectName,
            topicName: topicName,
            qualityRating: qualityRating,
            sessionDuration: sessionDuration
        )
        session.id = id
        session.timestamp = timestamp
        session.wasCorrect = wasCorrect
        return session
    }
}

struct MemoryBackup: Codable {
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

struct ChatBackup: Codable {
    let id: UUID; let role: String; let content: String; let timestamp: Date; let sessionID: UUID?

    init(from c: ChatMessage) {
        id = c.id; role = c.role; content = c.content; timestamp = c.timestamp; sessionID = c.sessionID
    }

    func toModel() -> ChatMessage {
        let message = ChatMessage(role: role, content: content, sessionID: sessionID)
        message.id = id
        message.timestamp = timestamp
        return message
    }
}

struct ChatSessionBackup: Codable {
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

struct ActivityBackup: Codable {
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

struct StudySessionBackup: Codable {
    let id: UUID; let subjectName: String; let topicsCovered: String
    let startDate: Date; let endDate: Date; let cardsReviewed: Int; let correctCount: Int; let xpEarned: Int

    init(from session: StudySession) {
        id = session.id; subjectName = session.subjectName; topicsCovered = session.topicsCovered
        startDate = session.startDate; endDate = session.endDate; cardsReviewed = session.cardsReviewed
        correctCount = session.correctCount; xpEarned = session.xpEarned
    }

    func toModel() -> StudySession {
        let session = StudySession(
            subjectName: subjectName,
            topicsCovered: topicsCovered,
            startDate: startDate,
            endDate: endDate,
            cardsReviewed: cardsReviewed,
            correctCount: correctCount,
            xpEarned: xpEarned
        )
        session.id = id
        return session
    }
}

struct StudyPlanBackup: Codable {
    let id: UUID; let subjectName: String; let topicName: String; let subtopicName: String
    let planMarkdown: String; let createdDate: Date; let scheduledDate: Date; let scheduledEndDate: Date
    let isCompleted: Bool; let notes: String; let durationMinutes: Int; let kindRaw: String; let reviewIntervalDays: Int?

    init(from plan: StudyPlan) {
        id = plan.id; subjectName = plan.subjectName; topicName = plan.topicName; subtopicName = plan.subtopicName
        planMarkdown = plan.planMarkdown; createdDate = plan.createdDate; scheduledDate = plan.scheduledDate
        scheduledEndDate = plan.scheduledEndDate; isCompleted = plan.isCompleted; notes = plan.notes
        durationMinutes = plan.durationMinutes; kindRaw = plan.kindRaw; reviewIntervalDays = plan.reviewIntervalDays
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
            reviewIntervalDays: reviewIntervalDays
        )
        plan.id = id
        plan.createdDate = createdDate
        plan.scheduledEndDate = scheduledEndDate
        plan.isCompleted = isCompleted
        return plan
    }
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
