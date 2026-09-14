import SwiftUI
import SwiftData

struct CardLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StudyCard.createdDate, order: .reverse) private var cards: [StudyCard]
    @State private var search = ""
    @State private var subjectName = ""
    @State private var selectedTopics: Set<String> = []
    @State private var style: CardStyle?
    @State private var practiceCards: [StudyCard] = []
    @State private var showingPractice = false

    private var subjects: [String] { Set(cards.compactMap { $0.subject?.name }).sorted() }
    private var topics: [String] {
        Set(cards.filter { subjectName.isEmpty || $0.subject?.name == subjectName }.map(\.topicName)).sorted()
    }
    private var filtered: [StudyCard] {
        cards.filter {
            (subjectName.isEmpty || $0.subject?.name == subjectName)
                && (selectedTopics.isEmpty || selectedTopics.contains($0.topicName))
                && (style == nil || $0.cardStyle == style)
                && (search.isEmpty || $0.front.localizedCaseInsensitiveContains(search) || $0.topicName.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TextField("Search your cards", text: $search).textFieldStyle(.roundedBorder)
                Picker("Subject", selection: $subjectName) {
                    Text("All subjects").tag("")
                    ForEach(subjects, id: \.self) { Text($0).tag($0) }
                }.frame(maxWidth: 220)
                Menu(selectedTopics.isEmpty ? "All topics" : "\(selectedTopics.count) topics") {
                    Button("All topics") { selectedTopics.removeAll() }
                    ForEach(topics, id: \.self) { topic in
                        Toggle(topic, isOn: Binding(
                            get: { selectedTopics.contains(topic) },
                            set: { if $0 { selectedTopics.insert(topic) } else { selectedTopics.remove(topic) } }
                        ))
                    }
                }
                Picker("Format", selection: $style) {
                    Text("All formats").tag(Optional<CardStyle>.none)
                    ForEach(CardStyle.allCases) { Text($0.label).tag(Optional($0)) }
                }.frame(maxWidth: 180)
            }.padding(24)
            Divider()
            if filtered.isEmpty {
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
                                Text(CardRecallPresentation.prompt(front: card.front, style: card.cardStyle, revealed: false))
                                    .font(.custom("Georgia", size: 18)).lineLimit(3)
                                DisclosureGroup("Answer") {
                                    FormattedMessageContent(text: card.back).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                                }
                                .font(IBTypography.caption)
                            }
                            .padding(20).surfaceCard()
                        }
                    }.padding(24)
                }
            }
            HStack {
                Text("\(filtered.count) cards").font(IBTypography.body).foregroundStyle(IBColors.inkSecondary)
                Spacer()
                Button("Practise this set") {
                    practiceCards = filtered
                    showingPractice = true
                }
                .buttonStyle(PrimaryButtonStyle()).disabled(filtered.isEmpty)
            }
            .padding(20).background(IBColors.surface)
        }
        .background(IBColors.canvas)
        .navigationTitle("Your cards")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        .frame(minWidth: 760, minHeight: 620)
        .onChange(of: subjectName) { _, _ in selectedTopics.removeAll() }
        .sheet(isPresented: $showingPractice) { CardPracticeView(cards: practiceCards) }
    }
}

struct CardPracticeView: View {
    let cards: [StudyCard]
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var revealed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if index < cards.count {
                    HStack {
                        Text("FREE PRACTICE").font(IBTypography.captionBold).tracking(1)
                        Spacer()
                        Text("\(index + 1) / \(cards.count)").monospacedDigit()
                    }
                    ProgressView(value: Double(index) / Double(max(cards.count, 1)))
                    ScrollView { RecallCardView(card: cards[index], revealed: $revealed).id(cards[index].id) }
                    Button(revealed ? "Next card" : "Reveal answer") {
                        if revealed { index += 1; revealed = false } else { revealed = true }
                    }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.space, modifiers: [])
                } else {
                    ContentUnavailableView("Set complete", systemImage: "checkmark.circle",
                                           description: Text("You practised \(cards.count) cards."))
                    Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(28).background(IBColors.canvas)
            .navigationTitle("Practise")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .frame(minWidth: 640, minHeight: 620)
    }
}
