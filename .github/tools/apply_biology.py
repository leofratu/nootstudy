from pathlib import Path


def edit(path, old, new, count=1):
    p = Path(path)
    text = p.read_text()
    assert text.count(old) == count, (path, old[:100], text.count(old), count)
    p.write_text(text.replace(old, new))


p = Path('IBVault/Services/SyllabusSeeder.swift')
text = p.read_text()
text = text.replace('self = rawValue.uppercased()', 'self = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()')
assert text.count('switch subjectName {') == 2
text = text.replace('switch subjectName {', 'switch subjectName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {')
for name in ['English B', 'Russian A Literature', 'Biology', 'Mathematics AA', 'Economics', 'Business Management', 'Advanced Mathematics', 'Fundamentals of the Universe']:
    text = text.replace('case "' + name + '"', 'case "' + name.lower() + '"')
text = text.replace('case lifeCourseName', 'case "life"').replace('"Founder Academy", "Startups & Venture Capital"', '"founder academy", "startups & venture capital"')
start = text.index('    private static var biologyCurriculum:')
end = text.index('    private static var mathAACurriculum:', start)
text = text[:start] + '    private static var biologyCurriculum: [CurriculumUnit] { BiologyStudyService.curriculum }\n\n    // MARK: - Mathematics: Analysis and Approaches\n\n' + text[end:]
p.write_text(text)
edit(str(p), '''            return metadata(
                firstAssessment: "2025",
                title: "IB Diploma Programme Biology",
                path: "programmes/diploma-programme/curriculum/sciences/biology/"
            )''', '''            return CurriculumMetadata(
                catalogVersion: BiologyCatalog.version,
                firstAssessment: "2025",
                sourceTitle: "IB Diploma Programme Biology",
                sourceURL: URL(string: BiologyCatalog.sourceURL) ?? URL(fileURLWithPath: "/")
            )''')
edit(str(p), '''        var nodesByKey: [String: CurriculumNode] = [:]
        for node in existingNodes {''', '''        // A missing bundle must not be mistaken for a deliberately empty syllabus.
        if subjects.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "biology" }),
           BiologyCatalog.failure != nil { return false }
        var nodesByKey: [String: CurriculumNode] = [:]
        // Keep the latest recorded evidence rather than an arbitrary fetch-order row.
        let orderedNodes = existingNodes.sorted {
            if $0.hasRecordedEvidence != $1.hasRecordedEvidence { return $0.hasRecordedEvidence }
            let left = $0.masteryUpdatedAt ?? $0.updatedAt
            let right = $1.masteryUpdatedAt ?? $1.updatedAt
            if left != right { return left > right }
            return $0.id.uuidString < $1.id.uuidString
        }
        for node in orderedNodes {''')
edit(str(p), 'for (key, node) in nodesByKey where !expectedKeys.contains(key) {', 'for (key, node) in nodesByKey where !expectedKeys.contains(key) && !node.hasRecordedEvidence {')
edit('IBVault/Models/CurriculumNode.swift', '    var stableKey: String {', '''    /// Retired and other-level records containing evidence remain user data.
    var hasRecordedEvidence: Bool {
        recordedMasteryRaw != nil || masteryUpdatedAt != nil || masterySource != nil || masteryNote != nil
    }

    var stableKey: String {''')
edit('IBVault/Engine/ProficiencyTracker.swift', 'let reviewCount = card.totalReviewCount', 'let reviewCount = card.successfulReviewCount // Failed attempts alone do not demonstrate learning.')
edit('IBVault/Engine/ProficiencyTracker.swift', 'calculateMastery(for: subject.cards)', 'calculateMastery(for: subject.cards.filter(BiologyStudyService.isEligible))')
queue = 'IBVault/Engine/ReviewQueueManager.swift'
edit(queue, 'for card in candidates {', 'for card in candidates where BiologyStudyService.isEligible(card) {')
edit(queue, 'remaining > 0 && !reviewedCanonicalIDs.contains', 'BiologyStudyService.isEligible(card) && remaining > 0 && !reviewedCanonicalIDs.contains')
edit(queue, 'let library = CardDuplicatePolicy.library(all)', 'let library = CardDuplicatePolicy.library(all.filter(BiologyStudyService.isEligible))')
edit(queue, 'return CardDuplicatePolicy.library(cards).cards', 'return CardDuplicatePolicy.library(cards.filter(BiologyStudyService.isEligible)).cards')
edit('IBVault/Models/Subject.swift', 'return cards.filter { $0.nextReviewDate <= now }.count', 'return cards.filter { BiologyStudyService.isEligible($0) && $0.nextReviewDate <= now }.count')
edit('IBVault/Models/Subject.swift', 'for card in cards {', 'for card in cards where BiologyStudyService.isEligible(card) {')
edit('IBVault/Engine/ReviewScheduler.swift', '            return subject.cards\n', '            return subject.cards.filter(BiologyStudyService.isEligible)\n')
edit('IBVault/Engine/ReviewScheduler.swift', '            subjectScopes.contains { $0.matches(card) }', '            BiologyStudyService.isEligible(card) && subjectScopes.contains { $0.matches(card) }')
edit('IBVault/Views/Review/ReviewSessionView.swift', '        .onAppear { loadCards() }', '        .onAppear { loadCards() }\n        .onChange(of: currentCard?.subject?.level) { _, _ in loadCards() }')
edit('IBVault/Views/Review/RecallCardView.swift', '        .onChange(of: card.id) { _, _ in resetChoices() }', '        .onChange(of: card.id) { _, _ in resetChoices() }\n        .onChange(of: revealed) { _, value in if !value { resetChoices() } }')
edit('IBVault/Views/Review/RecallCardView.swift', '                FormattedMessageContent(text: card.back).textSelection(.enabled)', '''                FormattedMessageContent(text: card.back).textSelection(.enabled)
                if let explanation = BiologyStudyService.explanation(for: card) {
                    Text(explanation).font(.callout).foregroundStyle(IBColors.inkSecondary).textSelection(.enabled)
                }''')
browser = 'IBVault/Views/Subjects/TopicBrowserView.swift'
edit(browser, '    var body: some View {\n        VStack(spacing: 0) {', '''    @ViewBuilder var body: some View {
        if subject.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "biology" {
            BiologyStudyView(subject: subject)
        } else {
            legacyBrowser
        }
    }

    private var legacyBrowser: some View {
        VStack(spacing: 0) {''')
edit(browser, '        .onChange(of: searchText) { _, _ in synchronizeSelection() }', '        .onChange(of: searchText) { _, _ in synchronizeSelection() }\n        .onChange(of: subject.level) { _, _ in synchronizeSelection() }')
edit(browser, '        let mastery = ProficiencyTracker.masteryPercentage(for: cards)', '''        let recorded = CurriculumProgressService.node(in: nodes, subjectName: subject.name,
            level: subject.level, topicName: topic, subtopicName: subtopic)
        let mastery = CurriculumProgressService.effectiveMastery(cards: cards, node: recorded)''')
edit(browser, 'let hasProgress = count > 0 || !workSessions.isEmpty', 'let hasProgress = mastery >= 1 // Opening pages or creating cards does not complete a concept.')
edit(browser, '                    if count > 0 {', '                    if count > 0 || recorded?.recordedProficiency != nil {')
edit('IBVaultTests/SyllabusSeederTests.swift', '#expect(biology.contains { $0.name == "Higher Level Extension" })', '#expect(biology.flatMap(\\.topics).contains { $0.name == "A2.3 Viruses" })')
edit('.github/workflows/study-validation.yml', '''          XCODE=$(find /Applications -maxdepth 1 -name 'Xcode_26*.app' | sort | tail -n 1)
          test -n "$XCODE"
          sudo xcode-select -s "$XCODE"''', '''          test -d /Applications/Xcode_26.4.app/Contents/Developer
          sudo xcode-select -s /Applications/Xcode_26.4.app/Contents/Developer''')
edit('.github/workflows/study-validation.yml', '            | tee "$RUNNER_TEMP/study-tests.log"', '            2>&1 | tee "$RUNNER_TEMP/study-tests.log"')
