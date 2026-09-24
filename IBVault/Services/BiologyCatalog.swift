import Foundation

/// Original, AI-assisted revision material. Topic presence is never a claim of
/// complete IB understanding-level coverage; each package declares its gaps.
nonisolated struct BiologyTopic: Codable, Identifiable, Sendable {
    let code: String
    let title: String
    let hlOnly: Bool
    let prerequisites: [String]
    let sections: [BiologySection]
    let questions: [BiologyQuestion]
    let remaining: String

    var id: String { code }
    var name: String { "\(code) \(title)" }
    var theme: String { String(code.prefix(1)) }
    func sections(at level: IBCourseLevel) -> [BiologySection] {
        guard level == .hl || !hlOnly else { return [] }
        return sections.filter { level == .hl || $0.hlOnly != true }
    }
    func questions(at level: IBCourseLevel) -> [BiologyQuestion] {
        let available = Set(sections(at: level).map(\.key))
        return questions.filter { available.contains($0.sectionKey) && (level == .hl || $0.hlOnly != true) }
    }
    func contains(_ query: String, at level: IBCourseLevel) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || name.localizedCaseInsensitiveContains(query)
            || BiologyCatalog.themeName(theme).localizedCaseInsensitiveContains(query)
            || sections(at: level).contains {
                $0.title.localizedCaseInsensitiveContains(query) || $0.body.localizedCaseInsensitiveContains(query)
            }
    }
}

nonisolated struct BiologySection: Codable, Identifiable, Sendable {
    let key: String
    let title: String
    let body: String
    let pitfall: String
    let syllabusPoints: [String]?
    let hlOnly: Bool?
    var id: String { key }
}

nonisolated struct BiologyQuestion: Codable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case mcq, written, data }
    let key: String
    let sectionKey: String
    let kind: Kind
    let command: String
    let prompt: String
    let answer: String
    let distractors: [String]
    let explanation: String
    let hlOnly: Bool?
    var id: String { key }
    var markingPoints: [String] { answer.components(separatedBy: "~") }
    var formattedAnswer: String { markingPoints.joined(separator: "\n\n") }
    var options: [String] { kind == .mcq ? [answer] + distractors : [] }
}

nonisolated enum BiologyCatalog {
    static let sourceName = "Noot Study Biology • original AI-assisted revision"
    static let sourceID = "noot-biology-2025-v1"
    static let version = "2026.09 / first assessment 2025"
    static let sourceURL = "https://www.ibo.org/programmes/diploma-programme/curriculum/sciences/biology/"
    static let themes = ["A", "B", "C", "D"]
    static let result: Result<[BiologyTopic], any Error> = Result { try load(bundle: .main) }

    static var topics: [BiologyTopic] { (try? result.get()) ?? [] }
    static var failure: String? {
        if case .failure(let error) = result { return error.localizedDescription }
        return nil
    }
    static func topics(at level: IBCourseLevel) -> [BiologyTopic] {
        topics.filter { level == .hl || !$0.hlOnly }
    }
    /// Resolve exact official codes/titles and narrowly equivalent old labels.
    /// Broad retired groups such as Genetics are deliberately not mapped to one
    /// new topic: doing so could assign mastery to material never assessed.
    static func topic(named name: String, at level: IBCourseLevel) -> BiologyTopic? {
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let aliases = ["cells and cell structure": "a2.2"]
        let resolved = aliases[query] ?? query
        return topics(at: level).first {
            $0.code.lowercased() == resolved || $0.title.lowercased() == resolved || $0.name.lowercased() == resolved
        }
    }

    static func topic(reference: String) -> BiologyTopic? {
        let code = reference.split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
        let prefix = code.split(separator: ".").prefix(2).joined(separator: ".")
        return topics.first { $0.code.caseInsensitiveCompare(prefix) == .orderedSame }
    }

    static func themeName(_ code: String) -> String {
        switch code {
        case "A": return "Unity and diversity"
        case "B": return "Form and function"
        case "C": return "Interaction and interdependence"
        case "D": return "Continuity and change"
        default: return "Unknown theme"
        }
    }
    static func resourceID(topic: String, key: String) -> String { "\(topic)#\(key)" }
    static func question(reference: String) -> (topic: BiologyTopic, question: BiologyQuestion)? {
        let parts = reference.split(separator: "#", maxSplits: 1).map(String.init)
        guard parts.count == 2, let topic = topics.first(where: { $0.code == parts[0] }),
              let question = topic.questions.first(where: { $0.key == parts[1] }) else { return nil }
        return (topic, question)
    }
    static func load(bundle: Bundle) throws -> [BiologyTopic] {
        let urls = try themes.map { theme in
            guard let url = bundle.url(forResource: theme, withExtension: "json", subdirectory: "Materials/Biology") else {
                throw CatalogError.invalid("Missing Biology material \(theme).json. Reinstall a complete app build.")
            }
            return url
        }
        return try load(urls: urls)
    }
    static func load(urls: [URL]) throws -> [BiologyTopic] {
        let topics = try urls.flatMap { url in
            try JSONDecoder().decode([BiologyTopic].self, from: Data(contentsOf: url))
        }.sorted { $0.code < $1.code }
        try validate(topics)
        return topics
    }
    static func validate(_ topics: [BiologyTopic]) throws {
        let codes = Set(topics.map(\.code))
        guard topics.count == 40, codes.count == 40 else {
            throw CatalogError.invalid("Expected 40 distinct Biology topics; found \(topics.count) entries and \(codes.count) identifiers.")
        }
        let commands: Set<String> = ["identify", "state", "outline", "describe", "distinguish", "compare", "explain", "suggest", "calculate", "determine", "discuss", "evaluate"]
        var prompts = Set<String>()
        for topic in topics {
            func require(_ condition: Bool, _ reason: String) throws {
                if !condition { throw CatalogError.invalid("\(topic.code): \(reason)") }
            }
            try require(topic.code.range(of: #"^[ABCD][1-4]\.[1-3]$"#, options: .regularExpression) != nil, "invalid topic code")
            try require(!topic.title.isEmpty && !topic.remaining.isEmpty, "missing title or coverage limitations")
            try require(!topic.sections.isEmpty && !topic.questions.isEmpty, "no teaching or practice")
            try require(Set(topic.sections.map(\.key)).count == topic.sections.count, "duplicate lesson keys")
            try require(Set(topic.questions.map(\.key)).count == topic.questions.count, "duplicate question keys")
            try require(Set(topic.prerequisites).count == topic.prerequisites.count, "duplicate prerequisites")
            try require(topic.prerequisites.allSatisfy { codes.contains($0) && $0 != topic.code }, "invalid prerequisite")
            for section in topic.sections {
                try require([section.key, section.title, section.body, section.pitfall].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, "empty lesson field")
                let refs = section.syllabusPoints ?? []
                try require(Set(refs).count == refs.count, "duplicate understanding reference")
                try require(refs.allSatisfy {
                    $0.hasPrefix(topic.code + ".") && $0.range(of: #"^[ABCD][1-4]\.[1-3]\.[1-9][0-9]*$"#, options: .regularExpression) != nil
                }, "invalid understanding reference")
            }
            for question in topic.questions {
                guard let section = topic.sections.first(where: { $0.key == question.sectionKey }) else {
                    throw CatalogError.invalid("\(topic.code): question \(question.key) references a missing lesson")
                }
                try require(topic.hlOnly || section.hlOnly != true || question.hlOnly == true, "HL lesson has an SL question")
                try require([question.key, question.prompt, question.answer, question.explanation].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, "empty question field")
                try require(commands.contains(question.command), "unsupported command term")
                try require(prompts.insert(question.prompt.lowercased()).inserted, "duplicate question prompt")
                try require(question.markingPoints.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, "empty marking point")
                if question.kind == .mcq {
                    let options = question.options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    try require(options.count == 4 && Set(options).count == 4 && !options.contains(""), "MCQ needs four distinct, nonempty options")
                } else {
                    try require(question.distractors.isEmpty, "written question has MCQ options")
                }
            }
            for section in topic.sections {
                try require(topic.questions.contains { $0.sectionKey == section.key }, "lesson \(section.key) has no assessed practice")
            }
        }
        let graph = Dictionary(uniqueKeysWithValues: topics.map { ($0.code, $0.prerequisites) })
        var visited = Set<String>()
        var active = Set<String>()
        func visit(_ code: String) throws {
            guard !visited.contains(code) else { return }
            guard active.insert(code).inserted else { throw CatalogError.invalid("Cyclic prerequisite at \(code)") }
            for prerequisite in graph[code] ?? [] { try visit(prerequisite) }
            active.remove(code)
            visited.insert(code)
        }
        for code in codes { try visit(code) }
    }
    enum CatalogError: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            switch self { case .invalid(let message): return message }
        }
    }
}

/// Bookmarks from ungraded practice, intentionally separate from FSRS/mastery.
/// Only known question IDs are retained. Bad preference data never hides lessons.
nonisolated enum BiologyPracticeBookmarks {
    static func key(subjectID: UUID) -> String { "biology.mistakes.v1.\(subjectID.uuidString)" }
    static func load(subjectID: UUID, defaults: UserDefaults = .standard) -> Set<String> {
        let valid = Set(BiologyCatalog.topics.flatMap { topic in
            topic.questions.map { BiologyCatalog.resourceID(topic: topic.code, key: $0.key) }
        })
        return Set(defaults.stringArray(forKey: key(subjectID: subjectID)) ?? []).intersection(valid)
    }
    static func save(_ ids: Set<String>, subjectID: UUID, defaults: UserDefaults = .standard) {
        defaults.set(ids.sorted(), forKey: key(subjectID: subjectID))
    }
}
