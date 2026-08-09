import SwiftUI
import SwiftData

struct SettingsView: View {
    private static let fixedTargetIBScore = 40

    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query private var subjects: [Subject]
    @Query(sort: \StudyPlan.scheduledDate, order: .forward) private var studyPlans: [StudyPlan]
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
    @State private var profileSaveTask: Task<Void, Never>?

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
    @AppStorage("ariaAutoCompact") private var ariaAutoCompact = true
    @AppStorage("ariaContextWindow") private var ariaContextWindow = 20

    // Study Settings
    @AppStorage("showMasteryPercent") private var showMasteryPercent = true
    @AppStorage("hapticFeedback") private var hapticFeedback = true
    @AppStorage("autoPlayNext") private var autoPlayNext = false
    @AppStorage("showDueCountBadge") private var showDueCountBadge = true
    @AppStorage("reviewOrder") private var reviewOrder = "spaced"
    @AppStorage(CalendarSyncPreferences.isEnabledKey) private var calendarSyncEnabled = false
    @AppStorage(CalendarSyncPreferences.calendarIdentifierKey) private var selectedCalendarIdentifier = ""

    @State private var calendarOptions: [CalendarSyncOption] = []
    @State private var calendarSyncStatus = ""
    @State private var isConfiguringCalendar = false

    @State private var adhdMedSettings: ADHDMedicationSettings = .default
    @State private var showMedicationPicker = false

    /// The categorized left-hand navigation for Settings.
    private enum SettingsSection: String, CaseIterable, Identifiable {
        case general = "General"
        case assistant = "AI & Memory"
        case subjects = "Subjects"
        case study = "Study"
        case data = "Data & Backup"
        case about = "About"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "person.crop.circle"
            case .assistant: return "sparkles"
            case .subjects: return "books.vertical"
            case .study: return "calendar"
            case .data: return "externaldrive"
            case .about: return "info.circle"
            }
        }
    }

    @State private var selectedSection: SettingsSection = .general

    private var profile: UserProfile? { profiles.first }

    private var sectionSummary: String {
        switch selectedSection {
        case .general: return "Your study identity, target, and report data"
        case .assistant: return "Provider, model, and response controls"
        case .subjects: return "Curriculum and subject configuration"
        case .study: return "Workload, calendar, focus, and reminders"
        case .data: return "Backups, recovery, and reset controls"
        case .about: return "Installed app and assistant details"
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
        Binding(
            get: {
                switch selectedProvider {
                case .gemini: return selectedModel
                case .junali: return junaliModel
                case .codexCLI: return codexModel
                }
            },
            set: { value in
                switch selectedProvider {
                case .gemini: selectedModel = value
                case .junali: junaliModel = value
                case .codexCLI: codexModel = value
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Settings")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IBColors.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.top, 14)

                ForEach(SettingsSection.allCases) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        Label(section.rawValue, systemImage: section.icon)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(IBColors.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 11)
                            .frame(height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedSection == section ? IBColors.surfaceHover : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(width: 194)
            .background(IBColors.canvasDeep)

            Divider()

            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 18) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedSection.rawValue)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(IBColors.ink)
                        Text(sectionSummary)
                            .font(.callout)
                            .foregroundStyle(IBColors.secondaryText)
                    }
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 16)

                Divider()

                sectionContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(IBColors.canvas)
        .navigationTitle("Settings")
        .sheet(isPresented: $showReportUpload) { ReportUploadView() }
        .sheet(isPresented: $showModelPicker) { GeminiModelPickerView(selectedModel: $selectedModel) }
        .onAppear {
            enforceFixedTarget()
            if let profile, profile.dailyGoal > ReviewDailyLimitPolicy.maximumCards {
                profile.dailyGoal = ReviewDailyLimitPolicy.maximumCards
                persistChanges()
            }
            refreshViewState()
            adhdMedSettings = ADHDMedicationSettings.loadFromDefaults()
            if calendarSyncEnabled {
                if let lastError = UserDefaults.standard.string(forKey: CalendarSyncPreferences.lastErrorKey) {
                    calendarSyncStatus = lastError
                } else if let lastSyncDate = UserDefaults.standard.object(forKey: CalendarSyncPreferences.lastSyncDateKey) as? Date {
                    calendarSyncStatus = "Last synced \(lastSyncDate.formatted(date: .abbreviated, time: .shortened))."
                }
                Task { await loadCalendarOptions() }
            }
        }
        .onDisappear {
            profileSaveTask?.cancel()
            persistChanges()
        }
        .sheet(isPresented: $showMedicationPicker) {
            MedicationPickerView(settings: $adhdMedSettings)
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .general:
            studyWorkspace
        case .assistant:
            Form { aiProviderSection; modelConfigurationSection }.formStyle(.grouped)
        case .subjects:
            Form { curriculumSection }.formStyle(.grouped)
        case .study:
            Form {
                studySection
                calendarSyncSection
                adhdSection
                notificationSection
                appearanceSection
            }
            .formStyle(.grouped)
        case .data:
            Form { backupSection; dataSection }.formStyle(.grouped)
        case .about:
            Form { aboutSection }.formStyle(.grouped)
        }
    }

    private var studyWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                workspaceBand(
                    title: "Study profile",
                    subtitle: "The settings ARIA uses to shape your study plan.",
                    symbol: "person.crop.circle",
                    tint: IBColors.electricBlue
                ) {
                    if let profile {
                        VStack(spacing: 0) {
                            HStack(spacing: 14) {
                                Label("Name", systemImage: "person")
                                    .frame(width: 150, alignment: .leading)
                                TextField("Your name", text: Binding(
                                    get: { profile.studentName },
                                    set: { profile.studentName = $0; scheduleProfileSave() }
                                ))
                                .textFieldStyle(.roundedBorder)
                            }
                            .padding(.vertical, 10)

                            Divider()

                            HStack(spacing: 14) {
                                Label("IB programme", systemImage: "calendar")
                                    .frame(width: 150, alignment: .leading)
                                Picker("IB programme", selection: Binding(
                                    get: { profile.ibYear },
                                    set: { profile.ibYear = $0; persistChanges() }
                                )) {
                                    ForEach(IBYear.allCases, id: \.self) { year in
                                        Text(year.rawValue).tag(year)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                Spacer()
                            }
                            .padding(.vertical, 10)

                            Divider()

                            HStack(spacing: 14) {
                                Label("Study intensity", systemImage: "gauge.with.dots.needle.67percent")
                                    .frame(width: 150, alignment: .leading)
                                Picker("Study intensity", selection: Binding(
                                    get: { profile.studyIntensity },
                                    set: { profile.studyIntensity = $0; persistChanges() }
                                )) {
                                    ForEach(StudyIntensity.allCases, id: \.self) { intensity in
                                        Text("\(intensity.emoji)  \(intensity.rawValue)").tag(intensity)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                Spacer()
                                Text("\(profile.studyIntensity.dailyCardSuggestion) cards/day")
                                    .font(.caption)
                                    .foregroundStyle(IBColors.secondaryText)
                            }
                            .padding(.vertical, 10)
                        }
                    }
                }

                workspaceBand(
                    title: "IB target",
                    subtitle: "Your saved diploma target is fixed for this workspace.",
                    symbol: "target",
                    tint: IBColors.teal
                ) {
                    HStack(alignment: .center, spacing: 18) {
                        Text("40 / 45")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(IBColors.ink)
                            .frame(width: 118, alignment: .leading)
                        VStack(alignment: .leading, spacing: 7) {
                            ProgressView(value: Double(Self.fixedTargetIBScore), total: 45)
                                .tint(IBColors.teal)
                            Text("Saved to your profile and used by prediction and planning surfaces.")
                                .font(.caption)
                                .foregroundStyle(IBColors.secondaryText)
                        }
                    }
                    .padding(.vertical, 8)
                }

                workspaceBand(
                    title: "Study behavior",
                    subtitle: "Keep the review flow predictable and low-friction.",
                    symbol: "rectangle.stack.badge.play",
                    tint: IBColors.gold
                ) {
                    VStack(spacing: 0) {
                        if let profile {
                            Stepper("Daily goal", value: Binding(
                                get: { profile.dailyGoal },
                                set: { profile.dailyGoal = $0; persistChanges() }
                            ), in: 5...30, step: 5)
                            .padding(.vertical, 10)
                            HStack {
                                Spacer()
                                Text("\(profile.dailyGoal) cards")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(IBColors.secondaryText)
                            }
                            .padding(.bottom, 10)
                            Divider()
                        }
                        Toggle("Start the next card automatically", isOn: $autoPlayNext)
                            .padding(.vertical, 10)
                        Divider()
                        Toggle("Show due-card count in navigation", isOn: $showDueCountBadge)
                            .padding(.vertical, 10)
                        Divider()
                        Toggle("Show mastery on recall cards", isOn: $showMasteryPercent)
                            .padding(.vertical, 10)
                    }
                }

                workspaceBand(
                    title: "Report and grades",
                    subtitle: "Bring your current subject results into the evidence model.",
                    symbol: "chart.bar.doc.horizontal",
                    tint: IBColors.coral
                ) {
                    Button {
                        showReportUpload = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.badge.plus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(IBColors.coral)
                                .frame(width: 34, height: 34)
                                .background(IBColors.coral.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Update report results")
                                    .font(.callout.weight(.bold))
                                Text(profile?.reportLastUploaded.map { "Last updated \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Enter current grades across subjects")
                                    .font(.caption)
                                    .foregroundStyle(IBColors.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(IBColors.tertiaryText)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
                }
            }
            .frame(maxWidth: 880, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func workspaceBand<Content: View>(
        title: String,
        subtitle: String,
        symbol: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(IBColors.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(IBColors.secondaryText)
                }
            }
            content()
        }
        .padding(.vertical, 4)
    }

    // MARK: - AI Provider
    private var aiProviderSection: some View {
        Section {
            Picker("Provider", selection: $selectedProviderRaw) {
                ForEach(AIProviderKind.allCases) { provider in
                    Label(provider.displayName, systemImage: provider.symbolName)
                        .tag(provider.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedProviderRaw) { _, _ in
                providerStatus = nil
                reasoningEffortRaw = AIConfiguration.normalizedReasoningEffort(
                    selectedReasoningEffort.wrappedValue,
                    for: selectedProvider
                ).rawValue
            }

            Text(selectedProvider.detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            providerCredentialEditor

            HStack(spacing: 10) {
                Button {
                    testSelectedProvider()
                } label: {
                    HStack(spacing: 6) {
                        if isTestingProvider {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "bolt.horizontal.circle")
                        }
                        Text(isTestingProvider ? "Checking" : "Check Provider")
                    }
                }
                .disabled(isTestingProvider)

                if let providerStatus {
                    Label(
                        providerStatus.message,
                        systemImage: providerStatus.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(providerStatus.isReady ? .green : .orange)
                    .lineLimit(3)
                }
            }

            NavigationLink("ARIA Memory Manager") { ARIAMemoryView() }

            VStack(alignment: .leading, spacing: 4) {
                Stepper("Context Window: \(ariaContextWindow) messages", value: $ariaContextWindow, in: 5...50, step: 5)
                Text("Past messages kept in each conversation before compacted memory is used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("Auto-Compact Older Conversation Context", isOn: $ariaAutoCompact)
        } header: {
            Label("AI Provider", systemImage: "brain.head.profile")
        } footer: {
            Text("Credentials stay in macOS Keychain. Local Codex reuses the Codex CLI sign-in and does not expose its token to IBVault.")
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
            VStack(alignment: .leading, spacing: 5) {
                TextField("Codex executable path (auto-detect when empty)", text: $codexCLIPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.callout, design: .monospaced))
                Text("Codex runs ephemerally in a read-only temporary workspace. The local development build is intentionally not App-Sandboxed so it can launch the CLI.")
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
                    if save() {
                        savedConfirmation = true
                        IBHaptics.success()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedConfirmation = false }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                if savedConfirmation {
                    Text("Saved").font(.caption).foregroundStyle(.green)
                }
                Spacer()
                if hasCredential {
                    Button("Delete Key", role: .destructive) { delete() }
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Model Configuration
    private var modelConfigurationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Model")
                    Spacer()
                    Text(selectedProvider.shortName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if selectedProvider == .gemini {
                    Button { showModelPicker = true } label: {
                        HStack {
                            Text(selectedModel).font(.system(.callout, design: .monospaced))
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                    }
                } else {
                    Picker("Preset", selection: activeModel) {
                        ForEach(AIConfiguration.knownModels[selectedProvider] ?? []) { option in
                            Text("\(option.name) · \(option.role)").tag(option.id)
                        }
                    }
                    TextField("Custom model ID", text: activeModel)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.callout, design: .monospaced))
                }
            }

            if selectedProvider != .gemini {
                Picker("Reasoning effort", selection: selectedReasoningEffort) {
                    ForEach(AIConfiguration.supportedReasoningEfforts(for: selectedProvider)) { effort in
                        Text(effort.displayName).tag(effort)
                    }
                }
                .pickerStyle(.menu)

                Text(selectedReasoningEffort.wrappedValue.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Answer detail", selection: selectedVerbosity) {
                    ForEach(AIResponseVerbosity.allCases) { verbosity in
                        Text(verbosity.displayName).tag(verbosity)
                    }
                }
                .pickerStyle(.segmented)
            }

            if selectedProvider == .codexCLI {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Web search", selection: selectedWebSearchMode) {
                        ForEach(AIWebSearchMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(selectedWebSearchMode.wrappedValue.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if selectedProvider == .gemini {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Temperature: \(String(format: "%.1f", ariaTemperature))")
                    Slider(value: $ariaTemperature, in: 0...1.5, step: 0.1)
                    Text(temperatureDescription).font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("Model & Reasoning", systemImage: "cpu")
        } footer: {
            Text("Medium is the balanced default. Increase effort for difficult synthesis or exam analysis; lower it for faster routine tutoring.")
        }
    }

    private var curriculumSection: some View {
        Section {
            ForEach(subjects.sorted { $0.name < $1.name }, id: \.id) { subject in
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(hex: subject.accentColorHex))
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
    private var studySection: some View {
        Section {
            if let p = profile {
                Stepper("Daily Goal: \(p.dailyGoal) cards", value: Binding(
                    get: { p.dailyGoal }, set: { p.dailyGoal = $0; persistChanges() }
                ), in: 5...30, step: 5)

                HStack {
                    Text("Streak Freezes"); Spacer()
                    Text("\(p.streakFreezes)")
                        .foregroundStyle(.secondary)
                    Image(systemName: "snowflake")
                        .foregroundStyle(.cyan)
                }
            }

            Picker("Review Order", selection: $reviewOrder) {
                Text("Spaced (FSRS)").tag("spaced")
                Text("Weakest First").tag("weakest")
                Text("Random Shuffle").tag("random")
            }

            Toggle(isOn: $autoPlayNext) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Advance Cards")
                    Text("Automatically show next card after rating")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle("Show Mastery % on Cards", isOn: $showMasteryPercent)

            Toggle("Due Count Badge", isOn: $showDueCountBadge)
        } header: {
            Label("Study", systemImage: "book.fill")
        }
    }

    private var calendarSyncSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { calendarSyncEnabled },
                set: { newValue in
                    if newValue {
                        Task { await enableCalendarSync() }
                    } else {
                        calendarSyncEnabled = false
                        calendarSyncStatus = "Sync paused. Existing calendar events were kept."
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Google Calendar Sync")
                    Text("Keep planned study sessions aligned with a calendar on your Google account")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if calendarSyncEnabled || isConfiguringCalendar {
                if calendarOptions.isEmpty {
                    HStack {
                        Text("Calendar")
                        Spacer()
                        if isConfiguringCalendar {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Load Calendars") {
                                Task { await loadCalendarOptions() }
                            }
                        }
                    }
                } else {
                    Picker("Calendar", selection: $selectedCalendarIdentifier) {
                        ForEach(calendarOptions) { option in
                            Text(option.displayName).tag(option.id)
                        }
                    }
                    .onChange(of: selectedCalendarIdentifier) { _, _ in
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
            Text("Choose a writable calendar from the Google account connected in macOS System Settings. Noot only manages events created for Noot study plans.")
        }
    }

    @MainActor
    private func enableCalendarSync() async {
        isConfiguringCalendar = true
        calendarSyncStatus = "Requesting calendar access..."
        defer { isConfiguringCalendar = false }

        do {
            try await loadCalendarOptions(keepProgressVisible: true)
            guard !calendarOptions.isEmpty else {
                calendarSyncEnabled = false
                calendarSyncStatus = "No writable calendars found. Add your Google account in macOS System Settings first."
                return
            }

            if !calendarOptions.contains(where: { $0.id == selectedCalendarIdentifier }) {
                selectedCalendarIdentifier = calendarOptions[0].id
            }
            calendarSyncEnabled = true
            try await CalendarSyncService.shared.sync(plans: studyPlans)
            calendarSyncStatus = syncSuccessMessage()
            NotificationCenter.default.post(name: .calendarSyncRequested, object: nil)
        } catch {
            calendarSyncEnabled = false
            CalendarSyncPreferences.recordFailure(error)
            calendarSyncStatus = error.localizedDescription
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
        do {
            try await loadCalendarOptions(keepProgressVisible: false)
            calendarSyncStatus = calendarOptions.isEmpty
                ? "No writable calendars found."
                : "Choose the calendar that belongs to your Google account."
        } catch {
            CalendarSyncPreferences.recordFailure(error)
            calendarSyncStatus = error.localizedDescription
        }
    }

    @MainActor
    private func syncCalendarsNow() async {
        guard calendarSyncEnabled, !selectedCalendarIdentifier.isEmpty else { return }
        isConfiguringCalendar = true
        defer { isConfiguringCalendar = false }

        do {
            try await CalendarSyncService.shared.sync(plans: studyPlans)
            calendarSyncStatus = syncSuccessMessage()
        } catch {
            CalendarSyncPreferences.recordFailure(error)
            calendarSyncStatus = error.localizedDescription
        }
    }

    private func syncSuccessMessage() -> String {
        "Synced \(studyPlans.count) study session\(studyPlans.count == 1 ? "" : "s") just now."
    }

    // MARK: - ADHD Section
    private var adhdSection: some View {
        Section {
            Button {
                showMedicationPicker = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "pills.fill")
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ADHD Medication Tracker")
                        if adhdMedSettings.isEnabled && adhdMedSettings.medicationType != .none {
                            Text("\(adhdMedSettings.medicationType.displayName) \(adhdMedSettings.doseMg)mg • \(adhdMedSettings.dailyDoses)× daily")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Configure medication for focus window predictions")
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
                        Text("Interactive plasma level visualization")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
        Section {
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
                        .foregroundStyle(.green)
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
                        .foregroundStyle(.orange)
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
                    .foregroundStyle(backupStatus.hasPrefix("✓") ? .green : .red)
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
    private var notificationSection: some View {
        Section {
            if let p = profile {
                DatePicker("Daily Reminder", selection: Binding(
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

                Button("Enable Streak Warnings") {
                    NotificationService.scheduleStreakWarning(); IBHaptics.light()
                }
            }
        } header: {
            Label("Notifications", systemImage: "bell.fill")
        }
    }

    // MARK: - Appearance
    private var appearanceSection: some View {
        Section {
            Toggle(isOn: $hapticFeedback) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .foregroundStyle(.tint)
                    Text("Haptic Feedback")
                }
            }
        } header: {
            Label("Appearance & Feel", systemImage: "paintbrush.fill")
        }
    }

    // MARK: - Data
    private var dataSection: some View {
        Section {
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
        } catch {
            // Surface the failure without rolling back the shared context:
            // a single failed settings save must not discard unrelated pending
            // work. The mutated setting remains pending and will autosave.
            backupStatus = "✗ Could not save changes: \(error.localizedDescription)"
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
        Section {
            LabeledContent("Version", value: "1.0.0")
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
                        Text(error).foregroundStyle(.red)
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
        let color = Color(hex: subject.accentColorHex)
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
                                    .font(.system(size: 14, weight: isSelected ? .bold : .regular, design: .rounded))
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
