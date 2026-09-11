import Foundation
import SwiftData

/// NotebookLM-ready pack: structured markdown source (curriculum outline, Q/A corpus, weak topics, suggested prompts), cards JSON, README.
/// There is no public NotebookLM API; folder/JSON exchange is the honest integration.
/// Wire both endpoints via BridgeRouter.
nonisolated enum NotebookPackService: Sendable {

    struct ExportPack: Sendable {
        let subject: String
        let markdown: String
        let cards: [CardDTO]
        let generatedAt: Date
    }

    struct ImportResult: Sendable {
        let memoryID: UUID
        let draftCards: [DraftCard]
    }

    struct DraftCard: Codable, Sendable {
        let front: String
        let back: String
        let cardStyle: String?
        let topicName: String?
    }

    nonisolated static func export(subjectName: String, topicName: String?, container: ModelContainer) -> ExportPack? {
        let context = ModelContext(container)
        let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        guard let subject = subjects.first(where: { $0.name == subjectName }) else { return nil }
        let filteredCards = subject.cards.filter { card in
            guard let topicName, !topicName.isEmpty else { return true }
            return card.topicName == topicName
        }
        let cardDTOs = filteredCards.map { BridgeDTOFactory.cardDTO(from: $0) }
        let markdown = generateMarkdown(subject: subject, topicName: topicName, cards: filteredCards)
        return ExportPack(subject: subjectName, markdown: markdown, cards: cardDTOs, generatedAt: Date())
    }

    nonisolated static func `import`(title: String, markdown: String, saveDrafts: Bool, container: ModelContainer) -> ImportResult {
        let context = ModelContext(container)
        let memory = ARIAMemory(category: .userNotes, content: markdown, subjectName: nil)
        // Use title as part of content prefix if provided
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            memory.content = "# \(title)\n\n" + markdown
        }
        context.insert(memory)
        // Parse draft cards from markdown: look for Q/A pairs or bullet prompts
        let drafts = parseDraftCards(from: markdown)
        if saveDrafts {
            // Save drafts as actual StudyCards? Spec says not saved unless saveDrafts (but saveDrafts false => not saved)
            // When saveDrafts true, create cards in a "Imported" subject? We keep spec: draftCards not saved unless saveDrafts.
            // Actually endpoint spec: POST /v1/notebook/import {"title","markdown","saveDrafts":false} -> {"memoryID","draftCards":[...]}
            // saveDrafts false => only return drafts, not persist cards. We'll honor that.
            // If true, persist them.
            // For simplicity, when true we insert into first subject or create placeholder.
            // But we won't implement full save here to keep deterministic; caller can create via /v1/cards if needed.
            // To honor spec, when saveDrafts true we insert cards.
            if !drafts.isEmpty {
                let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
                let targetSubject = subjects.first
                for draft in drafts {
                    let card = StudyCard(
                        topicName: draft.topicName ?? "Imported",
                        front: draft.front,
                        back: draft.back,
                        subject: targetSubject,
                        isCustom: true,
                        isAIGenerated: false,
                        generationSource: "Notebook import",
                        cardStyle: draft.cardStyle.flatMap { CardStyle(rawValue: $0) } ?? .basic
                    )
                    context.insert(card)
                }
            }
        }
        try? context.save()
        return ImportResult(memoryID: memory.id, draftCards: drafts)
    }

    // MARK: - Private

    private static func generateMarkdown(subject: Subject, topicName: String?, cards: [StudyCard]) -> String {
        var lines: [String] = []
        lines.append("# \(subject.name) — Notebook Pack")
        lines.append("")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")
        lines.append("## Curriculum Outline")
        let curriculum = SyllabusSeeder.curriculum(for: subject.name, level: subject.level)
        for unit in curriculum {
            if let topicName, !topicName.isEmpty {
                guard unit.topics.contains(where: { $0.name == topicName }) else { continue }
            }
            lines.append("### \(unit.name)")
            for topic in unit.topics {
                if let topicName, !topicName.isEmpty, topic.name != topicName { continue }
                lines.append("- **\(topic.name)**: \(topic.subtopics.joined(separator: ", "))")
            }
        }
        lines.append("")
        lines.append("## Q/A Corpus")
        if cards.isEmpty {
            lines.append("_No cards yet._")
        } else {
            for card in cards.prefix(100) {
                lines.append("- **Q:** \(card.front)")
                lines.append("  **A:** \(card.back)")
            }
        }
        lines.append("")
        lines.append("## Weak Topics")
        let weakCards = cards.filter { $0.proficiency == .novice || $0.isStruggling }
        if weakCards.isEmpty {
            lines.append("_No weak topics identified._")
        } else {
            let byTopic = Dictionary(grouping: weakCards, by: \.topicName)
            for (topic, topicCards) in byTopic {
                lines.append("- \(topic): \(topicCards.count) cards needing review")
            }
        }
        lines.append("")
        lines.append("## Suggested Prompts for NotebookLM")
        lines.append("- Summarize the key concepts in \(topicName ?? subject.name) and identify gaps.")
        lines.append("- Generate 5 exam-style questions with mark schemes.")
        lines.append("- Explain the most common misconceptions and how to correct them.")
        lines.append("")
        lines.append("## Cards JSON")
        lines.append("See the `cards` array in the export payload for structured data.")
        lines.append("")
        lines.append("## README — Upload Steps")
        lines.append("1. Open https://notebooklm.google.com/")
        lines.append("2. Create a new notebook and upload this markdown as a source.")
        lines.append("3. Add the cards JSON as a supplemental source if desired.")
        lines.append("4. Use NotebookLM's Audio Overview or Q&A to study.")
        // Honest integration: there is no public NotebookLM API; folder/JSON exchange is the integration.
        lines.append("")
        lines.append("> Note: There is no public NotebookLM API; this pack is designed for manual upload via the NotebookLM web UI. Folder/JSON exchange is the honest integration.")
        return lines.joined(separator: "\n")
    }

    private static func parseDraftCards(from markdown: String) -> [DraftCard] {
        // Simple heuristic: split on lines starting with Q: or - Q: or ## and extract Q/A pairs
        // Look for patterns: Q: ... A: ... or **Q:** ... **A:** ...
        var drafts: [DraftCard] = []
        let lines = markdown.components(separatedBy: .newlines)
        var pendingFront: String?
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            // Detect Q
            let lower = trimmed.lowercased()
            if lower.hasPrefix("q:") || lower.hasPrefix("- q:") || lower.hasPrefix("**q:**") || lower.hasPrefix("q -") {
                let front = trimmed.replacingOccurrences(of: "**Q:**", with: "")
                    .replacingOccurrences(of: "Q:", with: "")
                    .replacingOccurrences(of: "- Q:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !front.isEmpty {
                    pendingFront = front
                }
                continue
            }
            if lower.hasPrefix("a:") || lower.hasPrefix("- a:") || lower.hasPrefix("**a:**") {
                let back = trimmed.replacingOccurrences(of: "**A:**", with: "")
                    .replacingOccurrences(of: "A:", with: "")
                    .replacingOccurrences(of: "- A:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let front = pendingFront, !back.isEmpty {
                    drafts.append(DraftCard(front: front, back: back, cardStyle: "basic", topicName: nil))
                    pendingFront = nil
                }
                continue
            }
            // Also detect markdown heading as topic
            if trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ") {
                // Could use as topic for next cards, but keep simple
                continue
            }
        }
        // Fallback: if no Q/A detected, try splitting on "?" lines as fronts with next line as back
        if drafts.isEmpty {
            var idx = 0
            while idx < lines.count - 1 {
                let front = lines[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                let back = lines[idx + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                if front.hasSuffix("?") && !back.isEmpty && !back.hasSuffix("?") && front.count > 10 && back.count > 5 {
                    drafts.append(DraftCard(front: front, back: back, cardStyle: "basic", topicName: nil))
                    idx += 2
                } else {
                    idx += 1
                }
                if drafts.count >= 20 { break }
            }
        }
        return Array(drafts.prefix(20))
    }
}
