import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(sort: \StudyCard.nextReviewDate) private var allCards: [StudyCard]
    @Query private var subjects: [Subject]

    @State private var ariaService = ARIAService()
    @State private var reviewScheduler = ReviewScheduler()
    @State private var showReview = false
    @State private var selectedSubjectForReview: Subject?

    private var profile: UserProfile? { profiles.first }

    private var dueCards: [StudyCard] {
        allCards.filter { $0.isDue }
    }

    private var sortedSubjects: [Subject] {
        subjects.sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Hero stats bar
                    statsHeader
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .padding(.bottom, 8)

                    // ARIA greeting
                    ariaGreetingCard
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)

                    // Review + Subjects grid
                    HStack(alignment: .top, spacing: 16) {
                        // Left column: review queue
                        reviewCard
                        // Right column: tools
                        toolsCard
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)

                    // Subjects list
                    subjectsCard
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                }
            }
            .background(.background)
            .navigationTitle("Dashboard")
            .sheet(isPresented: $showReview) {
                ReviewSessionView(filterSubject: selectedSubjectForReview)
            }
            .task {
                await MainActor.run {
                    reviewScheduler.analyze(context: context)
                }
            }
        }
    }

    // MARK: - Stats Header
    private var statsHeader: some View {
        HStack(spacing: 0) {
            StatCard(
                value: "\(dueCards.count)",
                label: "Due Today",
                color: dueCards.isEmpty ? IBColors.success : IBColors.streakOrange,
                icon: "clock.badge.exclamationmark"
            )
            Divider().frame(height: 50)
            StatCard(
                value: "\(profile?.totalXP ?? 0)",
                label: "Total XP",
                color: IBColors.electricBlue,
                icon: "star.fill"
            )
            Divider().frame(height: 50)

            // Streak with fire
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text("🔥")
                        .font(.system(size: 18))
                    Text("\(profile?.currentStreak ?? 0)")
                        .font(IBTypography.stat)
                        .foregroundColor(IBColors.streakOrange)
                }
                Text("Day Streak")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 50)
            StatCard(
                value: "\(profile?.rank.emoji ?? "⚡") \(profile?.rank.rawValue ?? "—")",
                label: "Current Rank",
                color: IBColors.englishColor,
                icon: nil
            )
        }
        .padding(.vertical, 16)
        .glassCard()
        .padding(.vertical, 4)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    // MARK: - ARIA Greeting
    private var ariaGreetingCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(IBColors.electricBlue.opacity(0.1))
                    .frame(width: 38, height: 38)
                Image(systemName: "sparkles")
                    .foregroundStyle(IBColors.electricBlue)
                    .font(.system(size: 16, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("ARIA")
                    .font(.caption.bold())
                    .foregroundStyle(IBColors.electricBlue)
                Text(ariaService.generateGreeting(context: context))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(14)
        .glassCard()
        .padding(.vertical, 4)
    }

    // MARK: - Review Queue
    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.tint)
                Text("Review Queue")
                    .font(.headline)
                Spacer()
                Text("\(dueCards.count) due")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(dueCards.isEmpty ? Color.green.opacity(0.1) : Color.orange.opacity(0.12)))
                    .foregroundStyle(dueCards.isEmpty ? .green : .orange)
            }

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: reviewProgress)
                    .tint(IBColors.electricBlue)
                Text("\(Int(reviewProgress * 100))% of cards are currently not due")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if dueCards.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("All caught up!")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            } else {
                // Subject-specific review buttons
                let subjectsWithDue = reviewScheduler.schedules.prefix(3)
                if !subjectsWithDue.isEmpty {
                    ForEach(subjectsWithDue) { schedule in
                        Button {
                            IBHaptics.medium()
                            selectedSubjectForReview = schedule.subject
                            showReview = true
                        } label: {
                            HStack {
                                Circle()
                                    .fill(Color(hex: schedule.subject.accentColorHex))
                                    .frame(width: 8, height: 8)
                                Text(schedule.subject.name)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(schedule.dueCards) due")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Divider()
                }
                
                Button {
                    IBHaptics.medium()
                    selectedSubjectForReview = nil
                    showReview = true
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Review All")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(16)
        .glassCard()
    }

    // MARK: - Tools
    private var toolsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .foregroundStyle(.tint)
                Text("Tools")
                    .font(.headline)
            }

            NavigationLink {
                EffectivenessView()
            } label: {
                toolRow(icon: "chart.line.uptrend.xyaxis", color: .blue, label: "Effectiveness", desc: "Review performance insights")
            }

            NavigationLink {
                ADHDTrackerView()
            } label: {
                toolRow(icon: "pills.fill", color: .purple, label: "Medication", desc: "ADHD med tracker")
            }

            NavigationLink {
                MaterialsLibraryView()
            } label: {
                toolRow(icon: "books.vertical.fill", color: .orange, label: "Materials", desc: "Study resources library")
            }

            NavigationLink {
                AnalyticsView()
            } label: {
                toolRow(icon: "chart.bar.fill", color: .cyan, label: "Analytics", desc: "Weekly stats & retention")
            }
        }
        .padding(16)
        .glassCard()
    }

    private func toolRow(icon: String, color: Color, label: String, desc: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.callout.weight(.medium))
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var reviewProgress: Double {
        guard !allCards.isEmpty else { return 0 }
        let reviewed = allCards.filter { !$0.isDue }.count
        return Double(reviewed) / Double(allCards.count)
    }

    // MARK: - Subjects
    private var subjectsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "books.vertical.fill")
                    .foregroundStyle(.tint)
                Text("Subjects")
                    .font(.headline)
                Spacer()
                Text("\(sortedSubjects.count) enrolled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if sortedSubjects.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "books.vertical")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text("No subjects available yet.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
            } else {
                ForEach(sortedSubjects, id: \.id) { subject in
                    NavigationLink(destination: SubjectDetailView(subject: subject)) {
                        DashboardSubjectRow(subject: subject)
                    }
                    .buttonStyle(.plain)
                    if subject.id != sortedSubjects.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(16)
        .glassCard()
    }
}

// MARK: - Subject Row
private struct DashboardSubjectRow: View {
    let subject: Subject

    private var color: Color { Color(hex: subject.accentColorHex) }

    var body: some View {
        HStack(spacing: 12) {
            // Color indicator
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 4, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(subject.name)
                        .font(.callout.weight(.medium))
                    Text(subject.level)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(color.opacity(0.1)))
                        .foregroundStyle(color)
                }

                HStack(spacing: 12) {
                    Label("\(subject.cards.count) topics", systemImage: "square.stack")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if subject.dueCardsCount > 0 {
                        Label("\(subject.dueCardsCount) due", systemImage: "clock")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    } else {
                        Label("All clear", systemImage: "checkmark")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }

            Spacer()

            ProgressRing(
                progress: subject.masteryProgress,
                lineWidth: 4,
                size: 36,
                color: color
            )
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
