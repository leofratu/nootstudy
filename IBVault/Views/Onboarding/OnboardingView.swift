import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @State private var currentPage = 0

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Welcome to IB Vault")
                    .font(.largeTitle.bold())

                Text("Step \(currentPage + 1) of 3")
                    .foregroundStyle(.secondary)

                Group {
                    switch currentPage {
                    case 0:
                        welcomePage
                    case 1:
                        sciencePage
                    default:
                        subjectPage
                    }
                }

                Spacer()

                HStack {
                    Button("Back") {
                        currentPage -= 1
                    }
                    .disabled(currentPage == 0)

                    Spacer()

                    if currentPage < 2 {
                        Button("Continue") {
                            currentPage += 1
                            IBHaptics.light()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Start Studying") {
                            completeOnboarding()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(24)
        }
    }

    private var welcomePage: some View {
        GroupBox("What this app does") {
            VStack(alignment: .leading, spacing: 12) {
                Text("IB Vault helps you review IB topics with spaced repetition, active recall, and AI study support.")
                Label("Track due cards and mastery over time", systemImage: "clock.arrow.circlepath")
                Label("Use ARIA for study guidance and summaries", systemImage: "sparkles")
                Label("Keep all subjects in one study workspace", systemImage: "books.vertical")
            }
        }
    }

    private var sciencePage: some View {
        GroupBox("How learning works here") {
            VStack(alignment: .leading, spacing: 12) {
                Label("Spaced repetition schedules reviews at the right time", systemImage: "arrow.triangle.2.circlepath")
                Label("Active recall strengthens retention by making you retrieve answers", systemImage: "brain.head.profile")
                Label("Smart scheduling adapts when cards become due", systemImage: "chart.line.uptrend.xyaxis")
            }
        }
    }

    private var subjectPage: some View {
        GroupBox("Preloaded subjects") {
            List {
                subjectRow("English B", "HL")
                subjectRow("Russian A Literature", "SL")
                subjectRow("Biology", "SL")
                subjectRow("Mathematics AA", "SL")
                subjectRow("Economics", "HL")
                subjectRow("Business Management", "HL")
            }
            .frame(minHeight: 220)
        }
    }

    private func subjectRow(_ name: String, _ level: String) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(level)
                .foregroundStyle(.secondary)
        }
    }

    private func completeOnboarding() {
        IBHaptics.success()
        SyllabusSeeder.seedIfNeeded(context: context)
        NotificationService.requestPermission()

        if let profile = profiles.first {
            profile.onboardingCompleted = true
        } else {
            let profile = UserProfile()
            profile.onboardingCompleted = true
            context.insert(profile)
        }
        try? context.save()
    }
}
