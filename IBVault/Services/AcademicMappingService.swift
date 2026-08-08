import Foundation
import SwiftData

@MainActor
enum AcademicMappingService {
    private struct AIProposal: Decodable {
        let topic: String
        let subtopic: String
        let confidence: Double
        let rationale: String
    }

    @discardableResult
    static func proposeLocalMappings(
        for assessments: [AcademicAssessment],
        subject: Subject,
        existingMappings: [AcademicAssessmentMapping],
        context: ModelContext
    ) throws -> Int {
        let candidates = curriculumCandidates(for: subject)
        var inserted = 0
        for assessment in assessments where assessment.subjectName == subject.name {
            guard !existingMappings.contains(where: { $0.assessmentID == assessment.id }) else { continue }
            guard let candidate = rankedCandidates(for: assessment, candidates: candidates).first, candidate.score >= 0.28 else { continue }
            context.insert(makeMapping(assessment: assessment, subject: subject, candidate: candidate, proposedBy: "Local matcher"))
            inserted += 1
        }
        if inserted > 0 { try context.save() }
        return inserted
    }

    @discardableResult
    static func proposeWithARIA(
        for assessments: [AcademicAssessment],
        subject: Subject,
        existingMappings: [AcademicAssessmentMapping],
        context: ModelContext
    ) async throws -> Int {
        let candidates = curriculumCandidates(for: subject)
        var inserted = 0
        for assessment in assessments where assessment.subjectName == subject.name {
            guard !existingMappings.contains(where: { $0.assessmentID == assessment.id }) else { continue }
            let ranked = Array(rankedCandidates(for: assessment, candidates: candidates).prefix(20))
            guard !ranked.isEmpty else { continue }
            let prompt = """
            Match this school assessment to zero or more official IB curriculum subunits.
            Subject: \(subject.name) \(subject.level)
            Assessment title: \(assessment.title)
            Details: \(assessment.details)

            Candidate subunits:
            \(ranked.enumerated().map { "\($0.offset + 1). \($0.element.unit) > \($0.element.topic) > \($0.element.subtopic)" }.joined(separator: "\n"))

            Return raw JSON only. Use an empty array when none fit:
            [{"topic":"exact candidate topic","subtopic":"exact candidate subtopic","confidence":0.0,"rationale":"short reason"}]
            """
            let response = try await AIProviderService.generateContent(
                messages: [GeminiMessage(role: "user", text: prompt)],
                systemInstruction: "You map school assessments cautiously. Never invent curriculum labels. Prefer no mapping to a weak mapping.",
                modelOverride: AIConfiguration.provider == .gemini ? AIConfiguration.model(for: .gemini) : nil,
                timeout: 60
            )
            let proposals = parseProposals(response)
            for proposal in proposals {
                guard let candidate = candidates.first(where: {
                    $0.topic.caseInsensitiveCompare(proposal.topic) == .orderedSame &&
                        $0.subtopic.caseInsensitiveCompare(proposal.subtopic) == .orderedSame
                }) else { continue }
                context.insert(AcademicAssessmentMapping(
                    assessmentID: assessment.id,
                    subjectName: subject.name,
                    courseLevel: subject.level,
                    curriculumNodeKey: CurriculumNode.stableKey(
                        subjectName: subject.name,
                        level: subject.level,
                        unitName: candidate.unit,
                        topicName: candidate.topic,
                        subtopicName: candidate.subtopic
                    ),
                    unitName: candidate.unit,
                    topicName: candidate.topic,
                    subtopicName: candidate.subtopic,
                    status: .proposed,
                    confidence: proposal.confidence,
                    rationale: proposal.rationale,
                    proposedBy: "ARIA"
                ))
                inserted += 1
            }
        }
        if inserted > 0 { try context.save() }
        return inserted
    }

    private struct Candidate: Sendable {
        let unit: String
        let topic: String
        let subtopic: String
        let score: Double
    }

    private static func curriculumCandidates(for subject: Subject) -> [Candidate] {
        SyllabusSeeder.curriculum(for: subject.name, level: subject.level).flatMap { unit in
            unit.topics.flatMap { topic in
                topic.subtopics.map { Candidate(unit: unit.name, topic: topic.name, subtopic: $0, score: 0) }
            }
        }
    }

    private static func rankedCandidates(for assessment: AcademicAssessment, candidates: [Candidate]) -> [Candidate] {
        let source = tokenSet(assessment.title + " " + assessment.details)
        return candidates.map { candidate in
            let target = tokenSet(candidate.topic + " " + candidate.subtopic)
            let overlap = source.intersection(target).count
            let score = target.isEmpty ? 0 : Double(overlap) / Double(target.count)
            return Candidate(unit: candidate.unit, topic: candidate.topic, subtopic: candidate.subtopic, score: score)
        }
        .sorted { $0.score == $1.score ? $0.subtopic < $1.subtopic : $0.score > $1.score }
    }

    private static func makeMapping(assessment: AcademicAssessment, subject: Subject, candidate: Candidate, proposedBy: String) -> AcademicAssessmentMapping {
        AcademicAssessmentMapping(
            assessmentID: assessment.id,
            subjectName: subject.name,
            courseLevel: subject.level,
            curriculumNodeKey: CurriculumNode.stableKey(
                subjectName: subject.name,
                level: subject.level,
                unitName: candidate.unit,
                topicName: candidate.topic,
                subtopicName: candidate.subtopic
            ),
            unitName: candidate.unit,
            topicName: candidate.topic,
            subtopicName: candidate.subtopic,
            status: .proposed,
            confidence: candidate.score,
            rationale: "Keyword overlap between the assessment title and curriculum subunit.",
            proposedBy: proposedBy
        )
    }

    private static func tokenSet(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 })
    }

    private static func parseProposals(_ response: String) -> [AIProposal] {
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
        guard let start = cleaned.firstIndex(of: "["), let end = cleaned.lastIndex(of: "]") else { return [] }
        return (try? JSONDecoder().decode([AIProposal].self, from: Data(cleaned[start...end].utf8))) ?? []
    }
}
