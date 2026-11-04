import Foundation

nonisolated enum AIProviderKind: String, CaseIterable, Codable, Identifiable, Sendable {
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
    case max
    case ultra

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .xhigh: return "Extra high"
        default: return rawValue.capitalized
        }
    }

    var detail: String {
        switch self {
        case .none: return "Fastest response with no deliberate reasoning budget."
        case .low: return "Lower latency for routine questions and quick review."
        case .medium: return "Balanced speed and depth for everyday study support."
        case .high: return "Deeper reasoning for synthesis and exam analysis."
        case .xhigh: return "Extra depth for difficult, multi-step problems."
        case .max: return "Maximum depth for the hardest quality-first work."
        case .ultra: return "The deepest local Codex reasoning for unusually difficult work."
        }
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

nonisolated struct CodexCatalogModel: Codable, Sendable {
    struct ReasoningOption: Codable, Sendable {
        let reasoningEffort: String
    }

    let model: String
    let displayName: String
    let description: String
    let hidden: Bool
    let isDefault: Bool
    let supportedReasoningEfforts: [ReasoningOption]
}

nonisolated enum AIConfiguration {
    static let junaliDefaultBaseURL = "https://openapi.junliai.org/v1"
    static let codexDefaultModel = "gpt-5.6-sol"

    nonisolated private enum Key {
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
            fallback = cachedCodexModels.first(where: \.isDefault)?.model ?? codexDefaultModel
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

    static func modelDisplayName(_ model: String, for provider: AIProviderKind) -> String {
        knownModels[provider]?.first(where: { $0.id == model })?.name ?? model
    }

    static func supportedReasoningEfforts(for provider: AIProviderKind) -> [AIReasoningEffort] {
        switch provider {
        case .codexCLI:
            if let model = cachedCodexModels.first(where: { $0.model == self.model(for: provider) }) {
                let supported = model.supportedReasoningEfforts.compactMap { AIReasoningEffort(rawValue: $0.reasoningEffort) }
                if !supported.isEmpty { return supported }
            }
            return [.low, .medium, .high, .xhigh, .max, .ultra]
        case .junali:
            return [.none, .low, .medium, .high, .xhigh, .max]
        case .gemini:
            return []
        }
    }

    static func normalizedReasoningEffort(
        _ effort: AIReasoningEffort,
        for provider: AIProviderKind
    ) -> AIReasoningEffort {
        let supported = supportedReasoningEfforts(for: provider)
        guard !supported.isEmpty else { return effort }
        guard !supported.contains(effort) else { return effort }

        switch (provider, effort) {
        case (.codexCLI, .none): return .low
        case (.junali, .ultra): return .max
        default: return .medium
        }
    }

    static func reasoningEffortValue(for provider: AIProviderKind) -> String {
        normalizedReasoningEffort(reasoningEffort, for: provider).rawValue
    }

    static var conversationWindow: Int {
        24
    }

    static var autoCompactEnabled: Bool {
        true
    }

    /// Stores a fresh catalog. A selection the catalog used to list and no longer
    /// does has been retired, so it falls back to the new default. IDs that were
    /// never listed are deliberate custom choices and are left alone.
    static func syncCodexCatalog(_ models: [CodexCatalogModel]) {
        let previous = Set(cachedCodexModels.map(\.model))
        let current = Set(models.map(\.model))
        if let selected = UserDefaults.standard.string(forKey: Key.codexModel),
           previous.contains(selected), !current.contains(selected) {
            UserDefaults.standard.removeObject(forKey: Key.codexModel)
        }
        cachedCodexModels = models
    }

    static var cachedCodexModels: [CodexCatalogModel] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "codexModelCatalog"),
                  let models = try? JSONDecoder().decode([CodexCatalogModel].self, from: data) else { return [] }
            return models
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: "codexModelCatalog")
        }
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
            .codexCLI: cachedCodexModels.map {
                AIModelOption(id: $0.model, name: $0.displayName, role: $0.description)
            }
        ]
    }

    private static let openAICompatibleModels = [
        AIModelOption(id: "gpt-5.6-sol", name: "GPT-5.6 Sol", role: "Deep reasoning"),
        AIModelOption(id: "gpt-5.6-terra", name: "GPT-5.6 Terra", role: "Balanced"),
        AIModelOption(id: "gpt-5.6-luna", name: "GPT-5.6 Luna", role: "Fast")
    ]
}

nonisolated private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
