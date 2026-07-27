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
    @State private var selectedTab: NavigationTab? = .dashboard
    @State private var reviewQueueManager = ReviewQueueManager()
    @State private var progressionEvents = ProgressionEventCenter()

    private var dueCount: Int {
        reviewQueueManager.totalDueCount
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Section {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(IBColors.electricBlue)
                                .frame(width: 32, height: 32)
                            Image(systemName: "books.vertical.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text("IB Vault")
                                .font(.system(size: 14, weight: .bold))
                            Text("Study studio")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 5)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Section("WORKSPACE") {
                    ForEach([NavigationTab.dashboard, .subjects, .studySessions, .review], id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                            .badge(tab == .review && dueCount > 0 ? dueCount : 0)
                    }
                }

                Section("ASSISTANT") {
                    Label(NavigationTab.aria.rawValue, systemImage: NavigationTab.aria.icon)
                        .tag(NavigationTab.aria)
                }

                Section("INSIGHTS") {
                    Label(NavigationTab.analytics.rawValue, systemImage: NavigationTab.analytics.icon)
                        .tag(NavigationTab.analytics)
                    Label(NavigationTab.recommendations.rawValue, systemImage: NavigationTab.recommendations.icon)
                        .tag(NavigationTab.recommendations)
                    Label(NavigationTab.predictions.rawValue, systemImage: NavigationTab.predictions.icon)
                        .tag(NavigationTab.predictions)
                }

                Section("ACCOUNT") {
                    Label(NavigationTab.profile.rawValue, systemImage: NavigationTab.profile.icon)
                        .tag(NavigationTab.profile)
                    Label(NavigationTab.settings.rawValue, systemImage: NavigationTab.settings.icon)
                        .tag(NavigationTab.settings)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(IBColors.canvas)
            .navigationTitle("IB Vault")
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
            #endif
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .navigation) {
                    Button(action: toggleSidebar) {
                        Image(systemName: "sidebar.left")
                    }
                }
                #endif
            }
        } detail: {
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
                case .settings:
                    NavigationStack {
                        SettingsView()
                    }
                case .none:
                    ContentUnavailableView("Select a Section", systemImage: "sidebar.left", description: Text("Choose a section from the sidebar to get started."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #if os(macOS)
        .frame(minWidth: 1000, minHeight: 700)
        #endif
        .environment(reviewQueueManager)
        .environment(progressionEvents)
        .onAppear {
            reviewQueueManager.refreshDueCards(context: context)
        }
        .onChange(of: selectedTab) { _, _ in
            reviewQueueManager.refreshDueCards(context: context)
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: .ibVaultAppCommand)) { notification in
            handleAppCommand(notification.object)
        }
        #endif
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
        queueManager.eligibleCardsCount(context: context)
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
                        title: "Review workspace",
                        subtitle: reviewSubtitle,
                        symbol: "brain.head.profile",
                        tint: IBColors.electricBlue
                    ) {
                        StudioPill(title: dueCardsCount == 0 ? "QUEUE CLEAR" : "\(dueCardsCount) DUE", tint: dueCardsCount == 0 ? IBColors.success : IBColors.coral)
                    }

                    HStack(spacing: 12) {
                        StudioMetricTile(value: "\(dueCardsCount)", label: "Due now", symbol: "clock.badge.exclamationmark", tint: dueCardsCount == 0 ? IBColors.success : IBColors.coral, detail: dueCardsCount == 0 ? "No urgent cards" : "Ready for recall")
                        StudioMetricTile(value: "\(eligibleCount)", label: "Review pool", symbol: "square.stack.fill", tint: IBColors.electricBlue, detail: "Cards from studied material")
                        StudioMetricTile(value: studySessions.isEmpty ? "-" : "Ready", label: "Session status", symbol: "checkmark.seal.fill", tint: studySessions.isEmpty ? IBColors.tertiaryText : IBColors.teal, detail: studySessions.isEmpty ? "Study first" : "Start when focused")
                    }

                    VStack(alignment: .leading, spacing: 16) {
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
                                    Label("Begin review", systemImage: "play.fill")
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
                    .padding(20)
                    .glassCard()
                }
                .frame(maxWidth: 960, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(IBColors.canvas)
            .navigationTitle("Review")
            .sheet(isPresented: $showReview) { ReviewSessionView() }
            .sheet(isPresented: $showGuide) { StudyGuideView(subject: nil, mode: .preSession) }
        }
    }

    private var reviewSubtitle: String {
        if studySessions.isEmpty {
            return "Finish a study session first. Revision should only come from material you actually studied."
        }
        return "Review due cards from your completed study sessions, or open an ARIA study guide to prepare."
    }
}
