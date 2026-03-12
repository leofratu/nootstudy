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
    @State private var apiKey = ""
    @State private var showAPIKey = false
    @State private var hasKey = false
    @State private var savedConfirmation = false
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

    // ADHD Settings
    @AppStorage("adhdDoseMg") private var adhdDoseMg = 10

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        Form {
            presetSection
            reportSection
            ariaSection
            geminiModelSection
            studySection
            adhdSection
            backupSection
            notificationSection
            appearanceSection
            dataSection
            aboutSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .sheet(isPresented: $showReportUpload) { ReportUploadView() }
        .sheet(isPresented: $showModelPicker) { GeminiModelPickerView(selectedModel: $selectedModel) }
        .onAppear { refreshViewState() }
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
                    p.applyPreset(); try? context.save()
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
            Text("Presets auto-adjust your daily goal, starting rank, and XP based on your study intensity and IB year. ARIA uses this data for personalised recommendations.")
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

            Button { autoRankFromGrades() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI Auto-Update Rank")
                        Text("ARIA analyses your grades & reviews to set your rank")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Label("Report & Grades", systemImage: "chart.bar.doc.horizontal.fill")
        }
    }

    // MARK: - ARIA Configuration
    private var ariaSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Gemini API Key")
                    .font(.headline)
                HStack {
                    if showAPIKey {
                        TextField("Enter API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("Enter API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button { showAPIKey.toggle() } label: {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                HStack {
                    Button("Save to Keychain") {
                        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedKey.isEmpty else { return }
                        if KeychainService.saveAPIKey(trimmedKey) {
                            hasKey = true; savedConfirmation = true; IBHaptics.success()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedConfirmation = false }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    if savedConfirmation {
                        Text("✓ Saved")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    Spacer()
                    if hasKey {
                        Button("Delete Key", role: .destructive) {
                            _ = KeychainService.deleteAPIKey(); hasKey = false; apiKey = ""; IBHaptics.warning()
                        }
                        .controlSize(.small)
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: hasKey ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(hasKey ? .green : .orange)
                        .font(.caption)
                    Text(hasKey ? "API key stored in Keychain" : "No API key configured — ARIA requires a Gemini API key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            NavigationLink("ARIA Memory Manager") { ARIAMemoryView() }

            VStack(alignment: .leading, spacing: 4) {
                Stepper("Context Window: \(ariaContextWindow) messages", value: $ariaContextWindow, in: 5...50, step: 5)
                Text("How many past messages ARIA remembers per conversation. More = better context, higher token usage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: $ariaAutoCompact) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Compact Memory")
                    Text("Automatically summarise old conversations to save tokens")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("ARIA Configuration", systemImage: "brain.head.profile")
        }
    }

    // MARK: - Gemini Model Picker
    private var geminiModelSection: some View {
        Section {
            Button { showModelPicker = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "cpu.fill")
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI Model")
                        Text(selectedModel)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tint)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Temperature: \(String(format: "%.1f", ariaTemperature))")
                    Spacer()
                    Button("Reset") {
                        ariaTemperature = 0.7
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
                Slider(value: $ariaTemperature, in: 0...2, step: 0.1)
                    .tint(.accentColor)
                Text(temperatureDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Stepper("Max Output: \(ariaMaxTokens) tokens", value: $ariaMaxTokens, in: 1024...65536, step: 1024)
                Text("Maximum length of ARIA's responses. More tokens = longer answers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label("Gemini Provider", systemImage: "sparkle")
        } footer: {
            Text("Select your preferred Gemini model. Flash models are faster; Pro models are more capable. Temperature controls creativity (0 = focused, 2 = creative).")
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
                    get: { p.dailyGoal }, set: { p.dailyGoal = $0 }
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
            NavigationLink {
                ADHDTrackerView()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "pills.fill")
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ADHD Med Tracker")
                        Text("Ritalin IR \(adhdDoseMg)mg • 3× daily")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Picker("Default Dose", selection: $adhdDoseMg) {
                Text("10 mg").tag(10)
                Text("20 mg").tag(20)
            }.pickerStyle(.segmented)
        } header: {
            Label("ADHD Medication", systemImage: "heart.text.clipboard")
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
        latestBackupDate = BackupService.latestBackupDate
        backupCount = BackupService.listBackups().count
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
        
        // Clear UserDefaults
        let domain = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: domain)
        
        try? context.save()
        
        isResetting = false
    }

    // MARK: - About
    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: "1.0.0")
            LabeledContent("Platform", value: "macOS 14.0+")
            LabeledContent("AI Model") {
                Text(selectedModel)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tint)
            }
            LabeledContent("Temperature", value: String(format: "%.1f", ariaTemperature))
            LabeledContent("Max Tokens", value: "\(ariaMaxTokens)")
        } header: {
            Label("About", systemImage: "info.circle")
        }
    }

    // MARK: - AI Auto-Rank
    private func autoRankFromGrades() {
        guard let p = profile else { return }
        let allGrades = subjects.flatMap { $0.grades }
        guard !allGrades.isEmpty else { IBHaptics.warning(); return }
        guard let avg = Subject.overallGradeAverage(for: subjects) else { return }
        let totalReviews = (try? context.fetchCount(FetchDescriptor<ReviewSession>())) ?? 0
        p.autoUpdateFromGrades(averageGrade: avg, totalReviews: totalReviews)
        try? context.save(); IBHaptics.success()
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
            let allGrades = subjects.flatMap { $0.grades }
            if !allGrades.isEmpty {
                if let avg = Subject.overallGradeAverage(for: subjects) {
                    let totalReviews = (try? context.fetchCount(FetchDescriptor<ReviewSession>())) ?? 0
                    p.autoUpdateFromGrades(averageGrade: avg, totalReviews: totalReviews)
                }
            }
        }
        try? context.save(); IBHaptics.success(); dismiss()
    }
}
