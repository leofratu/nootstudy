import Foundation
import SwiftData

enum MemoryCategory: String, Codable, CaseIterable {
    case grades = "Grades & Targets"
    case weakTopics = "Weak Topics"
    case studyHabits = "Study Habits"
    case goals = "Personal Goals"
    case conversationHistory = "Conversation History"
    case userNotes = "User Notes"
    case subjectInsight = "Subject Insights"
    case sessionSummary = "Session Summary"
    case achievement = "Achievements"
    case struggle = "Struggles & Challenges"

    var icon: String {
        switch self {
        case .grades: return "chart.bar.fill"
        case .weakTopics: return "exclamationmark.triangle.fill"
        case .studyHabits: return "clock.fill"
        case .goals: return "target"
        case .conversationHistory: return "bubble.left.and.bubble.right.fill"
        case .userNotes: return "note.text"
        case .subjectInsight: return "book.fill"
        case .sessionSummary: return "sum"
        case .achievement: return "star.fill"
        case .struggle: return "brain.head.profile"
        }
    }
    
    var priority: Int {
        switch self {
        case .weakTopics: return 100
        case .grades: return 90
        case .goals: return 85
        case .achievement: return 80
        case .subjectInsight: return 70
        case .sessionSummary: return 60
        case .studyHabits: return 50
        case .struggle: return 40
        case .userNotes: return 30
        case .conversationHistory: return 10
        }
    }
    
    var decayRate: Double {
        switch self {
        case .grades, .achievement: return 0.5
        case .weakTopics, .struggle: return 0.8
        case .goals, .subjectInsight: return 0.6
        case .sessionSummary: return 0.7
        case .studyHabits: return 0.4
        case .userNotes: return 0.3
        case .conversationHistory: return 0.9
        }
    }
}

enum MemoryImportance: Int, Codable, Comparable {
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4
    
    static func < (lhs: MemoryImportance, rhs: MemoryImportance) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

@Model
final class ARIAMemory {
    var id: UUID
    var categoryRaw: String
    var content: String
    var timestamp: Date
    var isCompacted: Bool
    var isArchived: Bool
    var importanceRaw: Int
    var subjectName: String?
    var topicName: String?
    var importanceScore: Double
    var accessCount: Int
    var lastAccessed: Date?
    var relatedMemoryIDs: [UUID]
    var tags: [String]

    var category: MemoryCategory {
        get { MemoryCategory(rawValue: categoryRaw) ?? .conversationHistory }
        set { categoryRaw = newValue.rawValue }
    }
    
    var importance: MemoryImportance {
        get { MemoryImportance(rawValue: importanceRaw) ?? .medium }
        set { importanceRaw = newValue.rawValue }
    }

    var effectiveAge: Double {
        let days = Calendar.current.dateComponents([.day], from: timestamp, to: Date()).day ?? 0
        return Double(days) * category.decayRate
    }

    var relevanceBoost: Double {
        var boost = 1.0
        if accessCount > 3 { boost += 0.2 }
        if let lastAccessed = lastAccessed {
            let hoursSinceAccess = Calendar.current.dateComponents([.hour], from: lastAccessed, to: Date()).hour ?? 0
            if hoursSinceAccess < 24 { boost += 0.3 }
        }
        return boost
    }

    init(
        category: MemoryCategory,
        content: String,
        isCompacted: Bool = false,
        importance: MemoryImportance = .medium,
        subjectName: String? = nil,
        topicName: String? = nil,
        tags: [String] = []
    ) {
        self.id = UUID()
        self.categoryRaw = category.rawValue
        self.content = content
        self.timestamp = Date()
        self.isCompacted = isCompacted
        self.isArchived = false
        self.importanceRaw = importance.rawValue
        self.subjectName = subjectName
        self.topicName = topicName
        self.importanceScore = Double(importance.rawValue)
        self.accessCount = 0
        self.lastAccessed = nil
        self.relatedMemoryIDs = []
        self.tags = tags
    }
    
    func markAccessed() {
        accessCount += 1
        lastAccessed = Date()
    }
    
    func addRelatedMemory(_ id: UUID) {
        if !relatedMemoryIDs.contains(id) {
            relatedMemoryIDs.append(id)
        }
    }
}

@Model
final class ChatMessage {
    var id: UUID
    var role: String // "user" or "model"
    var content: String
    var timestamp: Date
    var sessionID: UUID?

    init(role: String, content: String, sessionID: UUID? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.sessionID = sessionID
    }
}

@Model
final class ARIAChatSession {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var lastMessagePreview: String
    var isArchived: Bool

    init(
        title: String = "New Chat",
        lastMessagePreview: String = "",
        isArchived: Bool = false
    ) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.lastMessagePreview = lastMessagePreview
        self.isArchived = isArchived
    }
}
