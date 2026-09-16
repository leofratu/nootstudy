import SwiftUI
import SwiftData

struct CardLibraryView: View {
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StudyCard.createdDate, order: .reverse) private var cards: [StudyCard]
    @Query(filter: #Predicate<ChatMessage> { $0.role == "study_test" }) private var testMessages: [ChatMessage]
    @State private var showingTests = false
    @State private var search = ""
    @State private var subjectName = ""
    @State private var selectedTopics: Set<String> = []
    @State private var style: CardStyle?
    @State private var unitName = ""
    @State private var practiceCards: [StudyCard] = []
    @State private var showingPractice = false
    @State private var showRepeatedCards = false
    @State private var selectedTest: SavedStudyTest?

    init(embedded: Bool = false, initialSubject: String = "", initialTopics: Set<String> = []) {
        self.embedded = embedded
        _subjectName = State(initialValue: initialSubject)
        _selectedTopics = State(initialValue: initialTopics)
    }

    private var tests: [SavedStudyTest] { StudyTestStore.read(testMessages) }

    private var uniqueCards: [StudyCard] {
        CardDuplicatePolicy.library(cards).cards.sorted { $0.createdDate > $1.createdDate }
    }

    private var subjects: [String] { Set(cards.compactMap { $0.subject?.name } + tests.map(\.subject)).sorted() }
    private var units: [String] {
        let cardUnits = cards.filter { subjectName.isEmpty || $0.subject?.name == subjectName }.map { StudyLibraryService.unit(for: $0) }
        let testUnits = tests.filter { subjectName.isEmpty || $0.subject == subjectName }.flatMap { test in
            test.topics.compactMap { SyllabusSeeder.unitName(for: test.subject, level: test.level, topicName: $0) }
        }
        return Set(cardUnits + testUnits).filter { !$0.isEmpty }.sorted()
    }
    private var topics: [String] {
        let cardTopics = cards.filter { (subjectName.isEmpty || $0.subject?.name == subjectName) && (unitName.isEmpty || StudyLibraryService.unit(for: $0) == unitName) }.map(\.topicName)
        let testTopics = tests.filter { subjectName.isEmpty || $0.subject == subjectName }.flatMap { test in
            test.topics.filter { unitName.isEmpty || SyllabusSeeder.unitName(for: test.subject, level: test.level, topicName: $0) == unitName }
        }
        return Set(cardTopics + testTopics).sorted()
    }
    private var filtered: [StudyCard] {
        (showRepeatedCards ? cards : uniqueCards).filter {
            (subjectName.isEmpty || $0.subject?.name == subjectName)
                && (selectedTopics.isEmpty || selectedTopics.contains($0.topicName))
                && (unitName.isEmpty || StudyLibraryService.unit(for: $0) == unitName)
                && (style == nil || $0.cardStyle == style)
                && StudyLibraryService.matches(search, card: $0)
        }
    }
    private var filteredTests: [SavedStudyTest] {
        tests.filter { test in
            let testUnits = test.topics.compactMap { SyllabusSeeder.unitName(for: test.subject, level: test.level, topicName: $0) }
            return (subjectName.isEmpty || test.subject == subjectName)
                && (unitName.isEmpty || testUnits.contains(unitName))
                && (selectedTopics.isEmpty || !selectedTopics.isDisjoint(with: test.topics))
                && StudyLibraryService.matches(search, fields: [test.subject, test.question, test.answer, test.feedback] + testUnits + test.topics + test.subtopics)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Library").font(IBTypography.largeTitle)
                    Text("Find it. Practise it again.").font(IBTypography.body).foregroundStyle(IBColors.inkSecondary)
                }
                Spacer()
                Picker("Content", selection: $showingTests) {
                    Text("Cards · \(uniqueCards.count)").tag(false)
                    Text("Tests · \(tests.count)").tag(true)
                }.pickerStyle(.segmented).frame(width: 260)
            }.padding(.horizontal, 24).padding(.top, 24)
            TextField("Search questions, answers, units or subtopics", text: $search)
                .textFieldStyle(.roundedBorder).accessibilityLabel("Search library")
                .padding(.horizontal, 24).padding(.top, 18)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                Picker("Subject", selection: $subjectName) {
                    Text("All subjects").tag("")
                    ForEach(subjects, id: \.self) { Text($0).tag($0) }
                }.frame(maxWidth: .infinity)
                Picker("Unit", selection: $unitName) {
                    Text("All units").tag("")
                    ForEach(units, id: \.self) { Text($0).tag($0) }
                }.frame(maxWidth: .infinity)
                Menu(selectedTopics.isEmpty ? "All topics" : "\(selectedTopics.count) topics") {
                    Button("All topics") { selectedTopics.removeAll() }
                    ForEach(topics, id: \.self) { topic in
                        Toggle(topic, isOn: Binding(
                            get: { selectedTopics.contains(topic) },
                            set: { if $0 { selectedTopics.insert(topic) } else { selectedTopics.remove(topic) } }
                        ))
                    }
                }
                if !showingTests { Picker("Format", selection: $style) {
                    Text("All formats").tag(Optional<CardStyle>.none)
                    ForEach(CardStyle.allCases) { Text($0.label).tag(Optional($0)) }
                }.frame(maxWidth: .infinity) }
            }.padding(24)
            Divider()
            if showingTests {
                testResults
            } else if filtered.isEmpty {
                ContentUnavailableView("No cards here yet", systemImage: "rectangle.stack",
                                       description: Text(cards.isEmpty ? "Create your first set in Card studio." : "Try another topic, format or search."))
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(filtered) { card in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    SubjectBadge(name: card.subject?.name ?? "Subject", level: card.subject?.level ?? "")
                                    Text(card.topicName).font(IBTypography.caption).foregroundStyle(IBColors.inkSecondary)
                                    Spacer()
                                    Label(card.cardStyle.label, systemImage: card.cardStyle.symbol).font(IBTypography.caption)
                                }
                                Text([StudyLibraryService.unit(for: card), card.subtopic].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(IBTypography.caption).foregroundStyle(IBColors.inkSecondary)
                                Text(CardRecallPresentation.prompt(front: card.front, style: card.cardStyle, revealed: false))
                                    .font(.custom("Georgia", size: 18)).lineLimit(3)
                                DisclosureGroup("Answer") {
                                    FormattedMessageContent(text: card.back).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                                }
                                .font(IBTypography.caption)
                                Button(card.cardStyle == .multipleChoice ? "Answer question" : "Revise card") {
                                    practiceCards = [card]; showingPractice = true
                                }.buttonStyle(SecondaryButtonStyle())
                            }
                            .padding(20).surfaceCard()
                        }
                    }.padding(24)
                }
            }
            if !showingTests { HStack {
                Text("\(filtered.count) cards").font(IBTypography.body).foregroundStyle(IBColors.inkSecondary)
                if uniqueCards.count < cards.count {
                    Toggle("Show repeated cards (\(cards.count - uniqueCards.count))", isOn: $showRepeatedCards)
                        .toggleStyle(.checkbox).font(IBTypography.caption)
                }
                Spacer()
                Button(style == .multipleChoice ? "Start quiz" : "Practise this set") {
                    practiceCards = CardDuplicatePolicy.library(filtered).cards
                    showingPractice = true
                }
                .buttonStyle(PrimaryButtonStyle()).disabled(filtered.isEmpty)
            }
            .padding(20).background(IBColors.surface) }
        }
        .background(IBColors.canvas)
        .navigationTitle("Library")
        .toolbar { ToolbarItem(placement: .cancellationAction) { if !embedded { Button("Close") { dismiss() } } } }
        .frame(minWidth: embedded ? 0 : 760, minHeight: 620)
        .onChange(of: subjectName) { _, _ in selectedTopics.removeAll(); unitName = "" }
        .onChange(of: unitName) { _, _ in selectedTopics.removeAll() }
        .sheet(isPresented: $showingPractice) { CardPracticeView(cards: practiceCards) }
        .sheet(item: $selectedTest) { SavedTestPracticeView(test: $0) }
    }

    private var testResults: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if filteredTests.isEmpty {
                    ContentUnavailableView("No tests found", systemImage: "doc.text.magnifyingglass",
                        description: Text(tests.isEmpty ? "Save a practice exam or an exam-marker question to find it here." : "Try another unit, topic or search."))
                        .frame(maxWidth: .infinity).padding(.vertical, 60)
                }
                ForEach(filteredTests) { test in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            SubjectBadge(name: test.subject, level: test.level)
                            Text(test.title).font(IBTypography.headline)
                            Spacer()
                            Text("\(test.maximumMarks) marks").font(IBTypography.mono)
                        }
                        Text(test.question).font(IBTypography.body).lineLimit(3)
                        HStack {
                            Text(test.updatedAt, style: .date).font(IBTypography.caption).foregroundStyle(IBColors.inkSecondary)
                            Spacer()
                            Button("Open test") { selectedTest = test }.buttonStyle(PrimaryButtonStyle())
                        }
                    }.padding(24).surfaceCard()
                }
            }.padding(24)
        }
    }
}

struct CardPracticeView: View {
    let cards: [StudyCard]
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var revealed = false
    @State private var answers: [UUID: Bool] = [:]

    private var isQuiz: Bool { !cards.isEmpty && cards.allSatisfy { $0.cardStyle == .multipleChoice } }
    private var canChoose: Bool {
        index < cards.count && CardGeneratorService.validatedChoices(back: cards[index].back, choices: cards[index].choices) != nil
            && cards[index].cardStyle == .multipleChoice
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if index < cards.count {
                    HStack {
                        Text(isQuiz ? "MULTIPLE-CHOICE QUIZ" : "FREE PRACTICE").font(IBTypography.captionBold).tracking(1)
                        Spacer()
                        Text("\(index + 1) / \(cards.count)").monospacedDigit()
                    }
                    ProgressView(value: Double(index) / Double(max(cards.count, 1)))
                    ScrollView {
                        RecallCardView(card: cards[index], revealed: $revealed) { correct in
                            answers[cards[index].id] = correct
                        }.id(cards[index].id)
                    }
                    if revealed || !canChoose {
                        Button(revealed ? (index + 1 == cards.count ? "Finish" : "Next card") : "Reveal answer") {
                            if revealed { index += 1; revealed = false } else { revealed = true }
                        }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.space, modifiers: [])
                    } else {
                        Text("Choose an option, then check your answer.")
                            .font(IBTypography.caption).foregroundStyle(IBColors.inkSecondary)
                    }
                } else {
                    ContentUnavailableView(isQuiz ? "Quiz complete" : "Set complete", systemImage: "checkmark.circle",
                                           description: Text(answers.isEmpty ? "You practised \(cards.count) cards." : "\(answers.values.filter { $0 }.count) of \(answers.count) multiple-choice answers correct."))
                    Button("Practise again") { index = 0; revealed = false; answers = [:] }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(28).background(IBColors.canvas)
            .navigationTitle(isQuiz ? "Quiz" : "Practise")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .frame(minWidth: 640, minHeight: 620)
    }
}
