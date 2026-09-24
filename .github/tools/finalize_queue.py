from pathlib import Path

path = Path('IBVault/Engine/ReviewQueueManager.swift')
text = path.read_text()
start = text.index('        var descriptor = FetchDescriptor<StudyCard>()')
end = text.index('        let library = CardDuplicatePolicy.library', start)
text = text[:start] + '        let all = try currentCards(in: context)\n' + text[end:]
marker = '''    @MainActor
    static func day(in context: ModelContext, now: Date = IBLocalClock.now,'''
replacement = '''    /// Fetch membership afresh, but avoid rehydrating every attribute when the
    /// same context already has all models registered. There is no separate
    /// cross-refresh cache: model identity, edits and faulting remain SwiftData's.
    /// Unsaved changes take the ordinary fetch path. A cold context also falls
    /// back to a single bulk fetch rather than causing one database read per ID.
    @MainActor
    static func currentCards(in context: ModelContext) throws -> [StudyCard] {
        let descriptor = FetchDescriptor<StudyCard>()
        guard !context.hasChanges else { return try context.fetch(descriptor) }
        let identifiers = try context.fetchIdentifiers(descriptor)
        var registered: [StudyCard] = []
        registered.reserveCapacity(identifiers.count)
        for identifier in identifiers {
            guard let card: StudyCard = context.registeredModel(for: identifier) else {
                return try context.fetch(descriptor)
            }
            registered.append(card)
        }
        return registered
    }

    @MainActor
    static func day(in context: ModelContext, now: Date = IBLocalClock.now,'''
assert marker in text
text = text.replace(marker, replacement)
text = text.replace('guard let cards = try? context.fetch(FetchDescriptor<StudyCard>()) else { return [] }',
                    'guard let cards = try? ReviewDailyLimitPolicy.currentCards(in: context) else { return [] }')
path.write_text(text)
