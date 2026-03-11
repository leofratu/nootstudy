import SwiftUI
import SwiftData

struct EffectivenessView: View {
    @Query private var profiles: [UserProfile]
    @Query(sort: \StudyActivity.date, order: .reverse) private var activity: [StudyActivity]

    private var profile: UserProfile? { profiles.first }

    private let methods: [(name: String, multiplier: Double, icon: String, color: Color, desc: String)] = [
        ("Re-reading notes", 1.0, "doc.text", Color.gray, "Passive review — lowest retention"),
        ("Highlighting", 1.05, "highlighter", Color.yellow.opacity(0.8), "Minimal active processing"),
        ("Summarising", 1.15, "list.bullet.rectangle", Color.orange, "Some elaboration benefit"),
        ("Teaching others", 1.4, "person.2.fill", Color.blue.opacity(0.7), "Feynman technique effect"),
        ("Practice testing", 1.5, "checkmark.circle", Color.green.opacity(0.8), "Active recall — strong yield"),
        ("IB Vault (SR + AR)", 1.7, "sparkles", IBColors.electricBlue, "Spaced repetition × active recall")
    ]

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
        ScrollView {
            VStack(spacing: 16) {
                // Hero multiplier
                multiplierHero
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                // Method comparison
                methodComparisonCard
                    .padding(.horizontal, 24)

                // Time equivalence
                timeCard
                    .padding(.horizontal, 24)

                // Science section
                scienceCard
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .background(.background)
        .navigationTitle("Effectiveness")
    }

    // MARK: - Multiplier Hero
    private var multiplierHero: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text(String(format: "%.1f×", personalMultiplier))
                        .font(.system(size: 48, weight: .heavy, design: .rounded))
                        .foregroundStyle(IBColors.electricBlue)
                    Text("Your Multiplier")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Divider().frame(height: 60)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(IBColors.electricBlue)
                        Text("Base method")
                        Spacer()
                        Text("1.7×")
                            .font(.callout.bold())
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                        Text("Streak bonus")
                        Spacer()
                        Text(String(format: "+%.2f×", streakBonus))
                            .font(.callout.bold())
                            .foregroundStyle(.orange)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("Consistency")
                        Spacer()
                        Text(String(format: "+%.2f×", consistencyBonus))
                            .font(.callout.bold())
                            .foregroundStyle(.green)
                    }
                }
                .font(.callout)
            }

            if let profile {
                HStack(spacing: 6) {
                    Text("🔥")
                    Text("\(profile.currentStreak) day streak")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .glassCard()
    }

    // MARK: - Method Comparison
    private var methodComparisonCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.tint)
                Text("Method Comparison")
                    .font(.headline)
            }

            ForEach(methods, id: \.name) { method in
                HStack(spacing: 10) {
                    Image(systemName: method.icon)
                        .foregroundStyle(method.color)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(method.name)
                                .font(.callout.weight(.medium))
                            Spacer()
                            Text(String(format: "%.1f×", method.multiplier))
                                .font(.callout.bold())
                                .foregroundStyle(method.color)
                        }
                        MasteryBar(
                            progress: method.multiplier / 2.0,
                            height: 6,
                            color: method.color
                        )
                        Text(method.desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                if method.name != methods.last?.name {
                    Divider()
                }
            }
        }
        .padding(16)
        .glassCard()
    }

    // MARK: - Time Equivalence
    private var timeCard: some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .font(.title2)
                    .foregroundStyle(IBColors.electricBlue)
                Text("1 hour")
                    .font(.title3.bold())
                Text("with IB Vault")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 4) {
                Text("≈")
                    .font(.title.bold())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 40)

            VStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("1h 42m")
                    .font(.title3.bold())
                Text("of re-reading")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .glassCard()
    }

    // MARK: - Science
    private var scienceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "book.closed.fill")
                    .foregroundStyle(.tint)
                Text("Learning Science")
                    .font(.headline)
            }

            Text("Practice testing and distributed practice are consistently high-utility learning strategies. IB Vault combines both by scheduling review and requiring retrieval instead of passive re-reading.")
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .glassCard()
    }
}
