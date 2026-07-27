import SwiftUI
import SwiftData

struct SubjectDetailView: View {
    let subject: Subject
    @Environment(\.modelContext) private var context
    @Query(sort: \StudySession.endDate, order: .reverse) private var studySessions: [StudySession]
    @Query(sort: \CurriculumNode.topicName) private var curriculumNodes: [CurriculumNode]
    @State private var showAddGrade = false
    @State private var showReview = false
    @State private var showStudyGuide = false
    @State private var showTopicBrowser = false
    @State private var masteryError: String?

    private var color: Color { Color(hex: subject.accentColorHex) }
    private var sortedCards: [StudyCard] { subject.cards.sorted { $0.topicName < $1.topicName } }
    private var sortedGrades: [Grade] { subject.grades.sorted { $0.date > $1.date } }
    private var curriculum: [CurriculumUnit] {
        SyllabusSeeder.curriculum(for: subject.name, level: subject.level)
    }
    private var curriculumTopicCount: Int { curriculum.flatMap(\.topics).count }
    private var curriculumSubunitCount: Int { curriculum.flatMap(\.topics).flatMap(\.subtopics).count }
    private var subjectCurriculumNodes: [CurriculumNode] {
        curriculumNodes.filter {
            $0.subjectName.caseInsensitiveCompare(subject.name) == .orderedSame &&
                $0.level.caseInsensitiveCompare(subject.level) == .orderedSame
        }
    }
    private var curriculumMastery: Double {
        let topics = curriculum.flatMap(\.topics)
        let subunitCount = topics.reduce(0) { $0 + $1.subtopics.count }
        guard subunitCount > 0 else { return 0 }
        let score = topics.reduce(0.0) { partial, topic in
            partial + CurriculumProgressService.topicMastery(
                subject: subject,
                topicName: topic.name,
                subtopics: topic.subtopics,
                nodes: subjectCurriculumNodes
            ) * Double(topic.subtopics.count)
        }
        return score / Double(subunitCount)
    }
    private var subjectWorkSessions: [StudySession] {
        studySessions.filter { $0.subjectName.caseInsensitiveCompare(subject.name) == .orderedSame }
    }
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
        .alert("Could Not Save Mastery", isPresented: Binding(
            get: { masteryError != nil },
            set: { if !$0 { masteryError = nil } }
        )) {
            Button("OK") { masteryError = nil }
        } message: {
            Text(masteryError ?? "The mastery update could not be saved.")
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
                    Label("\(curriculumTopicCount) topics", systemImage: "square.stack")
                    Label("\(curriculumSubunitCount) subunits", systemImage: "list.bullet.indent")
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

                Text("\(Int(subject.masteryProgress * 100))% review mastery")
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
                Text("\(Int(curriculumMastery * 100))% curriculum · \(subjectWorkSessions.count) work sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(curriculum, id: \.name) { unit in
                VStack(alignment: .leading, spacing: 8) {
                    Text(unit.name)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color)
                        .textCase(.uppercase)

                    ForEach(unit.topics, id: \.name) { topic in
                        let topicCards = subject.cards.filter { $0.topicName == topic.name }
                        let mastery = CurriculumProgressService.topicMastery(
                            subject: subject,
                            topicName: topic.name,
                            subtopics: topic.subtopics,
                            nodes: subjectCurriculumNodes
                        )
                        DisclosureGroup {
                            VStack(spacing: 0) {
                                ForEach(topic.subtopics, id: \.self) { subtopic in
                                    let cards = topicCards.filter { $0.subtopic == subtopic }
                                    let node = CurriculumProgressService.node(
                                        in: subjectCurriculumNodes,
                                        subjectName: subject.name,
                                        level: subject.level,
                                        topicName: topic.name,
                                        subtopicName: subtopic
                                    )
                                    let subMastery = CurriculumProgressService.effectiveMastery(cards: cards, node: node)
                                    let workSessions = CurriculumProgressService.matchingWorkSessions(
                                        in: studySessions,
                                        subjectName: subject.name,
                                        topicName: topic.name,
                                        subtopicName: subtopic
                                    )
                                    let hasProgress = !cards.isEmpty || node?.recordedProficiency != nil || !workSessions.isEmpty
                                    HStack(spacing: 10) {
                                        Image(systemName: hasProgress ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(hasProgress ? color : Color.secondary)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(subtopic).font(.callout)
                                            Text(subunitActivitySummary(cards: cards, workSessions: workSessions))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if let recorded = node?.recordedProficiency {
                                            Text(recorded.rawValue)
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(proficiencyColor(recorded))
                                                .padding(.horizontal, 7)
                                                .frame(height: 22)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .fill(proficiencyColor(recorded).opacity(0.1))
                                                )
                                        }
                                        if !cards.isEmpty || node?.recordedProficiency != nil {
                                            Text("\(Int(subMastery * 100))%")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(color)
                                            MasteryBar(progress: subMastery, height: 4, color: color)
                                                .frame(width: 54)
                                        }
                                        masteryMenu(
                                            current: node?.recordedProficiency,
                                            unitName: unit.name,
                                            topicName: topic.name,
                                            subtopicName: subtopic
                                        )
                                    }
                                    .padding(.vertical, 7)
                                    .padding(.leading, 12)
                                }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(topic.name)
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("\(topic.subtopics.count) subunits · \(topicCards.count) cards")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(Int(mastery * 100))%")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(color)
                                MasteryBar(progress: mastery, height: 5, color: color)
                                    .frame(width: 76)
                            }
                            .padding(.vertical, 3)
                        }
                        .tint(color)
                    }
                }
                if unit.name != curriculum.last?.name { Divider() }
            }
        }
        .padding(16)
        .glassCard()
    }

    private func subunitActivitySummary(cards: [StudyCard], workSessions: [StudySession]) -> String {
        var parts: [String] = []
        parts.append(cards.isEmpty ? "No cards" : "\(cards.count) cards · \(cards.filter(\.isDue).count) due")
        if !workSessions.isEmpty {
            parts.append("\(workSessions.count) work session\(workSessions.count == 1 ? "" : "s")")
            if let latest = workSessions.first {
                parts.append("last \(latest.endDate.formatted(date: .abbreviated, time: .omitted))")
            }
        }
        return parts.joined(separator: " · ")
    }

    private func masteryMenu(
        current: ProficiencyLevel?,
        unitName: String,
        topicName: String,
        subtopicName: String
    ) -> some View {
        Menu {
            ForEach(ProficiencyLevel.allCases, id: \.self) { level in
                Button {
                    setMastery(level, unitName: unitName, topicName: topicName, subtopicName: subtopicName)
                } label: {
                    Label(level.rawValue, systemImage: current == level ? "checkmark" : "gauge")
                }
            }
            if current != nil {
                Divider()
                Button("Clear Recorded Mastery", role: .destructive) {
                    clearMastery(topicName: topicName, subtopicName: subtopicName)
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .help("Set recorded mastery for \(subtopicName)")
    }

    private func setMastery(
        _ level: ProficiencyLevel,
        unitName: String,
        topicName: String,
        subtopicName: String
    ) {
        do {
            try CurriculumProgressService.setMastery(
                level,
                subject: subject,
                unitName: unitName,
                topicName: topicName,
                subtopicName: subtopicName,
                source: "Manual",
                context: context
            )
        } catch {
            masteryError = error.localizedDescription
        }
    }

    private func clearMastery(topicName: String, subtopicName: String) {
        do {
            try CurriculumProgressService.clearMastery(
                subject: subject,
                topicName: topicName,
                subtopicName: subtopicName,
                context: context
            )
        } catch {
            masteryError = error.localizedDescription
        }
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
