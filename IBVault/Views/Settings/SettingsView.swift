import AppKit
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    private static let fixedTargetIBScore = 40

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var profiles: [UserProfile]
    @Query private var subjects: [Subject]
    @State private var syncedPlanCount = 0
    @State private var apiKey = ""
    @State private var junaliAPIKey = ""
    @State private var showAPIKey = false
    @State private var showJunaliAPIKey = false
    @State private var hasKey = false
    @State private var hasJunaliKey = false
    @State private var savedConfirmation = false
    @State private var providerStatus: AIProviderStatus?
    @State private var isTestingProvider = false
    @State private var showReportUpload = false
    @State private var backupStatus = ""
    @State private var showBackups = false
    @State private var isBackingUp = false
    @State private var showModelPicker = false
    @State private var backupCount = 0
    @State private var latestBackupDate: Date?
    @State private var showResetConfirmation = false
    @State private var isResetting = false
    @State private var showPlaceholderCleanupConfirmation = false
    @State private var isCleaningPlaceholders = false
    @State private var profileSaveTask: Task<Void, Never>?
    @State private var settingsSaveError: String?
    @State private var credentialError: String?
    @State private var settingsSearch = ""
    @State private var initializedProfile = false
    @State private var loadedSections: Set<SettingsSection> = []
    @State private var codexModels: [AIModelOption] = []
    @State private var isLoadingCodexModels = false
    @State private var codexCatalogStatus = ""

    // ARIA Settings
    @AppStorage("geminiModel") private var selectedModel = "gemini-2.0-flash"
    @AppStorage("junaliModel") private var junaliModel = "gpt-5.6-sol"
    @AppStorage("codexModel") private var codexModel = "gpt-5.6-sol"
    @AppStorage("ariaProvider") private var selectedProviderRaw = AIProviderKind.gemini.rawValue
    @AppStorage("ariaReasoningEffort") private var reasoningEffortRaw = AIReasoningEffort.medium.rawValue
    @AppStorage("ariaVerbosity") private var verbosityRaw = AIResponseVerbosity.medium.rawValue
    @AppStorage("ariaWebSearchMode") private var webSearchModeRaw = AIWebSearchMode.cached.rawValue
    @AppStorage("junaliBaseURL") private var junaliBaseURL = AIConfiguration.junaliDefaultBaseURL
    @AppStorage("codexCLIPath") private var codexCLIPath = ""
    @AppStorage("ariaTemperature") private var ariaTemperature = 0.7

    // Study Settings
    @AppStorage("showMasteryPercent") private var showMasteryPercent = true
    @AppStorage("autoPlayNext") private var autoPlayNext = false
    @AppStorage(ReviewDailyLimitPolicy.enforceLimitKey) private var enforceDailyCardLimit = false
    @Environment(ReviewQueueManager.self) private var reviewQueue: ReviewQueueManager?
    @AppStorage("showDueCountBadge") private var showDueCountBadge = true
    @AppStorage("dailyReminderEnabled") private var dailyReminderEnabled = false
    @AppStorage(NotificationService.streakWarningEnabledKey) private var streakWarningEnabled = false
    @State private var notificationsBlocked = false
    @AppStorage("reviewOrder") private var reviewOrder = "spaced"
    @AppStorage("cardDefaultCount") private var cardDefaultCount = 6
    @AppStorage("cardDefaultTone") private var cardDefaultTone = "balanced"
    @AppStorage("cardDefaultStyle") private var cardDefaultStyle = "basic"
    @AppStorage("cardDefaultDifficulty") private var cardDefaultDifficulty = CardDifficulty.exam.rawValue
    @AppStorage(CalendarSyncPreferences.isEnabledKey) private var calendarSyncEnabled = false
    @AppStorage("appAppearance") private var appAppearanceRaw = IBAppearance.dark.rawValue
    @AppStorage(CalendarSyncPreferences.calendarIdentifierKey) private var selectedCalendarIdentifier = ""

    @State private var calendarOptions: [CalendarSyncOption] = []
    @State private var calendarSyncStatus = ""
    @State private var isConfiguringCalendar = false
    @State private var isGoogleConfigured = false
    @State private var isGoogleConnected = false
    @AppStorage(CalendarSyncPreferences.lastErrorKey) private var calendarLastError = ""

    @State private var adhdMedSettings: ADHDMedicationSettings = .default
    @State private var showMedicationPicker = false

    /// The categorized left-hand navigation for Settings.
    enum SettingsSection: String, CaseIterable, Identifiable {
        case general = "General"
        case assistant = "Coach & AI"
        case flashcards = "Flashcards"
        case study = "Schedule & Focus"
        case integrations = "Integrations"
        case data = "Data & Backup"
        case about = "About"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "person.crop.circle"
            case .assistant: return "sparkles"
            case .flashcards: return "rectangle.on.rectangle"
            case .study: return "calendar"
            case .integrations: return "link"
            case .data: return "externaldrive"
            case .about: return "info.circle"
            }
        }

        var searchTerms: String {
            switch self {
            case .general: return "name profile year intensity theme appearance grades report curriculum subjects level syllabus HL SL"
            case .assistant: return "AI provider model memory API key connection reasoning verbosity temperature creativity web search"
            case .flashcards: return "cards count number batch format basic cloze multiple choice balanced concise tone difficulty review daily goal order mastery badge auto advance"
            case .study: return "calendar Google sync focus ADHD medication notification reminder streak"
            case .integrations: return "bridge NotebookLM external integrations"
            case .data: return "backup restore export import reset delete recovery"
            case .about: return "version platform installed app"
            }
        }
    }

    @State private var selectedSection: SettingsSection = .general

    private let loadsExternalState: Bool

    init(initialSection: SettingsSection = .general, loadsExternalState: Bool = true) {
        _selectedSection = State(initialValue: initialSection)
        self.loadsExternalState = loadsExternalState
    }

    private var profile: UserProfile? { profiles.first }

    private var matchingSections: [SettingsSection] {
        let query = settingsSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return SettingsSection.allCases.filter {
            query.isEmpty || "\($0.rawValue) \($0.searchTerms)".localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedProvider: AIProviderKind {
        AIProviderKind(rawValue: selectedProviderRaw) ?? .gemini
    }

    private var selectedReasoningEffort: Binding<AIReasoningEffort> {
        Binding(
            get: { AIReasoningEffort(rawValue: reasoningEffortRaw) ?? .medium },
            set: { reasoningEffortRaw = $0.rawValue }
        )
    }

    private var selectedVerbosity: Binding<AIResponseVerbosity> {
        Binding(
            get: { AIResponseVerbosity(rawValue: verbosityRaw) ?? .medium },
            set: { verbosityRaw = $0.rawValue }
        )
    }

    private var selectedWebSearchMode: Binding<AIWebSearchMode> {
        Binding(
            get: { AIWebSearchMode(rawValue: webSearchModeRaw) ?? .cached },
            set: { webSearchModeRaw = $0.rawValue }
        )
    }

    private var activeModel: Binding<String> {
        // Keep a rendered picker bound to its own provider while SwiftUI
        // replaces the controls after a provider change.
        let provider = selectedProvider
        return Binding(
            get: {
                switch provider {
                case .gemini: return selectedModel
                case .junali: return junaliModel
                case .codexCLI: return codexModel
                }
            },
            set: { value in
                switch provider {
                case .gemini: selectedModel = value
                case .junali: junaliModel = value
                case .codexCLI: codexModel = value
                }
            }
        )
    }

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 820 {
                HStack(spacing: 0) {
                    settingsNavigation(compact: false)
                        .frame(width: 200)
                    settingsDetail
                }
            } else {
                VStack(spacing: 0) {
                    settingsNavigation(compact: true)
                    Rectangle().fill(IBColors.border).frame(height: 1)
                    settingsDetail
                }
            }
        }
        .background(IBColors.canvas)
        .tint(IBColors.accent)
        .navigationTitle("Settings")
        .sheet(isPresented: $showReportUpload) { ReportUploadView() }
        .sheet(isPresented: $showModelPicker) { GeminiModelPickerView(selectedModel: $selectedModel) }
        .task {
            guard loadsExternalState, !initializedProfile else { return }
            initializedProfile = true
            enforceFixedTarget()
            if let profile, profile.dailyGoal > ReviewDailyLimitPolicy.maximumCards {
                profile.dailyGoal = ReviewDailyLimitPolicy.maximumCards
                persistChanges()
            }
        }
        .task(id: selectedSection) { await loadSectionState() }
        .task(id: selectedProviderRaw) {
            if loadsExternalState, selectedProvider == .codexCLI { await loadCodexModels() }
        }
        .onChange(of: calendarLastError) { _, error in
            guard !isConfiguringCalendar else { return }
            refreshGoogleCalendarState()
            if !error.isEmpty { calendarSyncStatus = error }
            else if let date = UserDefaults.standard.object(forKey: CalendarSyncPreferences.lastSyncDateKey) as? Date {
                calendarSyncStatus = "Last synced \(date.formatted(date: .abbreviated, time: .shortened))."
            }
        }
        .onDisappear {
            profileSaveTask?.cancel()
            if loadsExternalState, context.hasChanges { persistChanges() }
        }
        .sheet(isPresented: $showMedicationPicker) {
            MedicationPickerView(settings: $adhdMedSettings)
        }
    }

    private func settingsNavigation(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(IBColors.inkSecondary)
                TextField("Find a setting", text: $settingsSearch)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Find a settings category")
                if !settingsSearch.isEmpty {
                    Button { settingsSearch = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("Clear settings search")
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(IBColors.surfaceRaised, in: RoundedRectangle(cornerRadius: IBRadius.sm))

            if matchingSections.isEmpty {
                Text("No matching settings. Try ‘cards’, ‘model’, or ‘theme’.")
                    .font(.callout).foregroundStyle(IBColors.inkSecondary)
            } else if compact {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(matchingSections) { section in
                            categoryButton(section).fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
                .frame(height: 44)
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(matchingSections) { section in categoryButton(section) }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxHeight: compact ? nil : .infinity, alignment: .topLeading)
        .background(IBColors.canvasDeep)
    }

    private func categoryButton(_ section: SettingsSection) -> some View {
        Button { selectedSection = section } label: {
            Label(section.rawValue, systemImage: section.icon)
                .font(.system(size: 13, weight: selectedSection == section ? .medium : .regular))
                .foregroundStyle(selectedSection == section ? IBColors.ink : IBColors.inkSecondary)
                .padding(.horizontal, 8).frame(height: 30)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selectedSection == section ? IBColors.ink.opacity(0.07) : Color.clear,
                            in: RoundedRectangle(cornerRadius: IBRadius.sm))
                .contentShape(Rectangle())
                .hoverHighlight()
        }
        .buttonStyle(IBPressStyle())
        .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
    }

    private var settingsDetail: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(selectedSection.rawValue).font(IBTypography.pageTitle)
                    }
                    .id("settings-top")
                    if let settingsSaveError {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(settingsSaveError, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(IBColors.danger)
                            Button("Retry save") { persistChanges() }
                        }
                    }
                    sectionContent
                        .id(selectedSection)
                        .transition(.opacity)
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(28)
                .frame(maxWidth: .infinity)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selectedSection)
            }
            .onChange(of: selectedSection) { _, _ in proxy.scrollTo("settings-top", anchor: .top) }
        }
    }

    @MainActor
    private func loadSectionState() async {
        guard loadsExternalState, !loadedSections.contains(selectedSection) else { return }
        let section = selectedSection
        switch section {
        case .assistant:
            refreshKeychainState()
            if selectedProvider == .codexCLI { await loadCodexModels() }
        case .data:
            refreshBackupState()
        case .study:
            adhdMedSettings = ADHDMedicationSettings.loadFromDefaults()
            refreshGoogleCalendarState()
            if !isGoogleConnected, let lastError = UserDefaults.standard.string(forKey: CalendarSyncPreferences.lastErrorKey) {
                calendarSyncStatus = isGoogleConfigured ? lastError : "\(lastError) Choose your OAuth file, then connect."
            }
            if isGoogleConnected {
                do {
                    try await loadCalendarOptions(keepProgressVisible: false)
                    if let lastError = UserDefaults.standard.string(forKey: CalendarSyncPreferences.lastErrorKey) {
                        calendarSyncStatus = lastError
                    } else if let lastSync = UserDefaults.standard.object(forKey: CalendarSyncPreferences.lastSyncDateKey) as? Date {
                        calendarSyncStatus = "Last synced \(lastSync.formatted(date: .abbreviated, time: .shortened))."
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    refreshGoogleCalendarState()
                    calendarSyncStatus = error.localizedDescription
                    return
                }
            }
        default:
            break
        }
        guard !Task.isCancelled else { return }
        loadedSections.insert(section)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .general:
            studyWorkspace
            curriculumSection
        case .assistant:
            modelConfigurationSection
            aiProviderSection
            assistantMemorySection
        case .flashcards:
            studySection
            flashcardDefaultsSection
        case .study:
            calendarSyncSection
            adhdSection
            notificationSection
        case .integrations:
            IntegrationSettingsSection()
        case .data:
            backupSection
            dataSection
        case .about:
            aboutSection
        }
    }

    private var studyWorkspace: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsGroup {
                if let profile {
                    SettingsField("Name") {
                        TextField("Your name", text: Binding(
                            get: { profile.studentName },
                            set: { profile.studentName = $0; scheduleProfileSave() }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Your name")
                    }
                    SettingsField("IB programme") {
                        Picker("IB programme", selection: Binding(
                            get: { profile.ibYear },
                            set: { profile.ibYear = $0; persistChanges() }
                        )) {
                            ForEach(IBYear.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 320, alignment: .leading)
                    }
                    SettingsField("Study intensity") {
                        SettingsChoices(values: StudyIntensity.allCases, selection: Binding(
                            get: { profile.studyIntensity },
                            set: { profile.studyIntensity = $0; persistChanges() }
                        ), label: { $0.rawValue })
                    }
                }
            } header: {
                Label("Study profile", systemImage: "person.crop.circle")
            }

            SettingsGroup {
                SettingsField("Theme") {
                    SettingsChoices(values: IBAppearance.allCases, selection: $appAppearanceRaw,
                                    value: { $0.rawValue }, label: { $0.rawValue })
                }
            } header: {
                Label("Appearance", systemImage: "paintbrush")
            }

            SettingsGroup {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Report results").font(.callout.weight(.semibold))
                        Text(profile?.reportLastUploaded.map {
                            "Updated \($0.formatted(date: .abbreviated, time: .omitted))"
                        } ?? "Add your current subject grades")
                        .font(.caption).foregroundStyle(IBColors.inkSecondary)
                    }
                    Spacer()
                    Button("Update grades") { showReportUpload = true }
                        .buttonStyle(SecondaryButtonStyle())
                }
            } header: {
                Label("Report & grades", systemImage: "chart.bar.doc.horizontal")
            }
        }
    }

    // MARK: - AI Provider
    private var aiProviderSection: some View {
        SettingsGroup {
            providerCredentialEditor

            HStack(spacing: 12) {
                Button {
                    testSelectedProvider()
                } label: {
                    Label(isTestingProvider ? "Checking…" : "Check connection",
                          systemImage: "bolt.horizontal.circle")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isTestingProvider)
                if isTestingProvider { ProgressView().controlSize(.small) }
            }

            if let providerStatus {
                Label(providerStatus.message,
                      systemImage: providerStatus.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(providerStatus.isReady ? IBColors.success : IBColors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Label("\(selectedProvider.shortName) connection", systemImage: "link")
        } footer: {
            Text("API keys are stored in macOS Keychain. Local Codex uses your existing CLI sign-in.")
        }
    }

    private var assistantMemorySection: some View {
        SettingsGroup {
            NavigationLink { ARIAMemoryView() } label: {
                HStack {
                    Label("Manage ARIA memory", systemImage: "brain")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption)
                }
            }
            .buttonStyle(.plain)
        } header: {
            Label("Conversation & memory", systemImage: "bubble.left.and.bubble.right")
        }
    }

    @ViewBuilder
    private var providerCredentialEditor: some View {
        switch selectedProvider {
        case .gemini:
            credentialEditor(
                title: "Gemini API key",
                text: $apiKey,
                isVisible: $showAPIKey,
                hasCredential: hasKey,
                save: {
                    hasKey = KeychainService.saveAPIKey(apiKey)
                    return hasKey
                },
                delete: {
                    _ = KeychainService.deleteAPIKey()
                    hasKey = false
                    apiKey = ""
                }
            )
        case .junali:
            VStack(alignment: .leading, spacing: 10) {
                TextField("Base URL", text: $junaliBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.callout, design: .monospaced))
                credentialEditor(
                    title: "Junali API key",
                    text: $junaliAPIKey,
                    isVisible: $showJunaliAPIKey,
                    hasCredential: hasJunaliKey,
                    save: {
                        hasJunaliKey = KeychainService.saveJunaliAPIKey(junaliAPIKey)
                        return hasJunaliKey
                    },
                    delete: {
                        _ = KeychainService.deleteJunaliAPIKey()
                        hasJunaliKey = false
                        junaliAPIKey = ""
                    }
                )
            }
        case .codexCLI:
            VStack(alignment: .leading, spacing: 8) {
                Text("Codex executable").font(.callout.weight(.medium))
                TextField("Codex executable path (auto-detect when empty)", text: $codexCLIPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.callout, design: .monospaced))
                Text("Leave the path empty to find Codex automatically. Your existing Codex sign-in is used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func credentialEditor(
        title: String,
        text: Binding<String>,
        isVisible: Binding<Bool>,
        hasCredential: Bool,
        save: @escaping () -> Bool,
        delete: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.callout.weight(.semibold))
            HStack {
                if isVisible.wrappedValue {
                    TextField("Enter key", text: text)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                } else {
                    SecureField("Enter key", text: text)
                        .textFieldStyle(.roundedBorder)
                }
                Button {
                    isVisible.wrappedValue.toggle()
                } label: {
                    Image(systemName: isVisible.wrappedValue ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(isVisible.wrappedValue ? "Hide API key" : "Show API key")
                .accessibilityLabel(isVisible.wrappedValue ? "Hide API key" : "Show API key")
            }
            HStack {
                Button("Save to Keychain") {
                    guard !text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    credentialError = nil
                    if save() {
                        savedConfirmation = true
                        IBHaptics.success()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedConfirmation = false }
                    } else {
                        credentialError = "Could not save the key. Try again."
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if savedConfirmation {
                    Text("Saved").font(.caption).foregroundStyle(IBColors.success)
                }
                Spacer()
                if hasCredential {
                    Button("Delete Key", role: .destructive) { delete() }
                        .controlSize(.small)
                }
            }
            if let credentialError {
                Label(credentialError, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(IBColors.danger)
            }
        }
    }

    // MARK: - Model Configuration
    private var modelConfigurationSection: some View {
        SettingsGroup {
            SettingsField("Provider") {
                SettingsChoices(values: AIProviderKind.allCases, selection: $selectedProviderRaw,
                                value: { $0.rawValue }, label: { $0.displayName })
                    .disabled(isTestingProvider)
                    .onChange(of: selectedProviderRaw) { _, _ in
                        providerStatus = nil
                        credentialError = nil
                        reasoningEffortRaw = AIConfiguration.normalizedReasoningEffort(
                            selectedReasoningEffort.wrappedValue, for: selectedProvider
                        ).rawValue
                    }
            }

            SettingsField("Model") {
                if selectedProvider == .gemini {
                    Button { showModelPicker = true } label: {
                        HStack {
                            Text(selectedModel).font(.system(.callout, design: .monospaced))
                            Spacer()
                            Text("Browse models")
                            Image(systemName: "chevron.down")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                } else {
                    Picker("Model preset", selection: activeModel) {
                        let models = selectedProvider == .codexCLI ? codexModels : (AIConfiguration.knownModels[selectedProvider] ?? [])
                        if !models.contains(where: { $0.id == activeModel.wrappedValue }) {
                            Text("Custom · \(activeModel.wrappedValue)").tag(activeModel.wrappedValue)
                        }
                        ForEach(models) { option in
                            Text(option.name).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)

                }
                if selectedProvider == .codexCLI {
                    if isLoadingCodexModels { ProgressView("Updating Codex models…").controlSize(.small) }
                    if !codexCatalogStatus.isEmpty {
                        Text(codexCatalogStatus).font(.caption).foregroundStyle(IBColors.inkSecondary)
                    }
                }
            }

            DisclosureGroup("Advanced") {
                VStack(alignment: .leading, spacing: 20) {
                    if selectedProvider != .gemini {
                        SettingsField("Custom model ID") {
                            TextField("Custom model ID", text: activeModel)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.callout, design: .monospaced))
                                .accessibilityLabel("Custom model ID")
                        }
                        SettingsField("Reasoning effort") {
                            SettingsChoices(values: AIConfiguration.supportedReasoningEfforts(for: selectedProvider),
                                            selection: selectedReasoningEffort, label: { $0.displayName })
                            Text(selectedReasoningEffort.wrappedValue.detail)
                                .font(.caption).foregroundStyle(IBColors.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        SettingsField("Answer detail") {
                            SettingsChoices(values: AIResponseVerbosity.allCases,
                                            selection: selectedVerbosity, label: { $0.displayName })
                        }
                    }
                    if selectedProvider == .codexCLI {
                        SettingsField("Web search") {
                            SettingsChoices(values: AIWebSearchMode.allCases,
                                            selection: selectedWebSearchMode, label: { $0.displayName })
                            Text(selectedWebSearchMode.wrappedValue.detail)
                                .font(.caption).foregroundStyle(IBColors.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if selectedProvider == .gemini {
                        SettingsField("Creativity · \(String(format: "%.1f", ariaTemperature))") {
                            Slider(value: $ariaTemperature, in: 0...1.5, step: 0.1)
                                .accessibilityLabel("Creativity")
                            Text(temperatureDescription).font(.caption).foregroundStyle(IBColors.inkSecondary)
                        }
                    }
                }
                .padding(.top, 12)
            }
        } header: {
            Label("Model & responses", systemImage: "cpu")
        }
    }

    @MainActor
    private func loadCodexModels() async {
        guard !isLoadingCodexModels else { return }
        isLoadingCodexModels = true
        codexModels = AIConfiguration.knownModels[.codexCLI] ?? []
        defer { isLoadingCodexModels = false }
        do {
            let models = try await AIProviderService.refreshCodexModels()
            codexModels = AIConfiguration.knownModels[.codexCLI] ?? []
            // Keep explicit selections, including provider IDs that the CLI
            // accepts without advertising them in its catalog.
            if UserDefaults.standard.string(forKey: "codexModel") == nil || codexModel.isEmpty,
               let defaultModel = models.first(where: \.isDefault) ?? models.first {
                codexModel = defaultModel.model
            }
            reasoningEffortRaw = AIConfiguration.normalizedReasoningEffort(selectedReasoningEffort.wrappedValue, for: .codexCLI).rawValue
            codexCatalogStatus = "Kept in sync with your installed Codex."
        } catch is CancellationError {
        } catch {
            codexCatalogStatus = "Couldn't update Codex models: \(error.localizedDescription)"
        }
    }

    private var curriculumSection: some View {
        SettingsGroup {
            if subjects.isEmpty {
                Label("No subjects yet", systemImage: "books.vertical")
                Text("Add your subjects during onboarding to choose their curriculum level here.")
                    .font(.callout).foregroundStyle(IBColors.inkSecondary)
            }
            ForEach(subjects.sorted { $0.name < $1.name }, id: \.id) { subject in
                HStack(spacing: 12) {
                    Circle()
                        .fill(IBColors.inkTertiary)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(subject.name)
                        let curriculum = SyllabusSeeder.curriculum(for: subject.name, level: subject.level)
                        Text("\(curriculum.count) units · \(curriculum.flatMap(\.topics).count) topics · \(curriculum.flatMap(\.topics).flatMap(\.subtopics).count) subunits")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Level", selection: Binding(
                        get: { subject.level },
                        set: { newLevel in
                            subject.level = newLevel
                            SyllabusSeeder.synchronizeCurriculum(context: context)
                        }
                    )) {
                        Text("SL").tag("SL")
                        Text("HL").tag("HL")
                    }
                    .labelsHidden()
                    .frame(width: 72)
                }
            }
        } header: {
            Label("Subjects & Curriculum", systemImage: "books.vertical")
        } footer: {
            Text("Changing a level refreshes the saved curriculum tree immediately. Existing personal flashcards are preserved.")
        }
    }

    private var temperatureDescription: String {
        switch ariaTemperature {
        case 0..<0.3: return "Very focused and deterministic — best for factual answers"
        case 0.3..<0.6: return "Balanced — good for study guides and analysis"
        case 0.6..<0.9: return "Default — creative yet reliable for tutoring"
        case 0.9..<1.3: return "More creative — good for brainstorming and essays"
        default: return "Highly creative — may produce unexpected responses"
        }
    }

    // MARK: - Study Settings
    private var flashcardDefaultsSection: some View {
        SettingsGroup {
            CardCountControl(count: $cardDefaultCount)
            Text("The total across your selected topics and formats, up to \(CardGenerationOptions.maximumCount) in one set.")
                .font(.caption).foregroundStyle(IBColors.inkSecondary)
            SettingsField("Answer style") {
                SettingsChoices(values: CardTone.allCases, selection: $cardDefaultTone,
                                value: { $0.rawValue }, label: { $0.label })
                Text((CardTone(rawValue: cardDefaultTone) ?? .balanced).summary)
                    .font(.caption).foregroundStyle(IBColors.inkSecondary)
            }
            SettingsField("Default format") {
                SettingsChoices(values: CardStyle.allCases, selection: $cardDefaultStyle,
                                value: { $0.rawValue }, label: { $0.label })
            }
            SettingsField("Difficulty") {
                SettingsChoices(values: CardDifficulty.allCases, selection: $cardDefaultDifficulty,
                                value: { $0.rawValue }, label: { $0.rawValue })
            }
        } header: {
            Label("New card defaults", systemImage: "rectangle.on.rectangle")
        }
    }

    private var studySection: some View {
        SettingsGroup {
            if let p = profile {
                HStack {
                    Text("Daily goal")
                    Spacer()
                    TextField("Daily goal", value: Binding(
                        get: { p.dailyGoal },
                        set: { p.dailyGoal = min(max($0, 1), ReviewDailyLimitPolicy.maximumCards); persistChanges() }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 64)
                    .accessibilityLabel("Daily goal in cards")
                    Stepper("Daily goal", value: Binding(
                        get: { p.dailyGoal }, set: { p.dailyGoal = $0; persistChanges() }
                    ), in: 1...ReviewDailyLimitPolicy.maximumCards, step: 5)
                    .labelsHidden()
                }

                SettingsToggle("Stop reviews at my goal", isOn: $enforceDailyCardLimit)
                .onChange(of: enforceDailyCardLimit) { _, _ in reviewQueue?.refreshDueCards(context: context) }
            }

            SettingsField("Review order") {
                SettingsChoices(values: ["spaced", "weakest", "random"], selection: $reviewOrder,
                                label: { order in
                    switch order {
                    case "weakest": return "Weakest first"
                    case "random": return "Shuffled"
                    default: return "Due first"
                    }
                })
            }

            SettingsToggle("Auto-advance cards", isOn: $autoPlayNext)

            SettingsToggle("Show mastery on cards", isOn: $showMasteryPercent)

            SettingsToggle("Show due-card count in sidebar", isOn: $showDueCountBadge)
        } header: {
            Label("Daily review", systemImage: "book.fill")
        }
    }

    private var calendarSyncSection: some View {
        SettingsGroup {
            HStack(spacing: 12) {
                Image(systemName: isGoogleConnected ? "checkmark.circle.fill" : "calendar.badge.plus")
                    .foregroundStyle(isGoogleConnected ? IBColors.success : IBColors.accent)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isGoogleConnected ? "Google Calendar connected" : "Connect Google Calendar")
                }
                Spacer()
                if isConfiguringCalendar {
                    ProgressView().controlSize(.small)
                } else if isGoogleConnected {
                    Button("Disconnect", role: .destructive) {
                        disconnectGoogleCalendar()
                    }
                }
            }

            if !isGoogleConnected {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isGoogleConfigured ? "OAuth configuration ready" : "Google OAuth configuration")
                        Text(isGoogleConfigured
                             ? "Your Desktop app credentials are stored securely."
                             : "Choose the Desktop app JSON downloaded from Google Cloud.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        chooseGoogleOAuthConfiguration()
                    } label: {
                        Label(isGoogleConfigured ? "Replace File" : "Choose File", systemImage: "doc.badge.plus")
                    }
                    .disabled(isConfiguringCalendar)
                }

                HStack {
                    Link(destination: URL(string: "https://console.cloud.google.com/auth/clients")!) {
                        Label("Open Google Cloud", systemImage: "arrow.up.right.square")
                    }
                    Spacer()
                    Button {
                        Task { await connectGoogleCalendar() }
                    } label: {
                        Label("Connect Google", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isGoogleConfigured || isConfiguringCalendar)
                }
            } else {
                Toggle(isOn: Binding(
                    get: { calendarSyncEnabled },
                    set: { newValue in
                        calendarSyncEnabled = newValue
                        if newValue {
                            calendarSyncStatus = "Syncing study sessions..."
                            Task { await syncCalendarsNow() }
                        } else {
                            calendarSyncStatus = "Sync paused. Existing Google Calendar events were kept."
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatic sync")
                        Text("Update Google Calendar when your study plan changes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(isConfiguringCalendar)

                if calendarOptions.isEmpty {
                    HStack {
                        Text("Calendar")
                        Spacer()
                        Button("Load Calendars") {
                            Task { await loadCalendarOptions() }
                        }
                        .disabled(isConfiguringCalendar)
                    }
                } else {
                    Picker("Calendar", selection: $selectedCalendarIdentifier) {
                        ForEach(calendarOptions) { option in
                            Text(option.displayName).tag(option.id)
                        }
                    }
                    .disabled(isConfiguringCalendar)
                    .onChange(of: selectedCalendarIdentifier) { _, _ in
                        guard calendarSyncEnabled else { return }
                        calendarSyncStatus = "Calendar changed. Syncing..."
                        Task { await syncCalendarsNow() }
                    }

                    HStack {
                        Button {
                            Task { await syncCalendarsNow() }
                        } label: {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(isConfiguringCalendar || selectedCalendarIdentifier.isEmpty)

                        Spacer()
                        if isConfiguringCalendar {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
            }

            if !calendarSyncStatus.isEmpty {
                Text(calendarSyncStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label("Calendar", systemImage: "calendar.badge.checkmark")
        } footer: {
            Text("Noot requests access only to read your calendar list and manage study events. Your Google password never enters the app.")
        }
    }

    @MainActor
    private func connectGoogleCalendar() async {
        guard !isConfiguringCalendar else { return }
        isConfiguringCalendar = true
        calendarSyncStatus = "Waiting for Google sign-in..."
        defer { isConfiguringCalendar = false }

        do {
            try await CalendarSyncService.shared.connect()
            refreshGoogleCalendarState()
            try await loadCalendarOptions(keepProgressVisible: true)
            guard !calendarOptions.isEmpty else {
                calendarSyncEnabled = false
                calendarSyncStatus = "Connected, but Google returned no writable calendars."
                return
            }

            if !calendarOptions.contains(where: { $0.id == selectedCalendarIdentifier }) {
                selectedCalendarIdentifier = calendarOptions[0].id
            }
        } catch {
            refreshGoogleCalendarState()
            calendarSyncEnabled = false
            CalendarSyncPreferences.recordFailure(error)
            calendarSyncStatus = error.localizedDescription
            return
        }

        // Connected from here on: a failed first pass stays on and retries with
        // the next plan change or Sync Now.
        calendarSyncEnabled = true
        do {
            try await syncCurrentStudyPlans()
            calendarSyncStatus = syncSuccessMessage()
            NotificationCenter.default.post(name: .calendarSyncRequested, object: nil)
        } catch {
            refreshGoogleCalendarState()
            CalendarSyncPreferences.recordFailure(error)
            calendarSyncStatus = error.localizedDescription
        }
    }

    @MainActor
    private func chooseGoogleOAuthConfiguration() {
        guard !isConfiguringCalendar else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose Google OAuth Configuration"
        panel.message = "Select the Desktop app JSON file downloaded from Google Cloud."
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CalendarSyncService.shared.importConfiguration(from: url)
            refreshGoogleCalendarState()
            calendarSyncStatus = "Configuration saved securely. Connect Google to continue."
        } catch {
            CalendarSyncPreferences.recordFailure(error)
            calendarSyncStatus = error.localizedDescription
        }
    }

    @MainActor
    private func disconnectGoogleCalendar() {
        guard !isConfiguringCalendar else { return }
        CalendarSyncService.shared.disconnect()
        calendarSyncEnabled = false
        calendarOptions = []
        calendarSyncStatus = "Google Calendar disconnected. Existing events were kept."
        refreshGoogleCalendarState()
    }

    @MainActor
    private func refreshGoogleCalendarState() {
        isGoogleConfigured = CalendarSyncService.shared.isConfigured
        isGoogleConnected = CalendarSyncService.shared.isConnected
        // Sync stays on, so reconnecting resumes it, and the app-wide banner
        // says why nothing is reaching the calendar.
        if !isGoogleConnected, calendarSyncEnabled {
            UserDefaults.standard.set(true, forKey: CalendarSyncPreferences.needsAttentionKey)
        }
    }

    @MainActor
    private func loadCalendarOptions(keepProgressVisible: Bool = false) async throws {
        if !keepProgressVisible { isConfiguringCalendar = true }
        defer { if !keepProgressVisible { isConfiguringCalendar = false } }

        calendarOptions = try await CalendarSyncService.shared.writableCalendars()
        if calendarOptions.contains(where: { $0.id == selectedCalendarIdentifier }) == false,
           let first = calendarOptions.first {
            selectedCalendarIdentifier = first.id
        }
    }

    @MainActor
    private func loadCalendarOptions() async {
        guard !isConfiguringCalendar else { return }
        do {
            try await loadCalendarOptions(keepProgressVisible: false)
            calendarSyncStatus = calendarOptions.isEmpty
                ? "No writable calendars found."
                : "Choose the calendar that belongs to your Google account."
        } catch {
            refreshGoogleCalendarState()
            CalendarSyncPreferences.recordFailure(error)
            calendarSyncStatus = error.localizedDescription
        }
    }

    @MainActor
    private func syncCalendarsNow() async {
        guard !isConfiguringCalendar, calendarSyncEnabled, !selectedCalendarIdentifier.isEmpty else { return }
        isConfiguringCalendar = true
        calendarSyncStatus = "Syncing study sessions..."
        defer { isConfiguringCalendar = false }

        do {
            try await syncCurrentStudyPlans()
            calendarSyncStatus = syncSuccessMessage()
        } catch {
            refreshGoogleCalendarState()
            CalendarSyncPreferences.recordFailure(error)
            calendarSyncStatus = error.localizedDescription
        }
    }

    private func syncSuccessMessage() -> String {
        "Synced \(syncedPlanCount) study session\(syncedPlanCount == 1 ? "" : "s") just now."
    }

    @MainActor
    private func syncCurrentStudyPlans() async throws {
        let plans = try context.fetch(FetchDescriptor<StudyPlan>(sortBy: [SortDescriptor(\StudyPlan.scheduledDate)]))
        try await CalendarSyncService.shared.sync(plans: plans)
        syncedPlanCount = plans.count
    }

    // MARK: - ADHD Section
    private var adhdSection: some View {
        SettingsGroup {
            Button {
                showMedicationPicker = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "pills.fill")
                        .foregroundStyle(IBColors.plum)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ADHD Medication Tracker")
                        if adhdMedSettings.isEnabled && adhdMedSettings.medicationType != .none {
                            Text("\(adhdMedSettings.medicationType.displayName) \(adhdMedSettings.doseMg)mg • \(adhdMedSettings.dailyDoses)× daily")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
            
            NavigationLink {
                ADHDTrackerView()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chart.xyaxis.line")
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Focus Window Timeline")
                    }
                }
            }
        } header: {
            Label("ADHD Medication", systemImage: "heart.text.clipboard")
        } footer: {
            Text("All medication data is stored locally and never sent to external servers. This information is completely private.")
        }
    }

    // MARK: - Backup & Restore
    private var backupSection: some View {
        SettingsGroup {
            Button { createBackup() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.doc.fill")
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Create Backup")
                        if let lastDate = latestBackupDate {
                            Text("Last backup: \(lastDate, style: .relative) ago")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Save all data to Documents folder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if isBackingUp { ProgressView().controlSize(.small) }
                }
            }.disabled(isBackingUp)

            Button { restoreBackup() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.up.doc.fill")
                        .foregroundStyle(IBColors.success)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Restore from Backup")
                        Text("Restore your most recent backup")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button { showBackups = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(IBColors.warning)
                    Text("View All Backups")
                    Spacer()
                    Text("\(backupCount)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }

            if !backupStatus.isEmpty {
                Text(backupStatus)
                    .font(.caption)
                    .foregroundStyle(backupStatus.hasPrefix("✓") ? IBColors.success : IBColors.danger)
            }
        } header: {
            Label("Backup & Recovery", systemImage: "externaldrive.fill")
        } footer: {
            Text("Backups are saved to your Documents folder. Each backup contains your profile, subjects, cards, grades, ARIA memory, and study history as JSON files.")
        }
        .sheet(isPresented: $showBackups) { BackupListView() }
    }

    private func createBackup() {
        isBackingUp = true; backupStatus = ""
        // The container is Sendable; export creates its own scratch context on
        // the background queue, so no main-actor context crosses the boundary.
        let container = context.container
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url = try BackupService.exportBackup(container: container)
                DispatchQueue.main.async {
                    refreshViewState()
                    isBackingUp = false; backupStatus = "✓ Saved to \(url.lastPathComponent)"; IBHaptics.success()
                }
            } catch {
                DispatchQueue.main.async {
                    isBackingUp = false; backupStatus = "✗ Backup failed: \(error.localizedDescription)"; IBHaptics.error()
                }
            }
        }
    }

    private func restoreBackup() {
        do {
            try BackupService.restoreFromLatest(context: context)
            refreshViewState()
            backupStatus = "✓ Restored successfully!"; IBHaptics.success()
        } catch {
            // A failed restore can leave the context holding pending deletes
            // and inserts from the aborted import. Discard them so the data
            // that was live before the restore attempt survives intact.
            context.rollback()
            backupStatus = "✗ Restore failed: \(error.localizedDescription)"; IBHaptics.error()
        }
    }

    private func refreshViewState() {
        refreshKeychainState()
        refreshBackupState()
    }

    private func enforceFixedTarget() {
        if let profile {
            guard profile.targetIBScore != Self.fixedTargetIBScore else { return }
            profile.targetIBScore = Self.fixedTargetIBScore
            persistChanges()
            return
        }

        let createdProfile = UserProfile()
        createdProfile.targetIBScore = Self.fixedTargetIBScore
        context.insert(createdProfile)
        persistChanges()
    }

    private func refreshKeychainState() {
        hasKey = KeychainService.hasAPIKey
        if hasKey, let loadedKey = KeychainService.loadAPIKey() {
            apiKey = loadedKey
        }
        hasJunaliKey = KeychainService.hasJunaliAPIKey
        if hasJunaliKey, let loadedKey = KeychainService.loadJunaliAPIKey() {
            junaliAPIKey = loadedKey
        }
    }

    private func refreshBackupState() {
        DispatchQueue.global(qos: .utility).async {
            let date = BackupService.latestBackupDate
            let count = BackupService.listBackups().count
            DispatchQueue.main.async {
                latestBackupDate = date
                backupCount = count
            }
        }
    }

    private func testSelectedProvider() {
        providerStatus = nil
        isTestingProvider = true
        AIConfiguration.provider = selectedProvider
        AIConfiguration.reasoningEffort = selectedReasoningEffort.wrappedValue
        AIConfiguration.verbosity = selectedVerbosity.wrappedValue
        AIConfiguration.webSearchMode = selectedWebSearchMode.wrappedValue
        AIConfiguration.junaliBaseURL = junaliBaseURL
        AIConfiguration.codexCLIPath = codexCLIPath
        AIConfiguration.setModel(activeModel.wrappedValue, for: selectedProvider)

        Task {
            let status = await AIProviderService.status(for: selectedProvider)
            await MainActor.run {
                providerStatus = status
                isTestingProvider = false
            }
        }
    }

    // MARK: - Notifications
    /// Scheduling does nothing until macOS grants permission, so a toggle only
    /// turns on once it has been granted.
    private func notificationToggle(
        _ flag: Binding<Bool>,
        enable: @escaping @MainActor () -> Void,
        disable: @escaping @MainActor () -> Void
    ) -> Binding<Bool> {
        Binding(
            get: { flag.wrappedValue },
            set: { isOn in
                guard isOn else {
                    flag.wrappedValue = false
                    disable()
                    return
                }
                Task { @MainActor in
                    let granted = await NotificationService.requestPermission()
                    notificationsBlocked = !granted
                    guard granted else { return }
                    flag.wrappedValue = true
                    enable()
                }
            }
        )
    }

    private var notificationSection: some View {
        SettingsGroup {
            if let p = profile {
                SettingsToggle("Daily reminder", isOn: notificationToggle($dailyReminderEnabled, enable: {
                    NotificationService.scheduleDailyReminder(hour: p.notificationHour, minute: p.notificationMinute, dueCount: 0)
                }, disable: {
                    NotificationService.cancelNotification(withIdentifier: NotificationConfig.default.dailyReminderID)
                }))

                if dailyReminderEnabled {
                    DatePicker("Time", selection: Binding(
                        get: {
                            var comps = DateComponents(); comps.hour = p.notificationHour; comps.minute = p.notificationMinute
                            return Calendar.current.date(from: comps) ?? Date()
                        },
                        set: { date in
                            p.notificationHour = Calendar.current.component(.hour, from: date)
                            p.notificationMinute = Calendar.current.component(.minute, from: date)
                            persistChanges()
                            NotificationService.scheduleDailyReminder(hour: p.notificationHour, minute: p.notificationMinute, dueCount: 0)
                        }
                    ), displayedComponents: .hourAndMinute)
                }

                SettingsToggle("Streak warning at 9 PM", isOn: notificationToggle($streakWarningEnabled, enable: {
                    NotificationService.refreshStreakWarning(for: p)
                }, disable: {
                    NotificationService.cancelNotification(withIdentifier: NotificationConfig.default.streakWarningID)
                }))

                if notificationsBlocked {
                    HStack {
                        Text("Notifications are blocked for Noot Study.")
                            .font(.caption)
                            .foregroundStyle(IBColors.danger)
                        Spacer()
                        Button("Open System Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        } header: {
            Label("Notifications", systemImage: "bell.fill")
        }
    }

    // MARK: - Data
    private var dataSection: some View {
        SettingsGroup {
            Button {
                showPlaceholderCleanupConfirmation = true
            } label: {
                Label("Delete Generated Placeholder Cards", systemImage: "rectangle.stack.badge.minus")
            }
            .disabled(isCleaningPlaceholders || placeholderCardCount == 0)
            .alert("Delete Generated Placeholder Cards?", isPresented: $showPlaceholderCleanupConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete \(placeholderCardCount) Cards", role: .destructive) {
                    deletePlaceholderCards()
                }
            } message: {
                Text("This removes only cards whose front starts with ‘What are the key concepts and learning objectives for’. A backup is saved first; custom and reviewed cards are not selected.")
            }

            Button("Reset All Data", role: .destructive) {
                showResetConfirmation = true
            }
            .alert("Reset All Data?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    resetAllData()
                }
            } message: {
                Text("A fresh backup will be saved to Documents first so a mistaken reset can be undone. This will delete all your study data including subjects, cards, and progress.")
            }
        } header: {
            Label("Data", systemImage: "trash")
        }
    }

    private var placeholderCardCount: Int {
        subjects.flatMap(\.cards).filter { card in
            card.front.hasPrefix("What are the key concepts and learning objectives for ")
        }.count
    }

    private func deletePlaceholderCards() {
        guard !isCleaningPlaceholders else { return }
        isCleaningPlaceholders = true
        do {
            _ = try BackupService.exportBackup(context: context)
            let cards = subjects.flatMap(\.cards).filter {
                $0.front.hasPrefix("What are the key concepts and learning objectives for ")
            }
            for card in cards {
                card.subject?.cards.removeAll { $0.id == card.id }
                context.delete(card)
            }
            try context.save()
            backupStatus = "Deleted \(cards.count) generated placeholder cards (backup saved first)."
            IBHaptics.success()
        } catch {
            context.rollback()
            backupStatus = "Placeholder cleanup failed: \(error.localizedDescription)"
            IBHaptics.error()
        }
        isCleaningPlaceholders = false
    }
    
    private func resetAllData() {
        guard !isResetting else { return }
        isResetting = true
        do {
            // Never wipe the only copy of data we can still back up. Write a
            // fresh backup first and abort if it cannot be saved, otherwise a
            // mistaken reset would permanently destroy chat history and ADHD
            // settings with no recovery path.
            _ = try BackupService.exportBackup(context: context)

            try deleteAll(UserProfile.self)
            try deleteAll(Subject.self)
            try deleteAll(StudyCard.self)
            try deleteAll(ReviewSession.self)
            try deleteAll(StudySession.self)
            try deleteAll(StudyActivity.self)
            try deleteAll(Achievement.self)
            try deleteAll(Grade.self)
            try deleteAll(StudyPlan.self)
            try deleteAll(ARIAMemory.self)
            try deleteAll(ARIAChatSession.self)
            try deleteAll(ChatMessage.self)
            try deleteAll(SubjectTrack.self)
            try deleteAll(UnitState.self)
            try deleteAll(CurriculumNode.self)
            try deleteAll(WeeklyChallenge.self)

            // Clear UserDefaults
            if let domain = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: domain)
            }
            _ = KeychainService.deleteAPIKey()
            _ = KeychainService.deleteJunaliAPIKey()

            try context.save()
            // The @State copy is not backed by UserDefaults, so re-read it now
            // that the domain (and the "adhdMedicationSettings" key) is gone.
            adhdMedSettings = .default
            refreshViewState()
            backupStatus = "✓ All data reset (a backup was saved first)"
            IBHaptics.success()
        } catch {
            context.rollback()
            backupStatus = "✗ Reset failed: \(error.localizedDescription)"
            IBHaptics.error()
        }
        isResetting = false
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        let all = try context.fetch(FetchDescriptor<T>())
        for model in all {
            context.delete(model)
        }
    }

    private func persistChanges() {
        do {
            try context.save()
            settingsSaveError = nil
        } catch {
            // Surface the failure without rolling back the shared context:
            // a single failed settings save must not discard unrelated pending
            // work. The mutated setting remains pending and will autosave.
            backupStatus = "✗ Could not save changes: \(error.localizedDescription)"
            settingsSaveError = "Could not save settings: \(error.localizedDescription)"
        }
    }

    private func scheduleProfileSave() {
        profileSaveTask?.cancel()
        profileSaveTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }
            persistChanges()
        }
    }

    // MARK: - About
    private var aboutSection: some View {
        SettingsGroup {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            LabeledContent("Platform", value: "macOS 14.0+")
            LabeledContent("AI Provider") {
                Text(selectedProvider.displayName)
                    .foregroundStyle(.tint)
            }
            LabeledContent("AI Model") {
                Text(activeModel.wrappedValue)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tint)
            }
            LabeledContent("Reasoning", value: selectedReasoningEffort.wrappedValue.displayName)
            LabeledContent("Answer Detail", value: selectedVerbosity.wrappedValue.displayName)
        } header: {
            Label("About", systemImage: "info.circle")
        }
    }

}

// Shared settings controls keep labels above controls at every window width.
private struct SettingsGroup<Content: View, Header: View, Footer: View>: View {
    let content: Content
    let header: Header
    let footer: Footer

    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header,
         @ViewBuilder footer: () -> Footer) {
        self.content = content()
        self.header = header()
        self.footer = footer()
    }

    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) where Footer == EmptyView {
        self.init(content: content, header: header, footer: { EmptyView() })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header.labelStyle(.titleOnly).font(IBTypography.sectionTitle).foregroundStyle(IBColors.ink)
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .font(.callout)
            .foregroundStyle(IBColors.ink)
            .toggleStyle(.switch)
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .background(IBColors.surface, in: RoundedRectangle(cornerRadius: 14))
            
            footer.font(.caption).foregroundStyle(IBColors.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SettingsToggle: View {
    let title: String
    let detail: String?
    @Binding var isOn: Bool

    init(_ title: String, detail: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        _isOn = isOn
    }

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(IBColors.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch)
        }
    }
}

private struct SettingsField<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.callout.weight(.semibold)).foregroundStyle(IBColors.ink)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

private struct SettingsChoices<Option: Hashable, Value: Hashable>: View {
    let values: [Option]
    @Binding var selection: Value
    let value: (Option) -> Value
    let label: (Option) -> String

    init(values: [Option], selection: Binding<Value>, value: @escaping (Option) -> Value,
         label: @escaping (Option) -> String) {
        self.values = values
        _selection = selection
        self.value = value
        self.label = label
    }

    init(values: [Option], selection: Binding<Value>, label: @escaping (Option) -> String) where Option == Value {
        self.init(values: values, selection: selection, value: { $0 }, label: label)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                ForEach(values, id: \.self) { option in
                    choice(option).fixedSize(horizontal: true, vertical: false)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 6)], spacing: 6) {
                ForEach(values, id: \.self) { option in choice(option) }
            }
        }
    }

    private func choice(_ option: Option) -> some View {
        let selected = selection == value(option)
        return Button { selection = value(option) } label: {
            Text(label(option))
                .font(.system(size: 12, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? IBColors.accent : IBColors.inkSecondary)
                .padding(.horizontal, 10)
                .frame(minHeight: 28)
                .frame(maxWidth: .infinity)
                .background(selected ? IBColors.highlight : IBColors.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: IBRadius.sm))
                .contentShape(Rectangle())
        }
        .buttonStyle(IBPressStyle())
        .accessibilityLabel(label(option))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Gemini Model Picker View
struct GeminiModelPickerView: View {
    @Binding var selectedModel: String
    @Environment(\.dismiss) private var dismiss
    @State private var models: [GeminiModel] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""

    private var filteredModels: [GeminiModel] {
        if searchText.isEmpty { return models }
        return models.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var flashModels: [GeminiModel] { filteredModels.filter { $0.id.contains("flash") } }
    private var proModels: [GeminiModel] { filteredModels.filter { $0.id.contains("pro") && !$0.id.contains("flash") } }
    private var otherModels: [GeminiModel] { filteredModels.filter { !$0.id.contains("flash") && !$0.id.contains("pro") } }

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Fetching models…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if let error = errorMessage {
                    Section("Error") {
                        Text(error).foregroundStyle(IBColors.danger)
                        Button("Retry") { loadModels() }
                    }
                } else {
                    Section {
                        TextField("Search models…", text: $searchText)
                    }

                    Section("Current Model") {
                        Text(selectedModel)
                            .font(.system(.body, design: .monospaced))
                    }

                    if !flashModels.isEmpty {
                        modelSection("Flash Models", subtitle: "Fast & efficient", models: flashModels)
                    }
                    if !proModels.isEmpty {
                        modelSection("Pro Models", subtitle: "Most capable", models: proModels)
                    }
                    if !otherModels.isEmpty {
                        modelSection("Other Models", subtitle: "Experimental & specialized", models: otherModels)
                    }
                }
            }
            .navigationTitle("Select Model")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { loadModels() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear { loadModels() }
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    private func modelSection(_ title: String, subtitle: String, models: [GeminiModel]) -> some View {
        Section {
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(models, id: \.id) { model in
                let isSelected = model.id == selectedModel
                Button {
                    selectedModel = model.id
                    IBHaptics.medium()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.displayName)
                            Text(model.id)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Label(model.tokenInfo, systemImage: "arrow.left.arrow.right")
                                    .font(.caption)
                                if model.supportsStreaming {
                                    Label("Stream", systemImage: "waveform")
                                        .font(.caption)
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        } header: {
            Text(title)
        }
    }

    private func loadModels() {
        guard let apiKey = KeychainService.loadAPIKey(), !apiKey.isEmpty else {
            errorMessage = "Please add your Gemini API key first in Settings → ARIA Configuration."
            isLoading = false
            return
        }
        isLoading = true; errorMessage = nil
        Task {
            do {
                let fetched = try await GeminiService.listModels(apiKey: apiKey)
                await MainActor.run { models = fetched; isLoading = false }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription; isLoading = false }
            }
        }
    }
}

// MARK: - Report Upload View
struct ReportUploadView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var subjects: [Subject]
    @Query private var profiles: [UserProfile]

    @State private var grades: [String: [String: Int]] = [:]
    @State private var saveError: String?
    let components = ["Paper 1", "Paper 2", "IA", "Overall"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Upload Report Card")
                            .font(.title2.bold())
                        Text("Enter your latest grades — ARIA will auto-analyse gaps and update your rank")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)

                    ForEach(subjects, id: \.id) { subject in
                        subjectGradeCard(subject)
                    }

                    Button { saveAllGrades() } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Save Report & Auto-Update Rank")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                .padding(.top)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { initGrades() }
            .alert("Could Not Save Report", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "Your grades could not be saved.")
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }

    private func subjectGradeCard(_ subject: Subject) -> some View {
        let color = IBColors.inkTertiary
        return GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle().fill(color).frame(width: 10, height: 10)
                    Text(subject.name).font(.headline)
                    Text(subject.level)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(components, id: \.self) { comp in
                    HStack {
                        Text(comp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .leading)
                        Spacer()
                        ForEach(1...7, id: \.self) { score in
                            let isSelected = grades[subject.name]?[comp] == score
                            Button {
                                grades[subject.name, default: [:]][comp] = score; IBHaptics.light()
                            } label: {
                                Text("\(score)")
                                    .font(.system(size: 14, weight: isSelected ? .bold : .regular))
                                    .foregroundColor(isSelected ? .white : .secondary)
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(isSelected ? color : Color.secondary.opacity(0.15)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }.padding(.horizontal)
    }

    private func initGrades() {
        for subject in subjects {
            var subGrades: [String: Int] = [:]
            for grade in subject.grades { subGrades[grade.component] = grade.score }
            grades[subject.name] = subGrades
        }
    }

    private func saveAllGrades() {
        var createdGrades: [Grade] = []
        for subject in subjects {
            guard let subGrades = grades[subject.name] else { continue }
            for (comp, score) in subGrades {
                if let existing = subject.grades.first(where: { $0.component == comp }) {
                    existing.score = score; existing.date = Date()
                } else {
                    let grade = Grade(component: comp, score: score, subject: subject)
                    context.insert(grade)
                    createdGrades.append(grade)
                }
            }
        }
        if let p = profiles.first {
            p.reportLastUploaded = Date()
        }
        do {
            try context.save()
            IBHaptics.success()
            dismiss()
        } catch {
            // Undo only the grades we inserted; a failed save must not roll
            // back unrelated pending work in the shared context.
            for grade in createdGrades {
                context.delete(grade)
            }
            saveError = error.localizedDescription
        }
    }
}
