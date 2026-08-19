import Foundation
import SwiftData

nonisolated struct StudyScope: Equatable, Sendable {
    let subjectName: String
    let unitNames: [String]
    let topicNames: [String]
    let subtopicNames: [String]

    var hasFilters: Bool {
        !topicNames.isEmpty || !subtopicNames.isEmpty || !unitNames.isEmpty
    }

    var title: String {
        if !topicNames.isEmpty {
            return topicNames.joined(separator: ", ")
        }
        if !unitNames.isEmpty {
            return unitNames.joined(separator: ", ")
        }
        return subjectName
    }

    var summary: String {
        var parts: [String] = []
        if !unitNames.isEmpty {
            parts.append(unitNames.joined(separator: ", "))
        }
        if !topicNames.isEmpty {
            parts.append(topicNames.joined(separator: ", "))
        }
        if !subtopicNames.isEmpty {
            parts.append(subtopicNames.joined(separator: ", "))
        }
        return parts.joined(separator: " • ")
    }

    func matches(_ card: StudyCard) -> Bool {
        if !subjectName.isEmpty, let cardSubjectName = card.subject?.name, cardSubjectName != subjectName {
            return false
        }

        if !topicNames.isEmpty, !topicNames.contains(card.topicName) {
            return false
        }

        guard !subtopicNames.isEmpty else { return true }
        let normalizedCardSubtopic = card.subtopic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCardSubtopic.isEmpty, normalizedCardSubtopic != card.topicName else {
            return false
        }

        return subtopicNames.contains(normalizedCardSubtopic)
    }

    static func parseList(_ rawValue: String) -> [String] {
        rawValue
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

nonisolated enum StudyPlanKind: String, Codable, Sendable {
    case studySession
    case followUpReview
}

nonisolated struct StudyPlanTask: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let minutes: Int
    let activityType: String
    let topicName: String
    let subtopicName: String
    let instructions: String
    let successCriterion: String
    let flashcardTarget: Int

    init(
        id: UUID = UUID(),
        title: String,
        minutes: Int,
        activityType: String,
        topicName: String,
        subtopicName: String = "",
        instructions: String,
        successCriterion: String,
        flashcardTarget: Int = 0
    ) {
        self.id = id
        self.title = title
        self.minutes = minutes
        self.activityType = activityType
        self.topicName = topicName
        self.subtopicName = subtopicName
        self.instructions = instructions
        self.successCriterion = successCriterion
        self.flashcardTarget = flashcardTarget
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, minutes, activityType, topicName, subtopicName
        case instructions, successCriterion, flashcardTarget
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        minutes = try container.decode(Int.self, forKey: .minutes)
        activityType = try container.decodeIfPresent(String.self, forKey: .activityType) ?? "active-recall"
        topicName = try container.decodeIfPresent(String.self, forKey: .topicName) ?? ""
        subtopicName = try container.decodeIfPresent(String.self, forKey: .subtopicName) ?? ""
        instructions = try container.decode(String.self, forKey: .instructions)
        successCriterion = try container.decodeIfPresent(String.self, forKey: .successCriterion)
            ?? "Can explain the result without notes."
        flashcardTarget = try container.decodeIfPresent(Int.self, forKey: .flashcardTarget) ?? 0
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(minutes, forKey: .minutes)
        try container.encode(activityType, forKey: .activityType)
        try container.encode(topicName, forKey: .topicName)
        try container.encode(subtopicName, forKey: .subtopicName)
        try container.encode(instructions, forKey: .instructions)
        try container.encode(successCriterion, forKey: .successCriterion)
        try container.encode(flashcardTarget, forKey: .flashcardTarget)
    }
}

nonisolated struct StudyPlanDraft: Codable, Equatable, Sendable {
    let overview: String
    let objectives: [String]
    let tasks: [StudyPlanTask]

    static func decode(from response: String) throws -> StudyPlanDraft {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate: String
        if let firstBrace = trimmed.firstIndex(of: "{"),
           let lastBrace = trimmed.lastIndex(of: "}") {
            candidate = String(trimmed[firstBrace...lastBrace])
        } else {
            candidate = trimmed
        }
        return try JSONDecoder().decode(Self.self, from: Data(candidate.utf8))
    }

    func normalized(
        durationMinutes: Int,
        topicNames: [String],
        subtopicNames: [String],
        subjectName: String = ""
    ) -> StudyPlanDraft {
        let targetCount: Int = switch durationMinutes {
        case ...30: 4
        case 31...60: 6
        case 61...90: 8
        default: 10
        }
        let fallbackTopics = topicNames.isEmpty ? ["Selected scope"] : topicNames
        let suppliedTasks = Array(tasks.filter { $0.minutes > 0 }.prefix(targetCount))
        let phases = Self.sessionPhases(count: targetCount, durationMinutes: durationMinutes)
        let firstResource = LearningResourceCatalog.resources(
            for: subjectName,
            topicNames: topicNames,
            limit: 1
        ).first
        var normalized = phases.enumerated().map { index, phase in
            let supplied = suppliedTasks.indices.contains(index) ? suppliedTasks[index] : nil
            let topic = supplied?.topicName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? supplied?.topicName ?? fallbackTopics[index % fallbackTopics.count]
                : fallbackTopics[index % fallbackTopics.count]
            let subtopic = supplied?.subtopicName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? supplied?.subtopicName ?? ""
                : (subtopicNames.isEmpty ? "" : subtopicNames[index % subtopicNames.count])
            var instructions = phase.instructions
            if index == 0, let firstResource {
                instructions += " Start with [\(firstResource.title)](\(firstResource.url.absoluteString)) from \(firstResource.provider): \(firstResource.purpose)"
            }
            if let supplied,
               !supplied.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               supplied.instructions.caseInsensitiveCompare(instructions) != .orderedSame {
                instructions += " ARIA extension: \(supplied.instructions)"
            }
            return StudyPlanTask(
                id: supplied?.id ?? UUID(),
                title: phase.title,
                minutes: phase.weight,
                activityType: phase.activityType,
                topicName: topic,
                subtopicName: subtopic,
                instructions: instructions,
                successCriterion: phase.successCriterion,
                flashcardTarget: phase.flashcardTarget
            )
        }

        let breakMinutes = normalized.filter { $0.activityType == "break" }.reduce(0) { $0 + $1.minutes }
        let workTasks = normalized.filter { $0.activityType != "break" }
        let workBudget = max(workTasks.count, durationMinutes - breakMinutes)
        let rawWorkTotal = max(workTasks.reduce(0) { $0 + $1.minutes }, 1)
        var remainingWorkMinutes = workBudget
        var remainingWorkTasks = workTasks.count
        normalized = normalized.enumerated().map { index, task in
            let minutes: Int
            if task.activityType == "break" {
                minutes = task.minutes
            } else if remainingWorkTasks == 1 {
                minutes = remainingWorkMinutes
            } else {
                let proposed = max(1, Int((Double(task.minutes) / Double(rawWorkTotal) * Double(workBudget)).rounded()))
                minutes = min(proposed, remainingWorkMinutes - (remainingWorkTasks - 1))
            }
            if task.activityType != "break" {
                remainingWorkMinutes -= minutes
                remainingWorkTasks -= 1
            }
            let topic = task.topicName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? fallbackTopics[index % fallbackTopics.count]
                : task.topicName
            let subtopic = task.subtopicName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !subtopicNames.isEmpty
                ? subtopicNames[index % subtopicNames.count]
                : task.subtopicName
            return StudyPlanTask(
                id: task.id,
                title: task.title,
                minutes: minutes,
                activityType: task.activityType,
                topicName: topic,
                subtopicName: subtopic,
                instructions: task.instructions,
                successCriterion: task.successCriterion,
                flashcardTarget: max(0, task.flashcardTarget)
            )
        }
        return StudyPlanDraft(
            overview: overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Build understanding first, then use retrieval, feedback, and transfer to make it durable."
                : overview,
            objectives: objectives.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            tasks: normalized
        )
    }

    private struct SessionPhase {
        let title: String
        let weight: Int
        let activityType: String
        let instructions: String
        let successCriterion: String
        let flashcardTarget: Int
    }

    private static func sessionPhases(count: Int, durationMinutes: Int) -> [SessionPhase] {
        let orient = SessionPhase(
            title: "Orient with a trusted source", weight: 12, activityType: "introduction",
            instructions: "Preview the learning goal, key vocabulary, and one representative example. Write two questions you expect to answer by the end.",
            successCriterion: "Can name the central question, define the essential terms, and predict how the example works.", flashcardTarget: 0
        )
        let vocabulary = SessionPhase(
            title: "Map the vocabulary", weight: 7, activityType: "explanation",
            instructions: "Connect the core terms in a small concept map. Explain each connection in one sentence instead of copying definitions.",
            successCriterion: "Can explain at least four meaningful connections between the terms.", flashcardTarget: 0
        )
        let model = SessionPhase(
            title: "Build the mental model", weight: 15, activityType: "explanation",
            instructions: "Work through one example with notes open. At every step, state why the step follows and what would change under a different assumption.",
            successCriterion: "Can reconstruct the example and justify each important step.", flashcardTarget: 0
        )
        let secondExample = SessionPhase(
            title: "Explain a contrasting example", weight: 9, activityType: "explanation",
            instructions: "Compare a second example with the first. Explain aloud which principle stays constant and which conditions change.",
            successCriterion: "Can distinguish the underlying rule from surface details.", flashcardTarget: 0
        )
        let retrieve = SessionPhase(
            title: "Retrieve with notes closed", weight: 14, activityType: "active-recall",
            instructions: "Close every source. Answer the two opening questions, recreate the key model, and state the explanation from memory before revealing anything.",
            successCriterion: "Produces a complete attempt from memory before checking the source.", flashcardTarget: 3
        )
        let teach = SessionPhase(
            title: "Teach it simply", weight: 8, activityType: "active-recall",
            instructions: "Explain the idea as if teaching a smart beginner. Mark every point where you use a vague word or cannot explain why.",
            successCriterion: "Gives a precise explanation without hiding gaps behind jargon.", flashcardTarget: 2
        )
        let feedback = SessionPhase(
            title: "Correct and encode feedback", weight: 10, activityType: "feedback",
            instructions: "Compare the closed-note attempt with the source or mark scheme. Correct each error in a different color and save only self-contained flashcards for durable gaps.",
            successCriterion: "Every error has a corrected explanation and each saved card has a specific answer.", flashcardTarget: 3
        )
        let interleave = SessionPhase(
            title: "Interleave a different case", weight: 10, activityType: "practice",
            instructions: "Switch to a related but different case. Decide which method or concept applies before solving, and explain why competing approaches do not fit.",
            successCriterion: "Selects and justifies the correct approach without pattern matching to the first example.", flashcardTarget: 0
        )
        let transfer = SessionPhase(
            title: "Transfer to a new problem", weight: 15, activityType: "exam-practice",
            instructions: "Attempt one unfamiliar application, exam question, pitch scenario, or decision case without notes. Then improve it using the rubric or success criteria.",
            successCriterion: "Applies the idea accurately in a new context and can defend the reasoning.", flashcardTarget: 0
        )
        let exit = SessionPhase(
            title: "Exit ticket and next gap", weight: 7, activityType: "check-in",
            instructions: "Without notes, write the three most important ideas, answer one opening question, and record one remaining gap. Leave future recall to the capped daily review queue.",
            successCriterion: "Can state three accurate takeaways, one unresolved gap, and one concrete next action.", flashcardTarget: 0
        )
        let recovery = SessionPhase(
            title: "Recovery break", weight: 15, activityType: "break",
            instructions: "Step away for 15 minutes. Move, drink water, and avoid opening another demanding task. Resume only when the timer ends.",
            successCriterion: "Returns after a genuine screen-free recovery period.", flashcardTarget: 0
        )

        var phases: [SessionPhase] = switch count {
        case ...4:
            [orient, retrieve, transfer, exit]
        case 5...6:
            [orient, model, retrieve, feedback, transfer, exit]
        case 7...8:
            [orient, model, secondExample, retrieve, feedback, interleave, transfer, exit]
        default:
            [orient, vocabulary, model, secondExample, retrieve, teach, feedback, interleave, transfer, exit]
        }
        guard durationMinutes >= 60,
              let retrievalIndex = phases.firstIndex(where: { $0.activityType == "active-recall" }) else {
            return phases
        }
        phases.insert(recovery, at: retrievalIndex + 1)
        if durationMinutes >= 120 {
            phases.insert(recovery, at: max(phases.count - 1, 0))
        }
        return phases
    }

    var markdown: String {
        var lines = ["## Session outcome", overview]
        if !objectives.isEmpty {
            lines.append("\n## Objectives")
            lines.append(contentsOf: objectives.map { "- \($0)" })
        }
        lines.append("\n## Time-blocked plan")
        for (index, task) in tasks.enumerated() {
            let scope = task.subtopicName.isEmpty ? task.topicName : "\(task.topicName) · \(task.subtopicName)"
            lines.append("\n### \(index + 1). \(task.title) — \(task.minutes) min")
            lines.append("**Scope:** \(scope)")
            lines.append(task.instructions)
            lines.append("**Done when:** \(task.successCriterion)")
            if task.flashcardTarget > 0 {
                lines.append("**Flashcards:** Review or create \(task.flashcardTarget)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

@Model
nonisolated final class StudyPlan {
    var id: UUID
    var subjectName: String
    var topicName: String
    var subtopicName: String
    var planMarkdown: String
    var createdDate: Date
    var scheduledDate: Date
    var scheduledEndDate: Date
    var isCompleted: Bool
    var notes: String
    var durationMinutes: Int
    var kindRaw: String
    var reviewIntervalDays: Int?
    var reviewScheduleOffsetsRaw: String?
    // Optional for migration from stores created before this flag existed.
    var prepareFlashcards: Bool?
    var planTasksJSON: String?
    var flashcardOnly: Bool?
    var flashcardTargetCount: Int?
    var flashcardDifficultyRaw: String?

    var kind: StudyPlanKind {
        get { StudyPlanKind(rawValue: kindRaw) ?? .studySession }
        set { kindRaw = newValue.rawValue }
    }

    var isFollowUpReview: Bool {
        kind == .followUpReview
    }

    var scheduleLabel: String {
        if isFollowUpReview {
            if let reviewIntervalDays {
                return "Review • Day \(reviewIntervalDays)"
            }
            return "Review"
        }
        return topicName
    }

    private static let scheduledTimeFormatter: DateFormatter = {
        IBLocalClock.formatter(dateFormat: "E d MMM, HH:mm")
    }()

    private static let scheduledEndTimeFormatter: DateFormatter = {
        IBLocalClock.formatter(dateFormat: "HH:mm")
    }()

    var scheduledTimeFormatted: String {
        Self.scheduledTimeFormatter.string(from: scheduledDate)
    }

    var scheduledEndTimeFormatted: String {
        Self.scheduledEndTimeFormatter.string(from: scheduledEndDate)
    }

    var isUpcoming: Bool {
        !isCompleted && scheduledDate > IBLocalClock.now
    }

    var isActive: Bool {
        !isCompleted && scheduledDate <= IBLocalClock.now && scheduledEndDate >= IBLocalClock.now
    }

    var isPast: Bool {
        isCompleted || scheduledEndDate < IBLocalClock.now
    }

    var selectedTopicNames: [String] {
        StudyScope.parseList(topicName)
    }

    var selectedSubtopicNames: [String] {
        StudyScope.parseList(subtopicName)
    }

    var selectedUnitNames: [String] {
        SyllabusSeeder.unitNames(for: subjectName, topicNames: selectedTopicNames)
    }

    var reviewScheduleOffsets: [Int] {
        let raw = reviewScheduleOffsetsRaw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parsed = raw
            .components(separatedBy: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0 > 0 }
        guard !parsed.isEmpty else { return [] }
        var seen = Set<Int>()
        return parsed.filter { seen.insert($0).inserted }
    }

    var revisitCount: Int {
        reviewScheduleOffsets.count
    }

    var studyScope: StudyScope {
        StudyScope(
            subjectName: subjectName,
            unitNames: selectedUnitNames,
            topicNames: selectedTopicNames,
            subtopicNames: selectedSubtopicNames
        )
    }

    var selectionSummary: String {
        let summary = studyScope.summary
        return summary.isEmpty ? topicName : summary
    }

    var planTasks: [StudyPlanTask] {
        get {
            guard let planTasksJSON,
                  let data = planTasksJSON.data(using: .utf8),
                  let tasks = try? JSONDecoder().decode([StudyPlanTask].self, from: data) else {
                return []
            }
            return tasks
        }
        set {
            guard !newValue.isEmpty,
                  let data = try? JSONEncoder().encode(newValue),
                  let encoded = String(data: data, encoding: .utf8) else {
                planTasksJSON = nil
                return
            }
            planTasksJSON = encoded
        }
    }

    init(
        subjectName: String,
        topicName: String,
        subtopicName: String = "",
        planMarkdown: String = "",
        scheduledDate: Date,
        durationMinutes: Int = 60,
        notes: String = "",
        kind: StudyPlanKind = .studySession,
        reviewIntervalDays: Int? = nil,
        reviewScheduleOffsets: [Int] = [],
        prepareFlashcards: Bool = false,
        planTasks: [StudyPlanTask] = [],
        flashcardOnly: Bool = false,
        flashcardTargetCount: Int? = nil,
        flashcardDifficulty: CardDifficulty? = nil
    ) {
        self.id = UUID()
        self.subjectName = subjectName
        self.topicName = topicName
        self.subtopicName = subtopicName
        self.planMarkdown = planMarkdown
        self.createdDate = IBLocalClock.now
        self.scheduledDate = scheduledDate
        self.scheduledEndDate = IBLocalClock.calendar.date(byAdding: .minute, value: durationMinutes, to: scheduledDate) ?? scheduledDate
        self.isCompleted = false
        self.notes = notes
        self.durationMinutes = durationMinutes
        self.kindRaw = kind.rawValue
        self.reviewIntervalDays = reviewIntervalDays
        self.reviewScheduleOffsetsRaw = reviewScheduleOffsets.map(String.init).joined(separator: ",")
        self.prepareFlashcards = prepareFlashcards
        self.planTasksJSON = nil
        self.flashcardOnly = flashcardOnly
        self.flashcardTargetCount = flashcardTargetCount
        self.flashcardDifficultyRaw = flashcardDifficulty?.rawValue
        self.planTasks = planTasks
    }
}

nonisolated extension StudyPlan: Identifiable {}
