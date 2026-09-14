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
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Topics", systemImage: "list.bullet")
                    .font(IBTypography.headline)
                Spacer()
                Text("\(selection.count) selected").font(IBTypography.caption).foregroundStyle(IBColors.accent)
                if !selection.isEmpty {
                    Button("Clear") { selection.removeAll() }.buttonStyle(.borderless)
                }
            }
            TextField("Search topics or subtopics", text: $search)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search topics or subtopics")
            if curriculum.isEmpty {
                Text("No curriculum is available for this subject.")
                    .foregroundStyle(IBColors.inkSecondary)
            } else if !curriculum.flatMap(\.topics).contains(where: matches) {
                ContentUnavailableView.search(text: search)
            } else {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(curriculum, id: \.name) { unit in
                        let visible = unit.topics.filter(matches)
                        if !visible.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(unit.name.uppercased())
                                    .font(IBTypography.captionBold)
                                    .tracking(1)
                                    .foregroundStyle(IBColors.inkSecondary)
                                    .padding(.top, 4)
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
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    if selected { selection.remove(whole) }
                    else {
                        selection = selection.filter { $0.topic != topic.name }
                        selection.insert(whole)
                    }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: selected ? "checkmark.square.fill" : (partialCount > 0 ? "minus.square.fill" : "square"))
                            .font(.system(size: 17))
                            .foregroundStyle(selected || partialCount > 0 ? IBColors.accent : IBColors.inkSecondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(topic.name).font(.system(size: 13, weight: .semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(partialCount > 0 ? "\(partialCount) subtopics selected" : "\(topic.subtopics.count) subtopics")
                                .font(IBTypography.caption).foregroundStyle(IBColors.inkSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Select \(topic.name)")
                .accessibilityValue(selected ? "Selected" : partialCount > 0 ? "Partially selected" : "Not selected")
                if !topic.subtopics.isEmpty {
                    Button {
                        if expanded.contains(topic.name) { expanded.remove(topic.name) }
                        else { expanded.insert(topic.name) }
                    } label: {
                        Image(systemName: expanded.contains(topic.name) ? "chevron.up" : "chevron.down")
                            .frame(width: 28, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(expanded.contains(topic.name) ? "Collapse" : "Expand") \(topic.name)")
                }
            }
            .padding(12)
            .background(selected || partialCount > 0 ? IBColors.highlight : IBColors.surface, in: RoundedRectangle(cornerRadius: IBRadius.md))
            .overlay(RoundedRectangle(cornerRadius: IBRadius.md).stroke(selected || partialCount > 0 ? IBColors.accent : IBColors.border, lineWidth: 1))

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
                    .padding(.leading, 24).padding(.vertical, 4)
                }
            }
        }
    }
}
