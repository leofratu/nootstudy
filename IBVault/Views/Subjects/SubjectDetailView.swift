import SwiftUI
import SwiftData

struct SubjectDetailView: View {
    let subject: Subject
    @State private var showAddGrade = false
    @State private var showReview = false
    @State private var showStudyGuide = false
    @State private var showTopicBrowser = false

    private var color: Color { Color(hex: subject.accentColorHex) }
    private var sortedCards: [StudyCard] { subject.cards.sorted { $0.topicName < $1.topicName } }
    private var sortedGrades: [Grade] { subject.grades.sorted { $0.date > $1.date } }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Hero with ring
                heroCard
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                // Actions
                actionsBar
                    .padding(.horizontal, 24)

                // Proficiency breakdown
                proficiencyCard
                    .padding(.horizontal, 24)

                // Topics
                topicsCard
                    .padding(.horizontal, 24)

                // Grades
                gradesCard
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .background(.background)
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
        .sheet(isPresented: $showTopicBrowser) {
            NavigationStack {
                TopicBrowserView(subject: subject)
            }
        }
    }

    // MARK: - Hero
    private var heroCard: some View {
        HStack(spacing: 20) {
            ProgressRing(
                progress: subject.masteryProgress,
                lineWidth: 6,
                size: 80,
                color: color
            )
            .glow(color: color, radius: 8)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: 4, height: 20)
                    Text(subject.name)
                        .font(.title2.bold())
                    Text(subject.level)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(color.opacity(0.12)))
                        .foregroundStyle(color)
                }

                HStack(spacing: 16) {
                    Label("\(subject.cards.count) topics", systemImage: "square.stack")
                    if subject.dueCardsCount > 0 {
                        Label("\(subject.dueCardsCount) due now", systemImage: "clock.badge.exclamationmark")
                            .foregroundStyle(.orange)
                    } else {
                        Label("All caught up", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                Text("\(Int(subject.masteryProgress * 100))% mastery")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
        .glassCard()
    }

    // MARK: - Actions
    private var actionsBar: some View {
        HStack(spacing: 12) {
            if subject.dueCardsCount > 0 {
                Button {
                    showReview = true
                    IBHaptics.medium()
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Review Due Cards")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Button {
                showStudyGuide = true
                IBHaptics.light()
            } label: {
                HStack {
                    Image(systemName: "book.fill")
                    Text("ARIA Study Guide")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                showTopicBrowser = true
                IBHaptics.light()
            } label: {
                HStack {
                    Image(systemName: "list.bullet.rectangle")
                    Text("Browse Curriculum")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    // MARK: - Proficiency
    private var proficiencyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.tint)
                Text("Proficiency Breakdown")
                    .font(.headline)
            }

            let breakdown = subject.overallProficiencyBreakdown
            let total = max(subject.cards.count, 1)

            ForEach(ProficiencyLevel.allCases, id: \.self) { level in
                let count = breakdown[level] ?? 0
                HStack(spacing: 10) {
                    Text(level.emoji)
                        .frame(width: 24)
                    Text(level.rawValue)
                        .font(.callout)
                        .frame(width: 90, alignment: .leading)
                    ProgressView(value: Double(count), total: Double(total))
                        .tint(proficiencyColor(level))
                    Text("\(count)")
                        .font(.callout.bold())
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                }
            }
        }
        .padding(16)
        .glassCard()
    }

    private func proficiencyColor(_ level: ProficiencyLevel) -> Color {
        switch level {
        case .novice: return IBColors.danger
        case .developing: return IBColors.warning
        case .proficient: return IBColors.electricBlue
        case .mastered: return IBColors.success
        }
    }

    // MARK: - Topics
    private var topicsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.bullet")
                    .foregroundStyle(.tint)
                Text("Topics")
                    .font(.headline)
                Spacer()
                Text("\(sortedCards.count) total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if sortedCards.isEmpty {
                HStack {
                    Spacer()
                    Text("No topics available yet.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                    Spacer()
                }
            } else {
                ForEach(sortedCards, id: \.id) { card in
                    SubjectTopicRow(card: card, color: color)
                    if card.id != sortedCards.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(16)
        .glassCard()
    }

    // MARK: - Grades
    private var gradesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.doc.horizontal.fill")
                    .foregroundStyle(.tint)
                Text("Grades")
                    .font(.headline)
                Spacer()
                Button {
                    showAddGrade = true
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            if sortedGrades.isEmpty {
                HStack {
                    Spacer()
                    Text("No grades recorded yet.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                    Spacer()
                }
            } else {
                ForEach(sortedGrades, id: \.id) { grade in
                    GradeSummaryRow(grade: grade, color: gradeColor(grade.score))
                    if grade.id != sortedGrades.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(16)
        .glassCard()
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
            .formStyle(.grouped)
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
        .frame(minWidth: 450, minHeight: 400)
    }
}

// MARK: - Topic Row
private struct SubjectTopicRow: View {
    let card: StudyCard
    var color: Color = IBColors.electricBlue

    var body: some View {
        HStack(spacing: 10) {
            Text(card.proficiency.emoji)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(card.topicName)
                    .font(.callout)
                HStack(spacing: 8) {
                    Text(card.proficiency.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(color.opacity(0.1)))
                        .foregroundStyle(color)

                    Text(card.isDue ? "Due now" : "Due in \(card.daysUntilDue)d")
                        .font(.caption)
                        .foregroundStyle(card.isDue ? .orange : .secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Grade Row
private struct GradeSummaryRow: View {
    let grade: Grade
    let color: Color

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(grade.component)
                    .font(.callout.weight(.medium))
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
                .font(.title2.bold())
                .foregroundColor(color)
        }
        .padding(.vertical, 2)
    }
}
