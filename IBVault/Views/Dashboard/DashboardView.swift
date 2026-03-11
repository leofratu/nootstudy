import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(sort: \StudyCard.nextReviewDate) private var allCards: [StudyCard]
    @Query private var subjects: [Subject]
    @Query(sort: \StudyActivity.date, order: .reverse) private var recentActivity: [StudyActivity]

    @State private var ariaService = ARIAService()
    @State private var showReview = false

    private var profile: UserProfile? { profiles.first }

    private var dueCards: [StudyCard] {
        allCards.filter { $0.isDue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                IBColors.navy.ignoresSafeArea()
                IBColors.meshGlow.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: IBSpacing.lg) {
                        headerSection
                        statsRow
                        ariaGreetingCard
                        insightsRow
                        materialsLink
                        reviewQueueCard
                        subjectsSnapshot
                    }
                    .padding(.horizontal, IBSpacing.md)
                    .padding(.bottom, 100)
                }
            }
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $showReview) {
                ReviewSessionView()
            }
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(greeting)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(IBColors.secondaryText)
                Text("Dashboard")
                    .font(IBTypography.largeTitle)
                    .foregroundColor(IBColors.softWhite)
            }
            Spacer()
            if let p = profile, p.currentStreak > 0 {
                StreakFire(streakCount: p.currentStreak)
            }
        }
        .padding(.top, IBSpacing.md)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    // MARK: - Stats Row
    private var statsRow: some View {
        HStack(spacing: IBSpacing.md) {
            statCard(value: dueCards.count, label: "Due Today", icon: "clock.fill", color: IBColors.electricBlue)
            statCard(value: profile?.totalXP ?? 0, label: "Total XP", icon: "star.fill", color: IBColors.warning)
            statCard(value: profile?.currentStreak ?? 0, label: "Day Streak", icon: "flame.fill", color: IBColors.streakOrange)
        }
    }

    private func statCard(value: Int, label: String, icon: String, color: Color) -> some View {
        GlassCard(cornerRadius: IBRadius.md, padding: IBSpacing.md) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(colors: [color, color.opacity(0.6)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .shadow(color: color.opacity(0.3), radius: 4)
                AnimatedCounter(value: value, font: IBTypography.stat, color: IBColors.softWhite)
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(IBColors.mutedGray)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - ARIA Greeting
    private var ariaGreetingCard: some View {
        GlassCard {
            HStack(spacing: IBSpacing.md) {
                PulseOrb(size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text("ARIA")
                        .font(IBTypography.captionBold)
                        .foregroundColor(IBColors.electricBlue)
                    Text(ariaService.generateGreeting(context: context))
                        .font(IBTypography.caption)
                        .foregroundColor(IBColors.softWhite)
                        .lineLimit(3)
                }
                Spacer()
            }
        }
    }

    // MARK: - Insights Row
    private var insightsRow: some View {
        HStack(spacing: IBSpacing.md) {
            NavigationLink {
                EffectivenessView()
            } label: {
                GlassCard(cornerRadius: IBRadius.md, padding: 14) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(IBColors.success.opacity(0.12)).frame(width: 34, height: 34)
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(IBColors.success)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("1.7× More").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(IBColors.softWhite)
                            Text("Effective").font(.system(size: 10, weight: .medium)).foregroundColor(IBColors.mutedGray)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 11)).foregroundColor(IBColors.tertiaryText)
                    }
                }
            }
            .buttonStyle(.plain)

            NavigationLink {
                ADHDTrackerView()
            } label: {
                GlassCard(cornerRadius: IBRadius.md, padding: 14) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(IBColors.electricBlue.opacity(0.12)).frame(width: 34, height: 34)
                            Image(systemName: "pills.fill")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(IBColors.electricBlue)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Med Track").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(IBColors.softWhite)
                            Text("ADHD").font(.system(size: 10, weight: .medium)).foregroundColor(IBColors.mutedGray)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 11)).foregroundColor(IBColors.tertiaryText)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Materials Link
    private var materialsLink: some View {
        NavigationLink {
            MaterialsLibraryView()
        } label: {
            GlassCard(cornerRadius: IBRadius.md, padding: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(IBColors.englishColor.opacity(0.12))
                            .frame(width: 38, height: 38)
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(IBColors.englishColor)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Materials Library")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(IBColors.softWhite)
                        Text("Guides, past papers, formula booklets & more")
                            .font(.system(size: 11)).foregroundColor(IBColors.mutedGray)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(IBColors.tertiaryText)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Review Queue
    private var reviewQueueCard: some View {
        GlassCard {
            VStack(spacing: IBSpacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Review Queue")
                            .font(IBTypography.headline)
                            .foregroundColor(IBColors.softWhite)
                        Text("\(dueCards.count) cards ready for review")
                            .font(IBTypography.caption)
                            .foregroundColor(IBColors.mutedGray)
                    }
                    Spacer()
                    ProgressRing(progress: reviewProgress, size: 44)
                }

                if !dueCards.isEmpty {
                    Button {
                        IBHaptics.medium()
                        showReview = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "play.fill")
                            Text("Start Review")
                        }
                        .font(IBTypography.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: IBRadius.sm)
                                .fill(IBColors.blueGradient)
                                .overlay(
                                    RoundedRectangle(cornerRadius: IBRadius.sm)
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.white.opacity(0.12), Color.clear],
                                                startPoint: .top, endPoint: .center
                                            )
                                        )
                                )
                        )
                        .shadow(color: IBColors.electricBlue.opacity(0.3), radius: 10, y: 4)
                    }
                }
            }
        }
    }

    private var reviewProgress: Double {
        guard !allCards.isEmpty else { return 0 }
        let reviewed = allCards.filter { !$0.isDue }.count
        return Double(reviewed) / Double(allCards.count)
    }

    // MARK: - Subjects Snapshot
    private var subjectsSnapshot: some View {
        VStack(alignment: .leading, spacing: IBSpacing.md) {
            Text("Subjects")
                .font(IBTypography.headline)
                .foregroundColor(IBColors.softWhite)

            ForEach(subjects, id: \.id) { subject in
                let accent = Color(hex: subject.accentColorHex)
                GlassCard(cornerRadius: IBRadius.md, padding: IBSpacing.sm) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(
                                RadialGradient(colors: [accent, accent.opacity(0.5)],
                                               center: .center, startRadius: 0, endRadius: 6)
                            )
                            .frame(width: 9, height: 9)
                            .shadow(color: accent.opacity(0.5), radius: 4)
                        Text(subject.name)
                            .font(IBTypography.callout)
                            .foregroundColor(IBColors.softWhite)
                        Text(subject.level)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(IBColors.mutedGray)
                        Spacer()
                        if subject.dueCardsCount > 0 {
                            Text("\(subject.dueCardsCount) due")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(IBColors.warning)
                        }
                        MasteryBar(
                            progress: subject.masteryProgress,
                            height: 4,
                            color: accent
                        )
                        .frame(width: 50)
                    }
                }
            }
        }
    }
}
