import SwiftUI
import SwiftData

struct EffectivenessView: View {
    @Query private var profiles: [UserProfile]
    @Query(sort: \StudyActivity.date, order: .reverse) private var activity: [StudyActivity]

    @State private var animateMultiplier = false
    @State private var selectedMethod = 0

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
        let streakBonus = min(Double(p.currentStreak) * 0.02, 0.3)  // Up to +0.3 for 15-day streak
        let consistencyBonus = activity.count > 7 ? 0.1 : 0.0  // +0.1 for weekly consistency
        return 1.7 + streakBonus + consistencyBonus
    }

    var body: some View {
        ZStack {
            IBColors.navy.ignoresSafeArea()
            IBColors.meshGlow.ignoresSafeArea()

            ScrollView {
                VStack(spacing: IBSpacing.lg) {
                    multiplierHero
                    PremiumDivider()
                    comparisonChart
                    timeEquivalence
                    scienceCard
                }
                .padding(.horizontal, IBSpacing.md)
                .padding(.bottom, 100)
            }
        }
        .navigationTitle("Study Effectiveness")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            withAnimation(IBAnimation.gentle.delay(0.3)) {
                animateMultiplier = true
            }
        }
    }

    // MARK: - Hero Multiplier
    private var multiplierHero: some View {
        GlassCard {
            VStack(spacing: IBSpacing.lg) {
                Text("Your Effectiveness")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(IBColors.secondaryText)
                    .textCase(.uppercase)
                    .tracking(1.5)

                ZStack {
                    // Background ring
                    Circle()
                        .stroke(IBColors.cardBorder.opacity(0.3), lineWidth: 8)
                        .frame(width: 160, height: 160)

                    // Progress ring
                    Circle()
                        .trim(from: 0, to: animateMultiplier ? personalMultiplier / 2.5 : 0)
                        .stroke(
                            AngularGradient(
                                colors: [IBColors.electricBlue.opacity(0.3), IBColors.electricBlue, Color(hex: "7C5CFC")],
                                center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)
                            ),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 160, height: 160)
                        .shadow(color: IBColors.electricBlue.opacity(0.3), radius: 8)

                    VStack(spacing: 4) {
                        Text(String(format: "%.1fx", animateMultiplier ? personalMultiplier : 1.0))
                            .font(.system(size: 48, weight: .heavy, design: .rounded))
                            .foregroundStyle(IBColors.blueGradient)
                            .contentTransition(.numericText())
                        Text("multiplier")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(IBColors.mutedGray)
                    }
                }

                // Breakdown
                HStack(spacing: IBSpacing.xl) {
                    VStack(spacing: 4) {
                        Text("1.7x")
                            .font(IBTypography.captionBold).foregroundColor(IBColors.electricBlue)
                        Text("Base Method")
                            .font(.system(size: 10)).foregroundColor(IBColors.mutedGray)
                    }
                    if let p = profile, p.currentStreak > 0 {
                        VStack(spacing: 4) {
                            Text("+\(String(format: "%.1f", min(Double(p.currentStreak) * 0.02, 0.3)))x")
                                .font(IBTypography.captionBold).foregroundColor(IBColors.streakOrange)
                            Text("Streak Bonus")
                                .font(.system(size: 10)).foregroundColor(IBColors.mutedGray)
                        }
                    }
                    if activity.count > 7 {
                        VStack(spacing: 4) {
                            Text("+0.1x")
                                .font(IBTypography.captionBold).foregroundColor(IBColors.success)
                            Text("Consistency")
                                .font(.system(size: 10)).foregroundColor(IBColors.mutedGray)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Comparison Chart
    private var comparisonChart: some View {
        VStack(alignment: .leading, spacing: IBSpacing.md) {
            Text("Method Comparison")
                .font(IBTypography.headline).foregroundColor(IBColors.softWhite)

            ForEach(Array(methods.enumerated()), id: \.offset) { index, method in
                let isOurs = index == methods.count - 1
                GlassCard(cornerRadius: IBRadius.sm, padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: method.icon)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(method.color)
                                .frame(width: 22)
                            Text(method.name)
                                .font(isOurs ? IBTypography.captionBold : IBTypography.caption)
                                .foregroundColor(isOurs ? IBColors.softWhite : IBColors.secondaryText)
                            Spacer()
                            Text("\(String(format: "%.1f", method.multiplier))x")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(method.color)
                        }
                        // Bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(IBColors.cardBorder.opacity(0.3))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(
                                        LinearGradient(
                                            colors: [method.color.opacity(0.6), method.color],
                                            startPoint: .leading, endPoint: .trailing
                                        )
                                    )
                                    .frame(width: animateMultiplier ? geo.size.width * (method.multiplier / 2.0) : 0)
                                    .shadow(color: method.color.opacity(0.3), radius: 3, x: 2)
                            }
                        }
                        .frame(height: 5)

                        Text(method.desc)
                            .font(.system(size: 10)).foregroundColor(IBColors.mutedGray)
                    }
                }
            }
        }
    }

    // MARK: - Time Equivalence
    private var timeEquivalence: some View {
        GlassCard {
            VStack(spacing: IBSpacing.md) {
                Text("Time Equivalence")
                    .font(IBTypography.headline).foregroundColor(IBColors.softWhite)

                HStack(spacing: IBSpacing.lg) {
                    VStack(spacing: 6) {
                        Image(systemName: "clock").font(.title2).foregroundColor(IBColors.mutedGray)
                        Text("1 hour").font(IBTypography.stat).foregroundColor(IBColors.softWhite)
                        Text("with IB Vault").font(.system(size: 11)).foregroundColor(IBColors.mutedGray)
                    }
                    .frame(maxWidth: .infinity)

                    Image(systemName: "equal").font(.title3).foregroundColor(IBColors.cardBorder)

                    VStack(spacing: 6) {
                        Image(systemName: "clock.fill").font(.title2).foregroundColor(IBColors.warning)
                        Text("1h 42m").font(IBTypography.stat).foregroundColor(IBColors.warning)
                        Text("re-reading notes").font(.system(size: 11)).foregroundColor(IBColors.mutedGray)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Science Card
    private var scienceCard: some View {
        GlassCard(cornerRadius: IBRadius.md) {
            VStack(alignment: .leading, spacing: IBSpacing.sm) {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(IBColors.electricBlue)
                    Text("The Science")
                        .font(IBTypography.captionBold).foregroundColor(IBColors.softWhite)
                }
                Text("Dunlosky et al. (2013) meta-analysis ranked 10 learning techniques. Practice testing and distributed practice were the only two rated \"high utility.\" IB Vault combines both — spaced repetition schedules optimally timed reviews, while flashcard-based retrieval forces active recall. This combination yields ~1.7x the retention of passive re-reading over the same study time.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(IBColors.secondaryText)
                    .lineSpacing(4)
            }
        }
    }
}
