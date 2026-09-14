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
    @State private var generationError: String?
    @State private var generationSuccessMessage: String?
    @State private var generationProgress: String?
    @State private var searchText = ""
    @State private var hoveredSubtopic: String?
    @State private var masteryError: String?
    @State private var showStudio = false
    @State private var studioSelection: Set<CardTopicSelection> = []

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
    private var accent: Color { IBColors.subjectColor(for: subject.name) }
    private var topicCount: Int { curriculum.flatMap(\.topics).count }
    private var subtopicCount: Int { curriculum.flatMap(\.topics).flatMap(\.subtopics).count }
    private var subjectCurriculumNodes: [CurriculumNode] {
        curriculumNodes.filter {
            $0.subjectName.caseInsensitiveCompare(subject.name) == .orderedSame &&
                $0.level.caseInsensitiveCompare(subject.level) == .orderedSame
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            browserHeader
            Divider()

            HSplitView {
                curriculumOutline
                    .frame(minWidth: 230, idealWidth: 280, maxWidth: 320)
                topicDetailPane
                    .frame(minWidth: 440, idealWidth: 540)
            }
        }
        .frame(minWidth: 780, minHeight: 620)
        .background(IBColors.canvas)
        .navigationTitle("Curriculum")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .onAppear { synchronizeSelection() }
        .onChange(of: searchText) { _, _ in synchronizeSelection() }
        .sheet(isPresented: $showStudio) {
            CardStudioView(initialSubject: subject, initialSelection: studioSelection)
                .frame(minWidth: 920, minHeight: 720)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showStudio = false }
                    }
                }
        }
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
                    .foregroundStyle(IBColors.inkSecondary)
            }

            Spacer(minLength: 18)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(IBColors.inkTertiary)
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
                            .stroke(IBColors.border, lineWidth: 1)
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

    private var curriculumOutline: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(curriculum, id: \.name) { unit in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(unit.name.uppercased())
                            .font(IBTypography.captionBold).tracking(1)
                            .foregroundStyle(IBColors.inkSecondary).padding(.bottom, 6)
                        ForEach(unit.topics, id: \.name) { topic in
                            Button {
                                selectedUnit = unit
                                selectedTopic = topic
                            } label: {
                                HStack {
                                    Text(topic.name).font(IBTypography.body)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 4)
                                    if selectedTopic?.name == topic.name {
                                        Image(systemName: "chevron.right").font(IBTypography.caption)
                                    }
                                }
                                .foregroundStyle(selectedTopic?.name == topic.name ? IBColors.accent : IBColors.ink)
                                .padding(12)
                                .background(selectedTopic?.name == topic.name ? IBColors.highlight : Color.clear,
                                            in: RoundedRectangle(cornerRadius: IBRadius.md))
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }.padding(16)
        }.background(IBColors.canvas)
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
                HStack {
                    Text("Subtopics").font(IBTypography.headline)
                    Spacer()
                    Button {
                        studioSelection = [CardTopicSelection(topic: topic.name)]
                        showStudio = true
                    } label: {
                        Label("Create cards", systemImage: "sparkles")
                    }.buttonStyle(PrimaryButtonStyle())
                }
                .padding(20)
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
                .foregroundStyle(IBColors.inkSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
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
                        .foregroundStyle(IBColors.inkSecondary)
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
                .foregroundStyle(IBColors.inkSecondary)
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
            .help("Generate adaptive cards for \(subtopic)")
            .accessibilityLabel("Create cards for \(subtopic)")
            masteryMenu(current: CurriculumProgressService.node(
                in: nodes, subjectName: subject.name, level: subject.level,
                topicName: topic, subtopicName: subtopic)?.recordedProficiency,
                topic: topic, subtopic: subtopic)
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
        .accessibilityLabel("Recorded mastery for \(subtopic)")
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

    private func paneEmptyState(symbol: String, title: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(IBColors.inkTertiary)
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(IBColors.inkSecondary)
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
        studioSelection = [CardTopicSelection(topic: topic, subtopic: subtopic)]
        showStudio = true
    }
}
