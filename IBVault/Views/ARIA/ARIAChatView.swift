import Foundation
import AppKit
import SwiftData
import SwiftUI

private struct ARIAChatFailure: Identifiable {
    let id: UUID
    let sessionID: UUID?
    let prompt: String?
    let provider: AIProviderKind
    let message: String
    let needsCodexSignIn: Bool

    init(
        error: Error,
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
    @State private var ariaService = ARIAService()
    @State private var inputText = ""
    @State private var streamingText = ""
    @State private var showMemory = false
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
        return visibleSessions.first(where: { $0.id == selectedSessionID }) ?? visibleSessions.first
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
                    }

                    ToolbarItem(placement: .primaryAction) {
                        Button { showMemory = true } label: {
                            Label("Memory", systemImage: "brain")
                        }
                    }
                }
                .sheet(isPresented: $showMemory) { ARIAMemoryView() }
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
                    RoundedRectangle(cornerRadius: 8)
                        .fill(IBColors.teal.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(IBColors.teal)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("ARIA")
                        .font(.system(size: 15, weight: .bold))
                    Text("STUDY COMPANION")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
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
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteChat(session)
                            } label: {
                                Label("Delete", systemImage: "trash")
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
                    .fill(IBColors.electricBlue.opacity(0.09))
                    .frame(width: 58, height: 58)
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(IBColors.electricBlue)
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
                    Image(systemName: ariaService.isLoading ? "stop.fill" : "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle().fill(
                                inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !ariaService.isLoading
                                    ? IBColors.tertiaryText.opacity(0.45) : IBColors.electricBlue
                            )
                        )
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !ariaService.isLoading)
                .help(ariaService.isLoading ? "Stop response" : "Send message")
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(IBColors.canvas)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(IBColors.cardBorder, lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(IBColors.surface)
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
        guard let selectedSession else {
            bootstrapSessionsIfNeeded()
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
              ChatMessageRole.isFailure(message.role) else { return }
        message.role = ChatMessageRole.dismissed(message.role)
        do {
            try context.save()
        } catch {
            context.rollback()
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
        guard ChatMessageRole.isFailure(message.role) else { return true }
        context.delete(message)
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            chatFailure = ARIAChatFailure(
                message: "The saved response could not be prepared for retry: \(error.localizedDescription)",
                sessionID: message.sessionID,
                provider: ChatMessageRole.failureProvider(for: message.role) ?? selectedProvider
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
              ChatMessageRole.isFailure(message.role) else { return false }
        message.content = content
        do {
            try context.save()
            chatFailure = nil
            return true
        } catch {
            context.rollback()
            return false
        }
    }

    @MainActor
    private func bootstrapSessionsIfNeeded() {
        var didMutate = false
        var preferredSelection = selectedSessionID

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
            didMutate = true
        }

        if visibleSessions.isEmpty && !didMutate {
            let session = ARIAChatSession()
            context.insert(session)
            preferredSelection = session.id
            didMutate = true
        }

        if didMutate {
            do {
                try context.save()
            } catch {
                context.rollback()
                chatFailure = ARIAChatFailure(
                    message: "Chat setup could not be saved: \(error.localizedDescription)",
                    sessionID: selectedSessionID,
                    provider: selectedProvider
                )
                return
            }
        }

        if selectedSessionID == nil {
            selectedSessionID = preferredSelection ?? visibleSessions.first?.id
        }
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
            context.rollback()
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
            context.rollback()
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
        guard !isLoading,
              let lastMessage = messages.last,
              lastMessage.role == ChatMessageRole.user,
              dismissedRecoveredFailureID != lastMessage.id else {
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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if messages.isEmpty && !isLoading {
                        emptyContent
                    }

                    ForEach(messages, id: \.id) { message in
                        if let persistedFailure = persistedFailure(for: message) {
                            ARIAChatFailureRow(
                                failure: persistedFailure,
                                onRetry: { onRetry(persistedFailure) },
                                onReconnectCodex: { onReconnectCodex(persistedFailure) },
                                onDismiss: { onDismissFailure(persistedFailure) }
                            )
                            .id(message.id)
                        } else if ChatMessageRole.isConversationRole(message.role) {
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

    private func persistedFailure(for message: ChatMessage) -> ARIAChatFailure? {
        guard ChatMessageRole.isFailure(message.role),
              let provider = ChatMessageRole.failureProvider(for: message.role),
              let messageIndex = messages.firstIndex(where: { $0.id == message.id }) else {
            return nil
        }

        let prompt = messages[..<messageIndex]
            .last(where: { $0.role == ChatMessageRole.user })?
            .content
        return ARIAChatFailure(
            message: message.content,
            sessionID: message.sessionID,
            prompt: prompt,
            provider: provider,
            needsCodexSignIn: ChatMessageRole.needsCodexAuthentication(message.role),
            id: message.id
        )
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

    private var isUser: Bool { message.role == ChatMessageRole.user }

    var body: some View {
        Group {
            if isUser {
                HStack(alignment: .top, spacing: 10) {
                    Spacer(minLength: 80)
                    VStack(alignment: .trailing, spacing: 5) {
                        Text("You")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(IBColors.secondaryText)
                        Text(message.content)
                            .lineSpacing(3)
                            .foregroundStyle(IBColors.ink)
                            .textSelection(.enabled)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(IBColors.electricBlue.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(IBColors.electricBlue.opacity(0.16), lineWidth: 1)
                                    )
                            )
                    }
                    .frame(maxWidth: 590, alignment: .trailing)
                    userAvatar
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ariaAvatar
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ARIA")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(IBColors.electricBlue)
                        FormattedMessageContent(text: message.content, preferRichRendering: true)
                            .textSelection(.enabled)
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
                .fill(IBColors.electricBlue.opacity(0.12))
                .frame(width: 30, height: 30)
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(IBColors.electricBlue)
        }
    }

    private var userAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 30, height: 30)
            Image(systemName: "person.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Streaming Message Row
struct StreamingMessageRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(IBColors.electricBlue.opacity(0.12))
                    .frame(width: 30, height: 30)
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(IBColors.electricBlue)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("ARIA")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IBColors.electricBlue)
                    .padding(.horizontal, 4)
                FormattedMessageContent(text: text, preferRichRendering: true)
                    .textSelection(.enabled)
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
            NativeMathBlockView(latex: latex)

        case .codeBlock(let code, let language):
            CodeBlockView(code: code, language: language)

        case .flashcard(let front, let back):
            FlashcardMessageView(front: front, back: back)
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
    case flashcard(front: String, back: String)
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
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
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
                sections.append(.codeBlock(code: code, language: codeBlockLanguage))
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

        return sections.isEmpty ? [.markdown(normalized)] : sections
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
        source
            .replacingOccurrences(of: "—", with: " - ")
            .replacingOccurrences(of: "–", with: " - ")
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
            
            if trimmedParagraph.contains("$$") {
                var buffer = ""
                var index = trimmedParagraph.startIndex
                
                while index < trimmedParagraph.endIndex {
                    let remaining = trimmedParagraph[index...]
                    
                    if remaining.hasPrefix("$$") {
                        let contentStart = trimmedParagraph.index(index, offsetBy: 2)
                        
                        if let closingRange = trimmedParagraph[contentStart...].range(of: "$$") {
                            let mathContent = String(trimmedParagraph[contentStart..<closingRange.lowerBound])
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            
                            let markdown = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !markdown.isEmpty {
                                sections.append(.markdown(markdown))
                            }
                            buffer = ""
                            
                            if !mathContent.isEmpty {
                                sections.append(.mathBlock(mathContent))
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

enum MathExpressionFormatter {
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
