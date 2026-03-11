import SwiftUI
import SwiftData

struct SubjectsGridView: View {
    @Query private var subjects: [Subject]

    private var sortedSubjects: [Subject] {
        subjects.sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            List {
                if sortedSubjects.isEmpty {
                    ContentUnavailableView("No Subjects", systemImage: "books.vertical", description: Text("Complete onboarding or seed the syllabus to add your study subjects."))
                } else {
                    Section("Your Subjects") {
                        ForEach(sortedSubjects, id: \.id) { subject in
                            NavigationLink(destination: SubjectDetailView(subject: subject)) {
                                SubjectListRow(subject: subject)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .controlSize(.small)
            .navigationTitle("Subjects")
        }
    }
}

struct SubjectListRow: View {
    let subject: Subject

    private var color: Color {
        Color(hex: subject.accentColorHex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(subject.name)
                    .font(.headline)
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
                .tint(color)
        }
        .padding(.vertical, 2)
    }
}
