import SwiftUI
import SwiftData

struct EffectivenessView: View {
    @Query private var profiles: [UserProfile]
    @Query(sort: \StudyActivity.date, order: .reverse) private var activity: [StudyActivity]

    private var profile: UserProfile? { profiles.first }

    // Study method multipliers (evidence-based from learning science research)
    private let methods: [(name: String, multiplier: Double, icon: String, color: Color, desc: String)] = [
        ("Re-reading notes", 1.0, "doc.text", IBColors.mutedGray, "Passive review — lowest retention"),
        ("Highlighting", 1.05, "highlighter", IBColors.warning.opacity(0.6), "Minimal active processing"),
        ("Summarising", 1.15, "list.bullet.rectangle", IBColors.warning, "Some elaboration benefit"),
        ("Teaching others", 1.4, "person.2.fill", IBColors.electricBlueMuted, "Feynman technique effect"),
        ("Practice testing", 1.5, "checkmark.circle", IBColors.success.opacity(0.7), "Active recall — strong yield"),
        ("IB Vault (SR + AR)", 1.7, "sparkles", IBColors.electricBlue, "Spaced repetition × active recall")
    ]

    // User's personal multiplier based on consistency
    private var personalMultiplier: Double {
        guard let p = profile else { return 1.7 }
        let streakBonus = min(Double(p.currentStreak) * 0.02, 0.3)
        let consistencyBonus = activity.count > 7 ? 0.1 : 0.0
        return 1.7 + streakBonus + consistencyBonus
    }

    private var streakBonus: Double {
        guard let p = profile else { return 0 }
        return min(Double(p.currentStreak) * 0.02, 0.3)
    }

    private var consistencyBonus: Double {
        activity.count > 7 ? 0.1 : 0.0
    }

    var body: some View {
        List {
            summarySection
            comparisonSection
            timeEquivalenceSection
            scienceSection
        }
        .listStyle(.inset)
        .controlSize(.small)
        .navigationTitle("Effectiveness")
    }

    private var summarySection: some View {
        Section("Your Multiplier") {
            LabeledContent("IB Vault estimate", value: String(format: "%.1fx", personalMultiplier))
            LabeledContent("Base method", value: "1.7x")
            LabeledContent("Streak bonus", value: String(format: "+%.1fx", streakBonus))
            LabeledContent("Consistency bonus", value: String(format: "+%.1fx", consistencyBonus))

            if let profile {
                Text("Current streak: \(profile.currentStreak) days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var comparisonSection: some View {
        Section("Method Comparison") {
            ForEach(methods, id: \.name) { method in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Label(method.name, systemImage: method.icon)
                        Spacer()
                        Text(String(format: "%.1fx", method.multiplier))
                            .foregroundStyle(.secondary)
                    }
                    Text(method.desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var timeEquivalenceSection: some View {
        Section("Time Equivalence") {
            LabeledContent("1 hour with IB Vault", value: "≈ 1h 42m of re-reading")
            LabeledContent("Why", value: "Spaced repetition + active recall")
        }
    }

    private var scienceSection: some View {
        Section("Learning Science") {
            Text("Practice testing and distributed practice are consistently high-utility learning strategies. IB Vault combines both by scheduling review and requiring retrieval instead of passive re-reading.")
                .foregroundStyle(.secondary)
        }
    }
}
