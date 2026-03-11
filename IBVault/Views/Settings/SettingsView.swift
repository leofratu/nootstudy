import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query private var subjects: [Subject]
    @State private var apiKey = ""
    @State private var showAPIKey = false
    @State private var hasKey = KeychainService.hasAPIKey
    @State private var savedConfirmation = false
    @State private var showReportUpload = false
    @State private var presetApplied = false
    @State private var backupStatus = ""
    @State private var showBackups = false
    @State private var isBackingUp = false
    @State private var showModelPicker = false

    // ARIA Settings
    @AppStorage("geminiModel") private var selectedModel = "gemini-2.0-flash"
    @AppStorage("ariaTemperature") private var ariaTemperature = 0.7
    @AppStorage("ariaMaxTokens") private var ariaMaxTokens = 4096
    @AppStorage("ariaAutoCompact") private var ariaAutoCompact = true
    @AppStorage("ariaContextWindow") private var ariaContextWindow = 20  // messages

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
        .navigationTitle("Settings")
        .sheet(isPresented: $showReportUpload) { ReportUploadView() }
        .sheet(isPresented: $showModelPicker) { GeminiModelPickerView(selectedModel: $selectedModel) }
    }

    // MARK: - Student Preset
    private var presetSection: some View {
        Section {
            if let p = profile {
                HStack {
                    Image(systemName: "person.fill").foregroundColor(IBColors.electricBlue)
                    TextField("Your Name", text: Binding(
                        get: { p.studentName }, set: { p.studentName = $0; try? context.save() }
                    )).foregroundColor(IBColors.softWhite)
                }
                HStack {
                    Image(systemName: "calendar").foregroundColor(IBColors.electricBlue)
                    Picker("IB Year", selection: Binding(
                        get: { p.ibYear }, set: { p.ibYear = $0; try? context.save() }
                    )) {
                        ForEach(IBYear.allCases, id: \.self) { year in
                            Text(year.rawValue).tag(year)
                        }
                    }.pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: IBSpacing.sm) {
                    HStack {
                        Image(systemName: "gauge.with.dots.needle.67percent").foregroundColor(IBColors.electricBlue)
                        Text("Study Intensity").foregroundColor(IBColors.softWhite)
                    }
                    Picker("Intensity", selection: Binding(
                        get: { p.studyIntensity }, set: { p.studyIntensity = $0; try? context.save() }
                    )) {
                        ForEach(StudyIntensity.allCases, id: \.self) { intensity in
                            HStack { Text(intensity.emoji); Text(intensity.rawValue) }.tag(intensity)
                        }
                    }.pickerStyle(.segmented)
                    Text("Suggests \(p.studyIntensity.dailyCardSuggestion) cards/day • \(String(format: "%.1f", p.studyIntensity.xpMultiplier))× XP")
                        .font(.system(size: 11)).foregroundColor(IBColors.mutedGray)
                }

                HStack {
                    Image(systemName: "target").foregroundColor(IBColors.electricBlue)
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
                        if presetApplied { Spacer(); Text("✓ Applied!").foregroundColor(IBColors.success) }
                    }.font(IBTypography.captionBold).foregroundColor(IBColors.electricBlue)
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
                HStack {
                    Image(systemName: "doc.text.fill").foregroundColor(IBColors.electricBlue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upload Report Card").foregroundColor(IBColors.softWhite)
                        if let date = profile?.reportLastUploaded {
                            Text("Last updated: \(date, style: .relative) ago")
                                .font(.system(size: 11)).foregroundColor(IBColors.mutedGray)
                        } else {
                            Text("Enter grades for all subjects at once")
                                .font(.system(size: 11)).foregroundColor(IBColors.mutedGray)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundColor(IBColors.mutedGray)
                }
            }

            Button { autoRankFromGrades() } label: {
                HStack {
                    Image(systemName: "sparkles").foregroundColor(IBColors.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI Auto-Update Rank").foregroundColor(IBColors.softWhite)
                        Text("ARIA analyses your grades & reviews to set your rank")
                            .font(.system(size: 11)).foregroundColor(IBColors.mutedGray)
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
            // API Key
            VStack(alignment: .leading, spacing: IBSpacing.sm) {
                Text("Gemini API Key").font(IBTypography.captionBold).foregroundColor(IBColors.softWhite)
                HStack {
                    if showAPIKey {
                        TextField("Enter API Key", text: $apiKey).textFieldStyle(.plain).font(IBTypography.mono)
                    } else {
                        SecureField("Enter API Key", text: $apiKey).textFieldStyle(.plain)
                    }
                    Button { showAPIKey.toggle() } label: {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye").foregroundColor(IBColors.mutedGray)
                    }
                }
                HStack {
                    Button("Save to Keychain") {
                        if KeychainService.saveAPIKey(apiKey) {
                            hasKey = true; savedConfirmation = true; IBHaptics.success()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedConfirmation = false }
                        }
                    }.font(IBTypography.captionBold).foregroundColor(IBColors.electricBlue)
                    if savedConfirmation { Text("✓ Saved").font(IBTypography.caption).foregroundColor(IBColors.success) }
                    Spacer()
                    if hasKey {
                        Button("Delete") {
                            _ = KeychainService.deleteAPIKey(); hasKey = false; apiKey = ""; IBHaptics.warning()
                        }.font(IBTypography.caption).foregroundColor(IBColors.danger)
                    }
                }
                Text(hasKey ? "✓ API key stored in Keychain" : "No API key configured — ARIA requires a Gemini API key")
                    .font(.system(size: 11)).foregroundColor(hasKey ? IBColors.success : IBColors.mutedGray)
            }

            NavigationLink("ARIA Memory Manager") { ARIAMemoryView() }

            // Context Window Size
            VStack(alignment: .leading, spacing: 4) {
                Stepper("Context Window: \(ariaContextWindow) messages", value: $ariaContextWindow, in: 5...50, step: 5)
                Text("How many past messages ARIA remembers per conversation. More = better context, higher token usage.")
                    .font(.system(size: 10)).foregroundColor(IBColors.mutedGray)
            }

            // Auto-compact toggle
            Toggle(isOn: $ariaAutoCompact) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Compact Memory").foregroundColor(IBColors.softWhite)
                    Text("Automatically summarise old conversations to save tokens")
                        .font(.system(size: 10)).foregroundColor(IBColors.mutedGray)
                }
            }.tint(IBColors.electricBlue)

        } header: {
            Label("ARIA Configuration", systemImage: "brain.head.profile")
        }
    }

    // MARK: - Gemini Model Picker
    private var geminiModelSection: some View {
        Section {
            Button { showModelPicker = true } label: {
                HStack {
                    Image(systemName: "cpu.fill").foregroundColor(IBColors.electricBlue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI Model").foregroundColor(IBColors.softWhite)
                        Text(selectedModel)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(IBColors.electricBlue)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundColor(IBColors.mutedGray)
                }
            }

            // Temperature
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Temperature: \(String(format: "%.1f", ariaTemperature))")
                        .foregroundColor(IBColors.softWhite)
                    Spacer()
                    Button("Reset") { ariaTemperature = 0.7 }
                        .font(.system(size: 11)).foregroundColor(IBColors.electricBlue)
                }
                Slider(value: $ariaTemperature, in: 0...2, step: 0.1)
                    .tint(IBColors.electricBlue)
                Text(temperatureDescription)
                    .font(.system(size: 10)).foregroundColor(IBColors.mutedGray)
            }

            // Max Tokens
            VStack(alignment: .leading, spacing: 4) {
                Stepper("Max Output: \(ariaMaxTokens) tokens", value: $ariaMaxTokens, in: 1024...65536, step: 1024)
                Text("Maximum length of ARIA's responses. More tokens = longer answers.")
                    .font(.system(size: 10)).foregroundColor(IBColors.mutedGray)
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
                    Text("\(p.streakFreezes)").foregroundColor(IBColors.warning)
                    Image(systemName: "snowflake").foregroundColor(IBColors.electricBlueLight)
                }
            }

            // Review order
            Picker("Review Order", selection: $reviewOrder) {
                Text("Spaced (SM-2)").tag("spaced")
                Text("Weakest First").tag("weakest")
                Text("Random Shuffle").tag("random")
            }

            Toggle(isOn: $autoPlayNext) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Advance Cards").foregroundColor(IBColors.softWhite)
                    Text("Automatically show next card after rating")
                        .font(.system(size: 10)).foregroundColor(IBColors.mutedGray)
                }
            }.tint(IBColors.electricBlue)

            Toggle(isOn: $showMasteryPercent) {
                Text("Show Mastery % on Cards").foregroundColor(IBColors.softWhite)
            }.tint(IBColors.electricBlue)

            Toggle(isOn: $showDueCountBadge) {
                Text("Due Count Badge").foregroundColor(IBColors.softWhite)
            }.tint(IBColors.electricBlue)
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
                HStack {
                    Image(systemName: "pills.fill").foregroundColor(IBColors.electricBlue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ADHD Med Tracker").foregroundColor(IBColors.softWhite)
                        Text("Ritalin IR \(adhdDoseMg)mg • 3× daily")
                            .font(.system(size: 11)).foregroundColor(IBColors.mutedGray)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundColor(IBColors.mutedGray)
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
                HStack {
                    Image(systemName: "arrow.down.doc.fill").foregroundColor(IBColors.electricBlue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Create Backup").foregroundColor(IBColors.softWhite)
                        if let lastDate = BackupService.latestBackupDate {
                            Text("Last backup: \(lastDate, style: .relative) ago")
                                .font(.system(size: 11)).foregroundColor(IBColors.mutedGray)
                        } else {
                            Text("Save all data to Documents folder")
                                .font(.system(size: 11)).foregroundColor(IBColors.mutedGray)
                        }
                    }
                    Spacer()
                    if isBackingUp { ProgressView().tint(IBColors.electricBlue) }
                }
            }.disabled(isBackingUp)

            Button { restoreBackup() } label: {
                HStack {
                    Image(systemName: "arrow.up.doc.fill").foregroundColor(IBColors.success)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Restore from Backup").foregroundColor(IBColors.softWhite)
                        Text("Restore your most recent backup")
                            .font(.system(size: 11)).foregroundColor(IBColors.mutedGray)
                    }
                }
            }

            Button { showBackups = true } label: {
                HStack {
                    Image(systemName: "folder.fill").foregroundColor(IBColors.warning)
                    Text("View All Backups").foregroundColor(IBColors.softWhite)
                    Spacer()
                    Text("\(BackupService.listBackups().count)")
                        .font(IBTypography.captionBold).foregroundColor(IBColors.mutedGray)
                    Image(systemName: "chevron.right").foregroundColor(IBColors.mutedGray)
                }
            }

            if !backupStatus.isEmpty {
                Text(backupStatus).font(.system(size: 12)).foregroundColor(IBColors.success)
            }
        } header: {
            Label("Backup & Recovery", systemImage: "externaldrive.fill")
        } footer: {
            Text("Backups are saved to Files → On My iPhone → IBVault Backups. Each backup contains your profile, subjects, cards, grades, ARIA memory, and study history as JSON files.")
        }
        .sheet(isPresented: $showBackups) { BackupListView() }
    }

    private func createBackup() {
        isBackingUp = true; backupStatus = ""
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url = try BackupService.exportBackup(context: context)
                DispatchQueue.main.async {
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
            backupStatus = "✓ Restored successfully!"; IBHaptics.success()
        } catch {
            backupStatus = "✗ Restore failed: \(error.localizedDescription)"; IBHaptics.error()
        }
    }

    // MARK: - Notifications
    private var notificationSection: some View {
        Section("Notifications") {
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
        }
    }

    // MARK: - Appearance
    private var appearanceSection: some View {
        Section {
            Toggle(isOn: $hapticFeedback) {
                HStack {
                    Image(systemName: "waveform").foregroundColor(IBColors.electricBlue)
                    Text("Haptic Feedback").foregroundColor(IBColors.softWhite)
                }
            }.tint(IBColors.electricBlue)
        } header: {
            Label("Appearance & Feel", systemImage: "paintbrush.fill")
        }
    }

    // MARK: - Data
    private var dataSection: some View {
        Section("Data") {
            Button("Reset All Data", role: .destructive) { }
                .foregroundColor(IBColors.danger)
        }
    }

    // MARK: - About
    private var aboutSection: some View {
        Section("About") {
            HStack { Text("Version"); Spacer(); Text("1.0.0").foregroundColor(IBColors.mutedGray) }
            HStack { Text("iOS"); Spacer(); Text("17.0+").foregroundColor(IBColors.mutedGray) }
            HStack {
                Text("AI Model"); Spacer()
                Text(selectedModel)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(IBColors.electricBlue)
            }
            HStack {
                Text("Temperature"); Spacer()
                Text(String(format: "%.1f", ariaTemperature)).foregroundColor(IBColors.mutedGray)
            }
            HStack {
                Text("Max Tokens"); Spacer()
                Text("\(ariaMaxTokens)").foregroundColor(IBColors.mutedGray)
            }
        }
    }

    // MARK: - AI Auto-Rank
    private func autoRankFromGrades() {
        guard let p = profile else { return }
        let allGrades = subjects.flatMap { $0.grades }
        guard !allGrades.isEmpty else { IBHaptics.warning(); return }
        let avg = Double(allGrades.map(\.score).reduce(0, +)) / Double(allGrades.count)
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

    // Categorised model groups
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
                        HStack {
                            ProgressView()
                            Text("Fetching models...")
                        }
                    }
                } else if let error = errorMessage {
                    Section("Error") {
                        Text(error)
                            .foregroundStyle(.red)
                        Button("Retry") { loadModels() }
                    }
                } else {
                    Section("Search") {
                        TextField("Search models...", text: $searchText)
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
                        Image(systemName: "arrow.clockwise").foregroundColor(IBColors.electricBlue)
                    }
                }
            }
            .onAppear { loadModels() }
        }
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
                VStack(alignment: .leading, spacing: IBSpacing.lg) {
                    VStack(alignment: .leading, spacing: IBSpacing.xs) {
                        Text("Upload Report Card")
                            .font(IBTypography.title).foregroundColor(IBColors.softWhite)
                        Text("Enter your latest grades — ARIA will auto-analyse gaps and update your rank")
                            .font(IBTypography.caption).foregroundColor(IBColors.mutedGray)
                    }.padding(.horizontal, IBSpacing.md)

                    ForEach(subjects, id: \.id) { subject in
                        subjectGradeCard(subject)
                    }

                    Button { saveAllGrades() } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Save Report & Auto-Update Rank")
                        }
                        .font(IBTypography.headline).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding()
                        .background(RoundedRectangle(cornerRadius: IBRadius.md).fill(IBColors.blueGradient))
                    }
                    .padding(.horizontal, IBSpacing.md)
                    .padding(.bottom, IBSpacing.xxl)
                }.padding(.top, IBSpacing.md)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { initGrades() }
        }
    }

    private func subjectGradeCard(_ subject: Subject) -> some View {
        let color = Color(hex: subject.accentColorHex)
        return GroupBox {
            VStack(alignment: .leading, spacing: IBSpacing.md) {
                HStack {
                    Circle().fill(color).frame(width: 10, height: 10)
                    Text(subject.name).font(IBTypography.headline).foregroundColor(IBColors.softWhite)
                    Text(subject.level).font(IBTypography.caption).foregroundColor(IBColors.mutedGray)
                }

                ForEach(components, id: \.self) { comp in
                    HStack {
                        Text(comp).font(IBTypography.caption).foregroundColor(IBColors.mutedGray).frame(width: 70, alignment: .leading)
                        Spacer()
                        ForEach(1...7, id: \.self) { score in
                            let isSelected = grades[subject.name]?[comp] == score
                            Button {
                                grades[subject.name, default: [:]][comp] = score; IBHaptics.light()
                            } label: {
                                Text("\(score)")
                                    .font(.system(size: 14, weight: isSelected ? .bold : .regular, design: .rounded))
                                    .foregroundColor(isSelected ? .white : IBColors.mutedGray)
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(isSelected ? color : IBColors.cardBorder))
                            }
                        }
                    }
                }
            }
        }.padding(.horizontal, IBSpacing.md)
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
                let avg = Double(allGrades.map(\.score).reduce(0, +)) / Double(allGrades.count)
                let totalReviews = (try? context.fetchCount(FetchDescriptor<ReviewSession>())) ?? 0
                p.autoUpdateFromGrades(averageGrade: avg, totalReviews: totalReviews)
            }
        }
        try? context.save(); IBHaptics.success(); dismiss()
    }
}
