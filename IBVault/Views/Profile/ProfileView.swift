import SwiftUI
import SwiftData

struct ProfileView: View {
    @Query private var profiles: [UserProfile]
    @Query private var achievements: [Achievement]
    @Query(sort: \StudyActivity.date, order: .reverse) private var activities: [StudyActivity]
    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            List {
                accountSection
                rankProgressSection
                activitySection
                achievementsSection
            }
            .listStyle(.inset)
            .controlSize(.small)
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(destination: SettingsView()) {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
        }
    }

    private var accountSection: some View {
        Section("Account") {
            if let p = profile {
                LabeledContent("Rank", value: "\(p.rank.emoji) \(p.rank.rawValue)")
                LabeledContent("Total XP", value: "\(p.totalXP)")
                LabeledContent("Current streak", value: "\(p.currentStreak)")
                LabeledContent("Best streak", value: "\(p.longestStreak)")
                LabeledContent("Streak freezes", value: "\(p.streakFreezes)")
            } else {
                Text("No profile available.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rankProgressSection: some View {
        Section("Rank Progress") {
            if let p = profile {
                if let next = p.rank.next {
                    LabeledContent("Next rank", value: next.rawValue)
                    ProgressView(value: p.progressToNextRank)
                    Text("\(p.totalXP) / \(next.xpRequired) XP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Maximum rank achieved.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Complete onboarding to create a profile.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var achievementsSection: some View {
        Section("Achievements") {
            if achievements.isEmpty {
                Text("No achievements yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(achievements, id: \.id) { achievement in
                    HStack(alignment: .top) {
                        Image(systemName: achievement.icon)
                            .foregroundStyle(achievement.unlocked ? Color.yellow : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(achievement.title)
                            Text(achievement.desc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if achievement.unlocked {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
        }
    }

    private var activitySection: some View {
        Section("Recent Activity") {
            let recent = Array(activities.prefix(14))
            if recent.isEmpty {
                Text("No study activity recorded yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recent, id: \.id) { activity in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.date, style: .date)
                            Text("\(activity.cardsReviewed) cards • \(Int(activity.minutesStudied)) min")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("+\(activity.xpEarned) XP")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
