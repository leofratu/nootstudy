import SwiftUI
#if os(macOS)
import AppKit
#endif

enum NavigationTab: String, CaseIterable, Hashable {
    case dashboard = "Dashboard"
    case subjects = "Subjects"
    case review = "Review"
    case aria = "ARIA"
    case profile = "Profile"

    var icon: String {
        switch self {
        case .dashboard: return "house.fill"
        case .subjects: return "books.vertical.fill"
        case .review: return "brain.head.profile"
        case .aria: return "sparkles"
        case .profile: return "person.fill"
        }
    }
}

struct ContentView: View {
    @State private var selectedTab: NavigationTab? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Section("Study") {
                    ForEach([NavigationTab.dashboard, .subjects, .review], id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }

                Section("Assistant") {
                    ForEach([NavigationTab.aria], id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }

                Section("Account") {
                    ForEach([NavigationTab.profile], id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
            }
            .listStyle(.sidebar)
            .controlSize(.small)
            .navigationTitle("IB Vault")
            #if os(macOS)
            .environment(\.defaultMinListRowHeight, 28)
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
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
                case .review: ReviewLaunchView()
                case .aria: ARIAChatView()
                case .profile: ProfileView()
                case .none:
                    ContentUnavailableView("Select a Section", systemImage: "sidebar.left")
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

    var body: some View {
        NavigationStack {
            Form {
                Section("About Review") {
                    Text("Start a spaced-repetition session for due cards or open an ARIA study guide first.")
                }

                Section("Actions") {
                    Button("Begin Session") {
                        IBHaptics.medium()
                        showReview = true
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Study Guide") {
                        IBHaptics.soft()
                        showGuide = true
                    }
                }
            }
            .formStyle(.grouped)
            .controlSize(.small)
            .navigationTitle("Review")
            .sheet(isPresented: $showReview) { ReviewSessionView() }
            .sheet(isPresented: $showGuide) { StudyGuideView(subject: nil, mode: .preSession) }
        }
    }
}
