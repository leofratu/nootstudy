import SwiftUI
import SwiftData

struct SubjectDetailView: View {
    let subject: Subject
    @State private var showAddGrade = false
    @State private var showReview = false
    @State private var showStudyGuide = false

    private var color: Color { Color(hex: subject.accentColorHex) }
    private var sortedCards: [StudyCard] { subject.cards.sorted { $0.topicName < $1.topicName } }
    private var sortedGrades: [Grade] { subject.grades.sorted { $0.date > $1.date } }

    var body: some View {
        List {
            overviewSection
            actionsSection
            proficiencySection
            topicsSection
            gradesSection
        }
        .navigationTitle(subject.name)
        .sheet(isPresented: $showAddGrade) {
            AddGradeView(subject: subject)
        }
        .sheet(isPresented: $showStudyGuide) {
            StudyGuideView(subject: subject, mode: .fullGuide)
        }
        .sheet(isPresented: $showReview) {
            ReviewSessionView(filterSubject: subject)
        }
    }

    private var overviewSection: some View {
        Section("Overview") {
            LabeledContent("Level", value: subject.level)
            LabeledContent("Topics", value: "\(subject.cards.count)")
            LabeledContent("Cards due now", value: "\(subject.dueCardsCount)")

            VStack(alignment: .leading, spacing: 8) {
                Text("Mastery")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: subject.masteryProgress)
                    .tint(color)
                Text("\(Int(subject.masteryProgress * 100))% complete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionsSection: some View {
        Section("Actions") {
            if subject.dueCardsCount > 0 {
                Button("Review Due Cards") {
                    showReview = true
                    IBHaptics.medium()
                }
                .buttonStyle(.borderedProminent)
            }

            Button("Open ARIA Study Guide") {
                showStudyGuide = true
                IBHaptics.light()
            }
        }
    }

    private var proficiencySection: some View {
        Section("Proficiency") {
            let breakdown = subject.overallProficiencyBreakdown
            ForEach(ProficiencyLevel.allCases, id: \.self) { level in
                HStack {
                    Text(level.emoji)
                    Text(level.rawValue)
                    Spacer()
                    Text("\(breakdown[level] ?? 0)")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var topicsSection: some View {
        Section("Topics") {
            if sortedCards.isEmpty {
                Text("No topics available yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedCards, id: \.id) { card in
                    SubjectTopicRow(card: card)
                }
            }
        }
    }

    private var gradesSection: some View {
        Section("Grades") {
            Button("Add Grade") {
                showAddGrade = true
            }

            if sortedGrades.isEmpty {
                Text("No grades recorded yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedGrades, id: \.id) { grade in
                    GradeSummaryRow(grade: grade, color: gradeColor(grade.score))
                }
            }
        }
    }

    private func gradeColor(_ score: Int) -> Color {
        switch score {
        case 6...7: return IBColors.success
        case 4...5: return IBColors.warning
        default: return IBColors.danger
        }
    }
}

// MARK: - Add Grade Sheet
struct AddGradeView: View {
    let subject: Subject
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var component = "Paper 1"
    @State private var score = 4
    @State private var predictedGrade = 5
    @State private var feedback = ""

    let components = ["Paper 1", "Paper 2", "IA", "EE", "TOK", "Overall"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Component") {
                    Picker("Component", selection: $component) {
                        ForEach(components, id: \.self) { c in
                            Text(c).tag(c)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Score (1-7)") {
                    Stepper(value: $score, in: 1...7) {
                        Text("\(score)")
                            .font(.title)
                    }
                }

                Section("Predicted Grade (1-7)") {
                    Stepper(value: $predictedGrade, in: 1...7) {
                        Text("\(predictedGrade)")
                            .font(.title)
                    }
                }

                Section("Teacher Feedback") {
                    TextEditor(text: $feedback)
                        .frame(minHeight: 60)
                }
            }
            .navigationTitle("Add Grade")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let grade = Grade(
                            component: component,
                            score: score,
                            predictedGrade: predictedGrade,
                            teacherFeedback: feedback,
                            subject: subject
                        )
                        context.insert(grade)
                        try? context.save()
                        IBHaptics.success()
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct SubjectTopicRow: View {
    let card: StudyCard

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.topicName)
            HStack(spacing: 8) {
                Text(card.proficiency.emoji)
                Text(card.proficiency.rawValue)
                    .foregroundStyle(.secondary)
                Text(card.isDue ? "Due now" : "Due in \(card.daysUntilDue)d")
                    .foregroundStyle(card.isDue ? Color.orange : Color.secondary)
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
    }
}

private struct GradeSummaryRow: View {
    let grade: Grade
    let color: Color

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(grade.component)
                Text(grade.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !grade.teacherFeedback.isEmpty {
                    Text(grade.teacherFeedback)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Text("\(grade.score)")
                .font(.title3.bold())
                .foregroundColor(color)
        }
        .padding(.vertical, 2)
    }
}
