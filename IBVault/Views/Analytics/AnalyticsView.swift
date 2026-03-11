import SwiftUI
import SwiftData

struct AnalyticsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StudyActivity.date, order: .reverse) private var activities: [StudyActivity]
    @Query private var subjects: [Subject]
    @Query(sort: \ReviewSession.timestamp, order: .reverse) private var sessions: [ReviewSession]

    var body: some View {
        NavigationStack {
            ZStack {
                IBColors.navy.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: IBSpacing.lg) {
                        Text("Analytics").font(IBTypography.largeTitle).foregroundColor(IBColors.softWhite)
                            .padding(.horizontal, IBSpacing.md).padding(.top, IBSpacing.md)
                        heatmapSection
                        weeklyStatsSection
                        subjectBreakdownSection
                        retentionSection
                    }.padding(.bottom, 100)
                }
            }.navigationBarHidden(true)
        }
    }

    private var heatmapSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: IBSpacing.sm) {
                Text("Study Activity").font(IBTypography.headline).foregroundColor(IBColors.softWhite)
                HeatmapView(activities: activities)
            }
        }.padding(.horizontal, IBSpacing.md)
    }

    private var weeklyStatsSection: some View {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let weekActivities = activities.filter { $0.date >= weekAgo }
        let totalCards = weekActivities.reduce(0) { $0 + $1.cardsReviewed }
        let totalXP = weekActivities.reduce(0) { $0 + $1.xpEarned }
        let totalMins = weekActivities.reduce(0.0) { $0 + $1.minutesStudied }
        let weekSessions = sessions.filter { $0.timestamp >= weekAgo }
        let retention = ProficiencyTracker.retentionRate(from: weekSessions)

        return GlassCard {
            VStack(alignment: .leading, spacing: IBSpacing.md) {
                Text("Weekly Report").font(IBTypography.headline).foregroundColor(IBColors.softWhite)
                HStack(spacing: IBSpacing.md) {
                    miniStat(value: "\(totalCards)", label: "Cards", color: IBColors.electricBlue)
                    miniStat(value: "\(totalXP)", label: "XP", color: IBColors.warning)
                    miniStat(value: "\(Int(totalMins))m", label: "Study Time", color: IBColors.success)
                    miniStat(value: "\(Int(retention * 100))%", label: "Retention", color: IBColors.electricBlueLight)
                }
            }
        }.padding(.horizontal, IBSpacing.md)
    }

    private func miniStat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(color)
            Text(label).font(IBTypography.caption).foregroundColor(IBColors.mutedGray)
        }.frame(maxWidth: .infinity)
    }

    private var subjectBreakdownSection: some View {
        VStack(alignment: .leading, spacing: IBSpacing.sm) {
            Text("Subject Breakdown").font(IBTypography.headline).foregroundColor(IBColors.softWhite)
                .padding(.horizontal, IBSpacing.md)
            ForEach(subjects, id: \.id) { subject in
                let mastery = ProficiencyTracker.masteryPercentage(for: subject)
                let weak = ProficiencyTracker.weakTopics(for: subject)
                GlassCard(cornerRadius: 12, padding: IBSpacing.sm) {
                    VStack(alignment: .leading, spacing: IBSpacing.xs) {
                        HStack {
                            Circle().fill(Color(hex: subject.accentColorHex)).frame(width: 8, height: 8)
                            Text(subject.name).font(IBTypography.body).foregroundColor(IBColors.softWhite)
                            Spacer()
                            Text("\(Int(mastery * 100))%").font(IBTypography.captionBold).foregroundColor(Color(hex: subject.accentColorHex))
                        }
                        MasteryBar(progress: mastery, height: 4, color: Color(hex: subject.accentColorHex))
                        if !weak.isEmpty {
                            Text("Weak: \(weak.prefix(3).map(\.topicName).joined(separator: ", "))").font(IBTypography.caption).foregroundColor(IBColors.danger).lineLimit(1)
                        }
                    }
                }.padding(.horizontal, IBSpacing.md)
            }
        }
    }

    private var retentionSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: IBSpacing.sm) {
                Text("Retention Over Time").font(IBTypography.headline).foregroundColor(IBColors.softWhite)
                if sessions.count < 5 {
                    Text("Complete more reviews to see your retention curve").font(IBTypography.caption).foregroundColor(IBColors.mutedGray)
                } else {
                    RetentionChart(sessions: Array(sessions.prefix(30)))
                }
            }
        }.padding(.horizontal, IBSpacing.md)
    }
}

struct RetentionChart: View {
    let sessions: [ReviewSession]
    var body: some View {
        let grouped = Dictionary(grouping: sessions) { Calendar.current.startOfDay(for: $0.timestamp) }
        let sorted = grouped.sorted { $0.key < $1.key }
        let rates = sorted.map { ProficiencyTracker.retentionRate(from: $0.value) }
        GeometryReader { geo in
            Path { path in
                guard rates.count > 1 else { return }
                let stepX = geo.size.width / CGFloat(rates.count - 1)
                for (i, rate) in rates.enumerated() {
                    let x = CGFloat(i) * stepX
                    let y = geo.size.height * (1 - rate)
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }.stroke(IBColors.electricBlue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }.frame(height: 100)
    }
}
