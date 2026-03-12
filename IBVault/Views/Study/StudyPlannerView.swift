import SwiftUI
import SwiftData

struct StudyPlannerView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StudyPlan.scheduledDate, order: .forward) private var allPlans: [StudyPlan]
    @Query(sort: \StudySession.startDate, order: .reverse) private var recentSessions: [StudySession]
    @Query private var subjects: [Subject]
    @State private var showNewSession = false
    @State private var selectedPlan: StudyPlan?

    private var upcomingPlans: [StudyPlan] {
        allPlans.filter { $0.isUpcoming || $0.isActive }
    }

    private var todayPlans: [StudyPlan] {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        return allPlans.filter { $0.scheduledDate >= today && $0.scheduledDate < tomorrow && !$0.isCompleted }
    }

    private var completedPlans: [StudyPlan] {
        allPlans.filter { $0.isCompleted }.suffix(10).reversed()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Hero
                    heroCard
                        .padding(.horizontal, 28)
                        .padding(.top, 24)

                    // Today's Sessions
                    if !todayPlans.isEmpty {
                        todaySection
                            .padding(.horizontal, 28)
                    }

                    // Calendar
                    StudyCalendarView(plans: allPlans) { plan in
                        openPlan(plan)
                    } onDeletePlan: { plan in
                        deletePlan(plan)
                    }
                    .padding(.horizontal, 28)

                    // Upcoming
                    if !upcomingPlans.isEmpty {
                        upcomingSection
                            .padding(.horizontal, 28)
                    }

                    // Recent Sessions
                    if !recentSessions.isEmpty {
                        recentSessionsSection
                            .padding(.horizontal, 28)
                    }

                    // Empty state
                    if allPlans.isEmpty && recentSessions.isEmpty {
                        emptyState
                            .padding(.horizontal, 28)
                    }

                    Spacer().frame(height: 24)
                }
            }
            .background(.background)
            .navigationTitle("Study Planner")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showNewSession = true
                        IBHaptics.medium()
                    } label: {
                        Label("New Session", systemImage: "plus.circle.fill")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                }
            }
            .sheet(isPresented: $showNewSession) {
                NewStudySessionView()
            }
            .sheet(item: $selectedPlan) { plan in
                if plan.isFollowUpReview {
                    ReviewSessionView(filterSubject: subject(for: plan))
                } else {
                    ActiveStudySessionView(plan: plan)
                }
            }
        }
    }

    // MARK: - Hero
    private var heroCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // Left info
                VStack(alignment: .leading, spacing: 8) {
                    Text("Study Sessions")
                        .font(.system(size: 22, weight: .bold, design: .rounded))

                    if todayPlans.isEmpty && upcomingPlans.isEmpty {
                        Text("Plan your study time. ARIA creates\npersonalised study plans for each session.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                    } else {
                        let todayCount = todayPlans.count
                        let upCount = upcomingPlans.count
                        Text("\(todayCount) today · \(upCount) upcoming")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Stats ring
                if !recentSessions.isEmpty {
                    let weekSessions = recentSessions.filter {
                        $0.startDate > Calendar.current.date(byAdding: .day, value: -7, to: Date())!
                    }.count
                    VStack(spacing: 4) {
                        ProgressRing(
                            progress: min(Double(weekSessions) / 7.0, 1.0),
                            lineWidth: 5,
                            size: 52,
                            color: IBColors.electricBlue
                        )
                        Text("\(weekSessions)/7 this week")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    showNewSession = true
                    IBHaptics.medium()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text("New Session")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }

    // MARK: - Today
    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(.orange)
                    .frame(width: 7, height: 7)
                Text("Today")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            .padding(.leading, 4)

            ForEach(todayPlans, id: \.id) { plan in
                planRow(plan)
            }
        }
    }

    // MARK: - Upcoming
    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(IBColors.electricBlue)
                    .frame(width: 7, height: 7)
                Text("Upcoming")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                Text("\(upcomingPlans.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(IBColors.electricBlue.opacity(0.1)))
                    .foregroundStyle(IBColors.electricBlue)
            }
            .padding(.leading, 4)

            ForEach(upcomingPlans, id: \.id) { plan in
                planRow(plan)
            }
        }
    }

    // MARK: - Plan Row
    private func planRow(_ plan: StudyPlan) -> some View {
        Button {
            openPlan(plan)
        } label: {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(subjectColor(plan.subjectName))
                    .frame(width: 3, height: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.subjectName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text(plan.scheduleLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if plan.isFollowUpReview {
                            Text("REVIEW")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(IBColors.electricBlue.opacity(0.1)))
                                .foregroundStyle(IBColors.electricBlue)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(plan.scheduledTimeFormatted)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("\(plan.durationMinutes)m")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }

                if plan.isActive {
                    Text("NOW")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.green.opacity(0.12)))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.quaternary)
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.03), radius: 4, y: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent Sessions
    private var recentSessionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
                Text("Recent")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            .padding(.leading, 4)

            ForEach(recentSessions.prefix(5), id: \.id) { session in
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(subjectColor(session.subjectName))
                        .frame(width: 3, height: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.subjectName)
                            .font(.system(size: 13, weight: .medium))
                        HStack(spacing: 6) {
                            if session.cardsReviewed > 0 {
                                Label("\(session.cardsReviewed)", systemImage: "square.stack")
                            }
                            Label(session.durationFormatted, systemImage: "clock")
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if session.cardsReviewed > 0 {
                        retentionBadge(session.retentionPercent)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.04))
                )
            }
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 20)

            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(.tertiary)

            Text("No study sessions yet")
                .font(.system(size: 16, weight: .semibold, design: .rounded))

            Text("Create your first session. Pick a subject and topic,\nthen ARIA will build a personalised study plan.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            Button {
                showNewSession = true
                IBHaptics.medium()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Create First Session")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)

            Spacer().frame(height: 20)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [6]))
        )
    }

    private func retentionBadge(_ percent: Int) -> some View {
        let color: Color = percent >= 80 ? .green : percent >= 50 ? .orange : .red
        return Text("\(percent)%")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.1)))
            .foregroundStyle(color)
    }

    private func subjectColor(_ name: String) -> Color {
        switch name {
        case "English B": return IBColors.englishColor
        case "Russian A Literature": return IBColors.russianColor
        case "Biology": return IBColors.biologyColor
        case "Mathematics AA": return IBColors.mathColor
        case "Economics": return IBColors.economicsColor
        case "Business Management": return IBColors.businessColor
        default: return .gray
        }
    }

    private func openPlan(_ plan: StudyPlan) {
        selectedPlan = plan
        IBHaptics.light()
    }

    private func deletePlan(_ plan: StudyPlan) {
        // Schedule spaced repetition reviews before deleting
        if !plan.isFollowUpReview {
            scheduleSpacedReviews(for: plan)
        }
        
        context.delete(plan)
        try? context.save()
        IBHaptics.medium()
    }

    private func scheduleSpacedReviews(for plan: StudyPlan) {
        let cal = Calendar.current
        let endDate = plan.scheduledDate
        
        let reviewDays = [1, 3, 7]
        
        for days in reviewDays {
            guard let date = cal.date(byAdding: .day, value: days, to: endDate),
                  let scheduledAt = cal.date(bySettingHour: 16, minute: 0, second: 0, of: date) else { continue }
            
            let review = StudyPlan(
                subjectName: plan.subjectName,
                topicName: plan.topicName,
                subtopicName: plan.subtopicName,
                planMarkdown: """
                📝 **Spaced Repetition Review**

                Revisit \(plan.topicName) from your session on \(plan.scheduledDate.formatted(date: .abbreviated, time: .omitted)).

                **Quick Recall** (10 min): Try to recall key concepts without notes

                **Review Cards** (15 min): Work through flashcards

                **Practice** (10 min): Attempt one exam-style question

                **Self-Assessment**: Rate your confidence 1-5

                Interval: Day \(days) review
                """,
                scheduledDate: scheduledAt,
                durationMinutes: 30,
                kind: .followUpReview,
                reviewIntervalDays: days
            )
            context.insert(review)
        }
    }

    private func subject(for plan: StudyPlan) -> Subject? {
        subjects.first(where: { $0.name == plan.subjectName })
    }
}
