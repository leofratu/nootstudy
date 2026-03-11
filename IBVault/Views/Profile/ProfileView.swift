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
                VStack(spacing: 16) {
                    // Hero card with rank + stats
                    profileHero
                        .padding(.horizontal, 24)
                        .padding(.top, 20)

                    // Rank progress
                    rankProgressCard
                        .padding(.horizontal, 24)

                    // Stats grid
                    statsGrid
                        .padding(.horizontal, 24)

                    // Achievements
                    achievementsCard
                        .padding(.horizontal, 24)

                    // Recent Activity
                    activityCard
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                }
            }
            .background(.background)
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
                    .fill(IBColors.electricBlue.opacity(0.08))
                    .frame(width: 80, height: 80)
                Text(profile?.rank.emoji ?? "⚡")
                    .font(.system(size: 36))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(profile?.studentName ?? "Student")
                    .font(.title2.bold())
                HStack(spacing: 8) {
                    Text(profile?.rank.rawValue ?? "Unranked")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(IBColors.electricBlue)
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
                    .foregroundStyle(.yellow)
                Text("Rank Progress")
                    .font(.headline)
            }

            if let p = profile {
                if let next = p.rank.next {
                    HStack {
                        Text(p.rank.emoji)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: p.progressToNextRank)
                                .tint(IBColors.electricBlue)
                            Text("\(p.totalXP) / \(next.xpRequired) XP to \(next.rawValue)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(next.emoji)
                            .font(.title3)
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(.yellow)
                        Text("Maximum rank achieved!")
                            .font(.callout.weight(.medium))
                    }
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
                color: IBColors.electricBlue,
                icon: "star.fill"
            )
            Divider().frame(height: 50)
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text("🔥")
                        .font(.system(size: 16))
                    Text("\(profile?.currentStreak ?? 0)")
                        .font(IBTypography.stat)
                        .foregroundColor(IBColors.streakOrange)
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
                            .foregroundStyle(.cyan)
                        Text("\(profile?.streakFreezes ?? 0)")
                            .font(IBTypography.stat)
                            .foregroundColor(.cyan)
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
                    .foregroundStyle(.yellow)
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
                                .foregroundStyle(achievement.unlocked ? Color.yellow : Color.secondary)
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
                                .fill(achievement.unlocked ? Color.yellow.opacity(0.06) : Color.primary.opacity(0.03))
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
                            .foregroundStyle(IBColors.electricBlue)
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
