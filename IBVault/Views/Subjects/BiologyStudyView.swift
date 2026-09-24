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
    @State private var showOutline = false
    @State private var topicFilter = TopicFilter.all

    enum TopicFilter: String, CaseIterable { case all = "All", revisit = "Revisit", unreviewed = "Unreviewed" }

    enum StudyMode: String, CaseIterable { case learn = "Learn", flashcards = "Flashcards", practice = "Practice" }

    init(subject: Subject, initialCode: String = "", initialMode: StudyMode = .learn) {
        self.subject = subject
        _selectedCode = State(initialValue: initialCode)
        _mode = State(initialValue: initialMode)
        let subjectID = subject.id
        _cards = Query(filter: #Predicate<StudyCard> { $0.subject?.id == subjectID })
    }

    private var level: IBCourseLevel { subject.courseLevel }
    private var available: [BiologyTopic] { BiologyCatalog.topics(at: level) }
    private var visible: [BiologyTopic] {
        // Snapshot once per filter evaluation, not once for every syllabus row.
        let reviewed = Set(activeCards.filter { $0.totalReviewCount > 0 }.map(\.topicName))
        let recorded = Set(nodes.filter {
            $0.subjectName == subject.name && $0.level == subject.level && $0.recordedProficiency != nil
        }.map(\.topicName))
        return available.filter { topic in
            guard topic.contains(search, at: level) else { return false }
            switch topicFilter {
            case .all: return true
            case .revisit: return mistakeCount(topic) > 0
            case .unreviewed: return !reviewed.contains(topic.name) && !recorded.contains(topic.name)
            }
        }
    }
    private var selected: BiologyTopic? { available.first { $0.code == selectedCode } }
    private var selectionKey: String { "biology.selection.\(subject.id.uuidString).\(level.rawValue)" }
    private var activeCards: [StudyCard] { cards.filter { $0.subject?.id == subject.id && BiologyStudyService.isEligible($0) } }

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 860
            VStack(spacing: 0) {
                header(compact: compact)
                Divider().overlay(IBColors.border)
                if let failure = BiologyCatalog.failure {
                    ContentUnavailableView {
                        Label("Biology content could not load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(failure)
                        Text("Your saved cards and progress have not been removed. The card library is still available.")
                    }
                } else if compact {
                    VStack(spacing: 0) {
                        Button { showOutline = true } label: {
                            HStack {
                                Image(systemName: "sidebar.left")
                                Text(selected?.name ?? "Choose a syllabus topic").lineLimit(2)
                                Spacer()
                                Image(systemName: "chevron.down")
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }.buttonStyle(.plain).padding(.horizontal, 18)
                            .accessibilityLabel("Open syllabus navigator")
                        Divider()
                        detail
                    }
                } else {
                    HSplitView {
                        outline.frame(minWidth: 220, idealWidth: 270, maxWidth: 320)
                            .background(IBColors.surfaceRaised.opacity(0.45))
                        detail.frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                if let message {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle")
                        Text(message).frame(maxWidth: .infinity, alignment: .leading)
                        Button { self.message = nil } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).accessibilityLabel("Dismiss status message")
                    }.font(.callout).padding(14).background(IBColors.highlight)
                        .accessibilityElement(children: .combine).accessibilityAddTraits(.updatesFrequently)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 560)
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
        .onChange(of: topicFilter) { _, _ in reconcileSelection() }
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
        .sheet(isPresented: $showOutline) {
            VStack(spacing: 0) {
                HStack {
                    Text("Biology syllabus").font(.headline)
                    Spacer()
                    Button("Done") { showOutline = false }.keyboardShortcut(.cancelAction)
                }.padding(16)
                Divider()
                outline
            }.frame(minWidth: 380, idealWidth: 420, minHeight: 480, idealHeight: 680)
                .background(IBColors.canvas)
        }
        .sheet(isPresented: $showReview) { ReviewSessionView(filterSubject: subject) }
        .alert("Could not save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "Please try again.") }
    }

    private func header(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "leaf").font(.title2).foregroundStyle(IBColors.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Biology").font(.title2.weight(.semibold))
                    Text("\(available.count) topics · First assessment 2025")
                        .font(.caption).foregroundStyle(IBColors.inkSecondary)
                }
                Spacer(minLength: 8)
                Picker("Course level", selection: Binding(get: { level }, set: { changeLevel($0) })) {
                    Text("SL").tag(IBCourseLevel.sl)
                    Text("HL").tag(IBCourseLevel.hl)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 100)
                Button { showReview = true } label: {
                    if compact { Image(systemName: "arrow.clockwise") }
                    else { Label("Scheduled review", systemImage: "arrow.clockwise") }
                }.controlSize(.large).accessibilityLabel("Open scheduled review")
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(IBColors.inkSecondary)
                TextField("Find a topic, code or concept", text: $search)
                    .textFieldStyle(.plain).accessibilityLabel("Search Biology syllabus")
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("Clear syllabus search")
                }
                if let url = URL(string: BiologyCatalog.sourceURL), !compact {
                    Link("IB reference", destination: url).font(.caption)
                }
            }.padding(10).background(IBColors.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(IBColors.border, lineWidth: 1))
            Text("Original revision pack · Partial coverage · Not a teacher-certified course")
                .font(.caption).foregroundStyle(IBColors.inkSecondary)
        }.padding(.horizontal, 20).padding(.vertical, 16)
    }

    private var outline: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 7) {
                Picker("Topic status", selection: $topicFilter) {
                    ForEach(TopicFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                Text("\(visible.count) topics shown").font(.caption).foregroundStyle(IBColors.inkSecondary)
                if visible.isEmpty {
                    ContentUnavailableView("No matching topics", systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text("Try another search or choose All to see every topic at this level."))
                }
                ForEach(BiologyCatalog.themes, id: \.self) { theme in
                    let topics = visible.filter { $0.theme == theme }
                    if !topics.isEmpty {
                        Text("\(theme) · \(BiologyCatalog.themeName(theme))")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(topics) { topic in
                            Button { selectedCode = topic.code; showOutline = false } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                                        Text(topic.code).font(.caption.monospaced().weight(.semibold))
                                            .foregroundStyle(IBColors.accent)
                                        Text(topic.title).font(.callout.weight(selectedCode == topic.code ? .semibold : .regular))
                                    }
                                        .multilineTextAlignment(.leading)
                                    let count = mistakeCount(topic)
                                    Text(count > 0 ? "\(count) saved mistakes" : topic.hlOnly ? "HL only · Partial coverage" : "Core topic · Partial coverage")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                .padding(8).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .background(selectedCode == topic.code ? IBColors.highlight : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 7))
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain).id(topic.code)
                                .accessibilityAddTraits(selectedCode == topic.code ? .isSelected : [])
                        }
                    }
                }
            }.padding(12)
        }
        .onAppear { proxy.scrollTo(selectedCode, anchor: .center) }
        .onChange(of: selectedCode) { _, code in proxy.scrollTo(code, anchor: .center) }
        }
    }

    @ViewBuilder private var detail: some View {
        if let topic = selected {
            VStack(alignment: .leading, spacing: 0) {
                topicHeader(topic)
                HStack {
                    Button { moveTopic(topic, by: -1) } label: { Label("Previous", systemImage: "chevron.left") }
                        .disabled(!visible.contains(where: { $0.code == topic.code }) || visible.first?.code == topic.code)
                    Spacer()
                    Text(BiologyCatalog.themeName(topic.theme)).font(.caption).foregroundStyle(IBColors.inkSecondary)
                        .lineLimit(1)
                    Spacer()
                    Button { moveTopic(topic, by: 1) } label: { Label("Next", systemImage: "chevron.right") }
                        .disabled(!visible.contains(where: { $0.code == topic.code }) || visible.last?.code == topic.code)
                }.buttonStyle(.borderless).padding(.horizontal, 20).padding(.bottom, 12)
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

    private func levelDescription(_ topic: BiologyTopic) -> String {
        if topic.hlOnly { return "HL only" }
        if level == .sl { return "SL core" }
        return topic.sections.contains { $0.hlOnly == true } ? "Core + HL extensions" : "SL + HL core"
    }

    private func topicHeader(_ topic: BiologyTopic) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(topic.code) / \(levelDescription(topic))")
                .font(.caption.monospaced().weight(.medium)).foregroundStyle(IBColors.accent)
            Text(topic.title).font(.title2.weight(.semibold)).textSelection(.enabled)
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
            }.pickerStyle(.segmented).labelsHidden()
            ViewThatFits(in: .horizontal) {
                HStack {
                Button(mode == .flashcards ? "Add flashcards to review" : "Add questions to review") {
                    add(topic, flashcards: mode == .flashcards)
                }
                Text("Keeps your existing review history").font(.caption2).foregroundStyle(.secondary)
                }
                Button(mode == .flashcards ? "Add flashcards to review" : "Add questions to review") {
                    add(topic, flashcards: mode == .flashcards)
                }
            }
        }.padding(20)
    }

    private func lesson(_ topic: BiologyTopic) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !topic.prerequisites.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Builds on").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(topic.prerequisites, id: \.self) { code in
                            if let prerequisite = available.first(where: { $0.code == code }) {
                                Button(prerequisite.name) { search = ""; topicFilter = .all; selectedCode = code }
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
                        HStack(alignment: .top, spacing: 12) {
                            RoundedRectangle(cornerRadius: 2).fill(IBColors.accent).frame(width: 3)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Common misconception").font(.caption.weight(.semibold)).foregroundStyle(IBColors.accent)
                                Text(section.pitfall).font(.callout).foregroundStyle(IBColors.inkSecondary).textSelection(.enabled)
                            }
                        }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 6)
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

    private func moveTopic(_ topic: BiologyTopic, by delta: Int) {
        guard let current = visible.firstIndex(where: { $0.code == topic.code }) else { return }
        let next = current + delta
        if visible.indices.contains(next) { selectedCode = visible[next].code }
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
    @State private var writtenAnswer = ""
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
                BiologyAnswerOption(number: offset + 1, text: option, selected: selectedOption == option,
                                    revealed: revealed, correct: option == question.answer) { selectedOption = option }
                    .keyboardShortcut(KeyEquivalent(Character(String(offset + 1))), modifiers: [])
            }
            if !revealed {
                Button("Check answer") {
                    guard let selectedOption else { return }
                    revealed = true
                    record(selectedOption == question.answer, question: question)
                }.disabled(selectedOption == nil).keyboardShortcut(.return, modifiers: [])
            }
        } else if !revealed {
            Text("Your response").font(.caption.weight(.semibold)).foregroundStyle(IBColors.inkSecondary)
            TextEditor(text: $writtenAnswer).font(.body).frame(minHeight: 100, idealHeight: 140)
                .padding(8).background(IBColors.surface)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(IBColors.border, lineWidth: 1))
                .accessibilityLabel("Write your practice answer")
            Text("Work out your response before revealing the marking points. Equivalent scientifically correct wording is accepted by self-assessment, not exact-text matching.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Reveal marking points") { revealed = true }.keyboardShortcut(.return, modifiers: .command)
        }
        if revealed {
            Divider()
            if !writtenAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DisclosureGroup("Compare with your response") { Text(writtenAnswer).textSelection(.enabled).padding(.top, 8) }
            }
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
            if !graded { Button("Skip without grading") { index += 1 } }
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
        writtenAnswer = ""
        revealed = false
        graded = false
        options = questions.indices.contains(index) ? questions[index].options.shuffled() : []
    }
}


/// Explicit symbols and text make feedback understandable without colour.
struct BiologyAnswerOption: View {
    let number: Int
    let text: String
    let selected: Bool
    let revealed: Bool
    let correct: Bool
    let action: () -> Void

    private var feedback: String {
        if revealed && correct { return "Correct answer" }
        if revealed && selected { return "Your answer · incorrect" }
        return selected ? "Selected" : ""
    }
    private var symbol: String {
        if revealed && correct { return "checkmark.circle.fill" }
        if revealed && selected { return "xmark.circle.fill" }
        return selected ? "largecircle.fill.circle" : "circle"
    }
    var body: some View {
        Group {
            if revealed {
                optionContent.accessibilityElement(children: .combine)
            } else {
                Button(action: action) { optionContent }.buttonStyle(.plain)
            }
        }
        .accessibilityLabel("Option \(number): \(text)")
        .accessibilityValue(feedback)
    }

    private var optionContent: some View {
            HStack(alignment: .top, spacing: 12) {
                Text(String(number)).font(.caption.monospaced()).foregroundStyle(IBColors.inkSecondary)
                    .frame(width: 18).padding(.top, 3)
                VStack(alignment: .leading, spacing: 6) {
                    Text(text).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    if !feedback.isEmpty { Text(feedback).font(.caption.weight(.semibold)) }
                }
                Image(systemName: symbol).foregroundStyle(IBColors.accent)
            }.padding(14).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(selected || (revealed && correct) ? IBColors.highlight : IBColors.surface,
                            in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .stroke(selected || (revealed && correct) ? IBColors.accent : IBColors.border, lineWidth: 1))
    }
}
