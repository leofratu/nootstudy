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
    @State private var cardsPerSubtopic = 3
    @State private var generationError: String?
    @State private var generationSuccessMessage: String?
    @State private var generationProgress: String?
    @State private var searchText = ""

    private var curriculum: [CurriculumUnit] {
        let full = SyllabusSeeder.curriculum(for: subject.name, level: subject.level)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return full }
        return full.compactMap { unit in
            let topics = unit.topics.compactMap { topic -> CurriculumTopic? in
                if topic.name.localizedCaseInsensitiveContains(query) {
                    return topic
                }
                let subtopics = topic.subtopics.filter { $0.localizedCaseInsensitiveContains(query) }
                guard !subtopics.isEmpty else { return nil }
                return CurriculumTopic(name: topic.name, subtopics: subtopics, levels: topic.levels)
            }
            guard unit.name.localizedCaseInsensitiveContains(query) || !topics.isEmpty else { return nil }
            return CurriculumUnit(name: unit.name, topics: topics.isEmpty ? unit.topics : topics)
        }
    }

    private var metadata: CurriculumMetadata { SyllabusSeeder.metadata(for: subject.name) }

    private var topicCount: Int { curriculum.flatMap(\.topics).count }
    private var subtopicCount: Int { curriculum.flatMap(\.topics).flatMap(\.subtopics).count }

    private let coverageCardCounts = [2, 3, 5]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(subject.name)
                            .font(.title3.weight(.bold))
                        StudioPill(title: subject.level, tint: Color(hex: subject.accentColorHex))
                    }
                    Text("\(topicCount) topics · \(subtopicCount) subunits · \(metadata.catalogVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField("Search curriculum", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                Link(destination: metadata.sourceURL) {
                    Label("IB source", systemImage: "arrow.up.right.square")
                        .font(.caption.weight(.semibold))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(IBColors.surface)

            Divider()

            HSplitView {
                unitList
                    .frame(minWidth: 200, idealWidth: 220)

                topicList
                    .frame(minWidth: 220, idealWidth: 260)

                subtopicDetail
                    .frame(minWidth: 300, idealWidth: 400)
            }
        }
        .frame(minWidth: 720, minHeight: 500)
        .navigationTitle("Curriculum")
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
                            Text(generationProgress ?? "ARIA is generating flashcards…")
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

                    if let message = generationSuccessMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(message)
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
        .background(IBColors.canvas)
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
                Picker("Cards per subunit", selection: $cardsPerSubtopic) {
                    ForEach(coverageCardCounts, id: \.self) { n in
                        Text("\(n) each").tag(n)
                    }
                }
                .frame(width: 200)

                Button {
                    generateCoverage(for: topic)
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Build Full Coverage")
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
        generationSuccessMessage = nil
        generationProgress = subtopic.isEmpty ? "Generating cards for \(topic)…" : "Generating cards for \(subtopic)…"
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
                    }
                    do {
                        try context.save()
                        generationSuccessMessage = "Generated \(cards.count) adaptive cards for this subunit."
                        generationProgress = nil
                        isGenerating = false
                        IBHaptics.success()
                    } catch {
                        cards.forEach(context.delete)
                        generationError = "Cards were generated but could not be saved: \(error.localizedDescription)"
                        generationProgress = nil
                        isGenerating = false
                    }
                }
            } catch {
                await MainActor.run {
                    generationError = error.localizedDescription
                    generationProgress = nil
                    isGenerating = false
                }
            }
        }
    }

    private func generateCoverage(for topic: CurriculumTopic) {
        isGenerating = true
        generationError = nil
        generationSuccessMessage = nil
        generationProgress = "Preparing \(topic.subtopics.count) subunits…"
        IBHaptics.light()

        Task { @MainActor in
            let result = await CardGeneratorService.generateCoverage(
                subject: subject,
                topic: topic,
                cardsPerSubtopic: cardsPerSubtopic,
                context: context
            ) { current, total, subtopic in
                generationProgress = "Subunit \(current) of \(total): \(subtopic)"
            }

            for card in result.cards {
                context.insert(card)
            }

            do {
                try context.save()
                generationSuccessMessage = result.cards.isEmpty
                    ? "All \(result.coveredSubtopics) subunits already meet the selected coverage."
                    : "Generated \(result.cards.count) cards; \(result.coveredSubtopics) of \(topic.subtopics.count) subunits now meet the target."
                if result.failures.isEmpty {
                    generationError = nil
                } else {
                    let preview = result.failures.prefix(3).joined(separator: "\n")
                    let remaining = result.failures.count - min(result.failures.count, 3)
                    generationError = remaining > 0
                        ? "\(preview)\n…and \(remaining) more subunits need attention."
                        : preview
                }
                generationProgress = nil
                isGenerating = false
                if !result.cards.isEmpty || result.skippedSubtopics == topic.subtopics.count {
                    IBHaptics.success()
                }
            } catch {
                result.cards.forEach(context.delete)
                generationError = "Generated coverage could not be saved: \(error.localizedDescription)"
                generationProgress = nil
                isGenerating = false
            }
        }
    }
}
