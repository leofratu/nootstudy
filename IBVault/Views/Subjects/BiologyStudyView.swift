import SwiftUI
import SwiftData

struct BiologyStudyView: View {
    let subject: Subject
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var nodes: [CurriculumNode]
    @Query private var cards: [StudyCard]
    @State private var selectedCode: String
    @State private var search = ""
    @State private var mode = StudyMode.learn
    @State private var mistakes = Set<String>()
    @State private var message: String?
    @State private var error: String?
    @State private var showReview = false

    enum StudyMode: String, CaseIterable { case learn = "Learn", flashcards = "Flashcards", practice = "Practice" }

    init(subject: Subject, initialCode: String = "") {
        self.subject = subject
        _selectedCode = State(initialValue: initialCode)
    }

    private var level: IBCourseLevel { subject.courseLevel }
    private var available: [BiologyTopic] { BiologyCatalog.topics(at: level) }
    private var visible: [BiologyTopic] { available.filter { $0.contains(search, at: level) } }
    private var selected: BiologyTopic? { visible.first { $0.code == selectedCode } }
    private var selectionKey: String { "biology.selection.\(subject.id.uuidString).\(level.rawValue)" }
    private var activeCards: [StudyCard] { cards.filter { $0.subject?.id == subject.id && BiologyStudyService.isEligible($0) } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let failure = BiologyCatalog.failure {
                ContentUnavailableView {
                    Label("Biology content could not load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(failure)
                    Text("Your saved cards and progress have not been removed. You can still use the card library.")
                }
            } else {
                HSplitView {
                    outline.frame(minWidth: 210, idealWidth: 250, maxWidth: 310)
                    detail.frame(minWidth: 390, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if let message {
                Text(message).font(.callout).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(IBColors.highlight).accessibilityAddTraits(.updatesFrequently)
            }
        }
        .frame(minWidth: 660, minHeight: 560)
        .background(IBColors.canvas)
        .foregroundStyle(IBColors.ink)
        .navigationTitle("Biology")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        .onAppear {
            mistakes = BiologyPracticeBookmarks.load(subjectID: subject.id)
            if selectedCode.isEmpty { selectedCode = UserDefaults.standard.string(forKey: selectionKey) ?? "" }
            reconcileSelection()
        }
        .onChange(of: search) { _, _ in reconcileSelection() }
        .onChange(of: subject.level) { _, _ in
            selectedCode = UserDefaults.standard.string(forKey: selectionKey) ?? ""
            reconcileSelection()
            message = nil
        }
        .onChange(of: selectedCode) { _, code in
            if !code.isEmpty { UserDefaults.standard.set(code, forKey: selectionKey) }
            message = nil
        }
        .onChange(of: mistakes) { _, value in BiologyPracticeBookmarks.save(value, subjectID: subject.id) }
        .sheet(isPresented: $showReview) { ReviewSessionView(filterSubject: subject) }
        .alert("Could not save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "Please try again.") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Biology").font(.title2.bold())
                    Text("\(available.count) topics · First assessment 2025").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Course level", selection: Binding(get: { level }, set: changeLevel)) {
                    Text("SL").tag(IBCourseLevel.sl)
                    Text("HL").tag(IBCourseLevel.hl)
                }.pickerStyle(.segmented).frame(width: 120)
                Button("Scheduled review") { showReview = true }
            }
            HStack {
                TextField("Search code, topic or concept", text: $search).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search Biology syllabus")
                Link("IB reference", destination: URL(string: BiologyCatalog.sourceURL)!)
            }
            Text("Original revision pack · Partial coverage, not a complete or teacher-certified course")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(16)
    }

    private var outline: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if visible.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
                ForEach(BiologyCatalog.themes, id: \.self) { theme in
                    let topics = visible.filter { $0.theme == theme }
                    if !topics.isEmpty {
                        Text("\(theme) · \(BiologyCatalog.themeName(theme))")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(topics) { topic in
                            Button { selectedCode = topic.code } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(topic.name).font(.callout.weight(selectedCode == topic.code ? .semibold : .regular))
                                        .multilineTextAlignment(.leading)
                                    let count = mistakeCount(topic)
                                    Text(count > 0 ? "\(count) to revisit" : topic.hlOnly ? "HL only · Overview" : "SL + HL · Overview")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(9)
                                .background(selectedCode == topic.code ? IBColors.highlight : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 7))
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .accessibilityAddTraits(selectedCode == topic.code ? .isSelected : [])
                        }
                    }
                }
            }.padding(12)
        }
    }

    @ViewBuilder private var detail: some View {
        if let topic = selected {
            VStack(alignment: .leading, spacing: 0) {
                topicHeader(topic)
                Divider()
                Group {
                    switch mode {
                    case .learn: lesson(topic)
                    case .flashcards:
                        BiologyFlashcardView(sections: topic.sections(at: level))
                    case .practice:
                        BiologyPracticeView(topic: topic, level: level, mistakes: $mistakes) { keys in
                            add(topic, questionKeys: keys)
                        }
                    }
                }
                .id("\(topic.code)-\(level.rawValue)-\(mode.rawValue)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ContentUnavailableView("No matching topic", systemImage: "magnifyingglass",
                                   description: Text("Clear the search or choose another topic. HL-only material is hidden in SL."))
        }
    }

    private func topicHeader(_ topic: BiologyTopic) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(topic.name).font(.title2.bold()).textSelection(.enabled)
            let sections = topic.sections(at: level)
            let questions = topic.questions(at: level)
            Text("\(sections.count) explanations · \(sections.count) flashcards · \(questions.count) practice questions")
                .font(.caption).foregroundStyle(.secondary)
            let mastery = CurriculumProgressService.topicMastery(subject: subject, topicName: topic.name,
                                                                 subtopics: sections.map(\.title), nodes: nodes)
            ProgressView(value: min(1, max(0, mastery))) {
                Text("Review mastery of this pack: \(Int(mastery * 100))%")
            }.font(.caption)
            Picker("Study mode", selection: $mode) {
                ForEach(StudyMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            HStack {
                Button(mode == .flashcards ? "Add flashcards to review" : "Add questions to review") {
                    add(topic, flashcards: mode == .flashcards)
                }
                Text("Uses the existing spaced-review queue").font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(16)
    }

    private func lesson(_ topic: BiologyTopic) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !topic.prerequisites.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Builds on").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(topic.prerequisites, id: \.self) { code in
                            if let prerequisite = available.first(where: { $0.code == code }) {
                                Button(prerequisite.name) { search = ""; selectedCode = code }
                                    .buttonStyle(.link)
                            }
                        }
                    }
                }
                ForEach(topic.sections(at: level)) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.title).font(.title3.weight(.semibold))
                        if section.hlOnly == true { Text("HL extension").font(.caption.weight(.semibold)).foregroundStyle(IBColors.accent) }
                        Text(section.body).lineSpacing(5).textSelection(.enabled)
                        Label { Text(section.pitfall).textSelection(.enabled) } icon: { Image(systemName: "lightbulb") }
                            .font(.callout).foregroundStyle(.secondary)
                        if let points = section.syllabusPoints, !points.isEmpty {
                            Text("Relevant understandings: \(points.joined(separator: ", "))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Label("Remaining coverage", systemImage: "list.bullet.rectangle").font(.headline)
                    Text(topic.remaining).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    Text("Reading and free practice do not mark this syllabus topic complete. Saved review history is tracked separately. Older custom cards remain in the card library.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(22).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
        }
    }

    private func mistakeCount(_ topic: BiologyTopic) -> Int {
        topic.questions(at: level).filter { mistakes.contains(BiologyCatalog.resourceID(topic: topic.code, key: $0.key)) }.count
    }
    private func reconcileSelection() {
        if !visible.contains(where: { $0.code == selectedCode }) { selectedCode = visible.first?.code ?? "" }
    }
    private func changeLevel(_ value: IBCourseLevel) {
        let old = subject.level
        subject.courseLevel = value
        do {
            try context.save()
            if !SyllabusSeeder.synchronizeCurriculum(context: context) {
                error = "The course level was saved, but curriculum synchronization needs another attempt. Your existing progress is preserved."
            }
        } catch {
            subject.level = old
            self.error = error.localizedDescription
        }
    }
    private func add(_ topic: BiologyTopic, flashcards: Bool = false, questionKeys: Set<String>? = nil) {
        do {
            let count = try BiologyStudyService.addToReview(topic: topic, subject: subject, context: context,
                                                           flashcards: flashcards, questionKeys: questionKeys)
            message = count == 0 ? "These resources are already in your review library. Their schedules were preserved."
                : "Added \(count) resources. Scheduled review respects your daily allowance; adding cards does not award mastery."
        } catch { self.error = error.localizedDescription }
    }
}

private struct BiologyFlashcardView: View {
    let sections: [BiologySection]
    @State private var index = 0
    @State private var revealed = false

    var body: some View {
        ScrollView {
            if sections.indices.contains(index) {
                let section = sections[index]
                VStack(alignment: .leading, spacing: 20) {
                    Text("Flashcard \(index + 1) of \(sections.count)").font(.caption).foregroundStyle(.secondary)
                    Text("Explain: \(section.title)").font(.title2)
                    if revealed {
                        Text(section.body).lineSpacing(5).textSelection(.enabled)
                        Text(section.pitfall).font(.callout).foregroundStyle(.secondary)
                    }
                    Button(revealed ? "Hide explanation" : "Reveal explanation") { revealed.toggle() }
                        .keyboardShortcut(.space, modifiers: [])
                    HStack {
                        Button("Previous") { index -= 1 }.disabled(index == 0)
                        Spacer()
                        Button("Next") { index += 1 }.disabled(index + 1 >= sections.count)
                    }
                    Text("Ungraded practice. Add these flashcards to scheduled review to build review history.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(24).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
            }
        }.onChange(of: index) { _, _ in revealed = false }
    }
}

private struct BiologyPracticeView: View {
    let topic: BiologyTopic
    let level: IBCourseLevel
    @Binding var mistakes: Set<String>
    let addMistakes: (Set<String>) -> Void
    @State private var questions: [BiologyQuestion]
    @State private var index = 0
    @State private var selectedOption: String?
    @State private var options: [String] = []
    @State private var revealed = false
    @State private var graded = false
    @State private var answers: [String: Bool] = [:]

    init(topic: BiologyTopic, level: IBCourseLevel, mistakes: Binding<Set<String>>,
         addMistakes: @escaping (Set<String>) -> Void) {
        self.topic = topic
        self.level = level
        _mistakes = mistakes
        self.addMistakes = addMistakes
        let saved = mistakes.wrappedValue
        _questions = State(initialValue: topic.questions(at: level).sorted {
            let left = saved.contains(BiologyCatalog.resourceID(topic: topic.code, key: $0.key))
            let right = saved.contains(BiologyCatalog.resourceID(topic: topic.code, key: $1.key))
            return left != right ? left : $0.key < $1.key
        })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if questions.indices.contains(index) {
                    questionBody(questions[index])
                } else {
                    results
                }
            }.padding(24).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
        }
        .onAppear { prepareQuestion() }
        .onChange(of: index) { _, _ in prepareQuestion() }
    }

    @ViewBuilder private func questionBody(_ question: BiologyQuestion) -> some View {
        HStack {
            Text("Question \(index + 1) of \(questions.count)")
            Spacer()
            Text(question.command.capitalized)
        }.font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        Text(question.prompt).font(.title3).textSelection(.enabled)
        if question.kind == .mcq {
            ForEach(Array(options.enumerated()), id: \.offset) { offset, option in
                Button { selectedOption = option } label: {
                    HStack(alignment: .top) {
                        Image(systemName: selectedOption == option ? "largecircle.fill.circle" : "circle")
                        Text(option).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                        if revealed && option == question.answer { Image(systemName: "checkmark.circle.fill") }
                    }.padding(12).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(selectedOption == option ? IBColors.highlight : IBColors.surface,
                                    in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).disabled(revealed)
                    .accessibilityLabel("Option \(offset + 1): \(option)")
                    .accessibilityValue(revealed && option == question.answer ? "Correct answer" : selectedOption == option ? "Selected" : "")
            }
            if !revealed {
                Button("Check answer") {
                    guard let selectedOption else { return }
                    revealed = true
                    record(selectedOption == question.answer, question: question)
                }.disabled(selectedOption == nil).keyboardShortcut(.return, modifiers: [])
            }
        } else if !revealed {
            Text("Work out your response before revealing the marking points. Equivalent scientifically correct wording is accepted by self-assessment, not exact-text matching.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Reveal marking points") { revealed = true }.keyboardShortcut(.return, modifiers: [])
        }
        if revealed {
            Divider()
            if let correct = answers[question.key] {
                Label(correct ? "Correct / self-assessed correct" : "Needs another look",
                      systemImage: correct ? "checkmark.circle" : "arrow.counterclockwise")
                    .font(.headline)
            }
            ForEach(Array(question.markingPoints.enumerated()), id: \.offset) { _, point in
                Text(point).textSelection(.enabled)
            }
            Text(question.explanation).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            if let section = topic.sections(at: level).first(where: { $0.key == question.sectionKey }) {
                DisclosureGroup("Revisit: \(section.title)") { Text(section.body).padding(.top, 8) }
            }
            if question.kind != .mcq && !graded {
                HStack {
                    Button("Needs practice") { record(false, question: question) }
                    Button("Got it") { record(true, question: question) }
                }
            }
        }
        HStack {
            Button("Skip without grading") { index += 1 }
            Spacer()
            Button(index + 1 == questions.count ? "See results" : "Next question") { index += 1 }
                .disabled(!graded)
        }
        Text("Free practice does not award mastery. Mistakes are saved locally and shown first next time.")
            .font(.caption).foregroundStyle(.secondary)
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Practice results").font(.title2.bold())
            Text("\(answers.values.filter { $0 }.count) correct out of \(answers.count) assessed · \(questions.count - answers.count) skipped")
            Text("Written answers are self-assessed. This score is not a whole-topic mastery estimate.")
                .font(.callout).foregroundStyle(.secondary)
            let keys = Set(topic.questions(at: level).filter {
                mistakes.contains(BiologyCatalog.resourceID(topic: topic.code, key: $0.key))
            }.map(\.key))
            Button("Retry \(keys.count) saved mistakes") {
                questions = topic.questions(at: level).filter { keys.contains($0.key) }
                answers = [:]
                index = 0
                prepareQuestion()
            }.disabled(keys.isEmpty)
            Button("Add saved mistakes to scheduled review") { addMistakes(keys) }.disabled(keys.isEmpty)
            Button("Practice all questions again") {
                questions = topic.questions(at: level)
                answers = [:]
                index = 0
                prepareQuestion()
            }
        }
    }

    private func record(_ correct: Bool, question: BiologyQuestion) {
        guard !graded else { return }
        graded = true
        answers[question.key] = correct
        let id = BiologyCatalog.resourceID(topic: topic.code, key: question.key)
        if correct { mistakes.remove(id) } else { mistakes.insert(id) }
    }
    private func prepareQuestion() {
        selectedOption = nil
        revealed = false
        graded = false
        options = questions.indices.contains(index) ? questions[index].options.shuffled() : []
    }
}
