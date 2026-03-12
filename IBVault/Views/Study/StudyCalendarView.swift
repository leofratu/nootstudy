import SwiftUI
import SwiftData

struct StudyCalendarView: View {
    let plans: [StudyPlan]
    let onTapPlan: (StudyPlan) -> Void
    var onDeletePlan: ((StudyPlan) -> Void)?

    @State private var selectedWeekOffset = 0
    @State private var hoveredSlot: String?
    @State private var showDeleteConfirmation = false
    @State private var planToDelete: StudyPlan?

    private var currentWeekStart: Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let mondayOffset = (weekday == 1) ? -6 : (2 - weekday)
        let monday = cal.date(byAdding: .day, value: mondayOffset + (selectedWeekOffset * 7), to: today)!
        return monday
    }

    private var weekDays: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: currentWeekStart) }
    }

    // After-school study slots: 4pm to 10pm
    private let timeSlots = Array(16...21)

    private var visiblePlans: [StudyPlan] {
        plans.filter { !$0.isCompleted }
    }

    private var weekPlansCount: Int {
        visiblePlans.filter { plan in
            let start = Calendar.current.startOfDay(for: currentWeekStart)
            let end = Calendar.current.date(byAdding: .day, value: 7, to: start)!
            return plan.scheduledDate >= start && plan.scheduledDate < end
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerBar
                .padding(16)

            Divider().opacity(0.3)

            // Calendar Grid
            HStack(alignment: .top, spacing: 0) {
                // Time labels column
                VStack(spacing: 0) {
                    Color.clear.frame(height: 34)
                    ForEach(timeSlots, id: \.self) { hour in
                        Text(String(format: "%02d:00", hour))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(height: 52, alignment: .top)
                            .padding(.top, 3)
                    }
                }
                .frame(width: 42)
                .padding(.leading, 6)

                // Vertical divider
                Rectangle()
                    .fill(Color.primary.opacity(0.04))
                    .frame(width: 0.5)

                // Day columns
                ForEach(weekDays, id: \.self) { day in
                    if day != weekDays.first {
                        Rectangle()
                            .fill(Color.primary.opacity(0.03))
                            .frame(width: 0.5)
                    }
                    dayColumn(day)
                }
            }
            .padding(.bottom, 12)
        }
        .background(calendarBackground)
    }

    // Liquid glass background
    private var calendarBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.04),
                            Color.white.opacity(0.01),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.15),
                            Color.white.opacity(0.05),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        }
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }

    private var headerBar: some View {
        HStack(spacing: 10) {
            // Calendar icon with glow
            ZStack {
                Circle()
                    .fill(IBColors.electricBlue.opacity(0.06))
                    .frame(width: 28, height: 28)
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(IBColors.electricBlue)
            }

            Text("CALENDAR")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(1)

            Spacer()

            // Week stats
            if weekPlansCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                    Text("\(weekPlansCount) sessions")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(.orange.opacity(0.06))
                )
            }

            // Navigation
            HStack(spacing: 3) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedWeekOffset -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.secondary.opacity(0.06)))
                }
                .buttonStyle(.borderless)

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedWeekOffset = 0 }
                } label: {
                    Text("Today")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedWeekOffset += 1 }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.secondary.opacity(0.06)))
                }
                .buttonStyle(.borderless)
            }

            // Week range
            let weekLabel: String = {
                let fmt = DateFormatter()
                fmt.dateFormat = "d MMM"
                return "\(fmt.string(from: currentWeekStart)) – \(fmt.string(from: weekDays.last ?? currentWeekStart))"
            }()
            Text(weekLabel)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private func dayColumn(_ day: Date) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(day)
        let isPast = cal.startOfDay(for: day) < cal.startOfDay(for: Date())

        return VStack(spacing: 0) {
            // Day header
            VStack(spacing: 2) {
                Text(dayAbbrev(day))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(
                        isToday
                            ? AnyShapeStyle(IBColors.electricBlue)
                            : isPast
                                ? AnyShapeStyle(.quaternary)
                                : AnyShapeStyle(.tertiary)
                    )
                    .textCase(.uppercase)

                ZStack {
                    if isToday {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [IBColors.electricBlue, IBColors.electricBlue.opacity(0.8)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 24, height: 24)
                            .shadow(color: IBColors.electricBlue.opacity(0.3), radius: 6, y: 1)
                    }
                    Text(dayNum(day))
                        .font(.system(size: 12, weight: isToday ? .bold : .regular, design: .rounded))
                        .foregroundStyle(
                            isToday
                                ? AnyShapeStyle(.white)
                                : isPast
                                    ? AnyShapeStyle(.tertiary)
                                    : AnyShapeStyle(.primary)
                        )
                }
            }
            .frame(height: 34)

            // Time slots
            ForEach(timeSlots, id: \.self) { hour in
                let slotPlans = plansForSlot(day: day, hour: hour)
                let slotId = "\(dayNum(day))-\(hour)"
                ZStack {
                    // Base slot
                    Rectangle()
                        .fill(slotBackground(isToday: isToday, isPast: isPast, hour: hour))

                    // Grid line
                    VStack {
                        Rectangle()
                            .fill(Color.primary.opacity(0.03))
                            .frame(height: 0.5)
                        Spacer()
                    }

                    // Now indicator
                    if isToday && cal.component(.hour, from: Date()) == hour {
                        VStack {
                            HStack(spacing: 0) {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 6, height: 6)
                                Rectangle()
                                    .fill(.red)
                                    .frame(height: 1)
                            }
                            Spacer()
                        }
                        .padding(.top, CGFloat(cal.component(.minute, from: Date())) / 60.0 * 52)
                    }

                    // Plan block
                    if let plan = slotPlans.first {
                        Button {
                            onTapPlan(plan)
                        } label: {
                            sessionBlock(plan: plan)
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            hoveredSlot = hovering ? slotId : nil
                        }
                        .contextMenu {
                            if onDeletePlan != nil {
                                Button(role: .destructive) {
                                    planToDelete = plan
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete Session", systemImage: "trash")
                                }
                                
                                if !plan.isFollowUpReview {
                                    Divider()
                                    
                                    Button {
                                        planToDelete = plan
                                        showDeleteConfirmation = true
                                    } label: {
                                        Label("Delete & Add Review", systemImage: "arrow.triangle.2.circlepath")
                                    }
                                }
                            }
                        }
                        .alert("Delete Session?", isPresented: $showDeleteConfirmation) {
                            Button("Delete", role: .destructive) {
                                if let plan = planToDelete {
                                    onDeletePlan?(plan)
                                }
                            }
                            Button("Cancel", role: .cancel) {
                                planToDelete = nil
                            }
                        } message: {
                            if let plan = planToDelete, !plan.isFollowUpReview {
                                Text("This will also schedule spaced repetition reviews for this session.")
                            }
                        }
                    }
                }
                .frame(height: 52)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func sessionBlock(plan: StudyPlan) -> some View {
        let color = subjectColor(plan.subjectName)
        let isReview = plan.planMarkdown.contains("Spaced Repetition Review")

        return VStack(spacing: 1) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.2), color.opacity(0.12)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: color.opacity(0.15), radius: 3, y: 1)

                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(color.opacity(0.25), lineWidth: 0.5)

                VStack(spacing: 1) {
                    if isReview {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(color)
                    }
                    Text(subjectAbbrev(plan.subjectName))
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                }
            }
        }
        .padding(2)
    }

    private func slotBackground(isToday: Bool, isPast: Bool, hour: Int) -> Color {
        if isToday {
            return IBColors.electricBlue.opacity(0.015)
        }
        if isPast {
            return Color.secondary.opacity(0.008)
        }
        return Color.clear
    }

    private func dayAbbrev(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "E"; return f.string(from: date)
    }

    private func dayNum(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: date)
    }

    private func subjectAbbrev(_ name: String) -> String {
        switch name {
        case "English B": return "ENG"
        case "Russian A Literature": return "RUS"
        case "Biology": return "BIO"
        case "Mathematics AA": return "MAT"
        case "Economics": return "ECO"
        case "Business Management": return "BM"
        default: return String(name.prefix(3)).uppercased()
        }
    }

    private func plansForSlot(day: Date, hour: Int) -> [StudyPlan] {
        let cal = Calendar.current
        return visiblePlans.filter { plan in
            let planDay = cal.startOfDay(for: plan.scheduledDate)
            let slotDay = cal.startOfDay(for: day)
            guard planDay == slotDay else { return false }
            let planHour = cal.component(.hour, from: plan.scheduledDate)
            let planEndHour = cal.component(.hour, from: plan.scheduledEndDate)
            return hour >= planHour && hour < max(planEndHour, planHour + 1)
        }
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
}
