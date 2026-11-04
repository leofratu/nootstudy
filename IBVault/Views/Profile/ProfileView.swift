import SwiftUI
import SwiftData

struct ProfileView: View {
    @Query private var profiles: [UserProfile]
    @Query private var achievements: [Achievement]
    @Query(sort: \StudyActivity.date, order: .reverse) private var activities: [StudyActivity]
    @Query private var tracks: [SubjectTrack]
    @Query private var subjects: [Subject]
    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    StudioPageHeader(
                        eyebrow: "Learning identity",
                        title: profile?.studentName.isEmpty == false ? profile?.studentName ?? "Profile" : "Your profile",
                        subtitle: [profile?.achievedStep.displayName, profile?.ibYear.shortLabel].compactMap { $0 }.joined(separator: " · "),
                        symbol: profile?.achievedStep.rank.symbolName ?? "person.crop.circle.fill",
                        tint: IBColors.accent
                    ) {
                        EmptyView()
                    }

                    statsGrid
                    rankProgressCard
                    studyHeatmap
                    achievementsCard
                    activityCard
                }
                .frame(maxWidth: 1080, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(IBColors.canvas)
            .navigationTitle("Profile")
        }
    }

    private var liveMastery: Double {
        RankLadderView.liveMastery(subjects: subjects, tracks: tracks)
    }

    // MARK: - Rank
    private var rankProgressCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            StudioSectionHeader("Rank", symbol: "") { EmptyView() }
            RankLadderView(achieved: profile?.achievedStep ?? RankStep(ordinal: 0), liveMastery: liveMastery)
        }
        .padding(20)
        .surfaceCard()
    }

    private var studyHeatmap: some View {
        VStack(alignment: .leading, spacing: 14) {
            StudioSectionHeader("Consistency", subtitle: "Your last year of reviews and study time.", symbol: "") { EmptyView() }
            HeatmapView(activities: activities)
        }
        .padding(20)
        .surfaceCard()
    }

    // MARK: - Stats
    private var statsGrid: some View {
        HStack(spacing: 16) {
            StudioMetricTile(value: "\(profile?.totalXP ?? 0)", label: "Total XP", symbol: "")
            StudioMetricTile(value: "\(profile?.currentStreak ?? 0)", label: "Current streak", symbol: "")
            StudioMetricTile(value: "\(profile?.longestStreak ?? 0)", label: "Best streak", symbol: "")
            StudioMetricTile(value: "\(profile?.streakFreezes ?? 0)", label: "Streak freezes", symbol: "")
        }
    }

    // MARK: - Achievements
    private var achievementsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Achievements")
                    .font(IBTypography.sectionTitle)
                Spacer()
                let unlocked = achievements.filter(\.unlocked).count
                Text("\(unlocked)/\(achievements.count)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            if achievements.isEmpty {
                HStack {
                    Spacer()
                    Text("No achievements yet.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                    Spacer()
                }
            } else {
                let columns = [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 12)]
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(achievements, id: \.id) { achievement in
                        HStack(spacing: 8) {
                            Image(systemName: achievement.icon)
                                .foregroundStyle(achievement.unlocked ? IBColors.accent : IBColors.inkTertiary)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(achievement.title)
                                    .font(.caption.bold())
                                    .lineLimit(1)
                                Text(achievement.desc)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(achievement.unlocked ? 1 : 0.5)
                    }
                }
            }
        }
        .padding(20)
        .surfaceCard()
    }

    // MARK: - Recent Activity
    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent activity")
                .font(IBTypography.sectionTitle)

            let recent = Array(activities.prefix(10))
            if recent.isEmpty {
                HStack {
                    Spacer()
                    Text("No study activity recorded yet.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                    Spacer()
                }
            } else {
                ForEach(recent, id: \.id) { activity in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.date, style: .date)
                                .font(.callout)
                            HStack(spacing: 8) {
                                Label("\(activity.cardsReviewed)", systemImage: "square.stack")
                                Label("\(Int(activity.minutesStudied))m", systemImage: "clock")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("+\(activity.xpEarned) XP")
                            .font(.callout.bold())
                            .foregroundStyle(IBColors.accent)
                    }
                    .padding(.vertical, 2)
                    if activity.id != recent.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(20)
        .surfaceCard()
    }
}
