import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query private var subjects: [Subject]
    @Query private var studyCards: [StudyCard]
    @Query private var reviewSessions: [ReviewSession]
    @Query private var studySessions: [StudySession]
    @Query private var studyActivities: [StudyActivity]
    @Query private var achievements: [Achievement]
    @Query private var grades: [Grade]
    @Query private var studyPlans: [StudyPlan]
    @Query private var ariaMemories: [ARIAMemory]
    @Query private var ariaChatSessions: [ARIAChatSession]
    @Query private var chatMessages: [ChatMessage]
    @Query private var subjectTracks: [SubjectTrack]
    @Query private var unitStates: [UnitState]
    @Query private var curriculumNodes: [CurriculumNode]
    @Query private var weeklyChallenges: [WeeklyChallenge]
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
    @State private var presetApplied = false
    @State private var backupStatus = ""
    @State private var showBackups = false
    @State private var isBackingUp = false
    @State private var showModelPicker = false
    @State private var backupCount = 0
    @State private var latestBackupDate: Date?
    @State private var showResetConfirmation = false
    @State private var isResetting = false

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
    @AppStorage("ariaMaxTokens") private var ariaMaxTokens = 4096
    @AppStorage("ariaAutoCompact") private var ariaAutoCompact = true
    @AppStorage("ariaContextWindow") private var ariaContextWindow = 20

    // Study Settings
    @AppStorage("showMasteryPercent") private var showMasteryPercent = true
    @AppStorage("hapticFeedback") private var hapticFeedback = true
    @AppStorage("autoPlayNext") private var autoPlayNext = false
    @AppStorage("showDueCountBadge") private var showDueCountBadge = true
    @AppStorage("reviewOrder") private var reviewOrder = "spaced"

    @State private var adhdMedSettings: ADHDMedicationSettings = .default
    @State private var showMedicationPicker = false

    private var profile: UserProfile? { profiles.first }

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
        VStack(spacing: 0) {
            StudioPageHeader(
                eyebrow: "Workspace controls",
                title: "Settings",
                subtitle: "Configure your study plan, assistant, notifications, and local data without losing the thread of your work.",
                symbol: "slider.horizontal.3",
                tint: IBColors.electricBlue
            ) {
                StudioPill(title: "STUDY STUDIO", tint: IBColors.electricBlue)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 18)

            Form {
                presetSection
                reportSection
                aiProviderSection
                modelConfigurationSection
                curriculumSection
                studySection
                adhdSection
                backupSection
                notificationSection
                appearanceSection
                dataSection
                aboutSection
            }
            .formStyle(.grouped)
        }
        .background(IBColors.canvas)
        .navigationTitle("Settings")
        .sheet(isPresented: $showReportUpload) { ReportUploadView() }
        .sheet(isPresented: $showModelPicker) { GeminiModelPickerView(selectedModel: $selectedModel) }
        .onAppear { refreshViewState(); adhdMedSettings = ADHDMedicationSettings.loadFromDefaults() }
        .sheet(isPresented: $showMedicationPicker) {
            MedicationPickerView(settings: $adhdMedSettings)
        }
    }

    // MARK: - Student Preset
    private var presetSection: some View {
        Section {
            if let p = profile {
                HStack(spacing: 10) {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.tint)
                    TextField("Your Name", text: Binding(
                        get: { p.studentName }, set: { p.studentName = $0; try? context.save() }
                    ))
                }

                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .foregroundStyle(.tint)
                    Picker("IB Year", selection: Binding(
                        get: { p.ibYear }, set: { p.ibYear = $0; try? context.save() }
                    )) {
                        ForEach(IBYear.allCases, id: \.self) { year in
                            Text(year.rawValue).tag(year)
                        }
                    }.pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "gauge.with.dots.needle.67percent")
                            .foregroundStyle(.tint)
                        Text("Study Intensity")
                    }
                    Picker("Intensity", selection: Binding(
                        get: { p.studyIntensity }, set: { p.studyIntensity = $0; try? context.save() }
                    )) {
                        ForEach(StudyIntensity.allCases, id: \.self) { intensity in
                            HStack { Text(intensity.emoji); Text(intensity.rawValue) }.tag(intensity)
                        }
                    }.pickerStyle(.menu)
                    Text("Suggests \(p.studyIntensity.dailyCardSuggestion) cards/day • \(String(format: "%.1f", p.studyIntensity.xpMultiplier))× XP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Image(systemName: "target")
                        .foregroundStyle(.tint)
                    Stepper("Target Score: \(p.targetIBScore)/45", value: Binding(
                        get: { p.targetIBScore }, set: { p.targetIBScore = $0; try? context.save() }
                    ), in: 12...45)
                }

                Button {
                    p.dailyGoal = p.studyIntensity.dailyCardSuggestion
                    try? context.save()
                    presetApplied = true; IBHaptics.success()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { presetApplied = false }
                } label: {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        Text("Apply Preset")
                        if presetApplied { Spacer(); Text("✓ Applied!").foregroundStyle(.green) }
                    }
                }
            }
        } header: {
            Label("Student Profile", systemImage: "graduationcap.fill")
        } footer: {
            Text("Presets auto-adjust your daily goal based on your study intensity. ARIA uses this data for personalised recommendations. Rank is earned from your review history.")
        }
    }

    // MARK: - Report Upload
    private var reportSection: some View {
        Section {
            Button { showReportUpload = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upload Report Card")
                        if let date = profile?.reportLastUploaded {
                            Text("Last updated: \(date, style: .relative) ago")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Enter grades for all subjects at once")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            Label("Report & Grades", systemImage: "chart.bar.doc.horizontal.fill")
        }
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

            Stepper("Max output: \(ariaMaxTokens) tokens", value: $ariaMaxTokens, in: 1024...65536, step: 1024)
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
                    get: { p.dailyGoal }, set: { p.dailyGoal = $0; try? context.save() }
                ), in: 5...100, step: 5)

                HStack {
                    Text("Streak Freezes"); Spacer()
                    Text("\(p.streakFreezes)")
                        .foregroundStyle(.secondary)
                    Image(systemName: "snowflake")
                        .foregroundStyle(.cyan)
                }
            }

            Picker("Review Order", selection: $reviewOrder) {
                Text("Spaced (SM-2)").tag("spaced")
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
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url = try BackupService.exportBackup(context: context)
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
            backupStatus = "✗ Restore failed: \(error.localizedDescription)"; IBHaptics.error()
        }
    }

    private func refreshViewState() {
        hasKey = KeychainService.hasAPIKey
        if hasKey, let loadedKey = KeychainService.loadAPIKey() {
            apiKey = loadedKey
        }
        hasJunaliKey = KeychainService.hasJunaliAPIKey
        if hasJunaliKey, let loadedKey = KeychainService.loadJunaliAPIKey() {
            junaliAPIKey = loadedKey
        }
        latestBackupDate = BackupService.latestBackupDate
        backupCount = BackupService.listBackups().count
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
                        try? context.save()
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
                Text("This will delete all your study data including subjects, cards, and progress. This action cannot be undone.")
            }
        } header: {
            Label("Data", systemImage: "trash")
        }
    }
    
    private func resetAllData() {
        isResetting = true
        
        // Clear all SwiftData
        for profile in profiles { context.delete(profile) }
        for subject in subjects { context.delete(subject) }
        for card in studyCards { context.delete(card) }
        for session in reviewSessions { context.delete(session) }
        for session in studySessions { context.delete(session) }
        for activity in studyActivities { context.delete(activity) }
        for achievement in achievements { context.delete(achievement) }
        for grade in grades { context.delete(grade) }
        for plan in studyPlans { context.delete(plan) }
        for memory in ariaMemories { context.delete(memory) }
        for session in ariaChatSessions { context.delete(session) }
        for message in chatMessages { context.delete(message) }
        for track in subjectTracks { context.delete(track) }
        for state in unitStates { context.delete(state) }
        for node in curriculumNodes { context.delete(node) }
        for challenge in weeklyChallenges { context.delete(challenge) }
        
        // Clear UserDefaults
        let domain = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: domain)
        _ = KeychainService.deleteAPIKey()
        _ = KeychainService.deleteJunaliAPIKey()
        
        try? context.save()
        
        isResetting = false
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
            LabeledContent("Max Tokens", value: "\(ariaMaxTokens)")
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
        for subject in subjects {
            guard let subGrades = grades[subject.name] else { continue }
            for (comp, score) in subGrades {
                if let existing = subject.grades.first(where: { $0.component == comp }) {
                    existing.score = score; existing.date = Date()
                } else {
                    let grade = Grade(component: comp, score: score, subject: subject)
                    context.insert(grade)
                }
            }
        }
        if let p = profiles.first {
            p.reportLastUploaded = Date()
        }
        try? context.save(); IBHaptics.success(); dismiss()
    }
}
