import Charts
import SwiftUI

struct ADHDTrackerView: View {
    @State private var settings: ADHDMedicationSettings = .default
    @State private var showMedicationPicker = false

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    /// Hours since the first daily dose, the single x-axis domain used by both
    /// the timeline chart and the focus-window chart.
    private func hoursSinceFirstDose(_ date: Date) -> Double {
        let calendar = Calendar.current
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let doseStart = settings.firstDoseHour * 60 + settings.firstDoseMinute
        let adjusted = minutes < doseStart ? minutes + 24 * 60 : minutes
        return Double(adjusted - doseStart) / 60.0
    }

    /// The shared x-axis domain (0...16 hours) used by the timeline and
    /// focus-window charts. A focus window that extends past midnight (e.g. a
    /// 24-hour medication) can compute an end hour far beyond this domain;
    /// clamping keeps both charts aligned instead of letting a bar blow out the
    /// focus chart's axis.
    private func clampedDoseHour(_ hours: Double) -> Double {
        min(max(hours, 0), 16)
    }

    private var pkData: [(time: String, hour: Double, level: Double)] {
        guard settings.isEnabled && settings.medicationType != .none else {
            return []
        }

        var data: [(time: String, hour: Double, level: Double)] = []
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)

        for hourOffset in stride(from: 0, through: 23.5, by: 0.5) {
            let minutes = Int(hourOffset * 60)
            guard let time = calendar.date(byAdding: .minute, value: minutes, to: startOfDay) else { continue }
            let hour = hoursSinceFirstDose(time)
            guard (0...16).contains(hour) else { continue }
            let level = ADHDMedicationTracker.estimatePlasmaLevel(at: time, settings: settings)
            data.append((Self.timeFormatter.string(from: time), hour, level))
        }

        return data
    }

    private var doseSchedule: [(label: String, time: String, peak: String)] {
        let windows = ADHDMedicationTracker.focusWindows(settings: settings)

        return windows.map { window in
            (
                label: window.label,
                time: Self.timeFormatter.string(from: window.start),
                peak: Self.timeFormatter.string(from: window.peak)
            )
        }
    }

    private var maxLevel: Double {
        // Guard against an all-zero (or empty) profile so the status hero's
        // `level / maxLevel` can never divide by zero.
        max(pkData.map(\.level).max() ?? 1, 1)
    }

    private var therapeuticMin: Double {
        Double(settings.doseMg) * 0.25
    }

    private var currentStatus: (level: Double, status: String, colorName: String) {
        ADHDMedicationTracker.currentFocusStatus(at: Date(), settings: settings)
    }

    private var currentHourOffset: Double? {
        let hours = hoursSinceFirstDose(Date())
        guard (0...16).contains(hours) else { return nil }
        return hours
    }
    
    private var statusColor: Color {
        switch currentStatus.colorName {
        case "green": return IBColors.success
        case "blue": return .blue
        case "orange": return IBColors.warning
        default: return .gray
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !settings.isEnabled || settings.medicationType == .none {
                    disabledStateView
                } else {
                    statusHero
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                    
                    HStack(alignment: .top, spacing: 16) {
                        regimenCard
                        scheduleCard
                    }
                    .padding(.horizontal, 24)
                    
                    timelineCard
                        .padding(.horizontal, 24)
                    
                    focusWindowsCard
                        .padding(.horizontal, 24)
                }
                
                notesCard
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .background(.background)
        .navigationTitle("ADHD Medication")
        .onAppear { settings = ADHDMedicationSettings.loadFromDefaults() }
    }
    
    private var disabledStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "pills.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("Medication Tracking Disabled")
                .font(.title2.bold())
            
            Text("Enable medication tracking in Settings to see focus window predictions.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                showMedicationPicker = true
            } label: {
                Text("Configure Medication")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .sheet(isPresented: $showMedicationPicker) {
            MedicationPickerView(settings: $settings)
        }
    }
    
    private var statusHero: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.1))
                    .frame(width: 80, height: 80)
                VStack(spacing: 2) {
                    Text(String(format: "%.1f", currentStatus.level))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(statusColor)
                    Text("ng/mL")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "pills.fill")
                        .foregroundStyle(.purple)
                    Text(currentStatus.status)
                        .font(.title3.bold())
                        .foregroundStyle(statusColor)
                }
                Text("\(settings.medicationType.displayName) \(settings.doseMg)mg")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                
                ProgressView(value: min(currentStatus.level / maxLevel, 1.0))
                    .tint(statusColor)
            }
            Spacer()
        }
        .padding(20)
        .glassCard()
    }
    
    private var regimenCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "capsule.fill")
                    .foregroundStyle(.purple)
                Text("Regimen")
                    .font(.headline)
            }
            
            VStack(spacing: 6) {
                HStack {
                    Text("Medication")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(settings.medicationType.displayName)
                        .font(.callout.bold())
                }
                HStack {
                    Text("Dose")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(settings.doseMg) mg")
                        .font(.callout.bold())
                }
                HStack {
                    Text("Frequency")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(settings.dailyDoses)× daily")
                        .font(.callout.bold())
                }
            }
            .font(.callout)
        }
        .padding(16)
        .glassCard()
    }
    
    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.tint)
                Text("Schedule")
                    .font(.headline)
            }
            
            ForEach(Array(doseSchedule.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.purple.opacity(0.1))
                            .frame(width: 32, height: 32)
                        Text("\(index + 1)")
                            .font(.callout.bold())
                            .foregroundStyle(.purple)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.time)
                            .font(.callout.bold())
                        Text("Peak ~\(item.peak)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if index < doseSchedule.count - 1 {
                    Divider()
                }
            }
        }
        .padding(16)
        .glassCard()
    }
    
    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(.tint)
                Text("Estimated Plasma Level")
                    .font(.headline)
                Spacer()
                Text("Therapeutic min: \(String(format: "%.1f", therapeuticMin)) ng/mL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if !pkData.isEmpty {
                Chart {
                    ForEach(Array(pkData.enumerated()), id: \.offset) { _, point in
                        AreaMark(
                            x: .value("Hour", point.hour),
                            y: .value("Level", point.level)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.28), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        
                        LineMark(
                            x: .value("Hour", point.hour),
                            y: .value("Level", point.level)
                        )
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }
                    
                    RuleMark(y: .value("Min", therapeuticMin))
                        .foregroundStyle(IBColors.inkTertiary.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    
                    if let currentHourOffset {
                        RuleMark(x: .value("Current", currentHourOffset))
                            .foregroundStyle(Color.primary.opacity(0.22))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .frame(height: 200)
                .chartXAxis {
                    AxisMarks(values: .stride(by: 2)) { _ in
                        AxisTick()
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                            .foregroundStyle(Color.primary.opacity(0.08))
                    }
                }
            }
        }
        .padding(16)
        .glassCard()
    }
    
    private var focusWindowsCard: some View {
        let windows = ADHDMedicationTracker.focusWindows(settings: settings)
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "scope")
                    .foregroundStyle(.tint)
                Text("Focus Windows")
                    .font(.headline)
            }
            
            if !windows.isEmpty {
                Chart {
                    ForEach(Array(windows.enumerated()), id: \.offset) { index, window in
                        BarMark(
                            xStart: .value("Start", clampedDoseHour(hoursSinceFirstDose(window.start))),
                            xEnd: .value("End", clampedDoseHour(hoursSinceFirstDose(window.end))),
                            y: .value("Dose", "Dose \(index + 1)"),
                            height: .fixed(18)
                        )
                        .clipShape(Capsule())
                        .foregroundStyle(Color.blue.opacity(0.75))
                    }

                    if let currentHourOffset {
                        RuleMark(x: .value("Current", currentHourOffset))
                            .foregroundStyle(Color.primary.opacity(0.22))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .frame(height: CGFloat(windows.count * 50 + 40))
                .chartXAxis {
                    AxisMarks(values: .stride(by: 2)) { _ in
                        AxisTick()
                    }
                }
            }
        }
        .padding(16)
        .glassCard()
    }
    
    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(IBColors.success)
                Text("Privacy Notice")
                    .font(.caption.bold())
            }
            Text("All medication data is stored locally on your device. It is never sent to any external servers or used by AI features. This information stays strictly private.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .glassCard()
    }
}

struct MedicationPickerView: View {
    @Binding var settings: ADHDMedicationSettings
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Enable Medication Tracking", isOn: $settings.isEnabled)
                }
                
                if settings.isEnabled {
                    Section("Medication Type") {
                        Picker("Medication", selection: $settings.medicationType) {
                            ForEach(ADHDMedicationType.allCases, id: \.self) { med in
                                VStack(alignment: .leading) {
                                    Text(med.displayName)
                                    if !med.brandNames.isEmpty {
                                        Text(med.brandNames)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .tag(med)
                            }
                        }
                    }
                    
                    if settings.medicationType != .none {
                        Section("Dosage") {
                            Picker("Dose (mg)", selection: $settings.doseMg) {
                                ForEach(settings.medicationType.typicalDosesMg, id: \.self) { dose in
                                    Text("\(dose) mg").tag(dose)
                                }
                            }
                            
                            Stepper("Daily doses: \(settings.dailyDoses)", value: $settings.dailyDoses, in: settings.medicationType.typicalDailyDoses)
                        }
                        
                        Section("Schedule") {
                            DatePicker(
                                "First dose time",
                                selection: Binding(
                                    get: {
                                        let calendar = Calendar.current
                                        var components = DateComponents()
                                        components.hour = settings.firstDoseHour
                                        components.minute = settings.firstDoseMinute
                                        return calendar.date(from: components) ?? Date()
                                    },
                                    set: { date in
                                        settings.firstDoseHour = Calendar.current.component(.hour, from: date)
                                        settings.firstDoseMinute = Calendar.current.component(.minute, from: date)
                                    }
                                ),
                                displayedComponents: .hourAndMinute
                            )
                            
                            if settings.dailyDoses > 1 {
                                Stepper(
                                    "Dose interval: \(settings.doseIntervalMinutes / 60)h \(settings.doseIntervalMinutes % 60)m",
                                    value: $settings.doseIntervalMinutes,
                                    in: 120...480,
                                    step: 30
                                )
                            }
                        }
                    }
                }
            }
            .onChange(of: settings.medicationType) { _, newType in
                if !newType.typicalDosesMg.contains(settings.doseMg) {
                    settings.doseMg = newType.typicalDosesMg.first ?? settings.doseMg
                }
                if !newType.typicalDailyDoses.contains(settings.dailyDoses) {
                    settings.dailyDoses = newType.typicalDailyDoses.upperBound
                }
            }
            .navigationTitle("Medication Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        settings.saveToDefaults()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 500)
    }
}