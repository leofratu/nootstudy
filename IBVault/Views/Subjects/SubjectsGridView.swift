import SwiftUI
import SwiftData

struct SubjectsGridView: View {
    @Query private var subjects: [Subject]

    private var sortedSubjects: [Subject] {
        subjects.sorted { $0.name < $1.name }
    }

    let columns = [
        GridItem(.adaptive(minimum: 260, maximum: 400), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if sortedSubjects.isEmpty {
                    VStack(spacing: 16) {
                        Spacer().frame(height: 60)
                        Image(systemName: "books.vertical")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("No Subjects")
                            .font(.title3.bold())
                        Text("Complete onboarding or seed the syllabus to add your study subjects.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 350)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(sortedSubjects, id: \.id) { subject in
                            NavigationLink(destination: SubjectDetailView(subject: subject)) {
                                SubjectGridCard(subject: subject)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(24)
                }
            }
            .background(.background)
            .navigationTitle("Subjects")
        }
    }
}

// MARK: - Subject Card
struct SubjectGridCard: View {
    let subject: Subject

    private var color: Color { Color(hex: subject.accentColorHex) }
    private var dueCount: Int { subject.dueCardsCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: 4, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(subject.name)
                        .font(.headline)
                    Text(subject.level)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ProgressRing(
                    progress: subject.masteryProgress,
                    lineWidth: 3,
                    size: 40,
                    color: color
                )
            }

            Divider()

            // Stats row
            HStack(spacing: 16) {
                Label("\(subject.cards.count)", systemImage: "square.stack")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if dueCount > 0 {
                    Label("\(dueCount) due", systemImage: "clock.badge.exclamationmark")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                } else {
                    Label("All clear", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Spacer()

                // Proficiency breakdown mini
                let breakdown = subject.overallProficiencyBreakdown
                HStack(spacing: 2) {
                    ForEach(ProficiencyLevel.allCases, id: \.self) { level in
                        if let count = breakdown[level], count > 0 {
                            Text(level.emoji)
                                .font(.system(size: 10))
                        }
                    }
                }
            }

            // Mastery bar
            MasteryBar(progress: subject.masteryProgress, height: 5, color: color)
        }
        .padding(16)
        .glassCard()
        .contentShape(Rectangle())
    }
}
