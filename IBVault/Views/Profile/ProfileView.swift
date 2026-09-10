import SwiftUI
import SwiftData

struct ProfileView: View {
    @Query private var profiles: [UserProfile]
    @Query private var achievements: [Achievement]
    @Query(sort: \StudyActivity.date, order: .reverse) private var activities: [StudyActivity]
    @State private var showSettings = false
    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    StudioPageHeader(
                        eyebrow: "Learning identity",
                        title: profile?.studentName.isEmpty == false ? profile?.studentName ?? "Profile" : "Your profile",
                        subtitle: "Your earned rank, consistency, and the milestones behind your study practice.",
                        symbol: profile?.achievedStep.rank.symbolName ?? "person.crop.circle.fill",
                        tint: IBColors.accent
                    ) {
                        StudioPill(title: profile?.achievedStep.displayName.uppercased() ?? "UNRANKED", tint: IBColors.accent)
                    }

                    profileHero
                    rankProgressCard
                    statsGrid
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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView()
                }
                .frame(minWidth: 600, minHeight: 500)
            }
        }
    }

    // MARK: - Hero Card
    private var profileHero: some View {
        HStack(spacing: 20) {
            // Rank badge
            ZStack {
                Circle()
                    .fill(IBColors.accent.opacity(0.08))
                    .frame(width: 80, height: 80)
                Image(systemName: profile?.achievedStep.rank.symbolName ?? "bolt.circle")
                    .font(.system(size: 32))
                    .foregroundStyle(IBColors.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(profile?.studentName ?? "Student")
                    .font(.title2.bold())
                HStack(spacing: 8) {
                    Text(profile?.achievedStep.displayName ?? "Unranked")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(IBColors.accent)
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text(profile?.ibYear.rawValue ?? "")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text("\(profile?.studyIntensity.emoji ?? "") \(profile?.studyIntensity.rawValue ?? "") intensity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(20)
        .glassCard()
    }

    // MARK: - Rank Progress
    private var rankProgressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(IBColors.inkTertiary)
                Text("Rank Progress")
                    .font(.headline)
            }

            if let p = profile {
                HStack(spacing: 8) {
                    Image(systemName: p.achievedStep.rank.symbolName)
                        .foregroundStyle(IBColors.accent)
                    Text(p.achievedStep.displayName)
                        .font(.callout.weight(.medium))
                }
            }
        }
        .padding(16)
        .glassCard()
    }

    // MARK: - Stats Grid
    private var statsGrid: some View {
        HStack(spacing: 0) {
            StatCard(
                value: "\(profile?.totalXP ?? 0)",
                label: "Total XP",
                color: IBColors.accent,
                icon: "star.fill"
            )
            Divider().frame(height: 50)
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text("🔥")
                        .font(.system(size: 16))
                    Text("\(profile?.currentStreak ?? 0)")
                        .font(IBTypography.stat)
                        .foregroundColor(IBColors.inkTertiary)
                }
                Text("Current Streak")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            Divider().frame(height: 50)
            StatCard(
                value: "\(profile?.longestStreak ?? 0)",
                label: "Best Streak",
                color: IBColors.success,
                icon: "flame.fill"
            )
            Divider().frame(height: 50)
            HStack(spacing: 4) {
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "snowflake")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(IBColors.inkTertiary)
                        Text("\(profile?.streakFreezes ?? 0)")
                            .font(IBTypography.stat)
                            .foregroundColor(IBColors.inkTertiary)
                    }
                    Text("Freezes Left")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 16)
        .glassCard()
    }

    // MARK: - Achievements
    private var achievementsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "medal.fill")
                    .foregroundStyle(IBColors.inkTertiary)
                Text("Achievements")
                    .font(.headline)
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
                                .foregroundStyle(achievement.unlocked ? IBColors.inkTertiary : Color.secondary)
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
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(achievement.unlocked ? IBColors.inkTertiary.opacity(0.06) : Color.primary.opacity(0.03))
                        )
                        .opacity(achievement.unlocked ? 1 : 0.5)
                    }
                }
            }
        }
        .padding(16)
        .glassCard()
    }

    // MARK: - Recent Activity
    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.tint)
                Text("Recent Activity")
                    .font(.headline)
            }

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
        .padding(16)
        .glassCard()
    }
}
