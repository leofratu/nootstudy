import SwiftUI

struct ADHDTrackerView: View {
    @AppStorage("adhdDoseMg") private var doseMg = 10
    @AppStorage("adhdDose1Hour") private var dose1Hour = 9
    @AppStorage("adhdDose1Min") private var dose1Min = 0
    @AppStorage("adhdDoseInterval") private var doseIntervalMin = 270 // 4h30m in minutes

    // PK data from user-provided clinical estimates
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

    // 10 mg IR, 3x daily, 4h30m intervals
    private let pk10mg: [(time: String, hour: Double, level: Double)] = [
        ("9 AM",   0, 0.0),  ("10 AM",  1, 3.6),  ("11 AM",  2, 4.3),
        ("12 PM",  3, 4.0),  ("1 PM",   4, 3.4),   ("1:30 PM", 4.5, 3.1),
        ("2 PM",   5, 5.2),  ("3 PM",   6, 6.4),   ("4 PM",   7, 6.0),
        ("5 PM",   8, 5.1),  ("6 PM",   9, 4.2),   ("7 PM",  10, 7.0),
        ("8 PM",  11, 7.0),  ("9 PM",  12, 6.2),   ("10 PM", 13, 5.1),
        ("11 PM", 14, 4.1),  ("12 AM", 15, 3.3)
    ]

    // 20 mg IR, 3x daily, 4h30m intervals (dose-scaled)
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

    // Current status based on actual time
    private var currentStatus: (level: Double, status: String, color: Color) {
        let now = Date()
        let cal = Calendar.current
        let currentMinutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let doseStart = dose1Hour * 60 + dose1Min
        let adjustedCurrent = currentMinutes < doseStart ? currentMinutes + 24 * 60 : currentMinutes
        let hoursSinceFirstDose = Double(adjustedCurrent - doseStart) / 60.0

        if hoursSinceFirstDose < 0 || hoursSinceFirstDose > 15 {
            return (0, "Not active", IBColors.mutedGray)
        }

        // Interpolate level
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
        return (0, "Not active", IBColors.mutedGray)
    }

    var body: some View {
        List {
            currentStatusSection
            doseSection
            scheduleSection
            concentrationSection
            notesSection
        }
        .listStyle(.inset)
        .controlSize(.small)
        .navigationTitle("Medication")
    }

    private var currentStatusSection: some View {
        Section("Current Status") {
            LabeledContent("Estimated state", value: currentStatus.status)
            LabeledContent("Estimated level", value: String(format: "%.1f ng/mL", currentStatus.level))
            ProgressView(value: min(currentStatus.level / maxLevel, 1.0))
                .tint(currentStatus.color)

            Text("Reference window starts at \(formattedTime(offsetMinutes: 0)) and runs for roughly 15 hours.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var doseSection: some View {
        Section("Regimen") {
            Picker("Dose", selection: $doseMg) {
                Text("10 mg").tag(10)
                Text("20 mg").tag(20)
            }
            .pickerStyle(.segmented)

            LabeledContent("First dose", value: formattedTime(offsetMinutes: 0))
            LabeledContent("Interval", value: formattedDuration(minutes: doseIntervalMin))
            LabeledContent("Daily frequency", value: "3 doses")
        }
    }

    private var scheduleSection: some View {
        Section("Dose Schedule") {
            ForEach(doseSchedule.indices, id: \.self) { index in
                let item = doseSchedule[index]
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(item.label)
                        Spacer()
                        Text(item.time)
                            .foregroundStyle(.secondary)
                    }
                    Text("Peak around \(item.peak) at ~\(item.peakLevel) ng/mL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var concentrationSection: some View {
        Section("Reference Timeline") {
            LabeledContent("Therapeutic minimum", value: String(format: "%.1f ng/mL", therapeuticMin))

            ForEach(Array(pkData.enumerated()), id: \.offset) { _, point in
                HStack {
                    Text(point.time)
                    Spacer()
                    Text(String(format: "%.1f ng/mL", point.level))
                        .foregroundStyle(.secondary)
                    Text(statusText(for: point.level))
                        .foregroundStyle(statusColor(for: point.level))
                }
                .font(.caption)
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            Text("This is a reference estimate based on the configured dose timing and clinical PK examples. It is not a direct measurement and should not replace medical guidance.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

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
        return IBColors.mutedGray
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
