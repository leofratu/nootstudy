import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(sort: \StudyCard.nextReviewDate) private var allCards: [StudyCard]
    @Query private var subjects: [Subject]

    @State private var ariaService = ARIAService()
    @State private var showReview = false

    private var profile: UserProfile? { profiles.first }

    private var dueCards: [StudyCard] {
        allCards.filter { $0.isDue }
    }

    private var sortedSubjects: [Subject] {
        subjects.sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            List {
                overviewSection
                assistantSection
                toolsSection
                reviewSection
                subjectsSection
            }
            .listStyle(.inset)
            .controlSize(.small)
            .navigationTitle("Dashboard")
            .sheet(isPresented: $showReview) {
                ReviewSessionView()
            }
        }
    }

    private var overviewSection: some View {
        Section("Overview") {
            Text(greeting)
                .foregroundStyle(.secondary)

            LabeledContent("Cards due today", value: "\(dueCards.count)")
            LabeledContent("Total XP", value: "\(profile?.totalXP ?? 0)")
            LabeledContent("Current streak", value: "\(profile?.currentStreak ?? 0)")
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    private var assistantSection: some View {
        Section("ARIA") {
            Text(ariaService.generateGreeting(context: context))
                .textSelection(.enabled)
        }
    }

    private var toolsSection: some View {
        Section("Tools") {
            NavigationLink {
                EffectivenessView()
            } label: {
                Label("Effectiveness", systemImage: "chart.line.uptrend.xyaxis")
            }

            NavigationLink {
                ADHDTrackerView()
            } label: {
                Label("Medication", systemImage: "pills")
            }

            NavigationLink {
                MaterialsLibraryView()
            } label: {
                Label("Materials", systemImage: "books.vertical")
            }
        }
    }

    private var reviewSection: some View {
        Section("Review Queue") {
            LabeledContent("Ready now", value: "\(dueCards.count)")

            VStack(alignment: .leading, spacing: 8) {
                Text("Progress")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: reviewProgress)
                Text("\(Int(reviewProgress * 100))% of cards are currently not due")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if dueCards.isEmpty {
                Text("No cards are due right now.")
                    .foregroundStyle(.secondary)
            } else {
                Button("Start Review") {
                    IBHaptics.medium()
                    showReview = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var reviewProgress: Double {
        guard !allCards.isEmpty else { return 0 }
        let reviewed = allCards.filter { !$0.isDue }.count
        return Double(reviewed) / Double(allCards.count)
    }

    private var subjectsSection: some View {
        Section("Subjects") {
            if sortedSubjects.isEmpty {
                Text("No subjects available yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedSubjects, id: \.id) { subject in
                    NavigationLink(destination: SubjectDetailView(subject: subject)) {
                        DashboardSubjectRow(subject: subject)
                    }
                }
            }
        }
    }
}

private struct DashboardSubjectRow: View {
    let subject: Subject

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(subject.name)
                Spacer()
                Text(subject.level)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("\(subject.cards.count) topics")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(subject.dueCardsCount == 0 ? "No cards due" : "\(subject.dueCardsCount) due")
                    .foregroundStyle(subject.dueCardsCount == 0 ? Color.secondary : Color.orange)
            }
            .font(.caption)

            ProgressView(value: subject.masteryProgress)
        }
        .padding(.vertical, 2)
    }
}
