import Foundation
import SwiftData

/// The search index is built from saved material, including curriculum names.
/// It never calls a provider or changes a card's review schedule.
enum StudyLibraryService {
    static func unit(for card: StudyCard) -> String {
        guard let subject = card.subject else { return "" }
        return SyllabusSeeder.unitName(for: subject.name, level: subject.level, topicName: card.topicName) ?? ""
    }

    nonisolated static func terms(_ text: String) -> [String] {
        CardDuplicatePolicy.normalize(text).split(separator: " ").map(String.init)
    }

    nonisolated static func matches(_ query: String, fields: [String]) -> Bool {
        let haystack = CardDuplicatePolicy.normalize(fields.joined(separator: " "))
        return terms(query).allSatisfy { haystack.contains($0) }
    }

    static func matches(_ query: String, card: StudyCard) -> Bool {
        matches(query, fields: [card.front, card.back, card.subject?.name ?? "", unit(for: card),
                               card.topicName, card.subtopic, card.syllabusReference ?? ""])
    }

    static func cards(in cards: [StudyCard], scopes: [CardTopicSelection], styles: Set<CardStyle> = []) -> [StudyCard] {
        CardDuplicatePolicy.library(cards).cards.filter { card in
            (styles.isEmpty || styles.contains(card.cardStyle)) && (scopes.isEmpty || scopes.contains {
                $0.topic.caseInsensitiveCompare(card.topicName) == .orderedSame
                    && ($0.subtopic.isEmpty || $0.subtopic.caseInsensitiveCompare(card.subtopic) == .orderedSame)
            })
        }.sorted {
            if $0.nextReviewDate != $1.nextReviewDate { return $0.nextReviewDate < $1.nextReviewDate }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    /// Give the model actual questions AND answers so it can recognise the
    /// same learning point even when a revision request uses different words.
    static func candidateContext(_ cards: [StudyCard], query: String = "", limit: Int = 80) -> String {
        let words = Set(terms(query)).subtracting(["the", "a", "me", "to", "for", "and", "please", "revise", "cards", "flashcards"])
        var ranked: [(card: StudyCard, score: Int)] = []
        for card in CardDuplicatePolicy.library(cards).cards {
            let fields = [card.front, card.back, card.topicName, card.subtopic, unit(for: card)]
            let content = Set(terms(fields.joined(separator: " ")))
            ranked.append((card, words.intersection(content).count))
        }
        ranked.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.card.id.uuidString < $1.card.id.uuidString
        }
        var records: [[String: String]] = []
        for (card, _) in ranked.prefix(limit) {
            let record: [String: String] = ["id": card.id.uuidString, "subject": card.subject?.name ?? "", "unit": unit(for: card),
                "topic": card.topicName, "subtopic": card.subtopic, "format": card.cardStyle.rawValue,
                "question": String(card.front.prefix(600)), "answer": String(card.back.prefix(900))]
            records.append(record)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: records, options: [.sortedKeys]) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Stored in the existing, backed-up conversation tables to avoid a destructive
/// library migration. A dedicated role distinguishes structured test records.
nonisolated struct SavedStudyTest: Codable, Identifiable {
    var id = UUID()
    var subject: String
    var level: String
    var topics: [String]
    var subtopics: [String]
    var question: String
    var answer = ""
    var markScheme = ""
    var feedback = ""
    var maximumMarks: Int
    var updatedAt = Date()

    var title: String { topics.isEmpty ? "Exam question" : topics.joined(separator: ", ") }
    var request: ExamMarkingRequest {
        .init(subject: subject, level: level, question: question, answer: answer,
              markScheme: markScheme, maximumMarks: maximumMarks)
    }
}

enum StudyTestStore {
    static let role = "study_test"

    static func read(_ messages: [ChatMessage]) -> [SavedStudyTest] {
        messages.filter { $0.role == role }.compactMap {
            try? JSONDecoder().decode(SavedStudyTest.self, from: Data($0.content.utf8))
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    static func save(_ test: SavedStudyTest, context: ModelContext) throws -> SavedStudyTest {
        var saved = test
        saved.updatedAt = Date()
        let content = String(decoding: try JSONEncoder().encode(saved), as: UTF8.self)
        let id = saved.id
        let messages = try context.fetch(FetchDescriptor<ChatMessage>(predicate: #Predicate { $0.sessionID == id }))
        let sessions = try context.fetch(FetchDescriptor<ARIAChatSession>(predicate: #Predicate { $0.id == id }))
        let existing = messages.first { $0.role == role }
        let session = sessions.first ?? ARIAChatSession(isArchived: true)
        let message = existing ?? ChatMessage(restoredRole: role, content: content, sessionID: id)
        let oldContent = message.content
        let oldTitle = session.title
        let oldPreview = session.lastMessagePreview
        let oldDate = session.updatedAt
        if sessions.isEmpty { session.id = id; context.insert(session) }
        if existing == nil { context.insert(message) }
        message.content = content
        session.title = "Test · \(saved.subject) · \(saved.title)"
        session.lastMessagePreview = String(saved.question.prefix(160))
        session.updatedAt = saved.updatedAt
        do { try context.save() }
        catch {
            if existing == nil { context.delete(message) } else { message.content = oldContent }
            if sessions.isEmpty { context.delete(session) }
            else { session.title = oldTitle; session.lastMessagePreview = oldPreview; session.updatedAt = oldDate }
            throw error
        }
        return saved
    }
}
