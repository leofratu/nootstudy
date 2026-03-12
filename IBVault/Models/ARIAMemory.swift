import Foundation
import SwiftData

enum MemoryCategory: String, Codable, CaseIterable {
    case grades = "Grades & Targets"
    case weakTopics = "Weak Topics"
    case studyHabits = "Study Habits"
    case goals = "Personal Goals"
    case conversationHistory = "Conversation History"
    case userNotes = "User Notes"

    var icon: String {
        switch self {
        case .grades: return "chart.bar.fill"
        case .weakTopics: return "exclamationmark.triangle.fill"
        case .studyHabits: return "clock.fill"
        case .goals: return "target"
        case .conversationHistory: return "bubble.left.and.bubble.right.fill"
        case .userNotes: return "note.text"
        }
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

    var category: MemoryCategory {
        get { MemoryCategory(rawValue: categoryRaw) ?? .conversationHistory }
        set { categoryRaw = newValue.rawValue }
    }

    init(category: MemoryCategory, content: String, isCompacted: Bool = false) {
        self.id = UUID()
        self.categoryRaw = category.rawValue
        self.content = content
        self.timestamp = Date()
        self.isCompacted = isCompacted
        self.isArchived = false
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
