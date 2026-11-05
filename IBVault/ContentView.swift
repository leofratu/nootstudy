import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

enum NavigationTab: String, CaseIterable, Hashable {
    case dashboard = "Today"
    case subjects = "Subjects"
    case studySessions = "Sessions"
    case review = "Review"
    case cardStudio = "Card studio"
    case library = "Library"
    case examMarker = "Exam marker"
    case aria = "ARIA"
    case analytics = "Progress"
    case recommendations = "Recommendations"
    case predictions = "Predictions"
    case profile = "Profile"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .dashboard: return "house.fill"
        case .subjects: return "books.vertical.fill"
        case .studySessions: return "calendar.badge.clock"
        case .review: return "brain.head.profile"
        case .cardStudio: return "rectangle.stack.badge.plus"
        case .library: return "books.vertical"
        case .examMarker: return "checkmark.bubble"
        case .aria: return "sparkles"
        case .analytics: return "chart.bar.fill"
        case .recommendations: return "lightbulb.fill"
        case .predictions: return "chart.line.uptrend.xyaxis"
        case .profile: return "person.fill"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @AppStorage("showDueCountBadge") private var showDueCountBadge = true
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var profiles: [UserProfile]
    @State private var selectedTab: NavigationTab? = .dashboard
    @State private var showCoach = false
    @State private var reviewQueueManager = ReviewQueueManager()
    @State private var progressionEvents = ProgressionEventCenter()
    @Namespace private var sidebarSelectionNamespace

    init(initialTab: NavigationTab = .dashboard) {
        _selectedTab = State(initialValue: initialTab == .aria ? .dashboard : (initialTab == .examMarker ? .library : initialTab))
        _showCoach = State(initialValue: initialTab == .aria)
    }

    private var dueCount: Int {
        reviewQueueManager.totalDueCount
    }

    private func sidebarBadge(for tab: NavigationTab) -> Text? {
        guard showDueCountBadge, tab == .review, dueCount > 0 else { return nil }
        return Text("\(dueCount)")
    }

    var body: some View {
        NavigationSplitView {
            sidebarList
        } detail: {
            detailPane
        }
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 620)
        #endif
        .environment(reviewQueueManager)
        .environment(progressionEvents)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showCoach.toggle() } label: { Label("Coach", systemImage: "sidebar.right") }
                    .help(showCoach ? "Hide your study coach" : "Show your study coach")
            }
        }
        // The coach sits beside the page you are working on rather than being
        // a separate chat product you leave your work to visit.
        .inspector(isPresented: $showCoach) {
            ARIAChatView()
                .inspectorColumnWidth(min: 340, ideal: 420, max: 620)
        }
        .tint(IBColors.accent)
        .onAppear {
            reviewQueueManager.ensureLoaded(context: context)
        }
        .task { await AIProviderService.syncCodexModelsIfDue() }
        // Refresh whenever SwiftData persists a change; observing every
        // card/session through @Query held whole tables in memory and
        // re-rendered the shell on each rating.
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            reviewQueueManager.scheduleRefresh(context: context)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            reviewQueueManager.scheduleRefresh(context: context)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            reviewQueueManager.scheduleRefresh(context: context)
            Task { await AIProviderService.syncCodexModelsIfDue() }
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: .ibVaultAppCommand)) { notification in
            handleAppCommand(notification.object)
        }
        #endif
    }

    private func sidebarButton(_ tab: NavigationTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            sidebarRow(tab)
        }
        .buttonStyle(IBPressStyle())
        .accessibilityLabel(tab.rawValue)
    }

    private func sidebarRow(_ tab: NavigationTab) -> some View {
        let isSelected = selectedTab == tab
        return HStack(spacing: 9) {
            Image(systemName: tab.icon)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? IBColors.accent : IBColors.inkTertiary)
                .frame(width: 18)
            Text(tab.rawValue)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .lineLimit(1)
                .foregroundStyle(isSelected ? IBColors.ink : IBColors.inkSecondary)
            Spacer(minLength: 4)
            if let badge = sidebarBadge(for: tab) {
                badge
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(IBColors.inkTertiary)
                    .contentTransition(.numericText())
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: IBRadius.sm)
                    .fill(IBColors.ink.opacity(0.07))
                    .matchedGeometryEffect(id: "sidebarSelection", in: sidebarSelectionNamespace)
            }
        }
        .contentShape(Rectangle())
        .hoverHighlight()
    }

    var sidebarList: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sidebarSection(nil, tabs: [.dashboard, .studySessions, .subjects])
                    sidebarSection("Flashcards", tabs: [.review, .cardStudio, .library])
                    sidebarSection("Insight", tabs: [.analytics, .recommendations, .predictions])
                }
                .padding(.horizontal, 10).padding(.vertical, 12)
                .animation(reduceMotion ? nil : IBAnimation.snappy, value: selectedTab)
            }
            sidebarFooter
        }
        .background(IBColors.canvasDeep)
        .navigationTitle("Noot Study")
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
    }

    private func sidebarSection(_ title: String?, tabs: [NavigationTab]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let title {
                Text(title).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(IBColors.inkTertiary)
                    .padding(.horizontal, 8).padding(.bottom, 4)
            }
            ForEach(tabs, id: \.self) { sidebarButton($0) }
        }
    }

    private var sidebarFooter: some View {
        let profile = profiles.first
        let name = profile?.studentName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return HStack(spacing: 2) {
            Button {
                selectedTab = .profile
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(name.isEmpty ? "Student" : name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(IBColors.ink)
                        .lineLimit(1)
                    Text(profile?.achievedStep.displayName ?? "Getting started")
                        .font(.system(size: 11))
                        .foregroundStyle(IBColors.inkTertiary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .hoverHighlight()
            }
            .buttonStyle(IBPressStyle())
            .accessibilityLabel("Profile")

            Button {
                selectedTab = .settings
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(selectedTab == .settings ? IBColors.accent : IBColors.inkTertiary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
                    .hoverHighlight()
            }
            .buttonStyle(IBPressStyle())
            .help("Settings")
            .accessibilityLabel("Settings")
        }
        .padding(8)
        .background(IBColors.canvasDeep)
    }

    private var detailPane: some View {
        ZStack {
            // Pages crossfade only: sliding a whole page while it also builds
            // its content is what made tab changes feel heavy.
            pageContent
                .id(selectedTab)
                .transition(.opacity)
        }
        .animation(reduceMotion ? nil : IBAnimation.page, value: selectedTab)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IBColors.canvas)
    }

    @ViewBuilder
    private var pageContent: some View {
        Group {
            switch selectedTab {
            case .dashboard: DashboardView()
            case .subjects: SubjectsGridView()
            case .studySessions: StudyPlannerView()
            case .review: ReviewLaunchView()
            case .cardStudio: CardStudioView()
            case .library: NavigationStack { CardLibraryView(embedded: true) }
            case .examMarker: NavigationStack { CardLibraryView(embedded: true) }
            case .aria: DashboardView()
            case .analytics: ProgressHubView()
            case .recommendations: SmartRecommendationsView()
            case .predictions: PredictiveGradeView()
            case .profile: ProfileView()
            case .settings:
                // The calendar banner sends the learner here to reconnect.
                NavigationStack {
                    SettingsView(initialSection: UserDefaults.standard.bool(forKey: CalendarSyncPreferences.needsAttentionKey) ? .study : .general)
                }
            case .none:
                ContentUnavailableView("Select a Section", systemImage: "sidebar.left", description: Text("Choose a section from the sidebar to get started."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IBColors.canvas)
        .background(IBColors.canvasDeep)
    }

    #if os(macOS)
    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }

    private func handleAppCommand(_ payload: Any?) {
        guard let command = IBVaultAppCommand.fromNotificationPayload(payload) else { return }
        if command == .showARIA {
            showCoach.toggle()
            return
        }
        if let targetTab = command.targetTab {
            selectedTab = targetTab
        }
        if command == .refreshReviewQueue {
            reviewQueueManager.refreshDueCards(context: context)
        }
    }
    #endif
}

// MARK: - Review Launch
struct ReviewLaunchView: View {
    @Environment(\.modelContext) private var context
    @Environment(ReviewQueueManager.self) private var queueManager
    @State private var showReview = false
    @State private var showGuide = false
    @AppStorage(ReviewDailyLimitPolicy.prioritySubjectKey) private var prioritySubject = ""
    @AppStorage("reviewOrder") private var reviewOrder = "spaced"
    @Query(sort: \StudySession.endDate, order: .reverse) private var studySessions: [StudySession]
    @Query(sort: \Subject.name) private var subjects: [Subject]

    private var dueSubjects: [(subject: Subject, due: Int)] {
        subjects
            .map { (subject: $0, due: queueManager.backlogCount(for: $0)) }
            .filter { $0.due > 0 || $0.subject.name == prioritySubject }
            .sorted { $0.due > $1.due }
    }

    private var eligibleCount: Int {
        queueManager.eligibleCardsCount()
    }
    private var dueCardsCount: Int {
        queueManager.dueCards.count
    }
    private var dueBacklogCount: Int {
        queueManager.totalDueBacklogCount
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    StudioPageHeader(
                        eyebrow: "Active recall",
                        title: "Review",
                        subtitle: reviewSubtitle,
                        symbol: "brain.head.profile"
                    ) {
                        HStack(spacing: 8) {
                            Button("Study guide") {
                                IBHaptics.soft()
                                showGuide = true
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            Button(dueCardsCount == 0 ? "Nothing due" : "Start review") {
                                IBHaptics.medium()
                                showReview = true
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(dueCardsCount == 0)
                        }
                    }

                    HStack(spacing: 16) {
                        StudioMetricTile(value: "\(dueCardsCount)", label: "Ready now", symbol: "rectangle.stack")
                        StudioMetricTile(value: "\(queueManager.reviewedTodayCount)", label: "Reviewed today", symbol: "checkmark.circle")
                        StudioMetricTile(value: "\(queueManager.deferredDueCount)", label: "Waiting for tomorrow", symbol: "calendar")
                        StudioMetricTile(value: "\(eligibleCount)", label: "Cards saved", symbol: "tray.full")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Today's goal")
                                .font(IBTypography.sectionTitle)
                                .foregroundStyle(IBColors.ink)
                            Spacer()
                            Text("\(queueManager.reviewedTodayCount) of \(queueManager.dailyGoal) cards")
                                .font(IBTypography.caption.monospacedDigit())
                                .foregroundStyle(IBColors.inkSecondary)
                        }
                        MasteryBar(progress: Double(queueManager.reviewedTodayCount) / Double(max(queueManager.dailyGoal, 1)), height: 6)
                    }
                    .padding(20)
                    .surfaceCard()

                    queueCard
                }
                .frame(maxWidth: 960, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(IBColors.canvas)
            .navigationTitle("Review")
            .sheet(isPresented: $showReview, onDismiss: {
                queueManager.refreshDueCards(context: context)
            }) { ReviewSessionView() }
            .sheet(isPresented: $showGuide) { StudyGuideView(subject: nil, mode: .preSession) }
            .task {
                queueManager.ensureLoaded(context: context)
            }
            .onChange(of: prioritySubject) { _, _ in
                queueManager.refreshDueCards(context: context)
            }
        }
    }

    private var queueCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Prioritize a subject")
                    .font(IBTypography.sectionTitle)
                    .foregroundStyle(IBColors.ink)
                Spacer()
                Picker("Order", selection: $reviewOrder) {
                    Text("Due first").tag("spaced")
                    Text("Weakest first").tag("weakest")
                    Text("Shuffled").tag("random")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 300)
                .accessibilityLabel("Review order")
            }
            if dueSubjects.isEmpty {
                Text("No cards are due.")
                    .font(IBTypography.body13)
                    .foregroundStyle(IBColors.inkSecondary)
            } else {
                VStack(spacing: 2) {
                    ForEach(dueSubjects, id: \.subject.id) { entry in
                        subjectRow(entry.subject, due: entry.due)
                    }
                }
            }
        }
        .padding(20)
        .surfaceCard()
    }

    private func subjectRow(_ subject: Subject, due: Int) -> some View {
        let isPriority = subject.name == prioritySubject
        return Button {
            IBHaptics.light()
            prioritySubject = isPriority ? "" : subject.name
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(hex: subject.accentColorHex))
                    .frame(width: 8, height: 8)
                Text("\(subject.name) \(subject.level)")
                    .font(.system(size: 13, weight: isPriority ? .medium : .regular))
                    .foregroundStyle(IBColors.ink)
                    .lineLimit(1)
                Spacer()
                if isPriority {
                    Label("First", systemImage: "pin.fill")
                        .font(IBTypography.caption)
                        .foregroundStyle(IBColors.accent)
                }
                Text("\(due) due")
                    .font(IBTypography.caption.monospacedDigit())
                    .foregroundStyle(IBColors.inkSecondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(isPriority ? IBColors.ink.opacity(0.07) : Color.clear,
                        in: RoundedRectangle(cornerRadius: IBRadius.sm))
            .contentShape(Rectangle())
            .hoverHighlight()
        }
        .buttonStyle(IBPressStyle())
        .accessibilityAddTraits(isPriority ? .isSelected : [])
    }

    /// Only shown when something is wrong or the day's limit has been reached;
    /// the tiles below already show how many cards are ready.
    private var reviewSubtitle: String? {
        if let error = queueManager.lastRefreshError { return error }
        if queueManager.remainingDailyAllowance == 0 {
            return "Daily limit reached. Remaining cards wait until tomorrow."
        }
        return nil
    }
}
