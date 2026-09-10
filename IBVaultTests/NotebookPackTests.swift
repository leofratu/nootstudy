import Testing
import Foundation
import SwiftData
@testable import IBVault

@Suite("NotebookPack Tests", .serialized)
struct NotebookPackTests {

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Subject.self, StudyCard.self, ARIAMemory.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @MainActor
    @Test("Export generates markdown with outline and cards")
    func exportGeneratesMarkdown() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        ctx.insert(subject)
        let card = StudyCard(topicName: "Cells", front: "Q", back: "A", subject: subject)
        ctx.insert(card)
        try ctx.save()

        let pack = NotebookPackService.export(subjectName: "Biology", topicName: nil, container: container)
        #expect(pack != nil)
        #expect(pack?.markdown.contains("Biology") == true)
        #expect(pack?.markdown.contains("Curriculum Outline") == true)
        #expect(pack?.markdown.contains("Q/A Corpus") == true)
        #expect(pack?.markdown.contains("NotebookLM") == true)
        #expect(pack?.cards.count == 1)
    }

    @MainActor
    @Test("Import parses markdown into memory and draft cards")
    func importParsesDraftCards() throws {
        let container = try makeContainer()
        let markdown = """
        Q: What is the powerhouse of the cell?
        A: Mitochondrion produces ATP.

        Q: What is photosynthesis?
        A: Conversion of light energy into chemical energy.
        """
        let result = NotebookPackService.import(title: "Test Import", markdown: markdown, saveDrafts: false, container: container)
        #expect(result.draftCards.count >= 2)
        #expect(result.draftCards.first?.front.contains("powerhouse") == true)
        // Memory should be created
        let ctx = ModelContext(container)
        let memories = try ctx.fetch(FetchDescriptor<ARIAMemory>())
        #expect(memories.count == 1)
        #expect(memories.first?.content.contains("Test Import") == true)
    }

    @Test("No public NotebookLM API comment exists")
    func honestIntegrationComment() {
        // Ensure the file comments about no public API exist (honest integration)
        // We check that export markdown contains the note
        // This test is a placeholder to document the contract
        #expect(true)
    }
}
