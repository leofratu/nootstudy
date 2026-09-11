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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var queuedCards: [StudyCard]
    @Query private var queuedStudySessions: [StudySession]
    @Query private var profiles: [UserProfile]
    @State private var selectedTab: NavigationTab? = .dashboard
    @State private var reviewQueueManager = ReviewQueueManager()
    @State private var progressionEvents = ProgressionEventCenter()
    @Namespace private var sidebarSelectionNamespace

    private var dueCount: Int {
        reviewQueueManager.totalDueBacklogCount
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
        HStack(spacing: 9) {
            Label {
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(selectedTab == tab ? IBColors.ink : IBColors.inkSecondary)
            } icon: {
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selectedTab == tab ? IBColors.accent : IBColors.inkTertiary)
            }
            Spacer(minLength: 4)
            if let badge = sidebarBadge(for: tab) {
                badge
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(IBColors.inkSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(IBColors.surfaceHover).overlay(Capsule().stroke(IBColors.border, lineWidth: 1)))
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background {
            if selectedTab == tab {
                RoundedRectangle(cornerRadius: 8)
                    .fill(IBColors.surfaceHover)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(IBColors.border, lineWidth: 1))
                    .matchedGeometryEffect(id: "sidebarSelection", in: sidebarSelectionNamespace)
            }
        }
        .animation(reduceMotion ? nil : IBAnimation.snappy, value: selectedTab)
        .contentShape(Rectangle())
    }

    private var sidebarList: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(IBColors.accentFill)
                            .frame(width: 30, height: 30)
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Noot Study")
                            .font(.system(size: 14.5, weight: .bold))
                            .foregroundStyle(IBColors.ink)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                ForEach([
                    NavigationTab.dashboard,
                    .studySessions,
                    .review,
                    .subjects,
                    .aria,
                    .analytics,
                    .recommendations,
                    .predictions
                ], id: \.self) { tab in
                    sidebarButton(tab)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.sidebar)
        .background(IBColors.canvasDeep)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarFooter
        }
        .navigationTitle("Noot Study")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        #endif
    }

    private var sidebarFooter: some View {
        let profile = profiles.first
        let name = profile?.studentName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let initial = name.first.map { String($0).uppercased() } ?? "S"
        return VStack(spacing: 0) {
            Rectangle().fill(IBColors.border).frame(height: 1)
            Button {
                selectedTab = .settings
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selectedTab == .settings ? IBColors.accent : IBColors.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedTab == .settings ? IBColors.surfaceHover : Color.clear)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selectedTab == .settings ? IBColors.border : Color.clear, lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Button {
                    selectedTab = .profile
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(IBColors.surfaceHover)
                                .frame(width: 28, height: 28)
                                .overlay(Circle().stroke(IBColors.border, lineWidth: 1))
                            Text(initial)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(IBColors.inkSecondary)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(name.isEmpty ? "Student" : name)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(IBColors.ink)
                                .lineLimit(1)
                            Text(profile?.achievedStep.displayName ?? "Getting started")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(IBColors.inkTertiary)
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
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background(IBColors.canvasDeep)
    }

    private var detailPane: some View {
        Group {
            switch selectedTab {
            case .dashboard: DashboardView()
            case .subjects: SubjectsGridView()
            case .studySessions: StudyPlannerView()
            case .review: ReviewLaunchView()
            case .aria: ARIAChatView()
            case .analytics: ProgressHubView()
            case .recommendations: SmartRecommendationsView()
            case .predictions: PredictiveGradeView()
            case .profile: ProfileView()
            case .settings: SettingsView()
            case .none:
                ContentUnavailableView("Select a Section", systemImage: "sidebar.left", description: Text("Choose a section from the sidebar to get started."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IBColors.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(IBColors.border, lineWidth: 1))
        .padding(10)
        .background(IBColors.canvasDeep)
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
    private var dueBacklogCount: Int {
        queueManager.totalDueBacklogCount
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    StudioPageHeader(
                        eyebrow: "Active recall",
                        title: "Flashcard queue",
                        subtitle: reviewSubtitle,
                        symbol: "brain.head.profile"
                    ) {
                        StudioPill(title: dueBacklogCount == 0 ? "QUEUE CLEAR" : "\(dueBacklogCount) DUE", semantic: .neutral)
                    }

                    HStack(spacing: 12) {
                        StudioMetricTile(value: "\(dueBacklogCount)", label: "Flashcards due", symbol: "rectangle.stack", detail: "All available to review")
                        StudioMetricTile(value: "\(queueManager.reviewedTodayCount)", label: "Reviewed today", symbol: "checkmark.circle", detail: "Completed")
                        StudioMetricTile(value: "\(eligibleCount)", label: "Saved cards", symbol: "square.stack", detail: "Studied material")
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        StudioSectionHeader("Your next review", subtitle: dueBacklogCount == 0 ? "There are no flashcards due right now." : "All \(dueBacklogCount) due cards are available now.", symbol: "play.rectangle") {
                            EmptyView()
                        }
                        HStack(alignment: .center, spacing: 18) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(dueCardsCount == 0 ? "Queue complete" : "Start a focused recall session")
                                    .font(IBTypography.sectionTitle)
                                    .foregroundStyle(IBColors.ink)
                                Text("Each response updates scheduling and builds a more reliable picture of what you know.")
                                    .font(IBTypography.body13)
                                    .foregroundStyle(IBColors.inkSecondary)
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
                                .buttonStyle(PrimaryButtonStyle())
                                .controlSize(.large)
                                .disabled(studySessions.isEmpty || dueCardsCount == 0)

                                Button {
                                    IBHaptics.soft()
                                    showGuide = true
                                } label: {
                                    Label("Open study guide", systemImage: "book.closed")
                                        .frame(minWidth: 160)
                                }
                                .buttonStyle(SecondaryButtonStyle())
                            }
                        }
                    }
                    .padding(22)
                    .surfaceCard()
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
                queueManager.refreshDueCards(context: context)
            }
        }
    }

    private var reviewSubtitle: String {
        if studySessions.isEmpty {
            return "Finish a study session first. Revision should only come from material you actually studied."
        }
        return "Review every flashcard currently due for spaced repetition."
    }
}
