import SwiftUI
import SwiftData

struct SubjectDetailView: View {
    let subject: Subject
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showAddGrade = false
    @State private var showReview = false
    @State private var showStudyGuide = false

    private var color: Color { Color(hex: subject.accentColorHex) }

    var body: some View {
        ZStack {
            IBColors.navy.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: IBSpacing.lg) {
                    headerSection
                    proficiencyBreakdown
                    topicsSection
                    gradesSection
                }
                .padding(.horizontal, IBSpacing.md)
                .padding(.bottom, 100)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                SubjectBadge(name: subject.name, level: subject.level)
            }
        }
        .sheet(isPresented: $showAddGrade) {
            AddGradeView(subject: subject)
        }
        .sheet(isPresented: $showStudyGuide) {
            StudyGuideView(subject: subject, mode: .fullGuide)
        }
        .fullScreenCover(isPresented: $showReview) {
            ReviewSessionView(filterSubject: subject)
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        GlassCard {
            VStack(spacing: IBSpacing.md) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(subject.name)
                            .font(IBTypography.title)
                            .foregroundColor(IBColors.softWhite)
                        Text("\(subject.level) • \(subject.cards.count) topics")
                            .font(IBTypography.caption)
                            .foregroundColor(IBColors.mutedGray)
                    }
                    Spacer()
                    ProgressRing(progress: subject.masteryProgress, size: 56, color: color)
                }

                if subject.dueCardsCount > 0 {
                    Button {
                        showReview = true
                        IBHaptics.medium()
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Review \(subject.dueCardsCount) Due Cards")
                        }
                        .font(IBTypography.captionBold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(color))
                    }
                }

                // Study Guide button
                Button {
                    showStudyGuide = true
                    IBHaptics.light()
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("ARIA Study Guide")
                    }
                    .font(IBTypography.captionBold)
                    .foregroundColor(color)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.5)))
                }
            }
        }
    }

    // MARK: - Proficiency Breakdown
    private var proficiencyBreakdown: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: IBSpacing.sm) {
                Text("Proficiency")
                    .font(IBTypography.headline)
                    .foregroundColor(IBColors.softWhite)

                let breakdown = subject.overallProficiencyBreakdown
                ForEach(ProficiencyLevel.allCases, id: \.self) { level in
                    HStack {
                        Text(level.emoji)
                        Text(level.rawValue)
                            .font(IBTypography.caption)
                            .foregroundColor(IBColors.softWhite)
                        Spacer()
                        Text("\(breakdown[level] ?? 0)")
                            .font(IBTypography.captionBold)
                            .foregroundColor(IBColors.mutedGray)
                    }
                }
            }
        }
    }

    // MARK: - Topics
    private var topicsSection: some View {
        VStack(alignment: .leading, spacing: IBSpacing.sm) {
            Text("Topics")
                .font(IBTypography.headline)
                .foregroundColor(IBColors.softWhite)

            ForEach(subject.cards.sorted(by: { $0.topicName < $1.topicName }), id: \.id) { card in
                GlassCard(cornerRadius: 12, padding: IBSpacing.sm) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.topicName)
                                .font(IBTypography.body)
                                .foregroundColor(IBColors.softWhite)
                            HStack(spacing: IBSpacing.sm) {
                                Text(card.proficiency.emoji)
                                Text(card.proficiency.rawValue)
                                    .font(IBTypography.caption)
                                    .foregroundColor(IBColors.mutedGray)
                                if card.isDue {
                                    Text("• Due now")
                                        .font(IBTypography.captionBold)
                                        .foregroundColor(IBColors.warning)
                                } else {
                                    Text("• Due in \(card.daysUntilDue)d")
                                        .font(IBTypography.caption)
                                        .foregroundColor(IBColors.mutedGray)
                                }
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(IBColors.mutedGray)
                    }
                }
            }
        }
    }

    // MARK: - Grades
    private var gradesSection: some View {
        VStack(alignment: .leading, spacing: IBSpacing.sm) {
            HStack {
                Text("Grades")
                    .font(IBTypography.headline)
                    .foregroundColor(IBColors.softWhite)
                Spacer()
                Button {
                    showAddGrade = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(color)
                }
            }

            if subject.grades.isEmpty {
                GlassCard(cornerRadius: 12) {
                    Text("No grades recorded yet")
                        .font(IBTypography.caption)
                        .foregroundColor(IBColors.mutedGray)
                        .frame(maxWidth: .infinity)
                }
            } else {
                ForEach(subject.grades.sorted(by: { $0.date > $1.date }), id: \.id) { grade in
                    GlassCard(cornerRadius: 12, padding: IBSpacing.sm) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(grade.component)
                                    .font(IBTypography.body)
                                    .foregroundColor(IBColors.softWhite)
                                if !grade.teacherFeedback.isEmpty {
                                    Text(grade.teacherFeedback)
                                        .font(IBTypography.caption)
                                        .foregroundColor(IBColors.mutedGray)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            Text("\(grade.score)")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(gradeColor(grade.score))
                        }
                    }
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
            ZStack {
                IBColors.navy.ignoresSafeArea()

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
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                        }
                    }

                    Section("Predicted Grade (1-7)") {
                        Stepper(value: $predictedGrade, in: 1...7) {
                            Text("\(predictedGrade)")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                        }
                    }

                    Section("Teacher Feedback") {
                        TextEditor(text: $feedback)
                            .frame(minHeight: 60)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Add Grade")
            .navigationBarTitleDisplayMode(.inline)
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
