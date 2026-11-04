import SwiftUI

struct TopicSelectionView: View {
    let subject: Subject
    @Binding var selection: Set<CardTopicSelection>
    @State private var search = ""
    @State private var expanded: Set<String> = []

    private var curriculum: [CurriculumUnit] {
        SyllabusSeeder.curriculum(for: subject.name, level: subject.level)
    }

    private func matches(_ topic: CurriculumTopic) -> Bool {
        search.isEmpty || topic.name.localizedCaseInsensitiveContains(search)
            || topic.subtopics.contains { $0.localizedCaseInsensitiveContains(search) }
            || (SyllabusSeeder.unitName(for: subject.name, level: subject.level, topicName: topic.name)?.localizedCaseInsensitiveContains(search) == true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(selection.count) selected").font(IBTypography.caption).foregroundStyle(IBColors.inkSecondary)
                Spacer()
                if !selection.isEmpty {
                    Button("Clear") { selection.removeAll() }.buttonStyle(.borderless)
                }
            }
            TextField("Search units, topics or subtopics", text: $search)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search topics or subtopics")
            if curriculum.isEmpty {
                Text("No curriculum is available for this subject.")
                    .foregroundStyle(IBColors.inkSecondary)
            } else if !curriculum.flatMap(\.topics).contains(where: matches) {
                ContentUnavailableView.search(text: search)
            } else {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(curriculum, id: \.name) { unit in
                        let visible = unit.topics.filter(matches)
                        if !visible.isEmpty {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(unit.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(IBColors.inkTertiary)
                                    .padding(.horizontal, 8)
                                    .padding(.bottom, 4)
                                ForEach(visible, id: \.name) { topic in
                                    topicRow(topic)
                                }
                            }
                        }
                    }
                }
            }
        }
        .foregroundStyle(IBColors.ink)
    }

    private func topicRow(_ topic: CurriculumTopic) -> some View {
        let whole = CardTopicSelection(topic: topic.name)
        let selected = selection.contains(whole)
        let partialCount = selection.filter { $0.topic == topic.name && !$0.subtopic.isEmpty }.count
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Button {
                    if selected { selection.remove(whole) }
                    else {
                        selection = selection.filter { $0.topic != topic.name }
                        selection.insert(whole)
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: selected ? "checkmark.square.fill" : (partialCount > 0 ? "minus.square.fill" : "square"))
                            .font(.system(size: 14))
                            .foregroundStyle(selected || partialCount > 0 ? IBColors.accent : IBColors.inkSecondary)
                        Text(topic.name).font(.system(size: 13))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Text(partialCount > 0 ? "\(partialCount) of \(topic.subtopics.count)" : "\(topic.subtopics.count)")
                            .font(IBTypography.caption.monospacedDigit()).foregroundStyle(IBColors.inkTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(IBPressStyle())
                .accessibilityLabel("Select \(topic.name)")
                .accessibilityValue(selected ? "Selected" : partialCount > 0 ? "Partially selected" : "Not selected")
                if !topic.subtopics.isEmpty {
                    Button {
                        withAnimation(IBAnimation.snappy) {
                            if expanded.contains(topic.name) { expanded.remove(topic.name) }
                            else { expanded.insert(topic.name) }
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(IBColors.inkTertiary)
                            .rotationEffect(.degrees(expanded.contains(topic.name) ? 90 : 0))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(IBPressStyle())
                    .accessibilityLabel("\(expanded.contains(topic.name) ? "Collapse" : "Expand") \(topic.name)")
                }
            }
            .padding(.leading, 8).padding(.trailing, 2).padding(.vertical, 3)
            .hoverHighlight()

            if expanded.contains(topic.name) || (!search.isEmpty && !topic.name.localizedCaseInsensitiveContains(search)) {
                ForEach(topic.subtopics.filter { search.isEmpty || topic.name.localizedCaseInsensitiveContains(search) || $0.localizedCaseInsensitiveContains(search) }, id: \.self) { subtopic in
                    let scope = CardTopicSelection(topic: topic.name, subtopic: subtopic)
                    Toggle(subtopic, isOn: Binding(
                        get: { selected || selection.contains(scope) },
                        set: { checked in
                            if selected {
                                selection.remove(whole)
                                for sub in topic.subtopics { selection.insert(CardTopicSelection(topic: topic.name, subtopic: sub)) }
                            }
                            if checked { selection.insert(scope) } else { selection.remove(scope) }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .font(IBTypography.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 30).padding(.vertical, 2)
                }
            }
        }
    }
}
