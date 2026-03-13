import SwiftUI
import SwiftData

struct SubjectDetailView: View {
    let subject: Subject
    @Query(sort: \StudySession.endDate, order: .reverse) private var studySessions: [StudySession]
    @State private var showAddGrade = false
    @State private var showReview = false
    @State private var showStudyGuide = false
    @State private var showTopicBrowser = false

    private var color: Color { Color(hex: subject.accentColorHex) }
    private var sortedCards: [StudyCard] { subject.cards.sorted { $0.topicName < $1.topicName } }
    private var sortedGrades: [Grade] { subject.grades.sorted { $0.date > $1.date } }
    private var reviewableDueCount: Int {
        let studiedScopes = StudySession.uniqueStudyScopes(from: studySessions)
            .filter { $0.subjectName == subject.name }
        guard !studiedScopes.isEmpty else { return 0 }
        return subject.cards.filter { card in
            card.isDue && studiedScopes.contains { $0.matches(card) }
        }.count
    }

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
                    if reviewableDueCount > 0 {
                        Label("\(reviewableDueCount) due now", systemImage: "clock.badge.exclamationmark")
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
            if reviewableDueCount > 0 {
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
                Text("Curriculum Mastery")
                    .font(.headline)
                Spacer()
                Text("\(subject.cards.count) cards")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if subject.cards.isEmpty {
                HStack {
                    Spacer()
                    Text("No topics available yet. Browse curriculum to start.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                    Spacer()
                }
            } else {
                let topics = Dictionary(grouping: subject.cards, by: { $0.topicName })
                    .sorted { 
                        let mastery1 = ProficiencyTracker.masteryPercentage(for: subject, topicName: $0.key)
                        let mastery2 = ProficiencyTracker.masteryPercentage(for: subject, topicName: $1.key)
                        return mastery1 < mastery2
                    }

                ForEach(topics, id: \.key) { topicName, topicCards in
                    DisclosureGroup {
                        let subtopics = Dictionary(grouping: topicCards, by: { $0.subtopic })
                            .sorted { 
                                let mastery1 = ProficiencyTracker.masteryPercentage(for: subject, topicName: topicName, subtopic: $0.key)
                                let mastery2 = ProficiencyTracker.masteryPercentage(for: subject, topicName: topicName, subtopic: $1.key)
                                return mastery1 < mastery2
                            }

                        VStack(spacing: 0) {
                            ForEach(subtopics, id: \.key) { subtopicName, subCards in
                                let subName = subtopicName.isEmpty ? "General" : subtopicName
                                let subMastery = ProficiencyTracker.masteryPercentage(for: subject, topicName: topicName, subtopic: subtopicName)
                                let dueCount = subCards.filter { $0.isDue }.count
                                
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Text(subName)
                                                .font(.callout)
                                            if dueCount > 0 {
                                                Text("\(dueCount) due")
                                                    .font(.caption2)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Capsule().fill(.orange.opacity(0.2)))
                                                    .foregroundStyle(.orange)
                                            }
                                            if subMastery < 0.3 {
                                                Text("Weak")
                                                    .font(.caption2)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Capsule().fill(.red.opacity(0.15)))
                                                    .foregroundStyle(.red)
                                            }
                                        }
                                        Text("\(subCards.count) cards")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("\(Int(subMastery * 100))%")
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundStyle(color)
                                        MasteryBar(progress: subMastery, height: 4, color: color)
                                            .frame(width: 60)
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.leading, 12)
                                
                                if subtopicName != subtopics.last?.key {
                                    Divider().padding(.leading, 12)
                                }
                            }
                        }
                        .padding(.top, 4)
                        
                    } label: {
                        let mastery = ProficiencyTracker.masteryPercentage(for: subject, topicName: topicName)
                        let dueCount = topicCards.filter { $0.isDue }.count
                        
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(topicName)
                                        .font(.callout.weight(.medium))
                                        .foregroundStyle(.primary)
                                    if mastery < 0.3 {
                                        Circle()
                                            .fill(.red)
                                            .frame(width: 6, height: 6)
                                    }
                                }
                                HStack(spacing: 8) {
                                    Text("\(topicCards.count) cards")
                                    Text("•")
                                    Text("\(Int(mastery * 100))% mastered")
                                    if dueCount > 0 {
                                        Text("•")
                                        Text("\(dueCount) due")
                                            .foregroundStyle(.orange)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            MasteryBar(progress: mastery, height: 5, color: color)
                                .frame(width: 80)
                        }
                        .padding(.vertical, 4)
                    }
                    .tint(color)

                    if topicName != topics.last?.key {
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
                    GradeSummaryRow(grade: grade, color: gradeColor(grade.resolvedIBScore))
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
    @State private var assessmentTitle = ""
    @State private var score = 4
    @State private var predictedGrade = 5
    @State private var achievedPoints = ""
    @State private var maxPoints = ""
    @State private var weightPercent = ""
    @State private var sourceName = "Manual"
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

                    TextField("Assessment title", text: $assessmentTitle)
                }

                Section("Score (1-7)") {
                    Stepper(value: $score, in: 1...7) {
                        Text("\(score)")
                            .font(.title)
                    }
                }

                Section("Assessment Breakdown") {
                    TextField("Achieved points", text: $achievedPoints)
                    TextField("Max points", text: $maxPoints)
                    TextField("Weight %", text: $weightPercent)
                    TextField("Source", text: $sourceName)
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
                            assessmentTitle: assessmentTitle,
                            achievedPoints: Double(achievedPoints),
                            maxPoints: Double(maxPoints),
                            weightPercent: Double(weightPercent),
                            sourceName: sourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : sourceName,
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
                Text(grade.displayTitle)
                    .font(.callout.weight(.medium))
                HStack(spacing: 6) {
                    Text(grade.component)
                    Text(grade.date, style: .date)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let sourceName = grade.sourceName, !sourceName.isEmpty {
                    Text(sourceName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if !grade.teacherFeedback.isEmpty {
                    Text(grade.teacherFeedback)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(grade.resolvedIBScore)")
                    .font(.title2.bold())
                    .foregroundColor(color)
                Text(grade.scoreSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 2)
    }
}
