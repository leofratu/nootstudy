from pathlib import Path
p = Path('IBVault/Views/Subjects/BiologyStudyView.swift')
s = p.read_text()
s = s.replace('@State private var showReview = false', '@State private var showReview = false\n    @State private var showOutline = false\n    @State private var topicFilter = TopicFilter.all\n\n    enum TopicFilter: String, CaseIterable { case all = "All", revisit = "Revisit", unreviewed = "Unreviewed" }')
s = s.replace('init(subject: Subject, initialCode: String = "") {', 'init(subject: Subject, initialCode: String = "", initialMode: StudyMode = .learn) {')
s = s.replace('_selectedCode = State(initialValue: initialCode)', '''_selectedCode = State(initialValue: initialCode)
        _mode = State(initialValue: initialMode)
        let subjectID = subject.id
        _cards = Query(filter: #Predicate<StudyCard> { $0.subject?.id == subjectID })''')
s = s.replace('private var visible: [BiologyTopic] { available.filter { $0.contains(search, at: level) } }', '''private var visible: [BiologyTopic] {
        // Snapshot once per filter evaluation, not once for every syllabus row.
        let reviewed = Set(activeCards.filter { $0.totalReviewCount > 0 }.map(\\.topicName))
        let recorded = Set(nodes.filter {
            $0.subjectName == subject.name && $0.level == subject.level && $0.recordedProficiency != nil
        }.map(\\.topicName))
        return available.filter { topic in
            guard topic.contains(search, at: level) else { return false }
            switch topicFilter {
            case .all: return true
            case .revisit: return mistakeCount(topic) > 0
            case .unreviewed: return !reviewed.contains(topic.name) && !recorded.contains(topic.name)
            }
        }
    }''')
s = s.replace('private var selected: BiologyTopic? { visible.first', 'private var selected: BiologyTopic? { available.first')
start = s.index('    var body: some View {')
end = s.index('        .background(IBColors.canvas)', start)
s = s[:start] + '''    var body: some View {
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
''' + s[end:]
s = s.replace('.onChange(of: search) { _, _ in reconcileSelection() }', '.onChange(of: search) { _, _ in reconcileSelection() }\n        .onChange(of: topicFilter) { _, _ in reconcileSelection() }')
s = s.replace('        .sheet(isPresented: $showReview)', '''        .sheet(isPresented: $showOutline) {
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
        .sheet(isPresented: $showReview)''')
start = s.index('    private var header: some View {')
end = s.index('    private var outline:', start)
s = s[:start] + '''    private func header(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "leaf").font(.title2).foregroundStyle(IBColors.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Biology").font(.title2.weight(.semibold))
                    Text("\\(available.count) topics · First assessment 2025")
                        .font(.caption).foregroundStyle(IBColors.inkSecondary)
                }
                Spacer(minLength: 8)
                Picker("Course level", selection: Binding(get: { level }, set: { changeLevel($0) })) {
                    Text("SL").tag(IBCourseLevel.sl)
                    Text("HL").tag(IBCourseLevel.hl)
                }.pickerStyle(.segmented).frame(width: 100)
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

''' + s[end:]
s = s.replace('LazyVStack(alignment: .leading, spacing: 14) {\n                if visible.isEmpty {', '''LazyVStack(alignment: .leading, spacing: 14) {
                Picker("Topic status", selection: $topicFilter) {
                    ForEach(TopicFilter.allCases, id: \\.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                Text("\\(visible.count) topics shown").font(.caption).foregroundStyle(IBColors.inkSecondary)
                if visible.isEmpty {''')
s = s.replace('ContentUnavailableView.search(text: search)', '''ContentUnavailableView("No matching topics", systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text("Try another search or choose All to see every topic at this level."))''')
s = s.replace('Button { selectedCode = topic.code } label: {', 'Button { selectedCode = topic.code; showOutline = false } label: {')
s = s.replace('Text(topic.name).font(.callout.weight(selectedCode == topic.code ? .semibold : .regular))', '''HStack(alignment: .firstTextBaseline, spacing: 7) {
                                        Text(topic.code).font(.caption.monospaced().weight(.semibold))
                                            .foregroundStyle(IBColors.accent)
                                        Text(topic.title).font(.callout.weight(selectedCode == topic.code ? .semibold : .regular))
                                    }''')
s = s.replace('.frame(maxWidth: .infinity, alignment: .leading).padding(9)', '.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(10)')
s = s.replace('count > 0 ? "\\(count) to revisit" : topic.hlOnly ? "HL only · Overview" : "SL + HL · Overview"', 'count > 0 ? "\\(count) saved mistakes" : topic.hlOnly ? "HL only · Partial coverage" : "Core topic · Partial coverage"')
s = s.replace('                topicHeader(topic)', '''                topicHeader(topic)
                HStack {
                    Button { moveTopic(topic, by: -1) } label: { Label("Previous", systemImage: "chevron.left") }
                        .disabled(!visible.contains(where: { $0.code == topic.code }) || visible.first?.code == topic.code)
                    Spacer()
                    Text(BiologyCatalog.themeName(topic.theme)).font(.caption).foregroundStyle(IBColors.inkSecondary)
                        .lineLimit(1)
                    Spacer()
                    Button { moveTopic(topic, by: 1) } label: { Label("Next", systemImage: "chevron.right") }
                        .disabled(!visible.contains(where: { $0.code == topic.code }) || visible.last?.code == topic.code)
                }.buttonStyle(.borderless).padding(.horizontal, 20).padding(.bottom, 12)''')
s = s.replace('            Text(topic.name).font(.title2.bold()).textSelection(.enabled)', '''            Text("\\(topic.code) / \\(topic.hlOnly ? "Higher level" : "Core + available HL extensions")")
                .font(.caption.monospaced().weight(.medium)).foregroundStyle(IBColors.accent)
            Text(topic.title).font(.title2.weight(.semibold)).textSelection(.enabled)''')
s = s.replace('            HStack {\n                Button(mode == .flashcards', '            ViewThatFits(in: .horizontal) {\n                HStack {\n                Button(mode == .flashcards')
s = s.replace('Text("Uses the existing spaced-review queue").font(.caption2).foregroundStyle(.secondary)\n            }', '''Text("Keeps your existing review history").font(.caption2).foregroundStyle(.secondary)
                }
                Button(mode == .flashcards ? "Add flashcards to review" : "Add questions to review") {
                    add(topic, flashcards: mode == .flashcards)
                }
            }''')
s = s.replace('        }.padding(16)\n    }\n\n    private func lesson', '        }.padding(20)\n    }\n\n    private func lesson')
s = s.replace('Button(prerequisite.name) { search = ""; selectedCode = code }', 'Button(prerequisite.name) { search = ""; topicFilter = .all; selectedCode = code }')
s = s.replace('''                        Label { Text(section.pitfall).textSelection(.enabled) } icon: { Image(systemName: "lightbulb") }
                            .font(.callout).foregroundStyle(.secondary)''', '''                        HStack(alignment: .top, spacing: 12) {
                            RoundedRectangle(cornerRadius: 2).fill(IBColors.accent).frame(width: 3)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Common misconception").font(.caption.weight(.semibold)).foregroundStyle(IBColors.accent)
                                Text(section.pitfall).font(.callout).foregroundStyle(IBColors.inkSecondary).textSelection(.enabled)
                            }
                        }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 6)''')
s = s.replace('    private func mistakeCount(_ topic: BiologyTopic) -> Int {', '''    private func moveTopic(_ topic: BiologyTopic, by delta: Int) {
        guard let current = visible.firstIndex(where: { $0.code == topic.code }) else { return }
        let next = current + delta
        if visible.indices.contains(next) { selectedCode = visible[next].code }
    }

    private func mistakeCount(_ topic: BiologyTopic) -> Int {''')
s = s.replace('    @State private var graded = false', '    @State private var graded = false\n    @State private var writtenAnswer = ""')
s = s.replace('''                Button { selectedOption = option } label: {
                    HStack(alignment: .top) {
                        Image(systemName: selectedOption == option ? "largecircle.fill.circle" : "circle")
                        Text(option).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                        if revealed && option == question.answer { Image(systemName: "checkmark.circle.fill") }
                    }.padding(12).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(selectedOption == option ? IBColors.highlight : IBColors.surface,
                                    in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).disabled(revealed)
                    .accessibilityLabel("Option \\(offset + 1): \\(option)")
                    .accessibilityValue(revealed && option == question.answer ? "Correct answer" : selectedOption == option ? "Selected" : "")''', '''                BiologyAnswerOption(number: offset + 1, text: option, selected: selectedOption == option,
                                    revealed: revealed, correct: option == question.answer) { selectedOption = option }
                    .keyboardShortcut(KeyEquivalent(Character(String(offset + 1))), modifiers: [])''')
s = s.replace('''        } else if !revealed {
            Text("Work out your response''', '''        } else if !revealed {
            Text("Your response").font(.caption.weight(.semibold)).foregroundStyle(IBColors.inkSecondary)
            TextEditor(text: $writtenAnswer).font(.body).frame(minHeight: 100, idealHeight: 140)
                .padding(8).background(IBColors.surface)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(IBColors.border, lineWidth: 1))
                .accessibilityLabel("Write your practice answer")
            Text("Work out your response''')
s = s.replace('''            Divider()
            if let correct = answers[question.key]''', '''            Divider()
            if !writtenAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DisclosureGroup("Compare with your response") { Text(writtenAnswer).textSelection(.enabled).padding(.top, 8) }
            }
            if let correct = answers[question.key]''')
s = s.replace('            Button("Skip without grading") { index += 1 }', '            if !graded { Button("Skip without grading") { index += 1 } }')
s = s.replace('        selectedOption = nil\n        revealed = false', '        selectedOption = nil\n        writtenAnswer = ""\n        revealed = false')
s = s.replace('Button("Reveal marking points") { revealed = true }.keyboardShortcut(.return, modifiers: [])', 'Button("Reveal marking points") { revealed = true }.keyboardShortcut(.return, modifiers: .command)')
s += '''

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
        Button(action: action) {
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
        }.buttonStyle(.plain).disabled(revealed)
            .accessibilityLabel("Option \\(number): \\(text)")
            .accessibilityValue(feedback)
    }
}
'''
import hashlib
assert hashlib.sha256(s.encode()).hexdigest() == 'b7c9612886e8ead7674067f878fdd89023f83c351609502769f33d545245e821', 'Design differs from the locally parsed and reviewed source'
p.write_text(s)
