import Testing
import Foundation
import SwiftData
@testable import IBVault

@Suite("Card Parsing Benchmark Tests")
struct CardParsingBenchmarkTests {

    @MainActor
    private func makeSubject() -> Subject {
        Subject(name: "Biology", level: "HL", accentColorHex: "#10B981")
    }

    @MainActor
    @Test("Local fallback for 50 cards completes quickly")
    func localFallback50Cards() {
        let subject = makeSubject()
        let profile = CardGeneratorService.adaptiveProfile(for: subject, topicName: "Cells", subtopic: "Prokaryotic cell structure")
        let clock = ContinuousClock()
        let start = clock.now
        let cards = CardGeneratorService.localStarterCards(subject: subject, topicName: "Cells", subtopic: "Prokaryotic cell structure", count: 50, profile: profile)
        let elapsed = clock.now - start
        let ms = Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000 * 1000 + Double(elapsed.components.seconds) * 1000
        // Log
        print("localFallback50Cards: \(ms) ms, count \(cards.count)")
        #expect(cards.count == min(50, SubjectKnowledge.knowledge(for: subject.name)?.keyConcepts.count ?? 0 + (SubjectKnowledge.knowledge(for: subject.name)?.commonMisconceptions.count ?? 0))
            || cards.count <= 50)
        #expect(ms < 500, "Local fallback should be <500ms, was \(ms)")
    }

    @MainActor
    @Test("Parse of 100 cards DTO JSON < 250 ms")
    func parse100CardsOffMain() async throws {
        let subject = Subject(name: "Biology", level: "HL", accentColorHex: "#10B981")
        // Build 100-card JSON payload
        var payloads: [[String: String]] = []
        for i in 0..<100 {
            payloads.append(["front": "Question \(i) about cell \(i)?", "back": "Answer \(i) detailed explanation for cell biology concept number \(i) with sufficient length.", "hint": "hint \(i)", "difficulty": "Standard", "skill": "Recall", "cardStyle": "basic"])
        }
        let data = try JSONEncoder().encode(payloads)
        let json = String(data: data, encoding: .utf8)!

        let clock = ContinuousClock()
        let start = clock.now
        let dtos = try await Task.detached(priority: .userInitiated) {
            try CardGeneratorService.extractCardDTOs(from: json)
        }.value
        let elapsed = clock.now - start
        let ms = Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
        print("parse100Cards DTO extract: \(ms) ms, dtos \(dtos.count)")

        // Map to cards on main (included in ceiling but we measure DTO extract only)
        #expect(dtos.count == 100)
        #expect(ms < 250, "Parse of 100 cards should be <250ms, was \(ms)")

        // Also verify full pipeline on MainActor is still bounded
        let profile = CardGeneratorService.adaptiveProfile(for: subject, topicName: "Cells", subtopic: "")
        let start2 = clock.now
        let cards = CardGeneratorService.cardsFromDTOs(dtos, subject: subject, topicName: "Cells", subtopic: "", profile: profile, options: nil)
        let elapsed2 = clock.now - start2
        let ms2 = Double(elapsed2.components.attoseconds) / 1e15 + Double(elapsed2.components.seconds) * 1000
        print("cardsFromDTOs 100: \(ms2) ms, cards \(cards.count)")
        #expect(cards.count == 100)
        #expect(ms + ms2 < 300, "Full parse+map should be <300ms")
    }
}
