from pathlib import Path

p = Path('IBVault/Views/Subjects/BiologyStudyView.swift')
s = p.read_text()
start = s.index('    private var outline: some View {')
end = s.index('    @ViewBuilder private var detail:', start)
s = s[:start] + '''    private var outline: some View {
        // The status controls stay visible when selection scrolls into view.
        // This is a bounded 40-topic catalog: eager rows avoid empty lazy-layout
        // regions during programmatic scrolling without a large-view workload.
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Picker("Topic status", selection: $topicFilter) {
                    ForEach(TopicFilter.allCases, id: \\.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                    .accessibilityLabel("Filter syllabus topics")
                Text("\\(visible.count) topics shown").font(.caption).foregroundStyle(IBColors.inkSecondary)
            }.padding(12)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 7) {
                        if visible.isEmpty {
                            ContentUnavailableView("No matching topics", systemImage: "line.3.horizontal.decrease.circle",
                                                   description: Text("Try another search or choose All to see every topic at this level."))
                        }
                        ForEach(BiologyCatalog.themes, id: \\.self) { theme in
                            let topics = visible.filter { $0.theme == theme }
                            if !topics.isEmpty {
                                Text("\\(theme) · \\(BiologyCatalog.themeName(theme))")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    .padding(.top, 5)
                                ForEach(topics) { topic in
                                    Button { selectedCode = topic.code; showOutline = false } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(alignment: .firstTextBaseline, spacing: 7) {
                                                Text(topic.code).font(.caption.monospaced().weight(.semibold))
                                                    .foregroundStyle(IBColors.accent)
                                                Text(topic.title).font(.callout.weight(selectedCode == topic.code ? .semibold : .regular))
                                            }.multilineTextAlignment(.leading)
                                            let count = mistakeCount(topic)
                                            Text(count > 0 ? "\\(count) saved mistakes" : topic.hlOnly ? "HL only · Partial coverage" : "Core topic · Partial coverage")
                                                .font(.caption2).foregroundStyle(.secondary)
                                        }
                                        .padding(8).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                        .background(selectedCode == topic.code ? IBColors.highlight : Color.clear,
                                                    in: RoundedRectangle(cornerRadius: 7))
                                        .contentShape(Rectangle())
                                    }.buttonStyle(.plain).id(topic.code)
                                        .accessibilityAddTraits(selectedCode == topic.code ? .isSelected : [])
                                }
                            }
                        }
                    }.padding(12)
                }
                .onAppear { proxy.scrollTo(selectedCode, anchor: .center) }
                .onChange(of: selectedCode) { _, code in proxy.scrollTo(code, anchor: .center) }
            }
        }
    }

''' + s[end:]
p.write_text(s)

p = Path('IBVaultVisualTests/BiologyVisualTests.swift')
s = p.read_text()
marker = '''        subject.level = "HL"
        let hl ='''
replacement = '''        let photosynthesis = BiologyStudyView(subject: subject, initialCode: "C1.3").modelContainer(store)
        try await render(photosynthesis, width: 420, height: 900, dark: false, name: "after-photosynthesis-sl-420")
        subject.level = "HL"
        let respiration = BiologyStudyView(subject: subject, initialCode: "C1.2").modelContainer(store)
        try await render(respiration, width: 1280, height: 900, dark: false, name: "after-respiration-hl-1280")
        let hl ='''
assert marker in s
p.write_text(s.replace(marker, replacement))
