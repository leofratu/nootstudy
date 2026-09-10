import SwiftUI
import SwiftData

struct StudyPlannerView: View {
    private enum PresentedSheet: Identifiable {
        case newSession(Date?)
        case plan(StudyPlan)
        case review(StudySession)

        var id: String {
            switch self {
            case .newSession: return "new-session"
            case .plan(let plan): return "plan-\(plan.id.uuidString)"
            case .review(let session): return "review-\(session.id.uuidString)"
            }
        }
    }
    @Environment(\.modelContext) private var context
    @Query(sort: \StudyPlan.scheduledDate, order: .forward) private var allPlans: [StudyPlan]
    @Query(sort: \StudySession.startDate, order: .reverse) private var recentSessions: [StudySession]
    @Query private var subjects: [Subject]
    @State private var selectedScheduleSlot: Date?
    @State private var presentedSheet: PresentedSheet?
    @State private var planPendingDeletion: StudyPlan?

    private var upcomingPlans: [StudyPlan] {
        // Today's plans are shown in their own section; excluding them here
        // prevents a same-day plan appearing in both "Today" and "Upcoming".
        allPlans.filter {
            !$0.isFollowUpReview && ($0.isUpcoming || $0.isActive) &&
                !IBLocalClock.calendar.isDate($0.scheduledDate, inSameDayAs: IBLocalClock.now)
        }
    }

    private var todayPlans: [StudyPlan] {
        let today = IBLocalClock.calendar.startOfDay(for: IBLocalClock.now)
        let tomorrow = IBLocalClock.calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return allPlans.filter {
            !$0.isFollowUpReview && $0.scheduledDate >= today && $0.scheduledDate < tomorrow && !$0.isCompleted
        }
    }

    private var completedPlans: [StudyPlan] {
        allPlans.filter { $0.isCompleted }.suffix(10).reversed()
    }

    private var weekSessionsCount: Int {
        let weekAgo = IBLocalClock.calendar.date(byAdding: .day, value: -7, to: IBLocalClock.now) ?? .distantPast
        return recentSessions.filter { $0.startDate >= weekAgo }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    StudioPageHeader(
                        eyebrow: "Study cadence",
                        title: "Study sessions",
                        subtitle: todayPlans.isEmpty ? "Plan a focused block, then turn the work into a review path you can trust." : (todayPlans.count == 1 ? "1 session is lined up for today." : "\(todayPlans.count) sessions are lined up for today."),
                        symbol: "calendar.badge.clock",
                        tint: IBColors.accent
                    ) {
                        Button {
                            selectedScheduleSlot = nil
                            presentedSheet = .newSession(nil)
                            IBHaptics.medium()
                        } label: {
                            Label("New session", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(IBColors.accent)
                        .keyboardShortcut("n", modifiers: .command)
                    }

                    HStack(spacing: 12) {
                        StudioMetricTile(value: "\(todayPlans.count)", label: "Today", symbol: "calendar", tint: IBColors.inkTertiary, detail: todayPlans.isEmpty ? "Open space" : "Scheduled blocks")
                        StudioMetricTile(value: "\(upcomingPlans.count)", label: "Upcoming", symbol: "clock.arrow.circlepath", tint: IBColors.accent, detail: "On your horizon")
                        StudioMetricTile(value: "\(weekSessionsCount)", label: "This week", symbol: "checkmark.seal.fill", tint: IBColors.inkTertiary, detail: "Completed sessions")
                    }

                    // Today's Sessions
                    if !todayPlans.isEmpty {
                        todaySection
                    }

                    // Calendar
                    StudyCalendarView(plans: allPlans.filter { !$0.isFollowUpReview }) { plan in
                        openPlan(plan)
                    } onDeletePlan: { plan in
                        planPendingDeletion = plan
                    } onSchedule: { date in
                        selectedScheduleSlot = date
                        presentedSheet = .newSession(date)
                    }

                    // Upcoming
                    if !upcomingPlans.isEmpty {
                        upcomingSection
                    }

                    // Recent Sessions
                    if !recentSessions.isEmpty {
                        recentSessionsSection
                    }

                    // Empty state
                    if allPlans.isEmpty && recentSessions.isEmpty {
                        emptyState
                    }
                }
                .frame(maxWidth: 1240, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(IBColors.canvas)
            .navigationTitle("Study Planner")
            .sheet(item: $presentedSheet, onDismiss: {
                presentedSheet = nil
                selectedScheduleSlot = nil
            }) { sheet in
                switch sheet {
                case .newSession(let date):
                    NewStudySessionView(initialScheduledDate: date)
                case .plan(let plan):
                    if plan.isFollowUpReview {
                        ReviewSessionView(filterSubject: subject(for: plan), filterPlan: plan)
                    } else {
                        ActiveStudySessionView(plan: plan)
                    }
                case .review(let session):
                    ReviewSessionView(filterSubject: subject(named: session.subjectName), reviewScopeSession: session)
                }
            }
            .confirmationDialog(
                "Delete this study block?",
                isPresented: Binding(
                    get: { planPendingDeletion != nil },
                    set: { if !$0 { planPendingDeletion = nil } }
                ),
                presenting: planPendingDeletion
            ) { plan in
                Button("Delete block", role: .destructive) {
                    deletePlan(plan)
                    planPendingDeletion = nil
                }
                Button("Cancel", role: .cancel) {
                    planPendingDeletion = nil
                }
            } message: { plan in
                Text("\(plan.subjectName) · \(plan.scheduleLabel). Saved flashcards and completed study history will remain.")
            }
        }
    }

    // MARK: - Today
    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(IBColors.warning)
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
                    .fill(IBColors.accent)
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
                    .background(Capsule().fill(IBColors.accent.opacity(0.1)))
                    .foregroundStyle(IBColors.accent)
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
                    .fill(IBColors.inkTertiary)
                    .frame(width: 3, height: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.subjectName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .help(plan.subjectName)
                    HStack(spacing: 6) {
                        Text(plan.selectionSummary.isEmpty ? plan.scheduleLabel : plan.selectionSummary)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .help(plan.selectionSummary.isEmpty ? plan.scheduleLabel : plan.selectionSummary)
                        if plan.isFollowUpReview {
                            Text("REVIEW")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(IBColors.accent.opacity(0.1)))
                                .foregroundStyle(IBColors.accent)
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
                        .background(Capsule().fill(IBColors.success.opacity(0.12)))
                        .foregroundStyle(IBColors.success)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.quaternary)
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .padding(12)
            .glassCard(cornerRadius: IBRadius.md)
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
                Button {
                    presentedSheet = .review(session)
                    IBHaptics.light()
                } label: {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(IBColors.inkTertiary)
                            .frame(width: 3, height: 44)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.subjectName)
                                .font(.system(size: 13, weight: .medium))
                            Text(session.scopeSummary)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
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

                        VStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .foregroundStyle(IBColors.accent)
                            Text("Revise")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(IBColors.accent)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)
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
                presentedSheet = .newSession(nil)
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
        let color: Color = percent >= 80 ? IBColors.success : percent >= 50 ? IBColors.warning : IBColors.danger
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
        case "Advanced Mathematics": return Color(hex: "8B5CF6")
        case "Fundamentals of the Universe": return Color(hex: "6366F1")
        case "Life", "Founder Academy", "Startups & Venture Capital": return Color(hex: "0EA5E9")
        default: return .gray
        }
    }

    private func openPlan(_ plan: StudyPlan) {
        presentedSheet = .plan(plan)
        IBHaptics.light()
    }

    private func deletePlan(_ plan: StudyPlan) {
        context.delete(plan)
        do {
            try context.save()
        } catch {
            context.insert(plan)
            return
        }
        IBHaptics.medium()
    }

    private func subject(for plan: StudyPlan) -> Subject? {
        subjects.first(where: { $0.name == plan.subjectName })
    }

    private func subject(named name: String) -> Subject? {
        subjects.first(where: { $0.name == name })
    }
}
