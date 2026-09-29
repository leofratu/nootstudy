import SwiftUI
import SwiftData

struct CardLibraryView: View {
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StudyCard.createdDate, order: .reverse) private var cards: [StudyCard]
    @Query(filter: #Predicate<ChatMessage> { $0.role == "study_test" }) private var testMessages: [ChatMessage]
    @State private var showingTests = false
    @State private var search = ""
    @State private var searchQuery = ""
    @State private var uniqueCards: [StudyCard] = []
    @State private var tests: [SavedStudyTest] = []
    @State private var searchIndex: [UUID: String] = [:]
    @State private var unitIndex: [UUID: String] = [:]
    @State private var refreshTask: Task<Void, Never>?
    @State private var isLoading = true
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

    private var subjects: [String] { Set(cards.compactMap { $0.subject?.name } + tests.map(\.subject)).sorted() }
    private var units: [String] {
        let cardUnits = cards.filter { subjectName.isEmpty || $0.subject?.name == subjectName }.compactMap { unitIndex[$0.id] }
        let testUnits = tests.filter { subjectName.isEmpty || $0.subject == subjectName }.flatMap { test in
            test.topics.compactMap { SyllabusSeeder.unitName(for: test.subject, level: test.level, topicName: $0) }
        }
        return Set(cardUnits + testUnits).filter { !$0.isEmpty }.sorted()
    }
    private var topics: [String] {
        let cardTopics = cards.filter { (subjectName.isEmpty || $0.subject?.name == subjectName) && (unitName.isEmpty || unitIndex[$0.id] == unitName) }.map(\.topicName)
        let testTopics = tests.filter { subjectName.isEmpty || $0.subject == subjectName }.flatMap { test in
            test.topics.filter { unitName.isEmpty || SyllabusSeeder.unitName(for: test.subject, level: test.level, topicName: $0) == unitName }
        }
        return Set(cardTopics + testTopics).sorted()
    }
    private func filteredCards(from uniqueCards: [StudyCard]) -> [StudyCard] {
        let words = StudyLibraryService.terms(searchQuery)
        return (showRepeatedCards ? cards : uniqueCards).filter { card in
            (subjectName.isEmpty || card.subject?.name == subjectName)
                && (selectedTopics.isEmpty || selectedTopics.contains(card.topicName))
                && (unitName.isEmpty || unitIndex[card.id] == unitName)
                && (style == nil || card.cardStyle == style)
                && words.allSatisfy { searchIndex[card.id]?.contains($0) == true }
        }
    }
    private var filteredTests: [SavedStudyTest] {
        tests.filter { test in
            let testUnits = test.topics.compactMap { SyllabusSeeder.unitName(for: test.subject, level: test.level, topicName: $0) }
            return (subjectName.isEmpty || test.subject == subjectName)
                && (unitName.isEmpty || testUnits.contains(unitName))
                && (selectedTopics.isEmpty || !selectedTopics.isDisjoint(with: test.topics))
                && StudyLibraryService.matches(searchQuery, fields: [test.subject, test.question, test.answer, test.feedback] + testUnits + test.topics + test.subtopics)
        }
    }

    var body: some View {
        // Reuse one library/filter snapshot throughout this render. Repeated
        // computed-property reads used to deduplicate and scan the full store.
        let uniqueCards = self.uniqueCards
        let filtered = filteredCards(from: uniqueCards)
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
            if isLoading {
                ProgressView("Loading your library…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if showingTests {
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
        .task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            rebuildIndex()
        }
        .task(id: search) {
            do { try await Task.sleep(for: .milliseconds(150)) }
            catch { return }
            searchQuery = search
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            refreshTask?.cancel()
            refreshTask = Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(150)) }
                catch { return }
                rebuildIndex()
            }
        }
        .onDisappear { refreshTask?.cancel() }
    }

    private func rebuildIndex() {
        var units: [UUID: String] = [:]
        var index: [UUID: String] = [:]
        for card in cards {
            let unit = StudyLibraryService.unit(for: card)
            units[card.id] = unit
            index[card.id] = CardDuplicatePolicy.normalize(
                [card.front, card.back, card.subject?.name ?? "", unit, card.topicName,
                 card.subtopic, card.syllabusReference ?? ""].joined(separator: " ")
            )
        }
        unitIndex = units
        searchIndex = index
        uniqueCards = CardDuplicatePolicy.library(cards).cards.sorted { $0.createdDate > $1.createdDate }
        tests = StudyTestStore.read(testMessages)
        isLoading = false
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
    @Environment(ReviewQueueManager.self) private var sharedQueue: ReviewQueueManager?
    @Environment(ProgressionEventCenter.self) private var sharedEvents: ProgressionEventCenter?
    @State private var localQueue = ReviewQueueManager()
    @State private var localEvents = ProgressionEventCenter()
    @State private var usesFreePractice = false

    var body: some View {
        Group {
            if usesFreePractice || cards.contains(where: { $0.modelContext == nil }) {
                FreeCardPracticeView(cards: cards)
            } else {
                ReviewSessionView(practiceCards: cards)
                    .safeAreaInset(edge: .bottom) {
                        HStack {
                            Text("Rate each answer to update mastery.")
                                .font(IBTypography.caption).foregroundStyle(IBColors.inkSecondary)
                            Spacer()
                            Button("Switch to free practice") { usesFreePractice = true }
                                .buttonStyle(.borderless)
                        }
                        .padding(16).background(IBColors.surface)
                    }
            }
        }
        .environment(sharedQueue ?? localQueue)
        .environment(sharedEvents ?? localEvents)
    }
}

private struct FreeCardPracticeView: View {
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
                    Text("Free practice does not change mastery or review dates. Save draft cards first to record a rated review.")
                        .font(IBTypography.caption).foregroundStyle(IBColors.inkSecondary)
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
