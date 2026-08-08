import Foundation
import AppKit
import SwiftData
import SwiftUI
import WebKit

private struct ARIAChatFailure: Identifiable {
    let id: UUID
    let sessionID: UUID?
    let prompt: String?
    let provider: AIProviderKind
    let message: String
    let needsCodexSignIn: Bool

    init(
        error: any Error,
        sessionID: UUID?,
        prompt: String?,
        provider: AIProviderKind
    ) {
        self.id = UUID()
        self.sessionID = sessionID
        self.prompt = prompt
        self.provider = provider
        self.message = error.localizedDescription
        if let providerError = error as? AIProviderError,
           case .codexNotAuthenticated = providerError {
            self.needsCodexSignIn = true
        } else {
            self.needsCodexSignIn = false
        }
    }

    init(
        message: String,
        sessionID: UUID?,
        prompt: String? = nil,
        provider: AIProviderKind,
        needsCodexSignIn: Bool = false,
        id: UUID = UUID()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.prompt = prompt
        self.provider = provider
        self.message = message
        self.needsCodexSignIn = needsCodexSignIn
    }
}

struct ARIAChatView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ARIAChatSession.updatedAt, order: .reverse) private var sessions: [ARIAChatSession]
    @AppStorage("ariaChatSidebarVisible") private var isSidebarVisible = true
    @AppStorage("ariaProvider") private var selectedProviderRaw = AIProviderKind.gemini.rawValue
    @AppStorage("ariaReasoningEffort") private var reasoningEffortRaw = AIReasoningEffort.medium.rawValue
    @AppStorage("ariaVerbosity") private var verbosityRaw = AIResponseVerbosity.medium.rawValue
    @AppStorage("ariaWebSearchMode") private var webSearchModeRaw = AIWebSearchMode.cached.rawValue
    @AppStorage("geminiModel") private var geminiModel = "gemini-2.0-flash"
    @AppStorage("junaliModel") private var junaliModel = AIConfiguration.codexDefaultModel
    @AppStorage("codexModel") private var codexModel = AIConfiguration.codexDefaultModel
    @AppStorage("ariaTemperature") private var ariaTemperature = 0.7
    @State private var ariaService: ARIAService
    @State private var inputText = ""
    @State private var streamingText = ""
    @State private var showMemory = false
    @State private var showChatCleanupConfirmation = false
    @State private var chatFailure: ARIAChatFailure?
    @State private var selectedSessionID: UUID?
    @State private var activeSessionID: UUID?
    @State private var activePrompt: String?
    @State private var activeProvider = AIProviderKind.gemini

    private var visibleSessions: [ARIAChatSession] {
        sessions.filter { !$0.isArchived }
    }

    private var selectedSession: ARIAChatSession? {
        guard let selectedSessionID else { return visibleSessions.first }
        // Never fall back to a different session when the @Query snapshot has
        // not caught up to a just-inserted chat: falling back makes the
        // conversation area flash the previous session's transcript right after
        // "New Chat". Return nil so the empty state shows until the new
        // session appears in the snapshot.
        return visibleSessions.first(where: { $0.id == selectedSessionID })
    }

    private var selectedProvider: AIProviderKind {
        AIProviderKind(rawValue: selectedProviderRaw) ?? .gemini
    }

    private var selectedReasoningEffort: AIReasoningEffort {
        let stored = AIReasoningEffort(rawValue: reasoningEffortRaw) ?? .medium
        return AIConfiguration.normalizedReasoningEffort(stored, for: selectedProvider)
    }

    private var selectedVerbosity: AIResponseVerbosity {
        AIResponseVerbosity(rawValue: verbosityRaw) ?? .medium
    }

    private var selectedWebSearchMode: AIWebSearchMode {
        AIWebSearchMode(rawValue: webSearchModeRaw) ?? .cached
    }

    private var selectedModel: String {
        switch selectedProvider {
        case .gemini: return geminiModel
        case .junali: return junaliModel
        case .codexCLI: return codexModel
        }
    }

    private var geminiCreativityName: String {
        if ariaTemperature <= 0.35 { return "Precise" }
        if ariaTemperature <= 0.85 { return "Balanced" }
        return "Exploratory"
    }

    init() {
        _ariaService = State(initialValue: ARIAServiceFactory.make())
    }

    var body: some View {
        GeometryReader { geometry in
            let usesExpandedChatLayout = geometry.size.width >= 1_100
            let showsSessionSidebar = isSidebarVisible && usesExpandedChatLayout

            NavigationStack {
                HStack(spacing: 0) {
                    if showsSessionSidebar {
                        sessionSidebar
                            .transition(.move(edge: .leading).combined(with: .opacity))

                        Divider()
                    }

                    VStack(spacing: 0) {
                        if let selectedSession {
                            ARIASessionConversationView(
                                sessionID: selectedSession.id,
                                isLoading: ariaService.isLoading && activeSessionID == selectedSession.id,
                                currentStatus: ariaService.currentStatus,
                                streamingText: activeSessionID == selectedSession.id ? streamingText : "",
                                failure: visibleFailure(for: selectedSession.id),
                                onRetry: retryFailure,
                                onReconnectCodex: reconnectCodex,
                                onDismissFailure: dismissFailure
                            ) {
                                emptyState
                            }
                            .id(selectedSession.id)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .layoutPriority(1)
                        } else {
                            emptyState
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }

                        Divider()

                        inputBar
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(IBColors.canvas)
                .navigationTitle(selectedSession?.title ?? "ARIA")
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        if usesExpandedChatLayout {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isSidebarVisible.toggle()
                                }
                            } label: {
                                Image(systemName: isSidebarVisible ? "sidebar.left" : "sidebar.right")
                            }
                            .help(isSidebarVisible ? "Hide Chats" : "Show Chats")
                        } else {
                            compactSessionMenu
                        }
                    }

                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            createNewChat()
                        } label: {
                            Label("New Chat", systemImage: "square.and.pencil")
                        }
                        .disabled(ariaService.isLoading)
                        .keyboardShortcut("n", modifiers: .command)
                    }

                    ToolbarItem(placement: .primaryAction) {
                        Button { showMemory = true } label: {
                            Label("Memory", systemImage: "brain")
                        }
                    }
                }
                .sheet(isPresented: $showMemory) { ARIAMemoryView() }
                .alert("Delete chats older than 30 days?", isPresented: $showChatCleanupConfirmation) {
                    Button("Delete", role: .destructive) {
                        deleteChatsOlderThan30Days()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This permanently removes the matching conversations and their messages.")
                }
                .task {
                    await MainActor.run {
                        bootstrapSessionsIfNeeded()
                        normalizeChatConfiguration()
                        ariaService.updateSuggestedPrompts(context: context)
                    }
                }
                .onChange(of: sessions.count) { _, _ in
                    bootstrapSessionsIfNeeded()
                }
            }
        }
    }

    private var compactSessionMenu: some View {
        Menu {
            ForEach(visibleSessions, id: \.id) { session in
                Button {
                    selectedSessionID = session.id
                    streamingText = ""
                } label: {
                    Label(
                        session.title,
                        systemImage: session.id == selectedSession?.id ? "checkmark" : "bubble.left"
                    )
                }
            }

            Divider()

            Button {
                createNewChat()
            } label: {
                Label("New Chat", systemImage: "square.and.pencil")
            }
        } label: {
            Image(systemName: "bubble.left.and.bubble.right")
        }
        .help("Switch chat")
        .disabled(ariaService.isLoading)
    }

    private var sessionSidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(IBGradient.accent)
                        .frame(width: 34, height: 34)
                        .shadow(color: IBColors.electricBlue.opacity(0.3), radius: 6, x: 0, y: 2)
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("ARIA")
                        .font(.system(size: 15, weight: .bold))
                    Text("STUDY COMPANION")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(IBColors.teal)
                }
                Spacer(minLength: 4)
                Text("\(visibleSessions.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(IBColors.secondaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(IBColors.canvas))
                Button {
                    createNewChat()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .bold))
                }
                .buttonStyle(.borderless)
                .disabled(ariaService.isLoading)
                .help("New Chat")
                Menu {
                    Button(role: .destructive) {
                        showChatCleanupConfirmation = true
                    } label: {
                        Label("Delete Chats Older Than 30 Days", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13, weight: .bold))
                }
                .menuStyle(.borderlessButton)
                .disabled(ariaService.isLoading)
                .help("Chat actions")
            }
            .padding(.horizontal, 14)
            .frame(height: 58)

            Divider()

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(visibleSessions, id: \.id) { session in
                        Button {
                            selectedSessionID = session.id
                            streamingText = ""
                        } label: {
                            ARIAChatSessionRow(
                                session: session,
                                isSelected: session.id == selectedSession?.id
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                deleteChat(session)
                            } label: {
                                Label("Delete Chat", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(9)
            }
        }
        .frame(width: 268)
        .frame(maxHeight: .infinity)
        .background(IBColors.surface)
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer().frame(height: 28)

            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(IBGradient.accent)
                    .frame(width: 60, height: 60)
                    .shadow(color: IBColors.electricBlue.opacity(0.35), radius: 14, x: 0, y: 6)
                Image(systemName: "sparkles")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 6) {
                Text("Choose a starting point")
                    .font(.title2.bold())
                Text("Your current curriculum and review history are ready.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            VStack(spacing: 8) {
                ForEach(ariaService.suggestedPrompts, id: \.self) { prompt in
                    PromptChip(text: prompt) { sendMessage(prompt) }
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: 460)

            Spacer()
        }
    }

    // MARK: - Input Bar
    private var inputBar: some View {
        VStack(spacing: 9) {
            configurationRail

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask ARIA…", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .onSubmit { sendMessage(inputText) }
                    .disabled(ariaService.isLoading)

                Button {
                    if ariaService.isLoading {
                        cancelGeneration()
                    } else {
                        sendMessage(inputText)
                    }
                } label: {
                    let canSend = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ariaService.isLoading
                    Image(systemName: ariaService.isLoading ? "stop.fill" : "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            Group {
                                if canSend {
                                    Circle().fill(IBGradient.accent)
                                } else {
                                    Circle().fill(IBColors.tertiaryText.opacity(0.45))
                                }
                            }
                            .shadow(color: canSend ? IBColors.electricBlue.opacity(0.3) : .clear, radius: 6, x: 0, y: 2)
                        )
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !ariaService.isLoading)
                .help(ariaService.isLoading ? "Stop response" : "Send message")
            }
            .padding(5)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(IBColors.surface)
                    .shadow(color: IBShadow.cardColor, radius: 10, x: 0, y: 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(IBColors.cardBorder, lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(IBColors.canvas)
    }

    private var configurationRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Menu {
                    ForEach(AIProviderKind.allCases) { provider in
                        Button {
                            selectProvider(provider)
                        } label: {
                            Label(
                                provider.displayName,
                                systemImage: provider == selectedProvider ? "checkmark" : provider.symbolName
                            )
                        }
                    }
                } label: {
                    ARIAConfigurationMenuLabel(
                        title: selectedProvider.shortName,
                        symbol: selectedProvider.symbolName,
                        tint: IBColors.teal
                    )
                }
                .help("AI provider")

                Menu {
                    ForEach(AIConfiguration.knownModels[selectedProvider] ?? []) { option in
                        Button {
                            setSelectedModel(option.id)
                        } label: {
                            Label(
                                "\(option.name) · \(option.role)",
                                systemImage: option.id == selectedModel ? "checkmark" : "cpu"
                            )
                        }
                    }

                    if !(AIConfiguration.knownModels[selectedProvider] ?? []).contains(where: { $0.id == selectedModel }) {
                        Divider()
                        Text("Custom: \(selectedModel)")
                    }
                } label: {
                    ARIAConfigurationMenuLabel(
                        title: AIConfiguration.modelDisplayName(selectedModel, for: selectedProvider),
                        symbol: "cpu",
                        tint: IBColors.electricBlue
                    )
                }
                .help("Model")

                if selectedProvider == .gemini {
                    Menu {
                        Button {
                            ariaTemperature = 0.2
                        } label: {
                            Label("Precise", systemImage: geminiCreativityName == "Precise" ? "checkmark" : "scope")
                        }
                        Button {
                            ariaTemperature = 0.7
                        } label: {
                            Label("Balanced", systemImage: geminiCreativityName == "Balanced" ? "checkmark" : "dial.medium")
                        }
                        Button {
                            ariaTemperature = 1.1
                        } label: {
                            Label("Exploratory", systemImage: geminiCreativityName == "Exploratory" ? "checkmark" : "wand.and.stars")
                        }
                    } label: {
                        ARIAConfigurationMenuLabel(
                            title: geminiCreativityName,
                            symbol: "dial.medium",
                            tint: IBColors.gold
                        )
                    }
                    .help("Response creativity")
                } else {
                    Menu {
                        ForEach(AIConfiguration.supportedReasoningEfforts(for: selectedProvider)) { effort in
                            Button {
                                reasoningEffortRaw = effort.rawValue
                            } label: {
                                Label(
                                    effort.displayName,
                                    systemImage: effort == selectedReasoningEffort ? "checkmark" : "brain.head.profile"
                                )
                            }
                        }
                    } label: {
                        ARIAConfigurationMenuLabel(
                            title: selectedReasoningEffort.displayName,
                            symbol: "brain.head.profile",
                            tint: IBColors.gold
                        )
                    }
                    .help("Reasoning effort: \(selectedReasoningEffort.detail)")

                    Menu {
                        ForEach(AIResponseVerbosity.allCases) { verbosity in
                            Button {
                                verbosityRaw = verbosity.rawValue
                            } label: {
                                Label(
                                    verbosity.displayName,
                                    systemImage: verbosity == selectedVerbosity ? "checkmark" : "text.alignleft"
                                )
                            }
                        }
                    } label: {
                        ARIAConfigurationMenuLabel(
                            title: selectedVerbosity.displayName,
                            symbol: "text.alignleft",
                            tint: IBColors.ink
                        )
                    }
                    .help("Answer detail")
                }

                if selectedProvider == .codexCLI {
                    Menu {
                        ForEach(AIWebSearchMode.allCases) { mode in
                            Button {
                                webSearchModeRaw = mode.rawValue
                            } label: {
                                Label(
                                    mode.displayName,
                                    systemImage: mode == selectedWebSearchMode ? "checkmark" : "globe"
                                )
                            }
                        }
                    } label: {
                        ARIAConfigurationMenuLabel(
                            title: selectedWebSearchMode.displayName,
                            symbol: "globe",
                            tint: IBColors.success
                        )
                    }
                    .help("Web search: \(selectedWebSearchMode.detail)")
                }
            }
        }
        .scrollClipDisabled()
        .disabled(ariaService.isLoading)
    }

    private func sendMessage(_ text: String) {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        // Guard before clearing inputText or persisting anything so a send
        // attempted while a response is streaming is never silently dropped.
        guard !ariaService.isLoading else { return }
        guard let selectedSession else {
            guard let bootstrappedSession = bootstrapSessionsIfNeeded() else { return }
            persistSelectedConfiguration()
            inputText = ""
            beginMessage(message, in: bootstrappedSession, persistUserMessage: true)
            return
        }
        persistSelectedConfiguration()
        inputText = ""
        beginMessage(message, in: selectedSession, persistUserMessage: true)
    }

    private func beginMessage(
        _ message: String,
        in session: ARIAChatSession,
        persistUserMessage: Bool
    ) {
        guard !ariaService.isLoading else { return }
        let provider = selectedProvider
        streamingText = ""
        chatFailure = nil
        activeSessionID = session.id
        activePrompt = message
        activeProvider = provider
        IBHaptics.light()
        ariaService.sendMessage(
            message,
            context: context,
            session: session,
            persistUserMessage: persistUserMessage,
            onToken: { partial in streamingText = partial },
            onComplete: { _ in
                streamingText = ""
                activeSessionID = nil
                activePrompt = nil
            },
            onError: { error, persistedFailureID in
                if persistedFailureID == nil {
                    chatFailure = ARIAChatFailure(
                        error: error,
                        sessionID: session.id,
                        prompt: message,
                        provider: provider
                    )
                }
                streamingText = ""
                activeSessionID = nil
                activePrompt = nil
            }
        )
    }

    private func retryFailure(_ failure: ARIAChatFailure) {
        guard !ariaService.isLoading,
              let prompt = failure.prompt,
              let sessionID = failure.sessionID,
              let session = visibleSessions.first(where: { $0.id == sessionID }) else {
            return
        }
        selectedSessionID = sessionID
        persistSelectedConfiguration()
        if !removePersistedFailure(id: failure.id) {
            return
        }
        beginMessage(prompt, in: session, persistUserMessage: false)
    }

    private func cancelGeneration() {
        guard ariaService.isLoading else { return }
        let sessionID = activeSessionID
        let prompt = activePrompt
        let provider = activeProvider
        let session = sessionID.flatMap { id in visibleSessions.first(where: { $0.id == id }) }
        let persistedFailureID = ariaService.cancelCurrentRequest(
            context: context,
            session: session,
            provider: provider
        )
        streamingText = ""
        activeSessionID = nil
        activePrompt = nil
        if persistedFailureID == nil {
            chatFailure = ARIAChatFailure(
                message: "Response stopped. Your message is saved and can be retried.",
                sessionID: sessionID,
                prompt: prompt,
                provider: provider
            )
        }
    }

    private func visibleFailure(for sessionID: UUID) -> ARIAChatFailure? {
        guard let chatFailure,
              chatFailure.sessionID == nil || chatFailure.sessionID == sessionID else {
            return nil
        }
        return chatFailure
    }

    private func dismissFailure(_ failure: ARIAChatFailure) {
        if chatFailure?.id == failure.id {
            chatFailure = nil
            return
        }

        guard let message = persistedMessage(id: failure.id),
              ChatMessageRole(storedValue: message.role)?.isFailure == true else { return }
        let previousRole = message.role
        if let parsedRole = ChatMessageRole(storedValue: message.role) { message.role = ChatMessageRole.dismissed(underlying: parsedRole).storedValue }
        do {
            try context.save()
        } catch {
            // Revert only this message's role, not unrelated pending work.
            message.role = previousRole
            chatFailure = ARIAChatFailure(
                message: "This recovery notice could not be dismissed: \(error.localizedDescription)",
                sessionID: failure.sessionID,
                prompt: failure.prompt,
                provider: failure.provider
            )
        }
    }

    private func removePersistedFailure(id: UUID) -> Bool {
        guard let message = persistedMessage(id: id) else { return true }
        guard ChatMessageRole(storedValue: message.role)?.isFailure == true else { return true }
        context.delete(message)
        do {
            try context.save()
            return true
        } catch {
            context.insert(message)
            chatFailure = ARIAChatFailure(
                message: "The saved response could not be prepared for retry: \(error.localizedDescription)",
                sessionID: message.sessionID,
                provider: ChatMessageRole(storedValue: message.role)?.failureProvider ?? selectedProvider
            )
            return false
        }
    }

    private func persistedMessage(id: UUID) -> ChatMessage? {
        let targetID = id
        var descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate<ChatMessage> { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func reconnectCodex(_ failure: ARIAChatFailure) {
        do {
            let command = try AIProviderService.codexLoginCommand()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)

            let terminalPaths = [
                "/System/Applications/Utilities/Terminal.app",
                "/Applications/Utilities/Terminal.app"
            ]
            guard let terminalPath = terminalPaths.first(where: { FileManager.default.fileExists(atPath: $0) }),
                  NSWorkspace.shared.open(URL(fileURLWithPath: terminalPath)) else {
                throw AIProviderError.processFailed("Could not open Terminal. The Codex sign-in command is on your clipboard.")
            }

            let statusMessage = "Terminal is open and the Codex sign-in command is copied. Paste it, finish the browser sign-in, then retry this message."
            if !updatePersistedFailure(failure, content: statusMessage) {
                chatFailure = ARIAChatFailure(
                    message: statusMessage,
                    sessionID: failure.sessionID,
                    prompt: failure.prompt,
                    provider: .codexCLI
                )
            }
        } catch {
            if !updatePersistedFailure(failure, content: error.localizedDescription) {
                chatFailure = ARIAChatFailure(
                    error: error,
                    sessionID: failure.sessionID,
                    prompt: failure.prompt,
                    provider: .codexCLI
                )
            }
        }
    }

    private func updatePersistedFailure(_ failure: ARIAChatFailure, content: String) -> Bool {
        guard let message = persistedMessage(id: failure.id),
              ChatMessageRole(storedValue: message.role)?.isFailure == true else { return false }
        let previousContent = message.content
        message.content = content
        do {
            try context.save()
            chatFailure = nil
            return true
        } catch {
            message.content = previousContent
            return false
        }
    }

    /// Ensures at least one usable chat session exists and returns the session
    /// that should be treated as selected. Returning it (instead of making the
    /// caller re-read the @Query snapshot) matters right after an insert, when
    /// the observed `sessions` array has not caught up yet and would otherwise
    /// report nil, silently dropping a freshly-sent message.
    @MainActor
    @discardableResult
    private func bootstrapSessionsIfNeeded() -> ARIAChatSession? {
        var didMutate = false
        var preferredSelection = selectedSessionID
        var bootstrappedSession: ARIAChatSession?

        let orphanDescriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate<ChatMessage> { $0.sessionID == nil },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        let orphanMessages = (try? context.fetch(orphanDescriptor)) ?? []
        if !orphanMessages.isEmpty {
            let legacySession = ARIAChatSession(
                title: "Previous Chat",
                lastMessagePreview: orphanMessages.last?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
            legacySession.updatedAt = orphanMessages.last?.timestamp ?? legacySession.updatedAt
            context.insert(legacySession)
            for message in orphanMessages {
                message.sessionID = legacySession.id
            }
            preferredSelection = preferredSelection ?? legacySession.id
            bootstrappedSession = bootstrappedSession ?? legacySession
            didMutate = true
        }

        if visibleSessions.isEmpty && !didMutate {
            let session = ARIAChatSession()
            context.insert(session)
            preferredSelection = session.id
            bootstrappedSession = bootstrappedSession ?? session
            didMutate = true
        }

        if didMutate {
            do {
                try context.save()
            } catch {
                if let bootstrappedSession {
                    context.delete(bootstrappedSession)
                }
                chatFailure = ARIAChatFailure(
                    message: "Chat setup could not be saved: \(error.localizedDescription)",
                    sessionID: selectedSessionID,
                    provider: selectedProvider
                )
                return nil
            }
        }

        if selectedSessionID == nil {
            selectedSessionID = preferredSelection ?? visibleSessions.first?.id
        }
        if let bootstrappedSession { return bootstrappedSession }
        // Match only the explicit selection. The previous `?? visibleSessions.first`
        // fallback could hand a freshly-typed message to a *different* session
        // when the selection pointed at a just-inserted chat the @Query snapshot
        // had not yet published. Returning nil keeps the input intact instead.
        return visibleSessions.first(where: { $0.id == selectedSessionID })
    }

    @MainActor
    private func createNewChat() {
        if !isSidebarVisible {
            withAnimation(.easeInOut(duration: 0.2)) {
                isSidebarVisible = true
            }
        }
        let session = ARIAChatSession()
        context.insert(session)
        do {
            try context.save()
        } catch {
            context.delete(session)
            chatFailure = ARIAChatFailure(
                message: "The new chat could not be saved: \(error.localizedDescription)",
                sessionID: selectedSessionID,
                provider: selectedProvider
            )
            return
        }
        selectedSessionID = session.id
        inputText = ""
        streamingText = ""
        chatFailure = nil
    }

    @MainActor
    private func deleteChat(_ session: ARIAChatSession) {
        // If a request is streaming into this session, stop it first. Writing to
        // a deleted SwiftData model raises an uncatchable exception, so we must
        // never delete a session that an in-flight task may still touch.
        if ariaService.isLoading && session.id == activeSessionID {
            ariaService.cancelCurrentRequest(context: context, session: session, provider: selectedProvider)
        }
        // The cancelled request no longer owns any active streaming state; keep
        // it from leaking into the next selected session.
        if session.id == activeSessionID {
            activeSessionID = nil
            activePrompt = nil
            streamingText = ""
        }

        let sessionID = session.id
        let messageDescriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate<ChatMessage> { $0.sessionID == sessionID }
        )
        for message in (try? context.fetch(messageDescriptor)) ?? [] {
            context.delete(message)
        }
        context.delete(session)
        do {
            try context.save()
        } catch {
            context.insert(session)
            chatFailure = ARIAChatFailure(
                message: "The chat could not be deleted: \(error.localizedDescription)",
                sessionID: selectedSessionID,
                provider: selectedProvider
            )
            return
        }
        if selectedSessionID == sessionID {
            selectedSessionID = visibleSessions.first(where: { $0.id != sessionID })?.id
        }
    }

    @MainActor
    private func deleteChatsOlderThan30Days() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        let staleSessions = sessions.filter { $0.updatedAt < cutoff }
        guard !staleSessions.isEmpty else { return }

        let staleIDs = Set(staleSessions.map(\.id))
        let messageDescriptor = FetchDescriptor<ChatMessage>()
        for message in (try? context.fetch(messageDescriptor)) ?? [] where message.sessionID.map(staleIDs.contains) == true {
            context.delete(message)
        }
        for session in staleSessions {
            context.delete(session)
        }
        do {
            try context.save()
            if let selectedSessionID, staleIDs.contains(selectedSessionID) {
                self.selectedSessionID = visibleSessions.first(where: { !staleIDs.contains($0.id) })?.id
            }
        } catch {
            context.rollback()
            chatFailure = ARIAChatFailure(
                message: "The old chats could not be deleted: \(error.localizedDescription)",
                sessionID: selectedSessionID,
                provider: selectedProvider
            )
        }
    }

    private func selectProvider(_ provider: AIProviderKind) {
        selectedProviderRaw = provider.rawValue
        reasoningEffortRaw = AIConfiguration.normalizedReasoningEffort(
            AIReasoningEffort(rawValue: reasoningEffortRaw) ?? .medium,
            for: provider
        ).rawValue
        chatFailure = nil
    }

    private func setSelectedModel(_ model: String) {
        switch selectedProvider {
        case .gemini: geminiModel = model
        case .junali: junaliModel = model
        case .codexCLI: codexModel = model
        }
    }

    private func normalizeChatConfiguration() {
        selectProvider(selectedProvider)
    }

    private func persistSelectedConfiguration() {
        AIConfiguration.provider = selectedProvider
        AIConfiguration.setModel(selectedModel, for: selectedProvider)
        AIConfiguration.reasoningEffort = selectedReasoningEffort
        AIConfiguration.verbosity = selectedVerbosity
        AIConfiguration.webSearchMode = selectedWebSearchMode
    }
}

private struct ARIASessionConversationView<EmptyContent: View>: View {
    @Query private var messages: [ChatMessage]
    let isLoading: Bool
    let currentStatus: String
    let streamingText: String
    let failure: ARIAChatFailure?
    let onRetry: (ARIAChatFailure) -> Void
    let onReconnectCodex: (ARIAChatFailure) -> Void
    let onDismissFailure: (ARIAChatFailure) -> Void
    let emptyContent: EmptyContent
    @State private var lastStreamingScrollCount = 0
    @State private var dismissedRecoveredFailureID: UUID?

    private var displayedFailure: ARIAChatFailure? {
        if let failure { return failure }
        // Only synthesize a recovery banner for a genuinely abandoned exchange:
        // the last saved message is a user message, nothing is in flight, it
        // hasn't already been dismissed, and it is recent enough to still be a
        // relaunch artifact rather than a stale, deliberately-abandoned prompt.
        guard !isLoading,
              let lastMessage = messages.last,
              lastMessage.role == ChatMessageRole.user.storedValue,
              dismissedRecoveredFailureID != lastMessage.id,
              Date().timeIntervalSince(lastMessage.timestamp) < Self.recoveryBannerRecencyWindow else {
            return nil
        }
        return ARIAChatFailure(
            message: "ARIA did not finish this response. The saved message can be retried without creating a duplicate.",
            sessionID: lastMessage.sessionID,
            prompt: lastMessage.content,
            provider: AIConfiguration.provider,
            id: lastMessage.id
        )
    }

    private static var recoveryBannerRecencyWindow: TimeInterval { 60 * 60 * 48 }

    init(
        sessionID: UUID,
        isLoading: Bool,
        currentStatus: String,
        streamingText: String,
        failure: ARIAChatFailure?,
        onRetry: @escaping (ARIAChatFailure) -> Void,
        onReconnectCodex: @escaping (ARIAChatFailure) -> Void,
        onDismissFailure: @escaping (ARIAChatFailure) -> Void,
        @ViewBuilder emptyContent: () -> EmptyContent
    ) {
        let selectedSessionID = sessionID
        _messages = Query(
            filter: #Predicate<ChatMessage> { $0.sessionID == selectedSessionID },
            sort: \ChatMessage.timestamp
        )
        self.isLoading = isLoading
        self.currentStatus = currentStatus
        self.streamingText = streamingText
        self.failure = failure
        self.onRetry = onRetry
        self.onReconnectCodex = onReconnectCodex
        self.onDismissFailure = onDismissFailure
        self.emptyContent = emptyContent()
    }

    var body: some View {
        let failureMap = failuresByID
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if messages.isEmpty && !isLoading {
                        emptyContent
                    }

                    ForEach(messages, id: \.id) { message in
                        if let persistedFailure = failureMap[message.id] {
                            ARIAChatFailureRow(
                                failure: persistedFailure,
                                onRetry: { onRetry(persistedFailure) },
                                onReconnectCodex: { onReconnectCodex(persistedFailure) },
                                onDismiss: { onDismissFailure(persistedFailure) }
                            )
                            .id(message.id)
                        } else if ChatMessageRole(storedValue: message.role)?.isConversation == true {
                            MessageRow(message: message)
                                .id(message.id)
                        }
                    }

                    if isLoading {
                        ARIAThinkingIndicator(status: currentStatus)
                        if !streamingText.isEmpty {
                            StreamingMessageRow(text: streamingText)
                                .id("streaming")
                        }
                    }

                    if let failure = displayedFailure {
                        ARIAChatFailureRow(
                            failure: failure,
                            onRetry: { onRetry(failure) },
                            onReconnectCodex: { onReconnectCodex(failure) },
                            onDismiss: {
                                if self.failure?.id == failure.id {
                                    onDismissFailure(failure)
                                } else {
                                    dismissedRecoveredFailureID = failure.id
                                }
                            }
                        )
                        .id(failure.id)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
            .onAppear {
                guard let lastMessageID = messages.last?.id else { return }
                proxy.scrollTo(lastMessageID, anchor: .bottom)
            }
            .onChange(of: messages.last?.id) { _, newValue in
                guard let newValue else { return }
                Task { @MainActor in
                    await Task.yield()
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(newValue, anchor: .bottom)
                    }
                }
            }
            .onChange(of: streamingText.count) { _, newValue in
                if newValue == 0 {
                    lastStreamingScrollCount = 0
                    return
                }
                guard isLoading,
                      lastStreamingScrollCount == 0 || newValue - lastStreamingScrollCount >= 192 else { return }
                lastStreamingScrollCount = newValue
                Task { @MainActor in
                    await Task.yield()
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
            .onChange(of: displayedFailure?.id) { _, failureID in
                guard let failureID else { return }
                Task { @MainActor in
                    await Task.yield()
                    proxy.scrollTo(failureID, anchor: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failuresByID: [UUID: ARIAChatFailure] {
        // Single pass over the transcript: track the last user prompt so each
        // persisted failure can attach the prompt that triggered it. Rebuilding
        // this per render is O(n) instead of the previous O(n·failures) scan.
        var map: [UUID: ARIAChatFailure] = [:]
        var lastUserPrompt: String?
        for message in messages {
            if message.role == ChatMessageRole.user.storedValue {
                lastUserPrompt = message.content
            } else if ChatMessageRole(storedValue: message.role)?.isFailure == true,
                      let provider = ChatMessageRole(storedValue: message.role)?.failureProvider {
                map[message.id] = ARIAChatFailure(
                    message: message.content,
                    sessionID: message.sessionID,
                    prompt: lastUserPrompt,
                    provider: provider,
                    needsCodexSignIn: ChatMessageRole(storedValue: message.role)?.needsCodexAuthentication == true,
                    id: message.id
                )
            }
        }
        return map
    }
}

private struct ARIAChatFailureRow: View {
    let failure: ARIAChatFailure
    let onRetry: () -> Void
    let onReconnectCodex: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(IBColors.danger.opacity(0.1))
                    .frame(width: 30, height: 30)
                Image(systemName: "exclamationmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(IBColors.danger)
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Text("\(failure.provider.shortName) could not answer")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(IBColors.ink)
                    Spacer(minLength: 8)
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.borderless)
                    .help("Dismiss")
                }

                Text(failure.message)
                    .font(.caption)
                    .foregroundStyle(IBColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    if failure.needsCodexSignIn {
                        Button(action: onReconnectCodex) {
                            Label("Reconnect Codex", systemImage: "terminal")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }

                    if failure.prompt != nil {
                        Button(action: onRetry) {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .tint(IBColors.electricBlue)
                        .controlSize(.small)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: 680, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(IBColors.danger.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(IBColors.danger.opacity(0.18), lineWidth: 1)
                    )
            )

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ARIAThinkingIndicator: View {
    let status: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(IBColors.electricBlue.opacity(0.12))
                    .frame(width: 30, height: 30)
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(IBColors.electricBlue)
            }
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text(status.isEmpty ? "Preparing your response…" : status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(IBColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(IBColors.cardBorder, lineWidth: 1)
                    )
            )
            Spacer()
        }
    }
}

private struct ARIAConfigurationMenuLabel: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(IBColors.ink)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(IBColors.tertiaryText)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(IBColors.canvas)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(IBColors.cardBorder, lineWidth: 1)
                )
        )
    }
}

private struct ARIAChatSessionRow: View {
    let session: ARIAChatSession
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isSelected ? IBColors.electricBlue : Color.clear)
                .frame(width: 3, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(session.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(isSelected ? IBColors.electricBlue : IBColors.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(session.updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(IBColors.tertiaryText)
                        .lineLimit(1)
                }

                Text(session.lastMessagePreview.isEmpty ? "No messages yet" : session.lastMessagePreview)
                    .font(.caption)
                    .foregroundStyle(IBColors.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? IBColors.electricBlue.opacity(0.08) : Color.clear)
        )
    }
}

// MARK: - Message Row
struct MessageRow: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == ChatMessageRole.user.storedValue }

    var body: some View {
        Group {
            if isUser {
                HStack(alignment: .top, spacing: 10) {
                    Spacer(minLength: 80)
                    VStack(alignment: .trailing, spacing: 5) {
                        HStack(spacing: 6) {
                            MessageCopyButton(text: message.content)
                            Text("You")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(IBColors.secondaryText)
                        }
                        Text(message.content)
                            .lineSpacing(3)
                            .foregroundStyle(.white)
                            .textSelection(.enabled)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(IBGradient.accent)
                                    .shadow(color: IBColors.electricBlue.opacity(0.25), radius: 8, x: 0, y: 3)
                            )
                    }
                    .frame(maxWidth: 590, alignment: .trailing)
                    userAvatar
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ariaAvatar
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text("ARIA")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(IBColors.electricBlue)
                            MessageCopyButton(text: message.content)
                        }
                        FormattedMessageContent(text: message.content, preferRichRendering: true)
                            .padding(14)
                            .glassCard(cornerRadius: 16)
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    Spacer(minLength: 20)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var ariaAvatar: some View {
        ZStack {
            Circle()
                .fill(IBGradient.accent)
                .frame(width: 30, height: 30)
                .shadow(color: IBColors.electricBlue.opacity(0.3), radius: 5, x: 0, y: 2)
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var userAvatar: some View {
        ZStack {
            Circle()
                .fill(IBColors.ink.opacity(0.06))
                .frame(width: 30, height: 30)
            Image(systemName: "person.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(IBColors.secondaryText)
        }
    }
}

private enum ARIAClipboard {
    @discardableResult
    static func copy(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}

private struct MessageCopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            copied = ARIAClipboard.copy(text)
            guard copied else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.caption2.weight(.semibold))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(copied ? IBColors.success : IBColors.secondaryText)
        .help(copied ? "Copied" : "Copy message")
    }
}

// MARK: - Streaming Message Row
struct StreamingMessageRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(IBGradient.accent)
                    .frame(width: 30, height: 30)
                    .shadow(color: IBColors.electricBlue.opacity(0.3), radius: 5, x: 0, y: 2)
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("ARIA")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IBColors.electricBlue)
                    .padding(.horizontal, 4)
                Text(text)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(14)
                    .glassCard(cornerRadius: 16)
            }
            .frame(maxWidth: 760, alignment: .leading)
            Spacer()
        }
    }
}

struct FormattedMessageContent: View {
    let text: String
    var preferRichRendering = false
    @State private var sections: [FormattedMessageSection]

    init(text: String, preferRichRendering: Bool = false) {
        self.text = text
        self.preferRichRendering = preferRichRendering
        _sections = State(initialValue: FormattedMessageFormatter.sections(from: text))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                sectionView(section)
            }
        }
        .foregroundStyle(IBColors.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: text) { _, newText in
            sections = FormattedMessageFormatter.sections(from: newText)
        }
    }

    @ViewBuilder
    private func sectionView(_ section: FormattedMessageSection) -> some View {
        switch section {
        case .markdown(let markdown):
            if let attributed = FormattedMessageFormatter.attributedMarkdown(from: markdown) {
                Text(attributed)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(markdown)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .listItem(let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .fontWeight(.semibold)
                    .frame(width: 20, alignment: .trailing)

                Text(FormattedMessageFormatter.attributedMarkdown(from: text) ?? AttributedString(text))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .mathBlock(let latex):
            MathJaxBlockView(latex: latex)

        case .codeBlock(let code, let language):
            CodeBlockView(code: code, language: language)

        case .diagram(let diagram):
            ARIADiagramView(diagram: diagram)

        case .flashcard(let front, let back):
            FlashcardMessageView(front: front, back: back)
        }
    }
}

private struct MathJaxBlockView: View {
    let latex: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var contentHeight: CGFloat = 48
    @State private var usesFallback = false

    var body: some View {
        Group {
            if usesFallback {
                NativeMathBlockView(latex: latex)
            } else {
                OfflineMathJaxView(
                    latex: latex,
                    colorScheme: colorScheme,
                    height: $contentHeight,
                    didFail: $usesFallback
                )
                .frame(height: min(max(contentHeight, 36), 360))
                .accessibilityLabel("Rendered mathematical expression")
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .topTrailing) {
            MessageCopyButton(text: latex)
                .opacity(0.72)
        }
    }
}

private struct OfflineMathJaxView: NSViewRepresentable {
    let latex: String
    let colorScheme: ColorScheme
    @Binding var height: CGFloat
    @Binding var didFail: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height, didFail: $didFail)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "mathHeight")
        controller.add(context.coordinator, name: "mathError")
        configuration.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastLatex != latex || context.coordinator.lastColorScheme != colorScheme else { return }
        context.coordinator.lastLatex = latex
        context.coordinator.lastColorScheme = colorScheme
        context.coordinator.didFail.wrappedValue = false
        guard let scriptURL = Bundle.main.url(forResource: "tex-svg", withExtension: "js") else {
            context.coordinator.didFail.wrappedValue = true
            return
        }
        let html = MathRenderingPolicy.htmlDocument(latex: latex, colorScheme: colorScheme)
        webView.loadHTMLString(html, baseURL: scriptURL.deletingLastPathComponent())
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mathHeight")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mathError")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var lastLatex = ""
        var lastColorScheme: ColorScheme?
        var height: Binding<CGFloat>
        var didFail: Binding<Bool>

        init(height: Binding<CGFloat>, didFail: Binding<Bool>) {
            self.height = height
            self.didFail = didFail
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "mathHeight", let rawHeight = message.body as? Double {
                height.wrappedValue = CGFloat(rawHeight)
            } else if message.name == "mathError" {
                didFail.wrappedValue = true
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            didFail.wrappedValue = true
        }
    }
}

private struct NativeMathBlockView: View {
    let latex: String

    private var content: NativeMathBlockContent {
        MathExpressionFormatter.blockContent(from: latex)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            blockBody
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var blockBody: some View {
        switch content {
        case .text(let text):
            NativeMathText(text: text)
        case .aligned(let rows):
            NativeAlignedMathView(rows: rows)
        case .matrix(let rows, let leftDelimiter, let rightDelimiter):
            NativeMatrixMathView(rows: rows, leftDelimiter: leftDelimiter, rightDelimiter: rightDelimiter)
        case .cases(let rows):
            NativeCasesMathView(rows: rows)
        }
    }
}

private enum NativeMathBlockContent {
    case text(String)
    case aligned([NativeAlignedMathRow])
    case matrix(rows: [[String]], leftDelimiter: String, rightDelimiter: String)
    case cases([NativeCaseMathRow])
}

private struct NativeAlignedMathRow {
    let leading: String
    let trailing: String?
}

private struct NativeCaseMathRow {
    let condition: String
    let explanation: String?
}

private struct NativeMathText: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 16, weight: .medium, design: .serif))
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
    }
}

private struct NativeAlignedMathView: View {
    let rows: [NativeAlignedMathRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(verbatim: row.leading)
                        .font(.system(size: 16, weight: .medium, design: .serif))
                        .frame(minWidth: 0, alignment: .trailing)
                    if let trailing = row.trailing {
                        Text(verbatim: trailing)
                            .font(.system(size: 16, weight: .medium, design: .serif))
                            .frame(minWidth: 0, alignment: .leading)
                    }
                }
            }
        }
        .textSelection(.enabled)
    }
}

private struct NativeMatrixMathView: View {
    let rows: [[String]]
    let leftDelimiter: String
    let rightDelimiter: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(leftDelimiter)
                .font(.system(size: 28, weight: .light, design: .serif))
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(verbatim: cell)
                                .font(.system(size: 16, weight: .medium, design: .serif))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            Text(rightDelimiter)
                .font(.system(size: 28, weight: .light, design: .serif))
                .foregroundStyle(.secondary)
        }
        .textSelection(.enabled)
    }
}

private struct NativeCasesMathView: View {
    let rows: [NativeCaseMathRow]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("{")
                .font(.system(size: 30, weight: .light, design: .serif))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(verbatim: row.condition)
                            .font(.system(size: 16, weight: .medium, design: .serif))
                        if let explanation = row.explanation {
                            Text(verbatim: explanation)
                                .font(.system(size: 14, weight: .regular, design: .serif))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .textSelection(.enabled)
    }
}

enum FormattedMessageSection: Equatable {
    case markdown(String)
    case listItem(marker: String, text: String)
    case mathBlock(String)
    case codeBlock(code: String, language: String)
    case diagram(ARIADiagramSpec)
    case flashcard(front: String, back: String)
}

private struct ARIADiagramView: View {
    let diagram: ARIADiagramSpec
    @State private var isExpanded = false
    @State private var zoom: CGFloat = 1
    @State private var zoomBase: CGFloat = 1
    @State private var offset = CGSize.zero
    @State private var offsetBase = CGSize.zero
    @State private var simulationResetID = UUID()

    private var canvasHeight: CGFloat { isExpanded ? 420 : 280 }

    private var modeTitle: String {
        if diagram.isSimulation { return "Simulation" }
        if diagram.isCanvas { return "Canvas" }
        if diagram.isFlow { return "Flow" }
        return "Graph"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: diagram.isSimulation ? "atom" : (diagram.isCanvas ? "rectangle.3.group.bubble" : (diagram.isFlow ? "point.3.connected.trianglepath.dotted" : "chart.xyaxis.line")))
                    .foregroundStyle(IBColors.teal)
                Text(diagram.title ?? (diagram.isSimulation ? "Interactive simulation" : (diagram.isCanvas ? "Interactive canvas" : (diagram.isFlow ? "Concept diagram" : "Interactive graph"))))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(IBColors.ink)
                    .lineLimit(2)
                Spacer()
                Text(modeTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(IBColors.secondaryText)
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .background(IBColors.canvas, in: Capsule())
                Button {
                    if diagram.isSimulation || diagram.isCanvas {
                        simulationResetID = UUID()
                    } else {
                        withAnimation(.easeOut(duration: 0.18)) {
                            zoom = 1
                            zoomBase = 1
                            offset = .zero
                            offsetBase = .zero
                        }
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Reset diagram")

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help(isExpanded ? "Collapse canvas" : "Expand canvas")
            }

            Divider()

            if diagram.isSimulation {
                ARIAParticleSimulationView(
                    mode: diagram.simulation ?? "atoms",
                    particleCount: diagram.particleCount ?? 18
                )
                .id(simulationResetID)
                .frame(height: canvasHeight)
            } else if diagram.isCanvas, let scene = diagram.canvas {
                ARIAGenerativeCanvasView(scene: scene, canvasHeight: canvasHeight - 92)
                    .id(simulationResetID)
            } else {
                Canvas { context, size in
                    if diagram.isFlow {
                        drawFlow(in: &context, size: size)
                    } else {
                        drawCoordinateGraph(in: &context, size: size)
                    }
                }
                .frame(height: canvasHeight)
                .background(IBColors.canvas.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .scaleEffect(zoom)
                .offset(offset)
                .clipped()
                .highPriorityGesture(
                    DragGesture()
                        .onChanged {
                            offset = CGSize(
                                width: offsetBase.width + $0.translation.width,
                                height: offsetBase.height + $0.translation.height
                            )
                        }
                        .onEnded { _ in
                            offset.width = min(max(offset.width, -120), 120)
                            offset.height = min(max(offset.height, -90), 90)
                            offsetBase = offset
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            zoom = min(max(zoomBase * value, 0.75), 2.5)
                        }
                        .onEnded { _ in
                            zoomBase = zoom
                        }
                )
                .accessibilityLabel(diagram.title ?? "Interactive ARIA diagram")
            }

            if !diagram.isFlow, !diagram.isCanvas, !diagram.graphSeries.isEmpty {
                HStack(spacing: 12) {
                    ForEach(Array(diagram.graphSeries.enumerated()), id: \.offset) { index, series in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(seriesColor(series, index: index))
                                .frame(width: 7, height: 7)
                            Text(series.label ?? "Series \(index + 1)")
                                .font(.caption2)
                                .foregroundStyle(IBColors.secondaryText)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(IBColors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(IBColors.cardBorder, lineWidth: 1)
                )
        )
    }

    private func drawCoordinateGraph(in context: inout GraphicsContext, size: CGSize) {
        let values = diagram.graphSeries.flatMap(\.points).filter { $0.count >= 2 }
        guard !values.isEmpty else {
            context.draw(Text("ARIA diagram data is empty").font(.caption), at: CGPoint(x: size.width / 2, y: size.height / 2))
            return
        }
        let xValues = values.map { $0[0] }
        let yValues = values.map { $0[1] }
        let xMin = (xValues.min() ?? -1).rounded(.down) - 1
        let xMax = (xValues.max() ?? 1).rounded(.up) + 1
        let yMin = (yValues.min() ?? -1).rounded(.down) - 1
        let yMax = (yValues.max() ?? 1).rounded(.up) + 1
        let safeXSpan = max(xMax - xMin, 1)
        let safeYSpan = max(yMax - yMin, 1)
        let plot = CGRect(x: 38, y: 16, width: max(size.width - 54, 80), height: max(size.height - 50, 80))
        func point(_ value: [Double]) -> CGPoint {
            CGPoint(
                x: plot.minX + CGFloat((value[0] - xMin) / safeXSpan) * plot.width,
                y: plot.maxY - CGFloat((value[1] - yMin) / safeYSpan) * plot.height
            )
        }

        for step in 0...5 {
            let x = plot.minX + CGFloat(step) / 5 * plot.width
            let y = plot.minY + CGFloat(step) / 5 * plot.height
            var vertical = Path()
            vertical.move(to: CGPoint(x: x, y: plot.minY))
            vertical.addLine(to: CGPoint(x: x, y: plot.maxY))
            context.stroke(vertical, with: .color(IBColors.cardBorder.opacity(0.7)), lineWidth: 0.5)
            var horizontal = Path()
            horizontal.move(to: CGPoint(x: plot.minX, y: y))
            horizontal.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(horizontal, with: .color(IBColors.cardBorder.opacity(0.7)), lineWidth: 0.5)
        }
        if xMin <= 0, xMax >= 0 {
            let x = point([0, yMin]).x
            var axis = Path()
            axis.move(to: CGPoint(x: x, y: plot.minY))
            axis.addLine(to: CGPoint(x: x, y: plot.maxY))
            context.stroke(axis, with: .color(IBColors.secondaryText), lineWidth: 1)
        }
        if yMin <= 0, yMax >= 0 {
            let y = point([xMin, 0]).y
            var axis = Path()
            axis.move(to: CGPoint(x: plot.minX, y: y))
            axis.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(axis, with: .color(IBColors.secondaryText), lineWidth: 1)
        }

        for (index, series) in diagram.graphSeries.enumerated() {
            let points = series.points.filter { $0.count >= 2 }
            guard let first = points.first else { continue }
            var path = Path()
            path.move(to: point(first))
            for value in points.dropFirst() { path.addLine(to: point(value)) }
            let color = seriesColor(series, index: index)
            context.stroke(path, with: .color(color), lineWidth: 2)
            for value in points {
                let position = point(value)
                context.fill(Path(ellipseIn: CGRect(x: position.x - 2.5, y: position.y - 2.5, width: 5, height: 5)), with: .color(color))
            }
        }
        if let xLabel = diagram.xLabel {
            context.draw(Text(xLabel).font(.caption2), at: CGPoint(x: plot.midX, y: size.height - 10))
        }
        if let yLabel = diagram.yLabel {
            context.draw(Text(yLabel).font(.caption2), at: CGPoint(x: 14, y: plot.midY))
        }
    }

    private func drawFlow(in context: inout GraphicsContext, size: CGSize) {
        let nodes = diagram.flowNodes
        guard !nodes.isEmpty else {
            context.draw(Text("ARIA diagram data is empty").font(.caption), at: CGPoint(x: size.width / 2, y: size.height / 2))
            return
        }
        let positions = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { index, node in
            let columns = max(Int(ceil(sqrt(Double(nodes.count)))), 1)
            let row = index / columns
            let column = index % columns
            let x = node.x.map { CGFloat($0) * size.width } ?? (CGFloat(column + 1) / CGFloat(columns + 1) * size.width)
            let rows = max(Int(ceil(Double(nodes.count) / Double(columns))), 1)
            let y = node.y.map { CGFloat($0) * size.height } ?? (CGFloat(row + 1) / CGFloat(rows + 1) * size.height)
            return (node.id, CGPoint(x: x, y: y))
        })
        for edge in diagram.flowEdges {
            guard let start = positions[edge.from], let end = positions[edge.to] else { continue }
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(IBColors.secondaryText.opacity(0.75)), lineWidth: 1.4)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let arrow = CGPoint(x: end.x - cos(angle) * 18, y: end.y - sin(angle) * 18)
            var arrowPath = Path()
            arrowPath.move(to: arrow)
            arrowPath.addLine(to: CGPoint(x: arrow.x - cos(angle - .pi / 5) * 7, y: arrow.y - sin(angle - .pi / 5) * 7))
            arrowPath.move(to: arrow)
            arrowPath.addLine(to: CGPoint(x: arrow.x - cos(angle + .pi / 5) * 7, y: arrow.y - sin(angle + .pi / 5) * 7))
            context.stroke(arrowPath, with: .color(IBColors.secondaryText.opacity(0.75)), lineWidth: 1.4)
            if let label = edge.label {
                context.draw(Text(label).font(.caption2), at: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 - 10))
            }
        }
        for (index, node) in nodes.enumerated() {
            guard let point = positions[node.id] else { continue }
            let rect = CGRect(x: point.x - 54, y: point.y - 19, width: 108, height: 38)
            let color = node.color.map(Color.init(hex:)) ?? seriesColor(nil, index: index)
            context.fill(Path(roundedRect: rect, cornerRadius: 7), with: .color(color.opacity(0.14)))
            context.stroke(Path(roundedRect: rect, cornerRadius: 7), with: .color(color.opacity(0.75)), lineWidth: 1)
            context.draw(
                Text(node.label).font(.caption.weight(.semibold)).foregroundColor(IBColors.ink),
                at: point,
                anchor: .center
            )
        }
    }

    private func seriesColor(_ series: ARIADiagramSpec.Series?, index: Int) -> Color {
        if let hex = series?.color, !hex.isEmpty { return Color(hex: hex) }
        return [IBColors.electricBlue, IBColors.teal, IBColors.coral, IBColors.gold][index % 4]
    }
}

private struct ARIAParticleSimulationView: View {
    let mode: String
    let particleCount: Int
    @State private var isPlaying = true
    @State private var speed = 1.0
    @State private var pausedElapsed: TimeInterval = 0
    @State private var activeStartedAt = Date()

    private var isAtomMode: Bool {
        mode.localizedCaseInsensitiveContains("atom") || mode.localizedCaseInsensitiveContains("electron")
    }

    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { timeline in
                Canvas { context, size in
                    let elapsed = pausedElapsed + (isPlaying ? timeline.date.timeIntervalSince(activeStartedAt) : 0)
                    let time = elapsed * speed
                    if isAtomMode {
                        drawAtom(in: &context, size: size, time: time)
                    } else {
                        drawParticles(in: &context, size: size, time: time)
                    }
                }
                .background(Color.black.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }

            HStack(spacing: 10) {
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderless)
                .help(isPlaying ? "Pause simulation" : "Play simulation")

                Slider(value: $speed, in: 0.25...2.5)
                    .frame(maxWidth: 150)
                Text("\(speed, format: .number.precision(.fractionLength(1)))x")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(IBColors.secondaryText)
                Spacer()
                Text(isAtomMode ? "Electron orbit model" : "Particle motion model")
                    .font(.caption2)
                    .foregroundStyle(IBColors.secondaryText)
            }
        }
        .accessibilityLabel(isAtomMode ? "Interactive atom simulation" : "Interactive particle simulation")
    }

    private func togglePlayback() {
        if isPlaying {
            pausedElapsed += Date().timeIntervalSince(activeStartedAt)
            isPlaying = false
        } else {
            activeStartedAt = Date()
            isPlaying = true
        }
    }

    private func drawAtom(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radii: [CGFloat] = [48, 88]
        for radius in radii {
            context.stroke(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(IBColors.electricBlue.opacity(0.24)),
                lineWidth: 1
            )
        }
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - 18, y: center.y - 18, width: 36, height: 36)),
            with: .color(IBColors.coral)
        )
        for index in 0..<4 {
            let radius = radii[index % radii.count]
            let angle = time * (index.isMultiple(of: 2) ? 1.3 : -0.9) + Double(index) * .pi / 2
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)),
                with: .color(IBColors.electricBlue)
            )
        }
    }

    private func drawParticles(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let count = min(max(particleCount, 4), 48)
        for index in 0..<count {
            let phase = Double(index) * 1.618
            let x = 14 + (sin(time * (0.35 + Double(index % 5) * 0.08) + phase) + 1) / 2 * max(size.width - 28, 1)
            let y = 14 + (cos(time * (0.48 + Double(index % 7) * 0.06) + phase * 0.7) + 1) / 2 * max(size.height - 28, 1)
            let color = [IBColors.electricBlue, IBColors.teal, IBColors.coral, IBColors.gold][index % 4]
            context.fill(
                Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)),
                with: .color(color.opacity(0.82))
            )
        }
    }
}

/// A data-only Canvas scene. ARIA can combine visual primitives and named
/// parameters without the app ever evaluating provider-supplied code.
private struct ARIAGenerativeCanvasView: View {
    let scene: ARIADiagramSpec.CanvasScene
    let canvasHeight: CGFloat
    @State private var isPlaying = true
    @State private var masterSpeed = 1.0
    @State private var pausedElapsed: TimeInterval = 0
    @State private var activeStartedAt = Date()
    @State private var controlValues: [String: Double]
    @State private var toggleValues: [String: Bool]

    init(scene: ARIADiagramSpec.CanvasScene, canvasHeight: CGFloat) {
        self.scene = scene
        self.canvasHeight = canvasHeight
        _controlValues = State(
            initialValue: Dictionary(
                (scene.controls ?? [])
                    .filter { $0.max > $0.min }
                    .map { ($0.id, min(max($0.value, $0.min), $0.max)) },
                uniquingKeysWith: { _, latest in latest }
            )
        )
        _toggleValues = State(
            initialValue: Dictionary(
                (scene.controls ?? [])
                    .filter { $0.kind?.lowercased() == "toggle" }
                    .map { ($0.id, $0.value >= 0.5) },
                uniquingKeysWith: { _, latest in latest }
            )
        )
    }

    private var validControls: [ARIADiagramSpec.CanvasScene.Control] {
        (scene.controls ?? []).filter { $0.max > $0.min && !$0.id.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { timeline in
                Canvas { context, size in
                    let elapsed = pausedElapsed + (isPlaying ? timeline.date.timeIntervalSince(activeStartedAt) : 0)
                    draw(in: &context, size: size, time: elapsed * masterSpeed)
                }
                .frame(height: max(canvasHeight, 210))
                .background(IBColors.canvas.opacity(0.82))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(IBColors.cardBorder.opacity(0.75), lineWidth: 1)
                )
            }

            HStack(spacing: 10) {
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderless)
                .help(isPlaying ? "Pause animation" : "Play animation")

                Text("Speed")
                    .font(.caption2)
                    .foregroundStyle(IBColors.secondaryText)
                Slider(value: $masterSpeed, in: 0.1...3)
                    .frame(maxWidth: 130)
                Text("\(masterSpeed, format: .number.precision(.fractionLength(1)))x")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(IBColors.secondaryText)
            }

            ForEach(validControls, id: \.id) { control in
                if control.kind?.lowercased() == "toggle" {
                    Toggle(
                        control.label,
                        isOn: Binding(
                            get: { toggleValues[control.id] ?? (control.value >= 0.5) },
                            set: { toggleValues[control.id] = $0 }
                        )
                    )
                    .font(.caption2)
                    .toggleStyle(.switch)
                    .padding(.horizontal, 2)
                } else {
                    HStack(spacing: 10) {
                        Text(control.label)
                            .font(.caption2)
                            .foregroundStyle(IBColors.secondaryText)
                            .frame(width: 104, alignment: .leading)
                        Slider(
                            value: Binding(
                                get: { controlValues[control.id] ?? control.value },
                                set: { controlValues[control.id] = $0 }
                            ),
                            in: control.min...control.max
                        )
                        Text(valueLabel(for: control))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(IBColors.secondaryText)
                            .frame(width: 54, alignment: .trailing)
                    }
                }
            }
        }
        .accessibilityLabel("Interactive ARIA Canvas")
    }

    private func valueLabel(for control: ARIADiagramSpec.CanvasScene.Control) -> String {
        let value = controlValues[control.id] ?? control.value
        let suffix = control.unit ?? ""
        return String(format: "%.2f", value) + suffix
    }

    private func togglePlayback() {
        if isPlaying {
            pausedElapsed += Date().timeIntervalSince(activeStartedAt)
            isPlaying = false
        } else {
            activeStartedAt = Date()
            isPlaying = true
        }
    }

    private func controlValue(_ id: String?, fallback: Double) -> Double {
        guard let id else { return fallback }
        return controlValues[id] ?? fallback
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: Double) {
        for element in scene.elements {
            if let visibilityControl = element.visibilityControl,
               !(toggleValues[visibilityControl] ?? true) {
                continue
            }
            let color = element.color.map(Color.init(hex:)) ?? IBColors.electricBlue
            let point = animatedPoint(for: element, size: size, time: time)
            let kind = element.kind.lowercased()
            let minDimension = min(size.width, size.height)
            let radius = CGFloat(controlValue(element.radiusControl, fallback: element.radius ?? 0.035)) * minDimension

            switch kind {
            case "polyline":
                let points = (element.points ?? [])
                    .filter { $0.count >= 2 }
                    .map { pointFor(x: $0[0], y: $0[1], size: size) }
                if let first = points.first {
                    var path = Path()
                    path.move(to: first)
                    for item in points.dropFirst() {
                        path.addLine(to: item)
                    }
                    context.stroke(path, with: .color(color), lineWidth: 2)
                }

            case "line":
                let end = pointFor(x: element.x2 ?? element.x ?? 0.5, y: element.y2 ?? element.y ?? 0.5, size: size)
                var path = Path()
                path.move(to: point)
                path.addLine(to: end)
                context.stroke(path, with: .color(color), lineWidth: 2)

            case "arrow", "vector":
                let end = pointFor(x: element.x2 ?? element.x ?? 0.5, y: element.y2 ?? element.y ?? 0.5, size: size)
                drawArrow(from: point, to: end, color: color, context: &context)

            case "rect", "rectangle":
                let width = CGFloat(element.width ?? 0.16) * size.width
                let height = CGFloat(element.height ?? 0.1) * size.height
                let rect = CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(color.opacity(0.2)))
                context.stroke(Path(roundedRect: rect, cornerRadius: 6), with: .color(color), lineWidth: 1.4)

            case "text", "label":
                context.draw(
                    Text(element.label ?? "").font(.caption.weight(.semibold)).foregroundColor(color),
                    at: point,
                    anchor: .center
                )

            default:
                let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.88)))
                if let label = element.label {
                    context.draw(
                        Text(label).font(.caption2.weight(.medium)).foregroundColor(IBColors.ink),
                        at: CGPoint(x: point.x, y: point.y + radius + 12),
                        anchor: .center
                    )
                }
            }
        }
    }

    private func animatedPoint(
        for element: ARIADiagramSpec.CanvasScene.Element,
        size: CGSize,
        time: Double
    ) -> CGPoint {
        let base = pointFor(x: element.x ?? 0.5, y: element.y ?? 0.5, size: size)
        let speed = controlValue(element.speedControl, fallback: element.speed ?? 1)
        let amplitude = CGFloat(controlValue(element.amplitudeControl, fallback: element.amplitude ?? 0.08)) * min(size.width, size.height)
        let phase = time * speed + (element.phase ?? 0)

        switch element.animation?.lowercased() {
        case "orbit", "circle":
            return CGPoint(x: base.x + cos(phase) * amplitude, y: base.y + sin(phase) * amplitude)
        case "sine", "wave":
            return CGPoint(x: base.x, y: base.y + sin(phase) * amplitude)
        case "linear", "drift":
            let progress = (sin(phase) + 1) / 2
            return CGPoint(x: base.x + (progress - 0.5) * amplitude * 2, y: base.y)
        case "bounce", "vibrate":
            return CGPoint(x: base.x + cos(phase * 1.37) * amplitude, y: base.y + sin(phase * 1.91) * amplitude)
        default:
            return base
        }
    }

    private func pointFor(x: Double, y: Double, size: CGSize) -> CGPoint {
        CGPoint(x: CGFloat(x) * size.width, y: CGFloat(y) * size.height)
    }

    private func drawArrow(from start: CGPoint, to end: CGPoint, color: Color, context: inout GraphicsContext) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(path, with: .color(color), lineWidth: 2)

        let angle = atan2(end.y - start.y, end.x - start.x)
        let head = CGPoint(x: end.x - cos(angle) * 11, y: end.y - sin(angle) * 11)
        var headPath = Path()
        headPath.move(to: head)
        headPath.addLine(to: CGPoint(x: head.x - cos(angle - .pi / 5) * 7, y: head.y - sin(angle - .pi / 5) * 7))
        headPath.move(to: head)
        headPath.addLine(to: CGPoint(x: head.x - cos(angle + .pi / 5) * 7, y: head.y - sin(angle + .pi / 5) * 7))
        context.stroke(headPath, with: .color(color), lineWidth: 2)
    }
}

private struct FlashcardMessageView: View {
    let front: String
    let back: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            flashcardSide(
                label: "Front",
                icon: "questionmark.circle.fill",
                tint: IBColors.electricBlue,
                text: front
            )

            flashcardSide(
                label: "Back",
                icon: "checkmark.seal.fill",
                tint: IBColors.success,
                text: back
            )
        }
    }

    private func flashcardSide(label: String, icon: String, tint: Color, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .textCase(.uppercase)
                Spacer()
            }

            Text(FormattedMessageFormatter.attributedMarkdown(from: text) ?? AttributedString(text))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(tint.opacity(0.08))
                )
        }
    }
}

// MARK: - Code Block View
private struct CodeBlockView: View {
    let code: String
    let language: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if !language.isEmpty {
                    Text(language)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .textCase(.lowercase)
                }
                Spacer()
                Button {
                    copied = ARIAClipboard.copy(code)
                    guard copied else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                        Text(copied ? "Copied" : "Copy")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.06))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(verbatim: code)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

enum FormattedMessageFormatter {
    static func sections(from source: String) -> [FormattedMessageSection] {
        let normalized = normalizeResponseText(source)
        var sections: [FormattedMessageSection] = []
        var markdownLines: [String] = []
        var frontLines: [String] = []
        var backLines: [String] = []
        var codeBlockLines: [String] = []
        var codeBlockLanguage = ""

        enum ParseMode {
            case markdown
            case flashcardFront
            case flashcardBack
            case codeBlock
        }

        var mode: ParseMode = .markdown

        func appendMarkdownBuffer() {
            let markdown = markdownLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !markdown.isEmpty else {
                markdownLines.removeAll()
                return
            }
            appendStructuredMarkdownSections(from: markdown, into: &sections)
            markdownLines.removeAll()
        }

        func appendFlashcardBuffer() {
            let front = frontLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let back = backLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !front.isEmpty && !back.isEmpty {
                sections.append(.flashcard(front: front, back: back))
            } else {
                let fallback = ([front, back].filter { !$0.isEmpty }).joined(separator: "\n")
                if !fallback.isEmpty {
                    appendMathAwareSections(from: fallback, into: &sections)
                }
            }

            frontLines.removeAll()
            backLines.removeAll()
        }

        func appendCodeBlockBuffer() {
            let code = codeBlockLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !code.isEmpty {
                if let diagram = diagramSpec(from: code, language: codeBlockLanguage) {
                    sections.append(.diagram(diagram))
                } else {
                    sections.append(.codeBlock(code: code, language: codeBlockLanguage))
                }
            }
            codeBlockLines.removeAll()
            codeBlockLanguage = ""
        }

        let lines = normalized.components(separatedBy: .newlines)
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Check for code block start
            if trimmed.hasPrefix("```") {
                if mode == .codeBlock {
                    // End code block
                    appendCodeBlockBuffer()
                    mode = .markdown
                } else {
                    // Start code block
                    appendMarkdownBuffer()
                    codeBlockLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                    codeBlockLines.removeAll()
                    mode = .codeBlock
                }
                i += 1
                continue
            }

            switch mode {
            case .codeBlock:
                codeBlockLines.append(line)

            case .markdown:
                if let frontPayload = flashcardPayload(in: trimmed, marker: "FRONT") {
                    appendMarkdownBuffer()
                    frontLines = [frontPayload]
                    mode = .flashcardFront
                } else {
                    markdownLines.append(line)
                }

            case .flashcardFront:
                if let backPayload = flashcardPayload(in: trimmed, marker: "BACK") {
                    backLines = [backPayload]
                    mode = .flashcardBack
                } else if let frontPayload = flashcardPayload(in: trimmed, marker: "FRONT") {
                    appendFlashcardBuffer()
                    frontLines = [frontPayload]
                    mode = .flashcardFront
                } else if isMarkdownHeader(trimmed) {
                    appendFlashcardBuffer()
                    markdownLines.append(line)
                    mode = .markdown
                } else if !trimmed.isEmpty {
                    frontLines.append(trimmed)
                }

            case .flashcardBack:
                if let frontPayload = flashcardPayload(in: trimmed, marker: "FRONT") {
                    appendFlashcardBuffer()
                    frontLines = [frontPayload]
                    mode = .flashcardFront
                } else if isMarkdownHeader(trimmed) {
                    appendFlashcardBuffer()
                    markdownLines.append(line)
                    mode = .markdown
                } else if !trimmed.isEmpty {
                    backLines.append(trimmed)
                }
            }
            
            i += 1
        }

        switch mode {
        case .markdown:
            appendMarkdownBuffer()
        case .flashcardFront, .flashcardBack:
            appendFlashcardBuffer()
        case .codeBlock:
            appendCodeBlockBuffer()
        }

        if !sections.contains(where: {
            if case .diagram = $0 { return true }
            return false
        }), let inferredSimulation = fallbackSimulation(for: normalized) {
            sections.append(.diagram(inferredSimulation))
        }

        return sections.isEmpty ? [.markdown(normalized)] : sections
    }

    private static func diagramSpec(from code: String, language: String) -> ARIADiagramSpec? {
        ARIAContentContract.decodeDiagram(from: code, language: language)
    }

    /// Old model responses may refuse a Canvas request instead of producing the
    /// protocol block. Preserve the explanation but still mount a usable native
    /// simulation for those already-saved messages.
    private static func fallbackSimulation(for source: String) -> ARIADiagramSpec? {
        let normalized = source.lowercased()
        let refusalTerms = [
            "cannot embed",
            "can't embed",
            "cannot render",
            "can't render",
            "compatible viewer",
            "canvas-ready"
        ]
        guard refusalTerms.contains(where: normalized.contains) else { return nil }

        if normalized.contains("atom") || normalized.contains("electron") {
            return ARIADiagramSpec(
                type: "simulation",
                title: "Atom simulation",
                xLabel: nil,
                yLabel: nil,
                series: nil,
                nodes: nil,
                edges: nil,
                simulation: "atoms",
                particleCount: 12
            )
        }
        guard normalized.contains("particle") || normalized.contains("velocity") || normalized.contains("motion") else {
            return nil
        }
        return ARIADiagramSpec(
            type: "simulation",
            title: "Particle simulation",
            xLabel: nil,
            yLabel: nil,
            series: nil,
            nodes: nil,
            edges: nil,
            simulation: "particles",
            particleCount: 20
        )
    }

    static func extractFlashcards(from source: String) -> [(front: String, back: String)] {
        let normalized = normalizeResponseText(source)
        let lines = normalized.components(separatedBy: .newlines)
        var cards: [(front: String, back: String)] = []
        var frontLines: [String] = []
        var backLines: [String] = []
        var mode: FlashcardParseMode = .idle

        func flush() {
            let front = frontLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let back = backLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !front.isEmpty && !back.isEmpty {
                cards.append((front: front, back: back))
            }
            frontLines.removeAll()
            backLines.removeAll()
            mode = .idle
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if let frontPayload = flashcardPayload(in: trimmed, marker: "FRONT") {
                flush()
                frontLines = [frontPayload]
                mode = .front
                continue
            }

            if let backPayload = flashcardPayload(in: trimmed, marker: "BACK") {
                if mode == .idle {
                    continue
                }
                backLines = [backPayload]
                mode = .back
                continue
            }

            switch mode {
            case .front:
                if trimmed.isEmpty {
                    continue
                }
                if isMarkdownHeader(trimmed) {
                    flush()
                } else {
                    frontLines.append(trimmed)
                }
            case .back:
                if trimmed.isEmpty {
                    continue
                }
                if isMarkdownHeader(trimmed) {
                    flush()
                } else {
                    backLines.append(trimmed)
                }
            case .idle:
                continue
            }
        }

        flush()
        return cards
    }

    static func attributedMarkdown(from source: String) -> AttributedString? {
        let processed = displayFriendlyMarkdown(
            normalizeResponseText(convertInlineMathToReadableText(in: source))
        )
        let options = AttributedString.MarkdownParsingOptions()
        return try? AttributedString(markdown: processed, options: options)
    }

    private static func normalizeResponseText(_ source: String) -> String {
        var result = source.replacingOccurrences(of: "\r\n", with: "\n")
        result = normalizeMathDelimiters(in: result)
        result = replaceRegex(pattern: #"[-—]{3,}\s*(FRONT:|BACK:)"#, template: "\n\n$1", in: result)
        result = replaceRegex(pattern: #"(?<=[.!?])(?=[A-Z])"#, template: " ", in: result)
        result = replaceRegex(pattern: #"(?m)^(#{1,6})([^ #\n])"#, template: "$1 $2", in: result)
        result = replaceRegex(pattern: #"(?m)(?<!\n)(#{1,6}\s)"#, template: "\n\n$1", in: result)
        result = replaceRegex(pattern: #"(?m)^\s*#{1,6}\s*$"#, template: "", in: result)
        result = replaceRegex(pattern: #"(?m)^\s*(?:[-*•]|\d+[.)])\s*$"#, template: "", in: result)
        result = replaceRegex(pattern: #"(?<=[^\n])\s+((?:[*•]|\d+[.)])\s)"#, template: "\n$1", in: result)
        result = replaceRegex(pattern: #"(?<=[^\n])\s*(FRONT:)"#, template: "\n\n$1", in: result)
        result = replaceRegex(pattern: #"(?<=[^\n])\s*(BACK:)"#, template: "\n$1", in: result)
        result = replaceRegex(pattern: #"(?m)^(#{1,6}\s+.+)\n(#{1,6}\s+.+)$"#, template: "$1\n\n$2", in: result)
        result = replaceRegex(pattern: #"(?m)(^\s*[*-]\s+\*\*[^*\n]+\*\*:)"#, template: "\n$1", in: result)
        result = replaceRegex(
            pattern: #"(?i)why it(?:'|\u2019)s critical for [^:]+:\s*"#,
            template: "\n\n### Why It Matters\n",
            in: result
        )
        result = replaceRegex(
            pattern: #"(?i)how did you go\?\s*"#,
            template: "\n\n### Check-in\nHow did you go?\n",
            in: result
        )
        // Preserve code blocks - don't collapse newlines inside them
        result = collapseNewlinesPreservingCodeBlocks(in: result)
        result = replaceRegex(pattern: #"\n{3,}"#, template: "\n\n", in: result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func displayFriendlyMarkdown(_ source: String) -> String {
        MessageRenderingPolicy.displaySafeMarkdown(source)
    }

    private static func appendStructuredMarkdownSections(
        from markdown: String,
        into sections: inout [FormattedMessageSection]
    ) {
        var paragraphLines: [String] = []

        func flushParagraph() {
            let paragraph = paragraphLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !paragraph.isEmpty {
                appendMathAwareSections(from: paragraph, into: &sections)
            }
            paragraphLines.removeAll()
        }

        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let item = listItem(from: trimmed) {
                flushParagraph()
                sections.append(.listItem(marker: item.marker, text: item.text))
            } else {
                paragraphLines.append(line)
            }
        }

        flushParagraph()
    }

    private static func listItem(from line: String) -> (marker: String, text: String)? {
        for prefix in ["- ", "* ", "• "] where line.hasPrefix(prefix) {
            let text = String(line.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : ("•", text)
        }

        let components = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard components.count == 2 else { return nil }
        let marker = String(components[0])
        let number = marker.dropLast()
        guard (marker.hasSuffix(".") || marker.hasSuffix(")")),
              Int(number) != nil else {
            return nil
        }
        let text = String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : (marker, text)
    }

    private static func collapseNewlinesPreservingCodeBlocks(in source: String) -> String {
        var result = ""
        var inCodeBlock = false
        var consecutiveNewlines = 0
        
        for char in source {
            if char == "`" {
                // Check for triple backtick
                let lastThree = result.suffix(2)
                if lastThree == "``" {
                    inCodeBlock.toggle()
                    result.append(char)
                    consecutiveNewlines = 0
                    continue
                }
            }
            
            if char == "\n" {
                if inCodeBlock {
                    result.append(char)
                    consecutiveNewlines = 0
                } else {
                    consecutiveNewlines += 1
                    if consecutiveNewlines <= 2 {
                        result.append(char)
                    }
                    // Skip additional newlines (3+)
                }
            } else {
                consecutiveNewlines = 0
                result.append(char)
            }
        }
        
        return result
    }

    private static func normalizeMathDelimiters(in source: String) -> String {
        source
            .replacingOccurrences(of: "\\[", with: "$$")
            .replacingOccurrences(of: "\\]", with: "$$")
            .replacingOccurrences(of: "\\(", with: "$")
            .replacingOccurrences(of: "\\)", with: "$")
    }

    private static func appendMathAwareSections(from source: String, into sections: inout [FormattedMessageSection]) {
        let paragraphs = source.components(separatedBy: "\n\n")
        
        for paragraph in paragraphs {
            let trimmedParagraph = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedParagraph.isEmpty else { continue }
            
            // Check for fenced code blocks first
            if trimmedParagraph.hasPrefix("```") {
                if let codeBlock = parseCodeBlock(from: trimmedParagraph) {
                    sections.append(.codeBlock(code: codeBlock.code, language: codeBlock.language))
                    continue
                }
            }
            
            if trimmedParagraph.contains("$") {
                var buffer = ""
                var index = trimmedParagraph.startIndex
                
                while index < trimmedParagraph.endIndex {
                    let remaining = trimmedParagraph[index...]
                    let delimiter: String?
                    if remaining.hasPrefix("$$"), !isEscapedDelimiter(at: index, in: trimmedParagraph) {
                        delimiter = "$$"
                    } else if remaining.hasPrefix("$"), !isEscapedDelimiter(at: index, in: trimmedParagraph) {
                        delimiter = "$"
                    } else {
                        delimiter = nil
                    }

                    if let delimiter {
                        let contentStart = trimmedParagraph.index(index, offsetBy: delimiter.count)

                        if let closingRange = nextMathDelimiter(
                            delimiter,
                            in: trimmedParagraph,
                            from: contentStart
                        ) {
                            let mathContent = String(trimmedParagraph[contentStart..<closingRange.lowerBound])
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            
                            if delimiter == "$" {
                                if !mathContent.isEmpty {
                                    buffer += MathRenderingPolicy.inlineText(mathContent)
                                }
                            } else {
                                let markdown = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !markdown.isEmpty {
                                    sections.append(.markdown(markdown))
                                }
                                buffer = ""

                                if !mathContent.isEmpty {
                                    sections.append(.mathBlock(mathContent))
                                }
                            }
                            
                            index = closingRange.upperBound
                            continue
                        }
                    }
                    
                    buffer.append(trimmedParagraph[index])
                    index = trimmedParagraph.index(after: index)
                }
                
                let markdown = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !markdown.isEmpty {
                    sections.append(.markdown(markdown))
                }
            } else {
                sections.append(.markdown(trimmedParagraph))
            }
        }
    }

    private static func nextMathDelimiter(
        _ delimiter: String,
        in source: String,
        from start: String.Index
    ) -> Range<String.Index>? {
        var index = start
        while index < source.endIndex {
            let remaining = source[index...]
            let isSingleDollarInsideDisplayMath = delimiter == "$" && remaining.hasPrefix("$$")
            if remaining.hasPrefix(delimiter),
               !isSingleDollarInsideDisplayMath,
               !isEscapedDelimiter(at: index, in: source) {
                let upperBound = source.index(index, offsetBy: delimiter.count)
                return index..<upperBound
            }
            index = source.index(after: index)
        }
        return nil
    }

    private static func isEscapedDelimiter(at index: String.Index, in source: String) -> Bool {
        guard index > source.startIndex else { return false }
        var cursor = source.index(before: index)
        var slashCount = 0
        while source[cursor] == "\\" {
            slashCount += 1
            guard cursor > source.startIndex else { break }
            cursor = source.index(before: cursor)
        }
        return slashCount.isMultiple(of: 2) == false
    }

    private static func parseCodeBlock(from source: String) -> (code: String, language: String)? {
        let lines = source.components(separatedBy: "\n")
        guard let firstLine = lines.first, firstLine.hasPrefix("```") else { return nil }
        
        let language = String(firstLine.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Find closing ```
        var codeLines: [String] = []
        var foundClosing = false
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
                foundClosing = true
                break
            }
            codeLines.append(line)
        }
        
        guard foundClosing || codeLines.count > 0 else { return nil }
        let code = codeLines.joined(separator: "\n")
        guard !code.isEmpty else { return nil }
        
        return (code: code, language: language)
    }

    private static func convertInlineMathToReadableText(in source: String) -> String {
        var result = ""
        var index = source.startIndex

        while index < source.endIndex {
            if source[index] == "$" {
                let next = source.index(after: index)

                if next < source.endIndex,
                   source[next] != "$",
                   let closing = source[next...].firstIndex(of: "$") {
                   let candidate = String(source[next..<closing])
                   let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

                    if !trimmed.isEmpty && !candidate.contains("\n") {
                        result += MathExpressionFormatter.inlineString(from: candidate)
                        index = source.index(after: closing)
                        continue
                    }
                }
            }

            result.append(source[index])
            index = source.index(after: index)
        }

        return result
    }

    private static func replaceRegex(pattern: String, template: String, in source: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
        let range = NSRange(source.startIndex..., in: source)
        return regex.stringByReplacingMatches(in: source, range: range, withTemplate: template)
    }

    private enum FlashcardParseMode {
        case idle
        case front
        case back
    }

    private static func flashcardPayload(in line: String, marker: String) -> String? {
        let stripped = stripFlashcardLinePrefix(from: line)
        let uppercased = stripped.uppercased()
        let markerPrefix = "\(marker.uppercased()):"
        guard uppercased.hasPrefix(markerPrefix) else { return nil }
        return String(stripped.dropFirst(markerPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripFlashcardLinePrefix(from line: String) -> String {
        var stripped = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"^[\-\*\•]\s*"#,
            #"^\d+[\.\)]\s*"#,
            #"(?i)^card\s*\d+\s*[:\-\.\)]\s*"#
        ]

        for pattern in patterns {
            stripped = replaceRegex(pattern: pattern, template: "", in: stripped)
        }

        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isMarkdownHeader(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("#") || (trimmed.hasPrefix("**") && trimmed.hasSuffix("**"))
    }
}

nonisolated enum MathExpressionFormatter {
    private static let commandMap: [String: String] = [
        "\\alpha": "α", "\\beta": "β", "\\gamma": "γ", "\\delta": "δ", "\\epsilon": "ϵ",
        "\\theta": "θ", "\\lambda": "λ", "\\mu": "μ", "\\pi": "π", "\\sigma": "σ",
        "\\phi": "φ", "\\omega": "ω", "\\Delta": "Δ", "\\Gamma": "Γ", "\\Lambda": "Λ",
        "\\Pi": "Π", "\\Sigma": "Σ", "\\Omega": "Ω", "\\times": "×", "\\cdot": "·",
        "\\pm": "±", "\\neq": "≠", "\\leq": "≤", "\\geq": "≥", "\\approx": "≈",
        "\\infty": "∞", "\\to": "→", "\\rightarrow": "→", "\\left": "", "\\right": "",
        "\\sum": "Σ", "\\prod": "∏", "\\int": "∫", "\\cdots": "⋯", "\\ldots": "…",
        "\\sin": "sin", "\\cos": "cos", "\\tan": "tan", "\\sec": "sec", "\\csc": "csc",
        "\\cot": "cot", "\\log": "log", "\\ln": "ln",
        "\\lim": "lim"
    ]

    private static let superscripts: [Character: String] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾", "n": "ⁿ", "i": "ⁱ"
    ]

    private static let subscripts: [Character: String] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎", "a": "ₐ", "e": "ₑ", "i": "ᵢ", "j": "ⱼ",
        "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ", "o": "ₒ", "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ",
        "u": "ᵤ", "v": "ᵥ", "x": "ₓ"
    ]

    static func inlineString(from source: String) -> String {
        prettified(source)
    }

    static func displayString(from source: String) -> String {
        prettified(source)
    }

    fileprivate static func blockContent(from source: String) -> NativeMathBlockContent {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)

        if let environment = parseEnvironment(in: trimmed) {
            switch environment.name {
            case "align", "align*", "aligned", "aligned*":
                let rows = parseAlignedRows(from: environment.body)
                if !rows.isEmpty {
                    return .aligned(rows)
                }
            case "cases":
                let rows = parseCaseRows(from: environment.body)
                if !rows.isEmpty {
                    return .cases(rows)
                }
            case "matrix", "pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix":
                let rows = parseMatrixRows(from: environment.body)
                if !rows.isEmpty {
                    let delimiters = delimiters(for: environment.name)
                    return .matrix(rows: rows, leftDelimiter: delimiters.0, rightDelimiter: delimiters.1)
                }
            default:
                break
            }
        }

        let lines = splitRows(in: trimmed)
            .map { prettified(stripAlignmentMarkers(from: $0)) }
            .filter { !$0.isEmpty }

        if lines.count > 1 {
            return .aligned(lines.map { NativeAlignedMathRow(leading: $0, trailing: nil) })
        }

        return .text(prettified(trimmed))
    }

    private static func prettified(_ source: String) -> String {
        var result = source.trimmingCharacters(in: .whitespacesAndNewlines)

        result = replaceBinaryCommand("\\frac", in: result) { lhs, rhs in
            formatFraction(lhs: lhs, rhs: rhs)
        }
        result = replaceBinaryCommand("\\dfrac", in: result) { lhs, rhs in
            formatFraction(lhs: lhs, rhs: rhs)
        }
        result = replaceBinaryCommand("\\tfrac", in: result) { lhs, rhs in
            formatFraction(lhs: lhs, rhs: rhs)
        }
        result = replaceUnaryCommand("\\sqrt", in: result) { value in
            "√(\(value))"
        }
        result = replaceUnaryCommand("\\text", in: result) { $0 }
        result = replaceUnaryCommand("\\mathrm", in: result) { $0 }
        result = replaceUnaryCommand("\\operatorname", in: result) { $0 }

        for (command, symbol) in commandMap {
            result = result.replacingOccurrences(of: command, with: symbol)
        }

        result = result
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .replacingOccurrences(of: "\\", with: "")

        result = applyScript(marker: "^", mapping: superscripts, to: result)
        result = applyScript(marker: "_", mapping: subscripts, to: result)

        return result
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replaceUnaryCommand(_ command: String, in source: String, transform: (String) -> String) -> String {
        replaceRegex(pattern: "\\\\\(command.dropFirst())\\{([^{}]+)\\}", in: source) { match in
            let rawValue = match.numberOfRanges > 1 ? nsRange(match.range(at: 1), in: source).flatMap { Range($0, in: source) }.map { String(source[$0]) } : nil
            return transform(prettified(rawValue ?? ""))
        }
    }

    private static func replaceBinaryCommand(_ command: String, in source: String, transform: (String, String) -> String) -> String {
        replaceRegex(pattern: "\\\\\(command.dropFirst())\\{([^{}]+)\\}\\{([^{}]+)\\}", in: source) { match in
            let lhs = match.numberOfRanges > 1 ? nsRange(match.range(at: 1), in: source).flatMap { Range($0, in: source) }.map { String(source[$0]) } ?? "" : ""
            let rhs = match.numberOfRanges > 2 ? nsRange(match.range(at: 2), in: source).flatMap { Range($0, in: source) }.map { String(source[$0]) } ?? "" : ""
            return transform(prettified(lhs), prettified(rhs))
        }
    }

    private static func replaceRegex(pattern: String, in source: String, replacement: (NSTextCheckingResult) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
        let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
        guard !matches.isEmpty else { return source }

        var result = source
        for match in matches.reversed() {
            let replacementText = replacement(match)
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: replacementText)
            }
        }
        return result == source ? source : replaceRegex(pattern: pattern, in: result, replacement: replacement)
    }

    private static func applyScript(marker: Character, mapping: [Character: String], to source: String) -> String {
        var result = ""
        var index = source.startIndex

        while index < source.endIndex {
            if source[index] == marker {
                let next = source.index(after: index)
                guard next < source.endIndex else {
                    index = next
                    continue
                }

                if source[next] == "{" {
                    if let closing = source[next...].firstIndex(of: "}") {
                        let content = source[source.index(after: next)..<closing]
                        let rendered = content.compactMap { mapping[$0] ?? String($0) }.joined()
                        result += rendered
                        index = source.index(after: closing)
                        continue
                    }
                } else {
                    let rendered = mapping[source[next]] ?? String(source[next])
                    result += rendered
                    index = source.index(after: next)
                    continue
                }
            }

            result.append(source[index])
            index = source.index(after: index)
        }

        return result
    }

    private static func nsRange(_ range: NSRange, in source: String) -> NSRange? {
        range.location == NSNotFound ? nil : range
    }

    private static func formatFraction(lhs: String, rhs: String) -> String {
        let numerator = needsGrouping(lhs) ? "(\(lhs))" : lhs
        let denominator = needsGrouping(rhs) ? "(\(rhs))" : rhs
        return "\(numerator)/\(denominator)"
    }

    private static func needsGrouping(_ expression: String) -> Bool {
        expression.contains(where: { "+-= ".contains($0) })
    }

    private static func parseEnvironment(in source: String) -> (name: String, body: String)? {
        let pattern = #"(?s)\\begin\{([A-Za-z\*]+)\}(.*?)\\end\{([A-Za-z\*]+)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(source.startIndex..., in: source)
        guard let match = regex.firstMatch(in: source, range: range),
              match.numberOfRanges >= 4,
              let nameRange = Range(match.range(at: 1), in: source),
              let bodyRange = Range(match.range(at: 2), in: source),
              let endNameRange = Range(match.range(at: 3), in: source) else {
            return nil
        }

        let name = String(source[nameRange])
        let endName = String(source[endNameRange])
        guard name == endName else { return nil }
        return (name, String(source[bodyRange]))
    }

    private static func parseAlignedRows(from source: String) -> [NativeAlignedMathRow] {
        splitRows(in: source).compactMap { row in
            let columns = row
                .components(separatedBy: "&")
                .map { prettified($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .filter { !$0.isEmpty }

            guard let first = columns.first else { return nil }
            let trailing = columns.dropFirst().joined(separator: " ")
            return NativeAlignedMathRow(
                leading: first,
                trailing: trailing.isEmpty ? nil : trailing
            )
        }
    }

    private static func parseCaseRows(from source: String) -> [NativeCaseMathRow] {
        splitRows(in: source).compactMap { row in
            let columns = row
                .components(separatedBy: "&")
                .map { prettified($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .filter { !$0.isEmpty }

            guard let first = columns.first else { return nil }
            let explanation = columns.dropFirst().joined(separator: " ")
            return NativeCaseMathRow(
                condition: first,
                explanation: explanation.isEmpty ? nil : explanation
            )
        }
    }

    private static func parseMatrixRows(from source: String) -> [[String]] {
        splitRows(in: source)
            .map { row in
                row
                    .components(separatedBy: "&")
                    .map { prettified($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    .filter { !$0.isEmpty }
            }
            .filter { !$0.isEmpty }
    }

    private static func splitRows(in source: String) -> [String] {
        source
            .components(separatedBy: "\\\\")
            .map { stripAlignmentMarkers(from: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func stripAlignmentMarkers(from source: String) -> String {
        source.replacingOccurrences(of: "&", with: " ")
    }

    private static func delimiters(for environment: String) -> (String, String) {
        switch environment {
        case "pmatrix":
            return ("(", ")")
        case "bmatrix":
            return ("[", "]")
        case "Bmatrix":
            return ("{", "}")
        case "vmatrix":
            return ("|", "|")
        case "Vmatrix":
            return ("‖", "‖")
        default:
            return ("", "")
        }
    }
}
