import SwiftUI
import SwiftData

struct ProfileView: View {
    @Query private var profiles: [UserProfile]
    @Query private var achievements: [Achievement]
    @Query(sort: \StudyActivity.date, order: .reverse) private var activities: [StudyActivity]
    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            ZStack {
                IBColors.navy.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: IBSpacing.lg) {
                        rankSection
                        xpSection
                        achievementsSection
                    }.padding(.horizontal, IBSpacing.md).padding(.bottom, 100)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape.fill").foregroundColor(IBColors.mutedGray)
                    }
                }
            }
        }
    }

    private var rankSection: some View {
        GlassCard {
            VStack(spacing: IBSpacing.md) {
                if let p = profile {
                    Text(p.rank.emoji).font(.system(size: 56))
                    Text(p.rank.rawValue).font(IBTypography.title).foregroundColor(IBColors.softWhite)
                    if let next = p.rank.next {
                        VStack(spacing: IBSpacing.xs) {
                            MasteryBar(progress: p.progressToNextRank, height: 8, color: IBColors.electricBlue)
                            HStack {
                                Text("\(p.totalXP) XP").font(IBTypography.caption).foregroundColor(IBColors.electricBlue)
                                Spacer()
                                Text("\(next.xpRequired) XP").font(IBTypography.caption).foregroundColor(IBColors.mutedGray)
                            }
                        }
                    } else {
                        Text("Maximum Rank Achieved!").font(IBTypography.caption).foregroundColor(IBColors.success)
                    }
                    HStack(spacing: IBSpacing.xl) {
                        VStack { Text("\(p.currentStreak)").font(IBTypography.title).foregroundColor(IBColors.streakOrange); Text("Streak").font(IBTypography.caption).foregroundColor(IBColors.mutedGray) }
                        VStack { Text("\(p.longestStreak)").font(IBTypography.title).foregroundColor(IBColors.electricBlue); Text("Best").font(IBTypography.caption).foregroundColor(IBColors.mutedGray) }
                        VStack { Text("\(p.streakFreezes)").font(IBTypography.title).foregroundColor(IBColors.warning); Text("Freezes").font(IBTypography.caption).foregroundColor(IBColors.mutedGray) }
                    }
                }
            }
        }
    }

    private var xpSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: IBSpacing.sm) {
                Text("XP History").font(IBTypography.headline).foregroundColor(IBColors.softWhite)
                let recent = Array(activities.prefix(14))
                if recent.isEmpty {
                    Text("No activity yet").font(IBTypography.caption).foregroundColor(IBColors.mutedGray)
                } else {
                    GeometryReader { geo in
                        let maxXP = max(1, recent.map(\.xpEarned).max() ?? 1)
                        HStack(alignment: .bottom, spacing: 4) {
                            ForEach(recent.reversed(), id: \.id) { a in
                                let h = CGFloat(a.xpEarned) / CGFloat(maxXP) * geo.size.height
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(IBColors.electricBlue.opacity(0.7))
                                    .frame(width: max(4, (geo.size.width - CGFloat(recent.count) * 4) / CGFloat(recent.count)), height: max(4, h))
                            }
                        }
                    }.frame(height: 80)
                }
            }
        }
    }

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: IBSpacing.sm) {
            Text("Achievements").font(IBTypography.headline).foregroundColor(IBColors.softWhite)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: IBSpacing.sm) {
                ForEach(achievements, id: \.id) { ach in
                    GlassCard(cornerRadius: 12, padding: IBSpacing.sm) {
                        HStack(spacing: IBSpacing.sm) {
                            Image(systemName: ach.icon)
                                .font(.title3).foregroundColor(ach.unlocked ? IBColors.warning : IBColors.mutedGray.opacity(0.4))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ach.title).font(IBTypography.captionBold).foregroundColor(ach.unlocked ? IBColors.softWhite : IBColors.mutedGray)
                                Text(ach.desc).font(.system(size: 10)).foregroundColor(IBColors.mutedGray).lineLimit(2)
                            }
                        }.opacity(ach.unlocked ? 1 : 0.5)
                    }
                }
            }
        }
    }
}
