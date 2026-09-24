from pathlib import Path


def edit(path, old, new, count=1):
    p = Path(path)
    text = p.read_text()
    assert text.count(old) == count, (path, text.count(old), old[:80])
    p.write_text(text.replace(old, new))


path = 'IBVault/Views/Subjects/BiologyStudyView.swift'
edit(path, '}.pickerStyle(.segmented)', '}.pickerStyle(.segmented).labelsHidden()', 3)
edit(path, '''    private var outline: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {''', '''    private var outline: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 7) {''')
edit(path, '.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(10)', '.padding(8).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)')
edit(path, '''                            }.buttonStyle(.plain)
                                .accessibilityAddTraits''', '''                            }.buttonStyle(.plain).id(topic.code)
                                .accessibilityAddTraits''')
edit(path, '''            }.padding(12)
        }
    }

    @ViewBuilder private var detail''', '''            }.padding(12)
        }
        .onAppear { proxy.scrollTo(selectedCode, anchor: .center) }
        .onChange(of: selectedCode) { _, code in proxy.scrollTo(code, anchor: .center) }
        }
    }

    @ViewBuilder private var detail''')
edit(path, r'''Text("\(topic.code) / \(topic.hlOnly ? "Higher level" : "Core + available HL extensions")")''', r'''Text("\(topic.code) / \(levelDescription(topic))")''')
edit(path, '    private func topicHeader(_ topic: BiologyTopic) -> some View {', '''    private func levelDescription(_ topic: BiologyTopic) -> String {
        if topic.hlOnly { return "HL only" }
        if level == .sl { return "SL core" }
        return topic.sections.contains { $0.hlOnly == true } ? "Core + HL extensions" : "SL + HL core"
    }

    private func topicHeader(_ topic: BiologyTopic) -> some View {''')
# Checked answers are informational, not disabled controls. Keep full contrast.
edit(path, '''    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {''', '''    var body: some View {
        Group {
            if revealed {
                optionContent.accessibilityElement(children: .combine)
            } else {
                Button(action: action) { optionContent }.buttonStyle(.plain)
            }
        }
        .accessibilityLabel("Option \\(number): \\(text)")
        .accessibilityValue(feedback)
    }

    private var optionContent: some View {
            HStack(alignment: .top, spacing: 12) {''')
edit(path, '''        }.buttonStyle(.plain).disabled(revealed)
            .accessibilityLabel("Option \\(number): \\(text)")
            .accessibilityValue(feedback)
    }
}''', '''    }
}''')
# AppKit window tests get their own host process. Both suites remain mandatory.
project = Path('project.yml')
text = project.read_text()
needle = 'targets:\n  IBVault:\n    type: application'
assert text.count(needle) == 1
text = text.replace(needle, '''  IBVaultVisual:
    shared: true
    build:
      targets:
        IBVault: all
    test:
      config: Debug
      targets:
        - IBVaultVisualTests
targets:
  IBVault:
    type: application''')
old_target = text[text.index('  IBVaultTests:\n    type: bundle.unit-test'):]
new_target = old_target.replace('IBVaultTests', 'IBVaultVisualTests').replace('com.nootstudy.ibvault.tests', 'com.nootstudy.ibvault.visualtests')
text += new_target
project.write_text(text)
old = Path('IBVaultTests/BiologyVisualTests.swift')
new = Path('IBVaultVisualTests/BiologyVisualTests.swift')
new.parent.mkdir(exist_ok=True)
old.rename(new)
edit(str(new), '''        let hosting = NSHostingView(rootView: view.environment(\\.colorScheme, dark ? .dark : .light)
            .frame(width: CGFloat(width), height: CGFloat(height)))''', '''        let hosting = NSHostingView(rootView: view
            .frame(width: CGFloat(width), height: CGFloat(height))
            .background(IBColors.canvas)
            .environment(\\.colorScheme, dark ? .dark : .light))''')
