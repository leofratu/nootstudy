import Foundation
import SwiftData

/// Typed chat-message role. `ChatMessage.role` persists the `storedValue`
/// string, so conversation/failure/cancellation/dismissed roles round-trip
/// through the store while call sites switch on typed cases instead of string
/// prefixes.
nonisolated indirect enum ChatMessageRole: Sendable, Equatable {
    case user
    case model
    case failure(provider: AIProviderKind, needsAuthentication: Bool = false)
    case cancelled(provider: AIProviderKind)
    case dismissed(underlying: ChatMessageRole)

    private static let failurePrefix = "error."
    private static let cancelledPrefix = "cancelled."
    private static let dismissedPrefix = "dismissed."
    private static let authenticationSuffix = ".authentication"

    /// The string persisted in `ChatMessage.role`.
    var storedValue: String {
        switch self {
        case .user:
            return "user"
        case .model:
            return "model"
        case .failure(let provider, let needsAuthentication):
            return ChatMessageRole.failurePrefix + provider.rawValue + (needsAuthentication ? ChatMessageRole.authenticationSuffix : "")
        case .cancelled(let provider):
            return ChatMessageRole.cancelledPrefix + provider.rawValue
        case .dismissed(let underlying):
            return ChatMessageRole.dismissedPrefix + underlying.storedValue
        }
    }

    /// Parses a persisted role string back into a typed value.
    init?(storedValue: String) {
        switch storedValue {
        case "user":
            self = .user
        case "model":
            self = .model
        default:
            if storedValue.hasPrefix(ChatMessageRole.dismissedPrefix) {
                let inner = String(storedValue.dropFirst(ChatMessageRole.dismissedPrefix.count))
                guard let underlying = ChatMessageRole(storedValue: inner) else { return nil }
                self = .dismissed(underlying: underlying)
            } else if storedValue.hasPrefix(ChatMessageRole.failurePrefix) {
                let rest = storedValue.dropFirst(ChatMessageRole.failurePrefix.count)
                let needsAuthentication = rest.hasSuffix(ChatMessageRole.authenticationSuffix)
                let providerRaw = needsAuthentication
                    ? String(rest.dropLast(ChatMessageRole.authenticationSuffix.count))
                    : String(rest)
                guard let provider = AIProviderKind(rawValue: providerRaw) else { return nil }
                self = .failure(provider: provider, needsAuthentication: needsAuthentication)
            } else if storedValue.hasPrefix(ChatMessageRole.cancelledPrefix) {
                let providerRaw = String(storedValue.dropFirst(ChatMessageRole.cancelledPrefix.count))
                guard let provider = AIProviderKind(rawValue: providerRaw) else { return nil }
                self = .cancelled(provider: provider)
            } else {
                return nil
            }
        }
    }

    var isConversation: Bool {
        self == .user || self == .model
    }

    var isFailure: Bool {
        if case .failure = self { return true }
        if case .cancelled = self { return true }
        return false
    }

    var failureProvider: AIProviderKind? {
        switch self {
        case .failure(let provider, _), .cancelled(let provider):
            return provider
        case .user, .model, .dismissed:
            return nil
        }
    }

    var needsCodexAuthentication: Bool {
        self == .failure(provider: .codexCLI, needsAuthentication: true)
    }
}

nonisolated enum MemoryCategory: String, Codable, CaseIterable, Sendable {
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

nonisolated enum MemoryImportance: Int, Codable, Comparable, Sendable {
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4
    
    static func < (lhs: MemoryImportance, rhs: MemoryImportance) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

@Model
nonisolated final class ARIAMemory {
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
        return Double(max(0, days)) * category.decayRate
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
nonisolated final class ChatMessage {
    var id: UUID
    var role: String
    var content: String
    var timestamp: Date
    var sessionID: UUID?

    init(role: ChatMessageRole, content: String, sessionID: UUID? = nil) {
        self.id = UUID()
        self.role = role.storedValue
        self.content = content
        self.timestamp = Date()
        self.sessionID = sessionID
    }

    /// Restore path: preserves an arbitrary persisted role string byte-for-byte
    /// (e.g. a role written by an older build), so a backup never re-tags a
    /// message during restore.
    init(restoredRole: String, content: String, sessionID: UUID? = nil) {
        self.id = UUID()
        self.role = restoredRole
        self.content = content
        self.timestamp = Date()
        self.sessionID = sessionID
    }
}

@Model
nonisolated final class ARIAChatSession {
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
