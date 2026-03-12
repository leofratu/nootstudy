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
    @State private var selectedTab: NavigationTab? = .dashboard
    @Query(sort: \StudyCard.nextReviewDate) private var allCards: [StudyCard]
    @Query(sort: \StudySession.endDate, order: .reverse) private var studySessions: [StudySession]

    private var studiedScopes: [StudyScope] {
        StudySession.uniqueStudyScopes(from: studySessions)
    }

    private var dueCount: Int {
        guard !studiedScopes.isEmpty else { return 0 }
        return allCards.filter { card in
            card.isDue && studiedScopes.contains { $0.matches(card) }
        }.count
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Section("Study") {
                    ForEach([NavigationTab.dashboard, .subjects, .studySessions, .review], id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                            .badge(tab == .review && dueCount > 0 ? dueCount : 0)
                    }
                }

                Section("Assistant") {
                    Label(NavigationTab.aria.rawValue, systemImage: NavigationTab.aria.icon)
                        .tag(NavigationTab.aria)
                }

                Section("Insights") {
                    Label(NavigationTab.analytics.rawValue, systemImage: NavigationTab.analytics.icon)
                        .tag(NavigationTab.analytics)
                    Label(NavigationTab.recommendations.rawValue, systemImage: NavigationTab.recommendations.icon)
                        .tag(NavigationTab.recommendations)
                    Label(NavigationTab.predictions.rawValue, systemImage: NavigationTab.predictions.icon)
                        .tag(NavigationTab.predictions)
                }

                Section("Account") {
                    Label(NavigationTab.profile.rawValue, systemImage: NavigationTab.profile.icon)
                        .tag(NavigationTab.profile)
                    Label(NavigationTab.settings.rawValue, systemImage: NavigationTab.settings.icon)
                        .tag(NavigationTab.settings)
                }
            }
            .listStyle(.sidebar)
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
    }

    #if os(macOS)
    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }
    #endif
}

// MARK: - Review Launch
struct ReviewLaunchView: View {
    @State private var showReview = false
    @State private var showGuide = false
    @Query(sort: \StudyCard.nextReviewDate) private var allCards: [StudyCard]
    @Query(sort: \StudySession.endDate, order: .reverse) private var studySessions: [StudySession]

    private var studiedScopes: [StudyScope] {
        StudySession.uniqueStudyScopes(from: studySessions)
    }

    private var eligibleCards: [StudyCard] {
        guard !studiedScopes.isEmpty else { return [] }
        return allCards.filter { card in
            studiedScopes.contains { $0.matches(card) }
        }
    }

    private var dueCards: [StudyCard] { eligibleCards.filter { $0.isDue } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Spacer().frame(height: 20)

                    // Hero
                    ZStack {
                        Circle()
                            .fill(IBColors.electricBlue.opacity(0.08))
                            .frame(width: 100, height: 100)
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(IBColors.electricBlue)
                    }

                    VStack(spacing: 6) {
                        Text("Spaced Repetition")
                            .font(.title2.bold())
                        Text(reviewSubtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 450)
                    }

                    // Stats
                    HStack(spacing: 0) {
                        StatCard(value: "\(dueCards.count)", label: "Cards Due", color: dueCards.isEmpty ? .green : .orange, icon: "clock.badge.exclamationmark")
                        Divider().frame(height: 50)
                        StatCard(value: "\(eligibleCards.count)", label: "Review Pool", color: IBColors.electricBlue, icon: "square.stack.fill")
                    }
                    .padding(.vertical, 12)
                    .glassCard()
                    .padding(.horizontal, 40)

                    // Actions
                    HStack(spacing: 12) {
                        Button {
                            IBHaptics.medium()
                            showReview = true
                        } label: {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Begin Session")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(studySessions.isEmpty || dueCards.isEmpty)

                        Button {
                            IBHaptics.soft()
                            showGuide = true
                        } label: {
                            HStack {
                                Image(systemName: "book.fill")
                                Text("Study Guide")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    .padding(.horizontal, 40)

                    Spacer()
                }
            }
            .background(.background)
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
