import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

enum NavigationTab: String, CaseIterable, Hashable {
    case dashboard = "Dashboard"
    case subjects = "Subjects"
    case studySessions = "Study Sessions"
    case review = "Review"
    case aria = "ARIA"
    case analytics = "Analytics"
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
    @Environment(\.modelContext) private var context
    @Query private var queuedCards: [StudyCard]
    @Query private var queuedStudySessions: [StudySession]
    @Query private var profiles: [UserProfile]
    @State private var selectedTab: NavigationTab? = .dashboard
    @State private var reviewQueueManager = ReviewQueueManager()
    @State private var progressionEvents = ProgressionEventCenter()

    private var dueCount: Int {
        reviewQueueManager.totalDueCount
    }

    private func sidebarBadge(for tab: NavigationTab) -> Text? {
        guard tab == .review, dueCount > 0 else { return nil }
        return Text("\(dueCount)")
    }

    var body: some View {
        NavigationSplitView {
            sidebarList
        } detail: {
            detailPane
        }
        #if os(macOS)
        .frame(minWidth: 940, minHeight: 600)
        #endif
        .environment(reviewQueueManager)
        .environment(progressionEvents)
        .onAppear {
            reviewQueueManager.refreshDueCards(context: context)
        }
        .onChange(of: selectedTab) { _, _ in
            reviewQueueManager.refreshDueCards(context: context)
        }
        // The badge, dashboard, and review screen all read the same snapshot.
        // Refresh it whenever SwiftData observes a card reschedule/delete or a
        // session scope change; relying on navigation events left stale badges.
        .onChange(of: queuedCards) { _, _ in
            reviewQueueManager.refreshDueCards(context: context)
        }
        .onChange(of: queuedStudySessions) { _, _ in
            reviewQueueManager.refreshDueCards(context: context)
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
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue)
    }

    private func sidebarRow(_ tab: NavigationTab) -> some View {
        Label {
            Text(tab.rawValue)
                .font(.system(size: 13, weight: .medium))
        } icon: {
            Image(systemName: tab.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selectedTab == tab ? IBColors.electricBlue : IBColors.secondaryText)
        }
        .overlay(alignment: .trailing) {
            if let badge = sidebarBadge(for: tab) {
                badge
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(IBColors.secondaryText)
                    .allowsHitTesting(false)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selectedTab == tab ? IBColors.electricBlue.opacity(0.11) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private var sidebarList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(IBGradient.accent)
                            .frame(width: 34, height: 34)
                            .shadow(color: IBColors.electricBlue.opacity(0.35), radius: 8, x: 0, y: 3)
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("IB Vault")
                            .font(.system(size: 14.5, weight: .bold))
                            .foregroundStyle(IBColors.ink)
                        Text("Study studio")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(IBColors.secondaryText)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)

                sidebarSectionHeader("WORKSPACE")
                ForEach([
                    NavigationTab.dashboard,
                    .subjects,
                    .studySessions,
                    .review
                ], id: \.self) { tab in
                    sidebarButton(tab)
                }

                sidebarSectionHeader("ASSISTANT")
                sidebarButton(.aria)

                sidebarSectionHeader("INSIGHTS")
                ForEach([
                    NavigationTab.analytics,
                    .recommendations,
                    .predictions
                ], id: \.self) { tab in
                    sidebarButton(tab)
                }

                sidebarSectionHeader("SYSTEM")
                sidebarButton(.settings)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .background(IBColors.canvas.opacity(0.45))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarFooter
        }
        .navigationTitle("IB Vault")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 210, ideal: 232, max: 300)
        #endif
        .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle Sidebar")
            }
            #endif
        }
    }

    private func sidebarSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(IBTypography.eyebrow(size: 9.5))
            .tracking(0.9)
            .foregroundStyle(IBColors.tertiaryText)
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 5)
    }

    private var sidebarFooter: some View {
        let profile = profiles.first
        let name = profile?.studentName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let initial = name.first.map { String($0).uppercased() } ?? "S"
        return VStack(spacing: 0) {
            Divider()
                .opacity(0.6)
            HStack(spacing: 10) {
                Button {
                    selectedTab = .profile
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(IBGradient.accent)
                                .frame(width: 30, height: 30)
                            Text(initial)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(name.isEmpty ? "Student" : name)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(IBColors.ink)
                                .lineLimit(1)
                            Text(profile?.achievedStep.displayName ?? "Getting started")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(IBColors.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private var detailPane: some View {
        Group {
            switch selectedTab {
            case .dashboard: DashboardView()
            case .subjects: SubjectsGridView()
            case .studySessions: StudyPlannerView()
            case .review: ReviewLaunchView()
            case .aria: ARIAChatView()
            case .analytics: AnalyticsView()
            case .recommendations: SmartRecommendationsView()
            case .predictions: PredictiveGradeView()
            case .profile: ProfileView()
            case .settings: SettingsView()
            case .none:
                ContentUnavailableView("Select a Section", systemImage: "sidebar.left", description: Text("Choose a section from the sidebar to get started."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    #if os(macOS)
    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }

    private func handleAppCommand(_ payload: Any?) {
        guard let command = IBVaultAppCommand.fromNotificationPayload(payload) else { return }

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
    @Query(sort: \StudySession.endDate, order: .reverse) private var studySessions: [StudySession]

    private var eligibleCount: Int {
        queueManager.eligibleCardsCount()
    }

    private var dueCardsCount: Int {
        queueManager.dueCards.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    StudioPageHeader(
                        eyebrow: "Active recall",
                        title: "Flashcard queue",
                        subtitle: reviewSubtitle,
                        symbol: "brain.head.profile",
                        tint: IBColors.electricBlue
                    ) {
                        StudioPill(title: dueCardsCount == 0 ? "QUEUE CLEAR" : "\(dueCardsCount) DUE", tint: dueCardsCount == 0 ? IBColors.success : IBColors.coral)
                    }

                    HStack(spacing: 12) {
                        StudioMetricTile(value: "\(dueCardsCount)", label: "Today", symbol: "clock.badge.exclamationmark", tint: dueCardsCount == 0 ? IBColors.success : IBColors.coral, detail: "Daily cap \(ReviewDailyLimitPolicy.maximumCards)")
                        StudioMetricTile(value: "\(queueManager.deferredDueCount)", label: "Deferred", symbol: "calendar.badge.clock", tint: IBColors.electricBlue, detail: "Saved for later queues")
                        StudioMetricTile(value: "\(eligibleCount)", label: "Saved cards", symbol: "square.stack.fill", tint: IBColors.teal, detail: "From studied material")
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        StudioSectionHeader("Your next review", subtitle: dueCardsCount == 0 ? "There is nothing scheduled for immediate review." : "Work through cards while recall is still effortful.", symbol: "play.rectangle.fill", tint: IBColors.electricBlue) {
                            EmptyView()
                        }

                        HStack(alignment: .center, spacing: 18) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(dueCardsCount == 0 ? "Queue complete" : "Start a focused recall session")
                                    .font(.title3.bold())
                                    .foregroundStyle(IBColors.ink)
                                Text("Each response updates scheduling and builds a more reliable picture of what you know.")
                                    .font(.callout)
                                    .foregroundStyle(IBColors.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 20)
                            VStack(spacing: 10) {
                                Button {
                                    IBHaptics.medium()
                                    showReview = true
                                } label: {
                                    Label("Start cards", systemImage: "play.fill")
                                        .frame(minWidth: 160)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .tint(IBColors.electricBlue)
                                .disabled(studySessions.isEmpty || dueCardsCount == 0)

                                Button {
                                    IBHaptics.soft()
                                    showGuide = true
                                } label: {
                                    Label("Open study guide", systemImage: "book.closed.fill")
                                        .frame(minWidth: 160)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(22)
                    .glassCard()
                }
                .frame(maxWidth: 960, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(IBColors.canvas)
            .navigationTitle("Review")
            .sheet(isPresented: $showReview, onDismiss: {
                // A completed review consumed the due queue; refresh the badge
                // and the launch metrics without waiting for a tab change.
                queueManager.refreshDueCards(context: context)
            }) { ReviewSessionView() }
            .sheet(isPresented: $showGuide) { StudyGuideView(subject: nil, mode: .preSession) }
        }
    }

    private var reviewSubtitle: String {
        if studySessions.isEmpty {
            return "Finish a study session first. Revision should only come from material you actually studied."
        }
        if queueManager.remainingDailyAllowance == 0 {
            return "Today's recall cap is complete. Your remaining cards stay saved for the next queue."
        }
        return "Review one bounded queue of saved cards. Extra due cards are deferred automatically."
    }
}
