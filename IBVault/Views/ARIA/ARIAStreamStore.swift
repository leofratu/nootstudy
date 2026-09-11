import Foundation

/// Isolated streaming state so token writes invalidate only the streaming row and
/// the send/stop control, never the sidebar, finalized messages, or config rail.
///
/// Created by the chat parent (`ARIAChatView`) and passed explicitly to the
/// two consumers that need it. Finalized messages and the session list never
/// observe this object.
@Observable
@MainActor
final class ARIAStreamStore {
    var streamingText: String = ""
    var statusText: String = ""
    var isLoading: Bool = false
    var activeSessionID: UUID?
    var activePrompt: String?
    var activeProvider: AIProviderKind = .gemini

    func begin(sessionID: UUID, prompt: String, provider: AIProviderKind) {
        streamingText = ""
        statusText = "Preparing your response…"
        isLoading = true
        activeSessionID = sessionID
        activePrompt = prompt
        activeProvider = provider
    }

    func reset() {
        streamingText = ""
        statusText = ""
        isLoading = false
        activeSessionID = nil
        activePrompt = nil
    }
}
