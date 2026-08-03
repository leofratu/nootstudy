import SwiftUI
import SwiftData

struct StudyPlannerView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StudyPlan.scheduledDate, order: .forward) private var allPlans: [StudyPlan]
    @Query(sort: \StudySession.startDate, order: .reverse) private var recentSessions: [StudySession]
    @Query private var subjects: [Subject]
    @State private var showNewSession = false
    @State private var selectedPlan: StudyPlan?
    @State private var selectedReviewSession: StudySession?

    private var upcomingPlans: [StudyPlan] {
        // Today's plans are shown in their own section; excluding them here
        // prevents a same-day plan appearing in both "Today" and "Upcoming".
        allPlans.filter {
            ($0.isUpcoming || $0.isActive) && !Calendar.current.isDateInToday($0.scheduledDate)
        }
    }

    private var todayPlans: [StudyPlan] {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        return allPlans.filter { $0.scheduledDate >= today && $0.scheduledDate < tomorrow && !$0.isCompleted }
    }

    private var completedPlans: [StudyPlan] {
        allPlans.filter { $0.isCompleted }.suffix(10).reversed()
    }

    private var weekSessionsCount: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
        return recentSessions.filter { $0.startDate >= weekAgo }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    StudioPageHeader(
                        eyebrow: "Study cadence",
                        title: "Study sessions",
                        subtitle: todayPlans.isEmpty ? "Plan a focused block, then turn the work into a review path you can trust." : "\(todayPlans.count) sessions are lined up for today.",
                        symbol: "calendar.badge.clock",
                        tint: IBColors.electricBlue
                    ) {
                        Button {
                            showNewSession = true
                            IBHaptics.medium()
                        } label: {
                            Label("New session", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(IBColors.electricBlue)
                        .keyboardShortcut("n", modifiers: .command)
                    }

                    HStack(spacing: 12) {
                        StudioMetricTile(value: "\(todayPlans.count)", label: "Today", symbol: "calendar", tint: IBColors.coral, detail: todayPlans.isEmpty ? "Open space" : "Scheduled blocks")
                        StudioMetricTile(value: "\(upcomingPlans.count)", label: "Upcoming", symbol: "clock.arrow.circlepath", tint: IBColors.electricBlue, detail: "On your horizon")
                        StudioMetricTile(value: "\(weekSessionsCount)", label: "This week", symbol: "checkmark.seal.fill", tint: IBColors.teal, detail: "Completed sessions")
                    }

                    // Today's Sessions
                    if !todayPlans.isEmpty {
                        todaySection
                    }

                    // Calendar
                    StudyCalendarView(plans: allPlans) { plan in
                        openPlan(plan)
                    } onDeletePlan: { plan, scheduleReviews in
                        deletePlan(plan, scheduleReviews: scheduleReviews)
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
            .sheet(isPresented: $showNewSession) {
                NewStudySessionView()
            }
            .sheet(item: $selectedPlan, onDismiss: {
                selectedPlan = nil
            }) { plan in
                if plan.isFollowUpReview {
                    ReviewSessionView(filterSubject: subject(for: plan), filterPlan: plan)
                } else {
                    // Do NOT dismiss the sheet on completion: ActiveStudySessionView
                    // flips into its own completion screen (stats, scheduled
                    // reviews, rank), which the user closes with "Done". Dismissing
                    // here would tear the sheet down the moment the session
                    // finished, before that screen could ever appear.
                    ActiveStudySessionView(plan: plan)
                }
            }
            .sheet(item: $selectedReviewSession, onDismiss: {
                selectedReviewSession = nil
            }) { session in
                ReviewSessionView(
                    filterSubject: subject(named: session.subjectName),
                    reviewScopeSession: session
                )
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
                        $0.startDate > (Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast)
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
                        Text(plan.selectionSummary.isEmpty ? plan.scheduleLabel : plan.selectionSummary)
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
                Button {
                    selectedReviewSession = session
                    IBHaptics.light()
                } label: {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(subjectColor(session.subjectName))
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
                                .foregroundStyle(IBColors.electricBlue)
                            Text("Revise")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(IBColors.electricBlue)
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
        case "Advanced Mathematics": return Color(hex: "8B5CF6")
        case "Fundamentals of the Universe": return Color(hex: "6366F1")
        case "Startups & Venture Capital": return Color(hex: "0EA5E9")
        default: return .gray
        }
    }

    private func openPlan(_ plan: StudyPlan) {
        selectedPlan = plan
        IBHaptics.light()
    }

    private func deletePlan(_ plan: StudyPlan, scheduleReviews: Bool) {
        // "Delete & Add Review" schedules follow-up reviews first; plain
        // "Delete Session" removes the plan (and its review chain) without them.
        if scheduleReviews && !plan.isFollowUpReview {
            scheduleSpacedReviews(for: plan)
        }

        context.delete(plan)
        do {
            try context.save()
        } catch {
            // Undo the deletion (and any review plans scheduled above) so the
            // plan is not lost to a half-persisted state; the delete dialog can
            // simply be reopened to retry.
            context.rollback()
            return
        }
        IBHaptics.medium()
    }

    private func scheduleSpacedReviews(for plan: StudyPlan) {
        let cal = Calendar.current
        let endDate = plan.scheduledDate
        let existingPlans = (try? context.fetch(FetchDescriptor<StudyPlan>())) ?? []
        
        let reviewDays = plan.reviewScheduleOffsets
        
        for days in reviewDays {
            guard let date = cal.date(byAdding: .day, value: days, to: endDate),
                  let scheduledAt = cal.date(bySettingHour: 16, minute: 0, second: 0, of: date) else { continue }

            let duplicateExists = existingPlans.contains {
                $0.isFollowUpReview &&
                !$0.isCompleted &&
                $0.subjectName == plan.subjectName &&
                $0.topicName == plan.topicName &&
                $0.subtopicName == plan.subtopicName &&
                $0.reviewIntervalDays == days &&
                Calendar.current.isDate($0.scheduledDate, equalTo: scheduledAt, toGranularity: .minute)
            }

            guard !duplicateExists else { continue }
            
            let review = StudyPlan(
                subjectName: plan.subjectName,
                topicName: plan.topicName,
                subtopicName: plan.subtopicName,
                planMarkdown: """
                📝 **Spaced Repetition Review**

                Revisit \(plan.selectionSummary) from your session on \(plan.scheduledDate.formatted(date: .abbreviated, time: .omitted)).

                **Quick Recall** (10 min): Try to recall key concepts without notes

                **Review Cards** (15 min): Work through flashcards

                **Practice** (10 min): Attempt one exam-style question

                **Self-Assessment**: Rate your confidence 1-5

                Interval: Day \(days) review
                """,
                scheduledDate: scheduledAt,
                durationMinutes: 30,
                kind: .followUpReview,
                reviewIntervalDays: days,
                reviewScheduleOffsets: []
            )
            context.insert(review)
        }
    }

    private func subject(for plan: StudyPlan) -> Subject? {
        subjects.first(where: { $0.name == plan.subjectName })
    }

    private func subject(named name: String) -> Subject? {
        subjects.first(where: { $0.name == name })
    }
}
