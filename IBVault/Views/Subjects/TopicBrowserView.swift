import SwiftUI
import SwiftData

struct TopicBrowserView: View {
    let subject: Subject
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CurriculumNode.topicName) private var curriculumNodes: [CurriculumNode]
    @Query(sort: \StudySession.endDate, order: .reverse) private var studySessions: [StudySession]
    @State private var selectedUnit: CurriculumUnit?
    @State private var selectedTopic: CurriculumTopic?
    @State private var isGenerating = false
    @State private var generationCount = 10
    @State private var cardsPerSubtopic = 3
    @State private var generationError: String?
    @State private var generationSuccessMessage: String?
    @State private var generationProgress: String?
    @State private var searchText = ""
    @State private var hoveredSubtopic: String?
    @State private var masteryError: String?
    @State private var cardStudioOptions = CardGenerationOptions(count: 10, difficulty: .exam, style: .basic, tone: .exam, cognitiveSkills: [], useInternalTools: false)

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
    private var accent: Color { Color(hex: subject.accentColorHex) }
    private var topicCount: Int { curriculum.flatMap(\.topics).count }
    private var subtopicCount: Int { curriculum.flatMap(\.topics).flatMap(\.subtopics).count }
    private var subjectCurriculumNodes: [CurriculumNode] {
        curriculumNodes.filter {
            $0.subjectName.caseInsensitiveCompare(subject.name) == .orderedSame &&
                $0.level.caseInsensitiveCompare(subject.level) == .orderedSame
        }
    }
    private let coverageCardCounts = [2, 3, 5]

    var body: some View {
        VStack(spacing: 0) {
            browserHeader
            Divider()

            HSplitView {
                unitPane
                    .frame(minWidth: 230, idealWidth: 250, maxWidth: 290)

                topicPane
                    .frame(minWidth: 280, idealWidth: 300, maxWidth: 350)

                topicDetailPane
                    .frame(minWidth: 480, idealWidth: 540)
            }
        }
        .frame(minWidth: 1040, minHeight: 620)
        .background(IBColors.canvas)
        .navigationTitle("Curriculum")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .onAppear { synchronizeSelection() }
        .onChange(of: searchText) { _, _ in synchronizeSelection() }
        .alert("Could Not Save Mastery", isPresented: Binding(
            get: { masteryError != nil },
            set: { if !$0 { masteryError = nil } }
        )) {
            Button("OK") { masteryError = nil }
        } message: {
            Text(masteryError ?? "The mastery update could not be saved.")
        }
    }

    private var browserHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(accent.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(subject.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(IBColors.ink)
                    StudioPill(title: subject.level, tint: accent)
                }
                Text("\(topicCount) topics · \(subtopicCount) subunits · \(metadata.catalogVersion)")
                    .font(.caption)
                    .foregroundStyle(IBColors.secondaryText)
            }

            Spacer(minLength: 18)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(IBColors.tertiaryText)
                TextField("Search topics and subunits", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .frame(width: 280, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(IBColors.canvas)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(IBColors.cardBorder, lineWidth: 1)
                    )
            )

            Link(destination: metadata.sourceURL) {
                Label("IB syllabus", systemImage: "arrow.up.right.square")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(IBColors.surface)
    }

    private var unitPane: some View {
        VStack(spacing: 0) {
            paneHeader("Units", detail: "\(curriculum.count)")
            Divider()

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(curriculum, id: \.name) { unit in
                        Button {
                            selectUnit(unit)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selectedUnit?.name == unit.name ? "folder.fill" : "folder")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(selectedUnit?.name == unit.name ? accent : IBColors.secondaryText)
                                    .frame(width: 18)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(unit.name)
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(IBColors.ink)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(2)
                                    Text("\(unit.topics.count) topics")
                                        .font(.caption2)
                                        .foregroundStyle(IBColors.secondaryText)
                                }
                                Spacer(minLength: 4)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedUnit?.name == unit.name ? accent.opacity(0.1) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }
        }
        .background(IBColors.surface)
    }

    private var topicPane: some View {
        VStack(spacing: 0) {
            paneHeader(selectedUnit?.name ?? "Topics", detail: "\(selectedUnit?.topics.count ?? 0)")
            Divider()

            if let unit = selectedUnit {
                let index = cardsBySubtopicKey
                let nodes = subjectCurriculumNodes
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(unit.topics, id: \.name) { topic in
                            topicSelectionRow(topic, index: index, nodes: nodes)
                        }
                    }
                    .padding(10)
                }
            } else {
                paneEmptyState(symbol: "rectangle.stack", title: "Select a unit")
            }
        }
        .background(IBColors.canvas)
    }

    private func topicSelectionRow(_ topic: CurriculumTopic, index: [String: [StudyCard]], nodes: [CurriculumNode]) -> some View {
        let count = cardCount(for: topic.name, in: index)
        let mastery = topicMastery(topic: topic, index: index, nodes: nodes)
        let isSelected = selectedTopic?.name == topic.name

        return Button {
            selectedTopic = topic
            clearGenerationStatus()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text(topic.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(IBColors.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isSelected ? accent : IBColors.tertiaryText)
                }

                HStack(spacing: 7) {
                    Label("\(topic.subtopics.count)", systemImage: "list.bullet")
                    Text("\(count) cards")
                    Spacer()
                    Text("\(Int(mastery * 100))%")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                }
                .font(.caption2)
                .foregroundStyle(IBColors.secondaryText)

                MasteryBar(progress: mastery, height: 3, color: accent)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? IBColors.surface : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? accent.opacity(0.28) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var topicDetailPane: some View {
        if let topic = selectedTopic {
            let index = cardsBySubtopicKey
            let nodes = subjectCurriculumNodes
            let sessionsByTopic = workSessionsByTopic(studySessions)
            VStack(spacing: 0) {
                topicHeader(topic, index: index)
                Divider()
                coverageToolbar(topic)
                CardStudioOptionsView(options: $cardStudioOptions, showsCount: false, compact: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .onChange(of: cardStudioOptions.count) { _, v in generationCount = v }
                generationStatus
                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(topic.subtopics.enumerated()), id: \.element) { rowIndex, subtopic in
                            subtopicRow(index: rowIndex, topic: topic.name, subtopic: subtopic, cardsIndex: index, nodes: nodes, sessionsByTopic: sessionsByTopic)
                            if rowIndex < topic.subtopics.count - 1 {
                                Divider().padding(.leading, 48)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                }
            }
            .background(IBColors.surface)
        } else {
            paneEmptyState(symbol: "book.closed", title: "Select a topic")
                .background(IBColors.surface)
        }
    }

    private func topicHeader(_ topic: CurriculumTopic, index: [String: [StudyCard]]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 4, height: 42)

            VStack(alignment: .leading, spacing: 5) {
                Text(topic.name)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(IBColors.ink)
                HStack(spacing: 10) {
                    Label("\(topic.subtopics.count) subunits", systemImage: "list.bullet")
                    Label("\(cardCount(for: topic.name, in: index)) cards", systemImage: "rectangle.stack.fill")
                }
                .font(.caption)
                .foregroundStyle(IBColors.secondaryText)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
    }

    private func coverageToolbar(_ topic: CurriculumTopic) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accent.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Coverage Builder")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(IBColors.ink)
                    Text("Fill every subunit to a consistent adaptive baseline.")
                        .font(.caption)
                        .foregroundStyle(IBColors.secondaryText)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 10) {
                Text("Cards per subunit")
                    .font(.caption)
                    .foregroundStyle(IBColors.secondaryText)

                VStack(alignment: .leading, spacing: 2) {
                    Slider(value: Binding(get: { Double(cardsPerSubtopic) }, set: { cardsPerSubtopic = Int($0.rounded()) }), in: 2...5, step: 1)
                    HStack {
                        Text("2").font(.caption2)
                        Spacer()
                        Text("\(cardsPerSubtopic) cards").font(.caption.weight(.semibold))
                        Spacer()
                        Text("5").font(.caption2)
                    }
                    .foregroundStyle(IBColors.secondaryText)
                }
                .frame(width: 170)

                Spacer(minLength: 8)

                Button {
                    generateCoverage(for: topic)
                } label: {
                    Label("Build Coverage", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(isGenerating)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(accent.opacity(0.045))
    }

    @ViewBuilder
    private var generationStatus: some View {
        if isGenerating || generationError != nil || generationSuccessMessage != nil {
            VStack(alignment: .leading, spacing: 7) {
                if isGenerating {
                    Label {
                        Text(generationProgress ?? "Generating adaptive flashcards…")
                    } icon: {
                        ProgressView().controlSize(.small)
                    }
                    .font(.caption)
                    .foregroundStyle(IBColors.secondaryText)
                }

                if let message = generationSuccessMessage {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(IBColors.success)
                }

                if let error = generationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(IBColors.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .background(IBColors.canvas)
        }
    }

    private func subtopicRow(
        index: Int,
        topic: String,
        subtopic: String,
        cardsIndex: [String: [StudyCard]],
        nodes: [CurriculumNode],
        sessionsByTopic: [String: [StudySession]]
    ) -> some View {
        let cards = cards(for: topic, subtopic: subtopic, in: cardsIndex)
        let count = cards.count
        let mastery = ProficiencyTracker.masteryPercentage(for: cards)
        let workSessions = workSessionsFor(topic: topic, subtopic: subtopic, in: sessionsByTopic)
        let hasProgress = count > 0 || !workSessions.isEmpty
        let isHovered = hoveredSubtopic == subtopic

        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(hasProgress ? accent.opacity(0.14) : IBColors.canvas)
                    .frame(width: 28, height: 28)
                if hasProgress {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(accent)
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(IBColors.secondaryText)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(subtopic)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(IBColors.ink)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text("\(count) cards")
                    if !workSessions.isEmpty {
                        Text("\(workSessions.count) work")
                    }
                    if count > 0 {
                        MasteryBar(progress: mastery, height: 3, color: accent)
                            .frame(width: 58)
                        Text("\(Int(mastery * 100))% mastery")
                    }
                }
                .font(.caption2)
                .foregroundStyle(IBColors.secondaryText)
            }

            Spacer(minLength: 8)

            Button {
                generateCards(topic: topic, subtopic: subtopic)
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(accent)
            .disabled(isGenerating)
            .help("Generate adaptive cards for \(subtopic)")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? IBColors.surfaceHover.opacity(0.75) : Color.clear)
        )
        .onHover { hovering in
            hoveredSubtopic = hovering ? subtopic : nil
        }
    }

    private func proficiencyColor(_ level: ProficiencyLevel) -> Color {
        switch level {
        case .novice: return IBColors.danger
        case .developing: return IBColors.warning
        case .proficient: return IBColors.electricBlue
        case .mastered: return IBColors.success
        }
    }

    private func masteryMenu(current: ProficiencyLevel?, topic: String, subtopic: String) -> some View {
        Menu {
            ForEach(ProficiencyLevel.allCases, id: \.self) { level in
                Button {
                    setMastery(level, topic: topic, subtopic: subtopic)
                } label: {
                    Label(level.rawValue, systemImage: current == level ? "checkmark" : "gauge")
                }
            }
            if current != nil {
                Divider()
                Button("Clear Recorded Mastery", role: .destructive) {
                    clearMastery(topic: topic, subtopic: subtopic)
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .help("Set recorded mastery for \(subtopic)")
    }

    private func setMastery(_ level: ProficiencyLevel, topic: String, subtopic: String) {
        do {
            try CurriculumProgressService.setMastery(
                level,
                subject: subject,
                unitName: SyllabusSeeder.unitName(for: subject.name, level: subject.level, topicName: topic) ?? "Curriculum",
                topicName: topic,
                subtopicName: subtopic,
                source: "Manual",
                context: context
            )
        } catch {
            masteryError = error.localizedDescription
        }
    }

    private func clearMastery(topic: String, subtopic: String) {
        do {
            try CurriculumProgressService.clearMastery(
                subject: subject,
                topicName: topic,
                subtopicName: subtopic,
                context: context
            )
        } catch {
            masteryError = error.localizedDescription
        }
    }

    private func paneHeader(_ title: String, detail: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(IBColors.secondaryText)
                .lineLimit(1)
            Spacer()
            Text(detail)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(IBColors.tertiaryText)
        }
        .textCase(.uppercase)
        .padding(.horizontal, 14)
        .frame(height: 38)
    }

    private func paneEmptyState(symbol: String, title: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(IBColors.tertiaryText)
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(IBColors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func synchronizeSelection() {
        guard let firstUnit = curriculum.first else {
            selectedUnit = nil
            selectedTopic = nil
            return
        }

        if let unitName = selectedUnit?.name,
           let matchingUnit = curriculum.first(where: { $0.name == unitName }) {
            selectedUnit = matchingUnit
            if let topicName = selectedTopic?.name,
               let matchingTopic = matchingUnit.topics.first(where: { $0.name == topicName }) {
                selectedTopic = matchingTopic
            } else {
                selectedTopic = matchingUnit.topics.first
            }
        } else {
            selectUnit(firstUnit)
        }
    }

    private func selectUnit(_ unit: CurriculumUnit) {
        selectedUnit = unit
        selectedTopic = unit.topics.first
        clearGenerationStatus()
    }

    private func clearGenerationStatus() {
        generationError = nil
        generationSuccessMessage = nil
        generationProgress = nil
    }

    /// Index of subject cards keyed by "topic|subtopic" so rows and counts do
    /// not rescan the whole card set on every render.
    private var cardsBySubtopicKey: [String: [StudyCard]] {
        var index: [String: [StudyCard]] = [:]
        for card in subject.cards {
            index["\(card.topicName)|\(card.subtopic)", default: []].append(card)
        }
        return index
    }

    private func cards(for topic: String, subtopic: String, in index: [String: [StudyCard]]) -> [StudyCard] {
        index["\(topic)|\(subtopic)"] ?? []
    }

    private func cardCount(for topicName: String, in index: [String: [StudyCard]]) -> Int {
        index.reduce(0) { partial, entry in
            entry.key.hasPrefix(topicName + "|") ? partial + entry.value.count : partial
        }
    }

    /// Single-pass topic mastery built from the card index so topic rows do not
    /// re-scan the whole card set through the curriculum service per row.
    private func topicMastery(topic: CurriculumTopic, index: [String: [StudyCard]], nodes: [CurriculumNode]) -> Double {
        guard !topic.subtopics.isEmpty else { return 0 }
        let score = topic.subtopics.reduce(0.0) { partial, subtopic in
            let cards = index["\(topic.name)|\(subtopic)"] ?? []
            let node = CurriculumProgressService.node(
                in: nodes,
                subjectName: subject.name,
                level: subject.level,
                topicName: topic.name,
                subtopicName: subtopic
            )
            return partial + CurriculumProgressService.effectiveMastery(cards: cards, node: node)
        }
        return score / Double(topic.subtopics.count)
    }

    /// Subject work sessions grouped by lowercased topic so subunit rows do not
    /// scan the session history once per row.
    private func workSessionsByTopic(_ sessions: [StudySession]) -> [String: [StudySession]] {
        var index: [String: [StudySession]] = [:]
        for session in sessions where session.subjectName.caseInsensitiveCompare(subject.name) == .orderedSame {
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

    private func generateCards(topic: String, subtopic: String) {
        isGenerating = true
        generationError = nil
        generationSuccessMessage = nil
        generationProgress = "Generating cards for \(subtopic)…"
        IBHaptics.light()

        Task {
            do {
                let opts = cardStudioOptions
                let cards = try await CardGeneratorService.generateCards(
                    subject: subject,
                    topicName: topic,
                    subtopic: subtopic,
                    count: opts.count,
                    context: context,
                    options: opts
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
