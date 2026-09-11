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
                                withAnimation(IBAnimation.smooth) {
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
                            Image(systemName: "square.and.pencil")
                        }
                        .disabled(ariaService.isLoading)
                        .keyboardShortcut("n", modifiers: .command)
                        .help("New chat")
                    }

                    ToolbarItem(placement: .primaryAction) {
                        Button { showMemory = true } label: {
                            Image(systemName: "brain")
                        }
                        .help("ARIA memory")
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
                    RoundedRectangle(cornerRadius: 7)
                        .fill(IBColors.electricBlue)
                        .frame(width: 34, height: 34)
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
                RoundedRectangle(cornerRadius: 8)
                    .fill(IBColors.electricBlue)
                    .frame(width: 50, height: 50)
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .semibold))
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

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask ARIA…", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
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
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(IBColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(IBColors.cardBorder, lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(IBColors.canvas)
    }

    private var configurationRail: some View {
        HStack(spacing: 8) {
            Menu {
                Section("Provider") {
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
                }

                Section("Model") {
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
                        Text("Custom: \(selectedModel)")
                    }
                }

                if selectedProvider == .gemini {
                    Section("Response style") {
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
                    }
                } else {
                    Section("Reasoning") {
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
                    }

                    Section("Answer detail") {
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
                    }
                }

                if selectedProvider == .codexCLI {
                    Section("Web search") {
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
                    }
                }
            } label: {
                Label(
                    "\(selectedProvider.shortName) · \(AIConfiguration.modelDisplayName(selectedModel, for: selectedProvider))",
                    systemImage: "slider.horizontal.3"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(IBColors.secondaryText)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Response settings")

            Spacer()

            if ariaService.isLoading {
                Text(ariaService.currentStatus)
                    .font(.caption)
                    .foregroundStyle(IBColors.secondaryText)
                    .lineLimit(1)
            }
        }
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
            withAnimation(IBAnimation.smooth) {
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
    @State private var lastStreamingScrollTime: ContinuousClock.Instant?
    @State private var dismissedRecoveredFailureID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    withAnimation(IBAnimation.gentle) {
                        proxy.scrollTo(newValue, anchor: .bottom)
                    }
                }
            }
            .onChange(of: streamingText) { oldValue, newValue in
                if newValue.isEmpty {
                    lastStreamingScrollTime = nil
                    return
                }
                guard isLoading else { return }
                // Time-based throttle ~16ms, reset per session via id change
                let now = ContinuousClock.now
                if let last = lastStreamingScrollTime, now - last < .milliseconds(16), !oldValue.isEmpty {
                    return
                }
                lastStreamingScrollTime = now
                Task { @MainActor in
                    await Task.yield()
                    if reduceMotion {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    } else {
                        withAnimation(IBAnimation.snappy) {
                            proxy.scrollTo("streaming", anchor: .bottom)
                        }
                    }
                }
            }
            .onChange(of: isLoading) { _, loading in
                if !loading { lastStreamingScrollTime = nil }
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
                        .lineLimit(2)
                        .help(session.title)
                    Spacer(minLength: 4)
                    Text(session.updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(IBColors.tertiaryText)
                        .lineLimit(1)
                }

                Text(session.lastMessagePreview.isEmpty ? "No messages yet" : session.lastMessagePreview)
                    .font(.caption)
                    .foregroundStyle(IBColors.secondaryText)
                    .lineLimit(2)
                    .help(session.lastMessagePreview)
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
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(IBColors.electricBlue)
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
                            .padding(.horizontal, 4)
                            .padding(.vertical, 6)
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
                .fill(IBColors.electricBlue)
                .frame(width: 30, height: 30)
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


struct FormattedMessageContent: View {
    let text: String
    var preferRichRendering = false
    @State private var sections: [FormattedMessageSection] = []
    @State private var parseTask: Task<Void, Never>?

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
        .task(id: text) {
            await debouncedParse(text)
        }
        .onDisappear {
            parseTask?.cancel()
        }
    }

    private func debouncedParse(_ newText: String) async {
        parseTask?.cancel()
        // Debounce 80ms, then parse off main thread
        let task = Task.detached(priority: .userInitiated) {
            try? await Task.sleep(nanoseconds: 80_000_000)
            if Task.isCancelled { return [FormattedMessageSection]() }
            return FormattedMessageFormatter.sections(from: newText)
        }
        parseTask = Task {
            let result = await task.value
            if Task.isCancelled { return }
            await MainActor.run {
                // Only update if text still matches (avoid stale)
                sections = result
            }
        }
        await parseTask?.value
    }

    @ViewBuilder
    private func sectionView(_ section: FormattedMessageSection) -> some View {
        switch section {
        case .heading(let level, let heading):
            Text(FormattedMessageFormatter.attributedMarkdown(from: heading) ?? AttributedString(heading))
                .font(level == 1 ? .title3.weight(.semibold) : .headline.weight(.semibold))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

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

        case .quote(let quote):
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(IBColors.cardBorder)
                    .frame(width: 2)
                Text(FormattedMessageFormatter.attributedMarkdown(from: quote) ?? AttributedString(quote))
                    .foregroundStyle(IBColors.secondaryText)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .divider:
            Divider()

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

// MARK: - Streaming rich row (uses same formatter, not plain Text)
struct StreamingMessageRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(IBColors.electricBlue)
                    .frame(width: 30, height: 30)
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("ARIA")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IBColors.electricBlue)
                    .padding(.horizontal, 4)
                // Rich rendering during streaming, debounced off main thread
                FormattedMessageContent(text: text, preferRichRendering: true)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
            }
            .frame(maxWidth: 760, alignment: .leading)
            Spacer()
        }
    }
}

private struct MathJaxBlockView: View {
    let latex: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var contentHeight: CGFloat = 44
    @State private var usesFallback = true
    @State private var isMathJaxReady = false

    var body: some View {
        Group {
            if usesFallback {
                NativeMathBlockView(latex: latex)
                    .overlay(alignment: .topTrailing) {
                        if isMathJaxReady {
                            ProgressView().controlSize(.mini).opacity(0.6)
                        }
                    }
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
        .task(id: latex) {
            // Show native first, then upgrade to MathJax after brief delay to avoid flash
            usesFallback = true
            try? await Task.sleep(nanoseconds: 50_000_000)
            if Task.isCancelled { return }
            // Trigger MathJax load by toggling fallback off; view will report height when ready
            usesFallback = false
        }
        .onChange(of: latex) { _, _ in
            usesFallback = true
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
        let configuration = MathJaxPool.shared.configuration(for: context.coordinator)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        if #available(macOS 13, *) {
            webView.isInspectable = false
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastLatex != latex || context.coordinator.lastColorScheme != colorScheme else { return }
        context.coordinator.lastLatex = latex
        context.coordinator.lastColorScheme = colorScheme
        context.coordinator.didFail.wrappedValue = false
        let html = MathRenderingPolicy.htmlDocument(latex: latex, colorScheme: colorScheme)
        // Use shared baseURL for tex-svg.js
        let baseURL = Bundle.main.url(forResource: "tex-svg", withExtension: "js")?.deletingLastPathComponent()
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        // Do not remove global handlers; pool is shared.
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
                didFail.wrappedValue = false
            } else if message.name == "mathError" {
                didFail.wrappedValue = true
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            didFail.wrappedValue = true
        }
    }
}

// Shared pool for MathJax
private final class MathJaxPool: Sendable {
    static let shared = MathJaxPool()
    private let config: WKWebViewConfiguration

    private init() {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false
        // Transparent
        let controller = WKUserContentController()
        // Handlers will be added per webview coordinator via copy? We use shared controller but need per-coordinator.
        // Instead we create config with empty controller and each coordinator adds handlers to its webView's controller.
        configuration.userContentController = controller
        if #available(macOS 14, *) {
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        }
        // Transparent background
        self.config = configuration
    }

    func configuration(for coordinator: OfflineMathJaxView.Coordinator) -> WKWebViewConfiguration {
        // Return a copy with coordinator-registered handlers
        let cfg = WKWebViewConfiguration()
        cfg.preferences = config.preferences
        cfg.suppressesIncrementalRendering = config.suppressesIncrementalRendering
        let controller = WKUserContentController()
        controller.add(coordinator, name: "mathHeight")
        controller.add(coordinator, name: "mathError")
        cfg.userContentController = controller
        return cfg
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
                        withAnimation(IBAnimation.gentle) {
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
                    withAnimation(IBAnimation.smooth) {
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(Array(diagram.graphSeries.enumerated()), id: \.offset) { index, series in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(seriesColor(series, index: index))
                                .frame(width: 7, height: 7)
                            Text(series.label ?? "Series \(index + 1)")
                                .font(.caption2)
                                .foregroundStyle(IBColors.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
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
        let plot = CGRect(x: 44, y: 20, width: max(size.width - 66, 80), height: max(size.height - 58, 80))
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
            context.draw(
                Text(shortDiagramLabel(yLabel, limit: 22)).font(.caption2),
                at: CGPoint(x: plot.minX + 4, y: plot.minY + 6),
                anchor: .topLeading
            )
        }
    }

    private func drawFlow(in context: inout GraphicsContext, size: CGSize) {
        let nodes = diagram.flowNodes
        guard !nodes.isEmpty else {
            context.draw(Text("ARIA diagram data is empty").font(.caption), at: CGPoint(x: size.width / 2, y: size.height / 2))
            return
        }
        let nodeInset = CGSize(width: 66, height: 30)
        let positions = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { index, node in
            let columns = max(Int(ceil(sqrt(Double(nodes.count)))), 1)
            let row = index / columns
            let column = index % columns
            let rawX = node.x.map { CGFloat($0) * size.width } ?? (CGFloat(column + 1) / CGFloat(columns + 1) * size.width)
            let rows = max(Int(ceil(Double(nodes.count) / Double(columns))), 1)
            let rawY = node.y.map { CGFloat($0) * size.height } ?? (CGFloat(row + 1) / CGFloat(rows + 1) * size.height)
            let x = min(max(rawX, nodeInset.width), max(nodeInset.width, size.width - nodeInset.width))
            let y = min(max(rawY, nodeInset.height), max(nodeInset.height, size.height - nodeInset.height))
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
                context.draw(Text(shortDiagramLabel(label, limit: 22)).font(.caption2), at: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 - 10))
            }
        }
        for (index, node) in nodes.enumerated() {
            guard let point = positions[node.id] else { continue }
            let rect = CGRect(x: point.x - 58, y: point.y - 21, width: 116, height: 42)
            let color = node.color.map(Color.init(hex:)) ?? seriesColor(nil, index: index)
            context.fill(Path(roundedRect: rect, cornerRadius: 7), with: .color(color.opacity(0.14)))
            context.stroke(Path(roundedRect: rect, cornerRadius: 7), with: .color(color.opacity(0.75)), lineWidth: 1)
            context.draw(
                Text(shortDiagramLabel(node.label, limit: 24)).font(.caption.weight(.semibold)).foregroundColor(IBColors.ink),
                at: point,
                anchor: .center
            )
        }
    }

    private func seriesColor(_ series: ARIADiagramSpec.Series?, index: Int) -> Color {
        if let hex = series?.color, !hex.isEmpty { return Color(hex: hex) }
        return [IBColors.electricBlue, IBColors.teal, IBColors.coral, IBColors.gold][index % 4]
    }

    private func shortDiagramLabel(_ label: String, limit: Int) -> String {
        guard label.count > limit else { return label }
        return String(label.prefix(max(limit - 1, 1))) + "…"
    }
}

private struct ARIAParticleSimulationView: View {
    let mode: String
    let particleCount: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isPlaying = true
    @State private var speed = 1.0
    @State private var pausedElapsed: TimeInterval = 0
    @State private var activeStartedAt = Date()
    @State private var isVisible = false

    private var isAtomMode: Bool {
        mode.localizedCaseInsensitiveContains("atom") || mode.localizedCaseInsensitiveContains("electron")
    }

    private var isPaused: Bool {
        !isVisible || scenePhase != .active || !isPlaying || reduceMotion
    }

    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: isPaused)) { timeline in
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
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false; if isPlaying { pausedElapsed += Date().timeIntervalSince(activeStartedAt) } }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isPlaying = true
    @State private var masterSpeed = 1.0
    @State private var pausedElapsed: TimeInterval = 0
    @State private var activeStartedAt = Date()
    @State private var isVisible = false
    @State private var controlValues: [String: Double]
    @State private var toggleValues: [String: Bool]

    private var isPaused: Bool {
        !isVisible || scenePhase != .active || !isPlaying || reduceMotion
    }

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
            TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: isPaused)) { timeline in
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
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false; if isPlaying { pausedElapsed += Date().timeIntervalSince(activeStartedAt) } }
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
                    Text(shortLabel(element.label ?? "", limit: 42)).font(.caption.weight(.semibold)).foregroundColor(color),
                    at: point,
                    anchor: .center
                )

            default:
                let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.88)))
                if let label = element.label {
                    context.draw(
                        Text(shortLabel(label, limit: 36)).font(.caption2.weight(.medium)).foregroundColor(IBColors.ink),
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
        let inset: CGFloat = 24
        let contentWidth = max(size.width - inset * 2, 1)
        let contentHeight = max(size.height - inset * 2, 1)
        return CGPoint(
            x: inset + CGFloat(min(max(x, 0), 1)) * contentWidth,
            y: inset + CGFloat(min(max(y, 0), 1)) * contentHeight
        )
    }

    private func shortLabel(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(max(limit - 1, 1))) + "…"
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
