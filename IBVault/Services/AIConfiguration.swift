import Foundation

enum AIProviderKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case gemini
    case junali
    case codexCLI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini: return "Google Gemini"
        case .junali: return "Junali"
        case .codexCLI: return "Local Codex"
        }
    }

    var shortName: String {
        switch self {
        case .gemini: return "Gemini"
        case .junali: return "Junali"
        case .codexCLI: return "Codex"
        }
    }

    var symbolName: String {
        switch self {
        case .gemini: return "sparkles"
        case .junali: return "network"
        case .codexCLI: return "terminal"
        }
    }

    var detail: String {
        switch self {
        case .gemini:
            return "Direct Gemini API access using a key stored in Keychain."
        case .junali:
            return "OpenAI-compatible responses through the configured Junali endpoint."
        case .codexCLI:
            return "Uses the installed Codex CLI and its existing local sign-in. No API key is copied into IBVault."
        }
    }
}

enum AIReasoningEffort: String, CaseIterable, Codable, Identifiable, Sendable {
    case none
    case low
    case medium
    case high
    case xhigh

    var id: String { rawValue }
    var displayName: String { rawValue == "xhigh" ? "Extra high" : rawValue.capitalized }

    var codexValue: String {
        self == .none ? "minimal" : rawValue
    }
}

enum AIResponseVerbosity: String, CaseIterable, Codable, Identifiable, Sendable {
    case low
    case medium
    case high

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum AIWebSearchMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case disabled
    case cached
    case live

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .disabled: return "Off"
        case .cached: return "Cached"
        case .live: return "Live"
        }
    }

    var detail: String {
        switch self {
        case .disabled:
            return "Answer only from the app context and the model's existing knowledge."
        case .cached:
            return "Allow Codex to use OpenAI's cached search index when sources are useful."
        case .live:
            return "Allow fresh web search for current or source-sensitive questions."
        }
    }
}

struct AIModelOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let role: String
}

enum AIConfiguration {
    static let junaliDefaultBaseURL = "https://openapi.junliai.org/v1"
    static let codexDefaultModel = "gpt-5.6-sol"

    private enum Key {
        static let provider = "ariaProvider"
        static let geminiModel = "geminiModel"
        static let junaliModel = "junaliModel"
        static let codexModel = "codexModel"
        static let reasoningEffort = "ariaReasoningEffort"
        static let verbosity = "ariaVerbosity"
        static let webSearchMode = "ariaWebSearchMode"
        static let junaliBaseURL = "junaliBaseURL"
        static let codexCLIPath = "codexCLIPath"
    }

    static var provider: AIProviderKind {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Key.provider),
                  let provider = AIProviderKind(rawValue: raw) else {
                return .gemini
            }
            return provider
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.provider) }
    }

    static var reasoningEffort: AIReasoningEffort {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Key.reasoningEffort),
                  let effort = AIReasoningEffort(rawValue: raw) else {
                return .medium
            }
            return effort
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.reasoningEffort) }
    }

    static var verbosity: AIResponseVerbosity {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Key.verbosity),
                  let verbosity = AIResponseVerbosity(rawValue: raw) else {
                return .medium
            }
            return verbosity
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.verbosity) }
    }

    static var webSearchMode: AIWebSearchMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Key.webSearchMode),
                  let mode = AIWebSearchMode(rawValue: raw) else {
                return .cached
            }
            return mode
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.webSearchMode) }
    }

    static var selectedModel: String {
        model(for: provider)
    }

    static func model(for provider: AIProviderKind) -> String {
        let key: String
        let fallback: String
        switch provider {
        case .gemini:
            key = Key.geminiModel
            fallback = "gemini-2.0-flash"
        case .junali:
            key = Key.junaliModel
            fallback = codexDefaultModel
        case .codexCLI:
            key = Key.codexModel
            fallback = codexDefaultModel
        }
        return UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? fallback
    }

    static func setModel(_ model: String, for provider: AIProviderKind) {
        let key: String
        switch provider {
        case .gemini: key = Key.geminiModel
        case .junali: key = Key.junaliModel
        case .codexCLI: key = Key.codexModel
        }
        UserDefaults.standard.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: key)
    }

    static var junaliBaseURL: String {
        get {
            UserDefaults.standard.string(forKey: Key.junaliBaseURL)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? junaliDefaultBaseURL
        }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.junaliBaseURL) }
    }

    static var codexCLIPath: String {
        get { UserDefaults.standard.string(forKey: Key.codexCLIPath)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.codexCLIPath) }
    }

    static var knownModels: [AIProviderKind: [AIModelOption]] {
        [
            .gemini: [
                AIModelOption(id: "gemini-2.5-pro", name: "Gemini 2.5 Pro", role: "Quality"),
                AIModelOption(id: "gemini-2.5-flash", name: "Gemini 2.5 Flash", role: "Balanced"),
                AIModelOption(id: "gemini-2.0-flash", name: "Gemini 2.0 Flash", role: "Compatible")
            ],
            .junali: openAICompatibleModels,
            .codexCLI: openAICompatibleModels
        ]
    }

    private static let openAICompatibleModels = [
        AIModelOption(id: "gpt-5.6-sol", name: "GPT-5.6 Sol", role: "Deep reasoning"),
        AIModelOption(id: "gpt-5.6-terra", name: "GPT-5.6 Terra", role: "Balanced"),
        AIModelOption(id: "gpt-5.6-luna", name: "GPT-5.6 Luna", role: "Fast")
    ]
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
