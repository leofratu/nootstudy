import Charts
import SwiftUI

struct ADHDTrackerView: View {
    @AppStorage("adhdDoseMg") private var doseMg = 10
    @AppStorage("adhdDose1Hour") private var dose1Hour = 9
    @AppStorage("adhdDose1Min") private var dose1Min = 0
    @AppStorage("adhdDoseInterval") private var doseIntervalMin = 270
    @State private var selectedHour: Double?

    private var basePKData: [(time: String, hour: Double, level: Double)] {
        doseMg == 20 ? pk20mg : pk10mg
    }

    private var pkData: [(time: String, hour: Double, level: Double)] {
        basePKData.map { point in
            (time: formattedTime(offsetMinutes: Int(point.hour * 60)), hour: point.hour, level: point.level)
        }
    }

    private var doseSchedule: [(label: String, time: String, peak: String, peakLevel: String)] {
        let peakLevels = doseMg == 20 ? ["8.6", "12.8", "14.0"] : ["4.3", "6.4", "7.0"]
        return (0..<3).map { index in
            let offset = index * doseIntervalMin
            return (
                label: "Dose \(index + 1)",
                time: formattedTime(offsetMinutes: offset),
                peak: formattedTime(offsetMinutes: offset + 120),
                peakLevel: peakLevels[index]
            )
        }
    }

    private let pk10mg: [(time: String, hour: Double, level: Double)] = [
        ("9 AM",   0, 0.0),  ("10 AM",  1, 3.6),  ("11 AM",  2, 4.3),
        ("12 PM",  3, 4.0),  ("1 PM",   4, 3.4),   ("1:30 PM", 4.5, 3.1),
        ("2 PM",   5, 5.2),  ("3 PM",   6, 6.4),   ("4 PM",   7, 6.0),
        ("5 PM",   8, 5.1),  ("6 PM",   9, 4.2),   ("7 PM",  10, 7.0),
        ("8 PM",  11, 7.0),  ("9 PM",  12, 6.2),   ("10 PM", 13, 5.1),
        ("11 PM", 14, 4.1),  ("12 AM", 15, 3.3)
    ]

    private let pk20mg: [(time: String, hour: Double, level: Double)] = [
        ("9 AM",   0, 0.0),  ("10 AM",  1, 7.2),   ("11 AM",  2, 8.6),
        ("12 PM",  3, 8.0),  ("1 PM",   4, 6.8),   ("1:30 PM", 4.5, 6.2),
        ("2 PM",   5, 10.3), ("3 PM",   6, 12.8),  ("4 PM",   7, 12.0),
        ("5 PM",   8, 10.2), ("6 PM",   9, 8.4),   ("7 PM",  10, 14.0),
        ("8 PM",  11, 14.0), ("9 PM",  12, 12.3),  ("10 PM", 13, 10.2),
        ("11 PM", 14, 8.3),  ("12 AM", 15, 6.7)
    ]

    private var maxLevel: Double { pkData.map(\.level).max() ?? 8 }
    private var therapeuticMin: Double { doseMg == 20 ? 5.0 : 2.5 }

    private var currentHourOffset: Double? {
        let now = Date()
        let cal = Calendar.current
        let currentMinutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let doseStart = dose1Hour * 60 + dose1Min
        let adjustedCurrent = currentMinutes < doseStart ? currentMinutes + 24 * 60 : currentMinutes
        let hoursSinceFirstDose = Double(adjustedCurrent - doseStart) / 60.0
        guard (0...15).contains(hoursSinceFirstDose) else { return nil }
        return hoursSinceFirstDose
    }

    private var highlightedPoint: (time: String, hour: Double, level: Double) {
        let targetHour = selectedHour ?? currentHourOffset ?? pkData.max(by: { $0.level < $1.level })?.hour ?? 0
        return pkData.min(by: { abs($0.hour - targetHour) < abs($1.hour - targetHour) }) ?? pkData[0]
    }

    private var focusWindows: [(label: String, start: Double, end: Double, peak: Double, color: Color)] {
        doseSchedule.indices.map { index in
            let start = Double(index * doseIntervalMin) / 60.0 + 0.75
            let peak = Double(index * doseIntervalMin) / 60.0 + 2.0
            let end = Double(index * doseIntervalMin) / 60.0 + 4.5
            let color: Color
            switch index {
            case 0: color = IBColors.electricBlue
            case 1: color = IBColors.success
            default: color = IBColors.warning
            }
            return (label: "Dose \(index + 1)", start: start, end: end, peak: peak, color: color)
        }
    }

    private var activeWindow: (label: String, start: Double, end: Double, peak: Double, color: Color)? {
        let reference = selectedHour ?? currentHourOffset
        guard let reference else { return nil }
        return focusWindows.first { reference >= $0.start && reference <= $0.end }
    }

    private var currentStatus: (level: Double, status: String, color: Color) {
        let now = Date()
        let cal = Calendar.current
        let currentMinutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let doseStart = dose1Hour * 60 + dose1Min
        let adjustedCurrent = currentMinutes < doseStart ? currentMinutes + 24 * 60 : currentMinutes
        let hoursSinceFirstDose = Double(adjustedCurrent - doseStart) / 60.0

        if hoursSinceFirstDose < 0 || hoursSinceFirstDose > 15 {
            return (0, "Not active", .gray)
        }

        var level = 0.0
        for i in 0..<pkData.count - 1 {
            if hoursSinceFirstDose >= pkData[i].hour && hoursSinceFirstDose <= pkData[i+1].hour {
                let t = (hoursSinceFirstDose - pkData[i].hour) / (pkData[i+1].hour - pkData[i].hour)
                level = pkData[i].level + t * (pkData[i+1].level - pkData[i].level)
                break
            }
        }

        if level >= therapeuticMin * 1.5 {
            return (level, "Peak Focus", IBColors.success)
        } else if level >= therapeuticMin {
            return (level, "Effective Range", IBColors.electricBlue)
        } else if level > 0 {
            return (level, "Wearing Off", IBColors.warning)
        }
        return (0, "Not active", .gray)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Status hero
                statusHero
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                // Regimen + Schedule side by side
                HStack(alignment: .top, spacing: 16) {
                    regimenCard
                    scheduleCard
                }
                .padding(.horizontal, 24)

                // PK timeline
                timelineCard
                    .padding(.horizontal, 24)

                focusWindowsCard
                    .padding(.horizontal, 24)

                // Notes
                notesCard
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .background(.background)
        .navigationTitle("Medication")
    }

    // MARK: - Status Hero
    private var statusHero: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(currentStatus.color.opacity(0.1))
                    .frame(width: 80, height: 80)
                VStack(spacing: 2) {
                    Text(String(format: "%.1f", currentStatus.level))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(currentStatus.color)
                    Text("ng/mL")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .glow(color: currentStatus.color, radius: 10)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "pills.fill")
                        .foregroundStyle(.purple)
                    Text(currentStatus.status)
                        .font(.title3.bold())
                        .foregroundStyle(currentStatus.color)
                }
                Text("Ritalin IR \(doseMg)mg • 3× daily")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ProgressView(value: min(currentStatus.level / maxLevel, 1.0))
                    .tint(currentStatus.color)
            }
            Spacer()
        }
        .padding(20)
        .glassCard()
    }

    // MARK: - Regimen
    private var regimenCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "capsule.fill")
                    .foregroundStyle(.purple)
                Text("Regimen")
                    .font(.headline)
            }

            Picker("Dose", selection: $doseMg) {
                Text("10 mg").tag(10)
                Text("20 mg").tag(20)
            }.pickerStyle(.segmented)

            VStack(spacing: 6) {
                HStack {
                    Text("First dose")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formattedTime(offsetMinutes: 0))
                        .font(.callout.bold())
                }
                HStack {
                    Text("Interval")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formattedDuration(minutes: doseIntervalMin))
                        .font(.callout.bold())
                }
                HStack {
                    Text("Frequency")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("3 doses")
                        .font(.callout.bold())
                }
            }
            .font(.callout)
        }
        .padding(16)
        .glassCard()
    }

    // MARK: - Schedule
    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.tint)
                Text("Schedule")
                    .font(.headline)
            }

            ForEach(doseSchedule.indices, id: \.self) { index in
                let item = doseSchedule[index]
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
                        Text("Peak ~\(item.peak) at \(item.peakLevel) ng/mL")
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

    // MARK: - PK Timeline
    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(.tint)
                Text("Plasma Level Timeline")
                    .font(.headline)
                Spacer()
                Text("Therapeutic min: \(String(format: "%.1f", therapeuticMin)) ng/mL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(Array(pkData.enumerated()), id: \.offset) { _, point in
                    AreaMark(
                        x: .value("Hour", point.hour),
                        y: .value("Level", point.level)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [IBColors.electricBlue.opacity(0.28), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Hour", point.hour),
                        y: .value("Level", point.level)
                    )
                    .foregroundStyle(IBColors.electricBlue)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                    PointMark(
                        x: .value("Hour", point.hour),
                        y: .value("Level", point.level)
                    )
                    .foregroundStyle(statusColor(for: point.level))
                    .symbolSize(abs(highlightedPoint.hour - point.hour) < 0.01 ? 90 : 36)
                }

                RuleMark(y: .value("Therapeutic minimum", therapeuticMin))
                    .foregroundStyle(IBColors.warning.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    .annotation(position: .topTrailing) {
                        Text("Target")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(IBColors.warning)
                    }

                if let currentHourOffset {
                    RuleMark(x: .value("Current", currentHourOffset))
                        .foregroundStyle(Color.primary.opacity(0.22))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }

                RuleMark(x: .value("Selected", highlightedPoint.hour))
                    .foregroundStyle(highlightedPoint.level >= therapeuticMin ? IBColors.success : IBColors.warning)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            }
            .frame(height: 220)
            .chartXSelection(value: $selectedHour)
            .chartXAxis {
                AxisMarks(values: .stride(by: 2)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                        .foregroundStyle(Color.primary.opacity(0.08))
                    AxisTick()
                    AxisValueLabel {
                        if let hour = value.as(Double.self) {
                            Text(formattedTime(offsetMinutes: Int(hour * 60)))
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedHour == nil ? "Current focus" : "Selected point")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(highlightedPoint.time)
                        .font(.headline)
                    Text(statusText(for: highlightedPoint.level))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor(for: highlightedPoint.level))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(String(format: "%.1f ng/mL", highlightedPoint.level))
                        .font(.title3.bold())
                        .foregroundStyle(statusColor(for: highlightedPoint.level))
                    Text(
                        highlightedPoint.level >= therapeuticMin
                            ? "Within your estimated focus band"
                            : "Below the estimated effective band"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .glassCard()
    }

    private var focusWindowsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "scope")
                    .foregroundStyle(.tint)
                Text("Focus Windows")
                    .font(.headline)
                Spacer()
                Text("Interactive dose map")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(focusWindows, id: \.label) { window in
                    BarMark(
                        xStart: .value("Start", window.start),
                        xEnd: .value("End", window.end),
                        y: .value("Dose", window.label)
                    )
                    .clipShape(Capsule())
                    .foregroundStyle(window.color.opacity(0.75))

                    PointMark(
                        x: .value("Peak", window.peak),
                        y: .value("Dose", window.label)
                    )
                    .foregroundStyle(window.color)
                    .symbol(.diamond)
                    .symbolSize(80)
                }

                if let currentHourOffset {
                    RuleMark(x: .value("Current", currentHourOffset))
                        .foregroundStyle(Color.primary.opacity(0.22))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .frame(height: 150)
            .chartXAxis {
                AxisMarks(values: .stride(by: 2)) { value in
                    AxisTick()
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                        .foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel {
                        if let hour = value.as(Double.self) {
                            Text(formattedTime(offsetMinutes: Int(hour * 60)))
                        }
                    }
                }
            }

            if let activeWindow {
                HStack(spacing: 12) {
                    Circle()
                        .fill(activeWindow.color)
                        .frame(width: 10, height: 10)
                    Text("\(activeWindow.label) is in its estimated effect window")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Text("Peak around \(formattedTime(offsetMinutes: Int(activeWindow.peak * 60)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Select a point on the plasma chart to inspect how it lines up with each dose window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .glassCard()
    }

    // MARK: - Notes
    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("Disclaimer")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            Text("This is a reference estimate based on the configured dose timing and clinical PK examples. It is not a direct measurement and should not replace medical guidance.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .glassCard()
    }

    // MARK: - Helpers
    private func statusText(for level: Double) -> String {
        if level >= therapeuticMin * 1.5 { return "Peak" }
        if level >= therapeuticMin { return "In range" }
        if level > 0 { return "Wearing off" }
        return "Inactive"
    }

    private func statusColor(for level: Double) -> Color {
        if level >= therapeuticMin * 1.5 { return IBColors.success }
        if level >= therapeuticMin { return IBColors.electricBlue }
        if level > 0 { return IBColors.warning }
        return .gray
    }

    private func formattedTime(offsetMinutes: Int) -> String {
        let total = (dose1Hour * 60 + dose1Min + offsetMinutes + 24 * 60) % (24 * 60)
        let hour = total / 60
        let minute = total % 60
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date)
    }

    private func formattedDuration(minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if mins == 0 { return "\(hours)h" }
        return "\(hours)h \(mins)m"
    }
}
