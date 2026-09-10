import SwiftUI
import SwiftData

struct SubjectDetailView: View {
    let subject: Subject
    @Query(sort: \StudySession.endDate, order: .reverse) private var studySessions: [StudySession]
    @Query private var academicAssessments: [AcademicAssessment]
    @Query private var academicMappings: [AcademicAssessmentMapping]
    @Query private var academicReports: [AcademicReportSnapshot]
    @State private var showAddGrade = false
    @State private var showReview = false
    @State private var showStudyGuide = false
    @State private var showTopicBrowser = false
    @State private var showAcademicImport = false
    @State private var showMappingReview = false
    // Curriculum subunits shown expanded by default so the per-subunit mastery
    // breakdown is visible without clicking into every topic.
    @State private var expandedUnits: Set<String> = []

    private var color: Color { IBColors.inkTertiary }
    private var sortedGrades: [Grade] { subject.grades.sorted { $0.date > $1.date } }
    private var curriculum: [CurriculumUnit] {
        SyllabusSeeder.curriculum(for: subject.name, level: subject.level)
    }
    private var curriculumTopicCount: Int { curriculum.flatMap(\.topics).count }
    private var curriculumSubunitCount: Int { curriculum.flatMap(\.topics).flatMap(\.subtopics).count }
    private var learningResources: [LearningResource] {
        LearningResourceCatalog.resources(
            for: subject.name,
            topicNames: curriculum.flatMap(\.topics).map(\.name),
            limit: 6
        )
    }
    private var subjectAssessments: [AcademicAssessment] {
        academicAssessments.filter {
            $0.subjectName.caseInsensitiveCompare(subject.name) == .orderedSame &&
                $0.courseLevel.caseInsensitiveCompare(subject.level) == .orderedSame
        }
    }
    private var subjectMappings: [AcademicAssessmentMapping] {
        academicMappings.filter {
            $0.subjectName.caseInsensitiveCompare(subject.name) == .orderedSame &&
                $0.courseLevel.caseInsensitiveCompare(subject.level) == .orderedSame
        }
    }
    private var subjectProgress: ProgressEvidence {
        ProgressEvidenceService.score(
            subjectName: subject.name,
            courseLevel: subject.level,
            cards: subject.cards,
            assessments: subjectAssessments,
            mappings: subjectMappings,
            reports: academicReports.filter {
                $0.subjectName.caseInsensitiveCompare(subject.name) == .orderedSame &&
                    $0.courseLevel.caseInsensitiveCompare(subject.level) == .orderedSame
            },
            workSessions: subjectWorkSessions
        )
    }

    private var masteryDescriptor: String {
        if subjectProgress.assessmentEvidence != nil { return "assessment-backed mastery" }
        if subjectProgress.recallMastery != nil { return "recall mastery" }
        return "no mastery evidence yet"
    }

    // MARK: - Lookup indexes
    // Built once per render (single pass over @Query/relationship data) so
    // per-topic/per-subunit rows never re-scan the full card or session
    // collections (previously O(cards × subtopics) per render).

    private var cardIndex: SubjectCardIndex {
        var index = SubjectCardIndex()
        for card in subject.cards {
            index.byTopic[card.topicName, default: []].append(card)
            index.bySubtopic["\(card.topicName)|\(card.subtopic)", default: []].append(card)
        }
        return index
    }

    private var subjectWorkSessions: [StudySession] {
        studySessions.filter { $0.subjectName.caseInsensitiveCompare(subject.name) == .orderedSame }
    }

    /// Subject work sessions keyed by lowercased topic name so subunit rows do
    /// not scan the session history once per row.
    private var workSessionsByTopic: [String: [StudySession]] {
        var index: [String: [StudySession]] = [:]
        for session in subjectWorkSessions {
            for topic in session.selectedTopicNames {
                index[topic.lowercased(), default: []].append(session)
            }
        }
        return index
    }

    private func workSessionsFor(topic: String, subtopic: String, in byTopic: [String: [StudySession]]) -> [StudySession] {
        guard let candidates = byTopic[topic.lowercased()] else { return [] }
        return candidates.filter { session in
            let sessionSubtopics = StudyScope.parseList(session.subtopicsCovered ?? "")
            return sessionSubtopics.isEmpty || sessionSubtopics.contains {
                $0.caseInsensitiveCompare(subtopic) == .orderedSame
            }
        }
    }

    private func topicMastery(_ topic: CurriculumTopic, index: SubjectCardIndex) -> Double {
        guard !topic.subtopics.isEmpty else { return 0 }
        let score = topic.subtopics.reduce(0.0) { partial, subtopic in
            partial + subtopicMastery(topic: topic.name, subtopic: subtopic, index: index)
        }
        return score / Double(topic.subtopics.count)
    }

    private func subtopicMastery(
        topic: String,
        subtopic: String,
        index: SubjectCardIndex
    ) -> Double {
        ProficiencyTracker.masteryPercentage(for: index.bySubtopic["\(topic)|\(subtopic)"] ?? [])
    }

    private func weightedCurriculumMastery(index: SubjectCardIndex) -> Double {
        let topics = curriculum.flatMap(\.topics)
        let subunitCount = topics.reduce(0) { $0 + $1.subtopics.count }
        guard subunitCount > 0 else { return 0 }
        let score = topics.reduce(0.0) { partial, topic in
            partial + topicMastery(topic, index: index) * Double(topic.subtopics.count)
        }
        return score / Double(subunitCount)
    }

    private var reviewableDueCount: Int {
        let studiedScopes = StudySession.uniqueStudyScopes(from: studySessions)
            .filter { $0.subjectName == subject.name }
        guard !studiedScopes.isEmpty else { return 0 }
        var count = 0
        for card in subject.cards where card.isDue {
            if studiedScopes.contains(where: { $0.matches(card) }) {
                count += 1
            }
        }
        return count
    }

    var body: some View {
        let dueCount = reviewableDueCount
        return ScrollView {
            LazyVStack(spacing: 16) {
                // Hero with ring
                heroCard(dueCount: dueCount)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                // Actions
                actionsBar(dueCount: dueCount)
                    .padding(.horizontal, 24)

                progressSignalCard
                    .padding(.horizontal, 24)

                // Proficiency breakdown
                proficiencyCard
                    .padding(.horizontal, 24)

                // Topics
                topicsCard
                    .padding(.horizontal, 24)

                // Exam-ready domain knowledge (curated per subject)
                if let knowledge = SubjectKnowledge.knowledge(for: subject.name) {
                    knowledgeCard(knowledge)
                        .padding(.horizontal, 24)
                }

                if !learningResources.isEmpty {
                    resourcesCard
                        .padding(.horizontal, 24)
                }

                // Grades
                gradesCard
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .background(.background)
        .navigationTitle(subject.name)
        .onAppear {
            // Show the full sub-unit mastery breakdown by default.
            if expandedUnits.isEmpty {
                expandedUnits = Set(curriculum.map(\.name))
            }
        }
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
        .sheet(isPresented: $showAcademicImport) {
            AcademicImportView()
        }
        .sheet(isPresented: $showMappingReview) {
            AcademicMappingReviewView(subject: subject)
        }
    }

    // MARK: - Hero
    private func heroCard(dueCount: Int) -> some View {
        let mastery = subjectProgress.blendedMastery ?? 0
        return HStack(spacing: 20) {
            ProgressRing(
                progress: mastery,
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
                    if dueCount > 0 {
                        Label("\(dueCount) due now", systemImage: "clock.badge.exclamationmark")
                            .foregroundStyle(IBColors.warning)
                    } else {
                        Label("All caught up", systemImage: "checkmark.circle")
                            .foregroundStyle(IBColors.success)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                Text("\(Int(mastery * 100))% \(masteryDescriptor)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
        .glassCard()
    }

    // MARK: - Actions
    private func actionsBar(dueCount: Int) -> some View {
        HStack(spacing: 12) {
            if dueCount > 0 {
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

            Button {
                showAcademicImport = true
                IBHaptics.light()
            } label: {
                Label("Import evidence", systemImage: "chart.bar.doc.horizontal")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help("Import academic records")

            Button {
                showMappingReview = true
                IBHaptics.light()
            } label: {
                Image(systemName: "arrow.triangle.branch")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .disabled(subjectAssessments.isEmpty)
            .help("Review assessment mappings")
        }
    }

    private var progressSignalCard: some View {
        HStack(spacing: 0) {
            progressSignal("Recall", value: subjectProgress.recallMastery, detail: subject.cards.isEmpty ? "No cards yet" : "\(subject.cards.count) FSRS cards", tint: color)
            Divider().frame(height: 42)
            progressSignal("Evidence", value: subjectProgress.assessmentEvidence, detail: subjectProgress.scoredAssessmentCount == 0 ? "Import results" : "\(subjectProgress.scoredAssessmentCount) scored", tint: IBColors.inkTertiary)
            Divider().frame(height: 42)
            progressSignal("Mappings", value: nil, detail: "\(subjectProgress.approvedMappingCount) approved", tint: IBColors.inkTertiary)
            Divider().frame(height: 42)
            progressSignal("Risk", value: nil, detail: subjectProgress.isAtRisk ? "Needs attention" : "On track", tint: subjectProgress.isAtRisk ? IBColors.inkTertiary : IBColors.success)
        }
        .padding(14)
        .glassCard()
    }

    private func progressSignal(_ label: String, value: Double?, detail: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(IBColors.inkSecondary)
            Text(value.map { "\(Int($0 * 100))%" } ?? "--")
                .font(.callout.weight(.bold))
                .foregroundStyle(tint)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(IBColors.inkTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
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

            if subject.cards.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.title3)
                        .foregroundStyle(color)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No recall cards yet")
                            .font(.callout.weight(.bold))
                        Text("Generate a focused set from the curriculum or import assessment evidence first.")
                            .font(.caption)
                            .foregroundStyle(IBColors.inkSecondary)
                    }
                }
                .padding(.vertical, 6)
            } else {
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
        }
        .padding(16)
        .glassCard()
    }

    private func proficiencyColor(_ level: ProficiencyLevel) -> Color {
        switch level {
        case .novice: return IBColors.danger
        case .developing: return IBColors.warning
        case .proficient: return IBColors.accent
        case .mastered: return IBColors.success
        }
    }

    // MARK: - Topics
    private var topicsCard: some View {
        let index = cardIndex
        let sessionsByTopic = workSessionsByTopic
        return LazyVStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.bullet")
                    .foregroundStyle(.tint)
                Text("Curriculum Mastery")
                    .font(.headline)
                Spacer()
                Text("\(Int((subjectProgress.blendedMastery ?? weightedCurriculumMastery(index: index)) * 100))% \(masteryDescriptor) · \(subjectWorkSessions.count) work sessions")
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
                        let topicCards = index.byTopic[topic.name] ?? []
                        let mastery = topicMastery(topic, index: index)
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedUnits.contains(unit.name) },
                                set: { isExpanded in
                                    if isExpanded { expandedUnits.insert(unit.name) } else { expandedUnits.remove(unit.name) }
                                }
                            )
                        ) {
                            VStack(spacing: 0) {
                                ForEach(topic.subtopics, id: \.self) { subtopic in
                                    let cards = index.bySubtopic["\(topic.name)|\(subtopic)"] ?? []
                                    let cardMastery = ProficiencyTracker.masteryPercentage(for: cards)
                                    let evidence = ProgressEvidenceService.score(
                                        subjectName: subject.name,
                                        courseLevel: subject.level,
                                        topicName: topic.name,
                                        subtopicName: subtopic,
                                        cards: cards,
                                        assessments: subjectAssessments,
                                        mappings: subjectMappings,
                                        workSessions: workSessionsFor(
                                            topic: topic.name,
                                            subtopic: subtopic,
                                            in: sessionsByTopic
                                        )
                                    )
                                    let subMastery = evidence.blendedMastery ?? cardMastery
                                    let workSessions = workSessionsFor(topic: topic.name, subtopic: subtopic, in: sessionsByTopic)
                                    let hasProgress = !cards.isEmpty || !workSessions.isEmpty || evidence.hasEvidence
                                    HStack(spacing: 10) {
                                        Image(systemName: hasProgress ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(hasProgress ? color : Color.secondary)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(subtopic).font(.callout)
                                            Text(subunitActivitySummary(cards: cards, workSessions: workSessions, evidence: evidence))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if hasProgress {
                                            Text("\(Int(subMastery * 100))%")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(color)
                                            MasteryBar(progress: subMastery, height: 4, color: color)
                                                .frame(width: 54)
                                        }
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

    private func subunitActivitySummary(cards: [StudyCard], workSessions: [StudySession], evidence: ProgressEvidence) -> String {
        var parts: [String] = []
        parts.append(cards.isEmpty ? "No cards" : "\(cards.count) cards · \(cards.filter(\.isDue).count) due")
        if !workSessions.isEmpty {
            parts.append("\(workSessions.count) work session\(workSessions.count == 1 ? "" : "s")")
            if let latest = workSessions.first {
                parts.append("last \(latest.endDate.formatted(date: .abbreviated, time: .omitted))")
            }
        }
        if evidence.scoredAssessmentCount > 0 {
            parts.append("\(evidence.scoredAssessmentCount) assessment\(evidence.scoredAssessmentCount == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Exam-ready knowledge

    private func knowledgeCard(_ knowledge: SubjectKnowledge) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(color)
                Text("Exam-ready knowledge")
                    .font(.headline)
                Spacer()
                Text("ARIA is tuned to these")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Key concepts")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
                ForEach(knowledge.keyConcepts, id: \.self) { item in
                    Label(item, systemImage: "book.closed")
                        .font(.callout)
                        .foregroundStyle(IBColors.ink)
                }
            }
            .padding(.vertical, 6)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("High-yield topics")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
                ForEach(knowledge.highYieldTopics, id: \.self) { item in
                    Label(item, systemImage: "checkmark.seal")
                        .font(.callout)
                        .foregroundStyle(IBColors.ink)
                }
            }
            .padding(.vertical, 6)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Common misconceptions")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
                ForEach(knowledge.commonMisconceptions, id: \.self) { item in
                    Label(item, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(IBColors.ink)
                }
            }
            .padding(.vertical, 6)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Exam technique")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
                ForEach(knowledge.examTechnique, id: \.self) { item in
                    Label(item, systemImage: "lightbulb")
                        .font(.callout)
                        .foregroundStyle(IBColors.ink)
                }
            }
            .padding(.vertical, 6)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: IBRadius.card)
                .fill(IBGradient.cardSheen)
                .shadow(color: IBShadow.cardColor, radius: IBShadow.cardRadius, x: 0, y: IBShadow.cardY)
                .overlay(RoundedRectangle(cornerRadius: IBRadius.card).strokeBorder(color.opacity(0.15), lineWidth: 0.5))
        )
    }

    private var resourcesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "books.vertical.fill")
                    .foregroundStyle(color)
                Text("Trusted resources")
                    .font(.headline)
                Spacer()
                Text("Selected for this course")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(learningResources) { resource in
                Link(destination: resource.url) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(color)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(resource.title)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(IBColors.ink)
                            Text("\(resource.provider) · \(resource.purpose)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open \(resource.title)")

                if resource.id != learningResources.last?.id {
                    Divider()
                }
            }
        }
        .padding(16)
        .glassCard()
    }

    // MARK: - Grades
    private var gradesCard: some View {
        VStack(alignment: .leading, spacing: 12) {            HStack {
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

// MARK: - Card Index
/// Single-pass lookup table over a subject's cards, built once per render.
private struct SubjectCardIndex {
    var byTopic: [String: [StudyCard]] = [:]
    var bySubtopic: [String: [StudyCard]] = [:]
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
    @State private var saveError: String?

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
                        do {
                            try context.save()
                            IBHaptics.success()
                            dismiss()
                        } catch {
                            // Undo only this insert, not unrelated pending work.
                            context.delete(grade)
                            saveError = error.localizedDescription
                        }
                    }
                }
            }
            .alert("Could Not Save Grade", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "The grade could not be saved.")
            }
        }
        .frame(minWidth: 450, minHeight: 400)
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
