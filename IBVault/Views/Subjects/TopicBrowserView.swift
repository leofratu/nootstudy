import SwiftUI
import SwiftData

struct TopicBrowserView: View {
    let subject: Subject
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var selectedUnit: CurriculumUnit?
    @State private var selectedTopic: CurriculumTopic?
    @State private var isGenerating = false
    @State private var generationCount = 10
    @State private var generationError: String?
    @State private var generatedCount: Int?

    private var curriculum: [CurriculumUnit] {
        SyllabusSeeder.curriculum(for: subject.name)
    }

    private let cardCounts = [5, 10, 15, 20]

    var body: some View {
        HSplitView {
            // Left: Unit list
            unitList
                .frame(minWidth: 200, idealWidth: 220)

            // Middle: Topic list
            topicList
                .frame(minWidth: 220, idealWidth: 260)

            // Right: Subtopics + generation
            subtopicDetail
                .frame(minWidth: 300, idealWidth: 400)
        }
        .frame(minWidth: 720, minHeight: 500)
        .navigationTitle("\(subject.name) Curriculum")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
    }

    // MARK: - Unit List
    private var unitList: some View {
        List(selection: Binding(
            get: { selectedUnit?.name },
            set: { name in selectedUnit = curriculum.first { $0.name == name }; selectedTopic = nil }
        )) {
            Section("Units") {
                ForEach(curriculum, id: \.name) { unit in
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Color(hex: subject.accentColorHex))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(unit.name)
                                .font(.callout.weight(.medium))
                            Text("\(unit.topics.count) topics")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(unit.name)
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Topic List
    private var topicList: some View {
        List(selection: Binding(
            get: { selectedTopic?.name },
            set: { name in selectedTopic = selectedUnit?.topics.first { $0.name == name } }
        )) {
            if let unit = selectedUnit {
                Section(unit.name) {
                    ForEach(unit.topics, id: \.name) { topic in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(topic.name)
                                    .font(.callout.weight(.medium))
                                HStack(spacing: 8) {
                                    Text("\(topic.subtopics.count) subtopics")
                                    Text("•")
                                    Text("\(cardCount(for: topic.name)) cards")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                let mastery = ProficiencyTracker.masteryPercentage(for: subject, topicName: topic.name)
                                if cardCount(for: topic.name) > 0 {
                                    HStack(spacing: 6) {
                                        MasteryBar(progress: mastery, height: 4, color: Color(hex: subject.accentColorHex))
                                        Text("\(Int(mastery * 100))%")
                                            .font(.system(size: 9, weight: .bold, design: .rounded))
                                            .foregroundStyle(Color(hex: subject.accentColorHex))
                                    }
                                }
                            }
                            Spacer()
                            if cardCount(for: topic.name) > 0 {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            }
                        }
                        .tag(topic.name)
                    }
                }
            } else {
                Text("Select a unit")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Subtopic Detail
    private var subtopicDetail: some View {
        ScrollView {
            if let topic = selectedTopic {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hex: subject.accentColorHex))
                                .frame(width: 4, height: 24)
                            Text(topic.name)
                                .font(.title2.bold())
                        }
                        HStack(spacing: 12) {
                            Label("\(topic.subtopics.count) subtopics", systemImage: "list.bullet")
                            Label("\(cardCount(for: topic.name)) cards generated", systemImage: "square.stack.fill")
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    // Subtopics
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Subtopics")
                            .font(.headline)
                        ForEach(topic.subtopics, id: \.self) { sub in
                            HStack(spacing: 10) {
                                Image(systemName: subtopicHasCards(topic: topic.name, subtopic: sub) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(subtopicHasCards(topic: topic.name, subtopic: sub) ? .green : .secondary)
                                    .font(.system(size: 14))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(sub)
                                        .font(.callout)

                                    let count = subtopicCardCount(topic: topic.name, subtopic: sub)
                                    HStack(spacing: 8) {
                                        Text("\(count) cards")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        if count > 0 {
                                            let mastery = ProficiencyTracker.masteryPercentage(for: subject, topicName: topic.name, subtopic: sub)
                                            HStack(spacing: 4) {
                                                MasteryBar(progress: mastery, height: 4, color: Color(hex: subject.accentColorHex))
                                                    .frame(width: 40)
                                                Text("\(Int(mastery * 100))%")
                                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                                    .foregroundStyle(Color(hex: subject.accentColorHex))
                                            }
                                        }
                                    }
                                }
                                Spacer()
                                Button {
                                    generateCards(topic: topic.name, subtopic: sub)
                                } label: {
                                    Label("Generate", systemImage: "sparkles")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(isGenerating)
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                    .padding(16)
                    .glassCard()
                    .padding(.horizontal, 20)

                    // Generate all
                    generateAllSection(topic: topic)
                        .padding(.horizontal, 20)

                    // Status
                    if isGenerating {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("ARIA is generating flashcards…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 20)
                    }

                    if let err = generationError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal, 20)
                    }

                    if let count = generatedCount {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("\(count) cards generated successfully!")
                                .font(.callout)
                                .foregroundStyle(.green)
                        }
                        .padding(.horizontal, 20)
                    }

                    Spacer().frame(height: 20)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("Select a topic")
                        .foregroundStyle(.secondary)
                    Text("Browse the curriculum and generate flashcards with ARIA")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.background)
    }

    // MARK: - Generate All Section
    private func generateAllSection(topic: CurriculumTopic) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color(hex: subject.accentColorHex))
                Text("Generate Cards for Entire Topic")
                    .font(.headline)
            }

            HStack(spacing: 12) {
                Picker("Cards per subtopic:", selection: $generationCount) {
                    ForEach(cardCounts, id: \.self) { n in
                        Text("\(n) cards").tag(n)
                    }
                }
                .frame(width: 200)

                Button {
                    generateCards(topic: topic.name, subtopic: "")
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Generate \(generationCount) Cards")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: subject.accentColorHex))
                .disabled(isGenerating)
            }
        }
        .padding(16)
        .glassCard()
    }

    // MARK: - Card Counting
    private func cardCount(for topicName: String) -> Int {
        subject.cards.filter { $0.topicName == topicName }.count
    }

    private func subtopicCardCount(topic: String, subtopic: String) -> Int {
        subject.cards.filter { $0.topicName == topic && $0.subtopic == subtopic }.count
    }

    private func subtopicHasCards(topic: String, subtopic: String) -> Bool {
        subtopicCardCount(topic: topic, subtopic: subtopic) > 0
    }

    // MARK: - Generation
    private func generateCards(topic: String, subtopic: String) {
        isGenerating = true
        generationError = nil
        generatedCount = nil
        IBHaptics.light()

        Task {
            do {
                let cards = try await CardGeneratorService.generateCards(
                    subject: subject,
                    topicName: topic,
                    subtopic: subtopic,
                    count: generationCount,
                    context: context
                )

                await MainActor.run {
                    for card in cards {
                        context.insert(card)
                        subject.cards.append(card)
                    }
                    try? context.save()
                    generatedCount = cards.count
                    isGenerating = false
                    IBHaptics.success()
                }
            } catch {
                await MainActor.run {
                    generationError = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }
}
