import Testing
import Foundation
import SwiftData
@testable import IBVault

/// One end-to-end tool scenario: a user message plus the JSON plan the model
/// would return, seeded into a fresh in-memory store. Each scenario runs through
/// the exact production pipeline (parse, dedupe, destructive gate, scratch-context
/// execution) via ARIAService.applyAppToolPlan.
nonisolated struct ToolScenario: Sendable {
    let id: String
    let name: String
    let userMessage: String
    let modelJSON: String
    let seed: @Sendable (ModelContext) throws -> Void
    let verify: @Sendable (ModelContext) throws -> Bool
    let expectedCompleted: Int?
    let expectedFailed: Int?
    let summaryContains: [String]

    init(
        id: String,
        name: String,
        userMessage: String,
        modelJSON: String,
        seed: @escaping @Sendable (ModelContext) throws -> Void = { _ in },
        expectedCompleted: Int? = 1,
        expectedFailed: Int? = 0,
        verify: @escaping @Sendable (ModelContext) throws -> Bool = { _ in true },
        summaryContains: [String] = []
    ) {
        self.id = id
        self.name = name
        self.userMessage = userMessage
        self.modelJSON = modelJSON
        self.seed = seed
        self.verify = verify
        self.expectedCompleted = expectedCompleted
        self.expectedFailed = expectedFailed
        self.summaryContains = summaryContains
    }
}

@MainActor
@Suite("ARIA Tool E2E — every data point malleable")
struct ARIAAppToolE2ETests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for:
            UserProfile.self,
            Subject.self,
            StudyCard.self,
            Grade.self,
            ReviewSession.self,
            ARIAMemory.self,
            ARIAChatSession.self,
            ChatMessage.self,
            StudyActivity.self,
            StudySession.self,
            StudyPlan.self,
            Achievement.self,
            UnitState.self,
            CurriculumNode.self,
            AcademicImport.self,
            AcademicAssessment.self,
            AcademicAssessmentMapping.self,
            AcademicReportSnapshot.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @Test(arguments: ARIAAppToolE2ETests.scenarios)
    func scenario(_ scenario: ToolScenario) async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try scenario.seed(context)
        try context.save()

        let service = ARIAService()
        let (completed, failed, notes) = try await service.applyAppToolPlan(
            scenario.modelJSON,
            userMessage: scenario.userMessage,
            context: context
        )

        var ok = true
        var detail = "completed=[\(completed.joined(separator: " | "))] failed=[\(failed.joined(separator: " | "))] notes=[\(notes.joined(separator: " | "))]"
        if let expectedCompleted = scenario.expectedCompleted, completed.count != expectedCompleted {
            ok = false
            detail += " | expected \(expectedCompleted) completed, got \(completed.count)"
        }
        if let expectedFailed = scenario.expectedFailed, failed.count != expectedFailed {
            ok = false
            detail += " | expected \(expectedFailed) failed, got \(failed.count)"
        }
        for term in scenario.summaryContains {
            let joined = (completed + failed + notes).joined(separator: " ")
            if !joined.localizedCaseInsensitiveContains(term) {
                ok = false
                detail += " | summary missing '\(term)'"
            }
        }
        let dataOK = (try? scenario.verify(context)) ?? false
        if !dataOK {
            ok = false
            detail += " | data verification failed"
        }

        #expect(ok, "\(scenario.id) — \(scenario.name): \(detail)")
    }

    nonisolated static var scenarios: [ToolScenario] {
        E2EScenarioLibrary.all()
    }
}

/// Non-isolated library that builds the full scenario matrix. Keep helpers here
/// so seed closures are plain `@Sendable` closures over `ModelContext`.
nonisolated enum E2EScenarioLibrary {

    @Sendable static func standardSeed(_ context: ModelContext) throws {
        let profile = UserProfile()
        profile.studentName = "Alex"
        profile.targetIBScore = 36
        profile.dailyGoal = 20
        profile.onboardingCompleted = true
        context.insert(profile)

        let bio = Subject(name: "Biology", level: "HL", accentColorHex: "#10B981")
        context.insert(bio)
        let eco = Subject(name: "Economics", level: "HL", accentColorHex: "#F59E0B")
        context.insert(eco)

        let card1 = StudyCard(topicName: "Cells and Cell Structure", subtopic: "Cell theory", front: "What is the cell theory?", back: "All living things are made of cells.", subject: bio)
        card1.proficiency = .developing
        let card2 = StudyCard(topicName: "Cells and Cell Structure", subtopic: "Prokaryotes", front: "What is a prokaryote?", back: "A cell without a nucleus.", subject: bio)
        card2.proficiency = .novice
        let card3 = StudyCard(topicName: "Genetics", subtopic: "", front: "Who is Mendel?", back: "Father of genetics.", subject: bio)
        card3.proficiency = .proficient
        context.insert(card1)
        context.insert(card2)
        context.insert(card3)

        let node = CurriculumNode(
            subjectName: "Biology", level: "HL", unitName: "Cells and Cell Structure",
            topicName: "Cells and Cell Structure", subtopicName: "Prokaryotic cell structure",
            catalogVersion: "2026.1", sourceTitle: "IB Biology", sourceURLString: "https://www.ibo.org/"
        )
        context.insert(node)

        let grade = Grade(component: "Paper 1", score: 5, teacherFeedback: "", assessmentTitle: "Term 1 Paper 1", subject: bio)
        context.insert(grade)

        let plan = StudyPlan(
            subjectName: "Biology", topicName: "Cells and Cell Structure",
            scheduledDate: Date().addingTimeInterval(86400), durationMinutes: 60
        )
        context.insert(plan)

        let memory = ARIAMemory(
            category: .weakTopics, content: "Struggles with cell membrane transport", subjectName: "Biology"
        )
        context.insert(memory)

        context.insert(UnitState(subjectName: "Biology", unitName: "Cells and Cell Structure", isTaught: false))
    }

    static func all() -> [ToolScenario] {
        var scenarios: [ToolScenario] = []
        studySessionScenarios(&scenarios)
        flashcardScenarios(&scenarios)
        gradeScenarios(&scenarios)
        masteryScenarios(&scenarios)
        profileScenarios(&scenarios)
        subjectScenarios(&scenarios)
        memoryScenarios(&scenarios)
        planDeleteScenarios(&scenarios)
        gateScenarios(&scenarios)
        extraScenarios(&scenarios)
        return scenarios
    }

    // MARK: - Extended edge-case matrix

    static func extraScenarios(_ out: inout [ToolScenario]) {
        out.append(ToolScenario(
            id: "assessment-01", name: "record_assessment calibrates subject and subunit evidence",
            userMessage: "Record my 18/20 Biology cell theory test as assessment evidence",
            modelJSON: #"[{"type":"record_assessment","subjectName":"Biology","assessmentTitle":"Cell theory test","assessmentType":"Test","category":"Summative","achievedPoints":18,"maxPoints":20,"topics":["Cells and Cell Structure"],"subtopics":["Prokaryotic cell structure"]}]"#,
            seed: standardSeed,
            verify: { ctx in
                let assessments = try ctx.fetch(FetchDescriptor<AcademicAssessment>())
                let mappings = try ctx.fetch(FetchDescriptor<AcademicAssessmentMapping>())
                guard let assessment = assessments.first else { return false }
                return assessment.normalizedScore == 0.9
                    && mappings.contains { $0.assessmentID == assessment.id && $0.status == .approved }
            },
            summaryContains: ["mastery will now use it"]
        ))

        out.append(ToolScenario(
            id: "assessment-02", name: "delete_assessment requires explicit request",
            userMessage: "Delete the Cell theory test assessment",
            modelJSON: #"[{"type":"delete_assessment","subjectName":"Biology","assessmentTitle":"Cell theory test"}]"#,
            seed: { ctx in
                try standardSeed(ctx)
                ctx.insert(AcademicAssessment(
                    sourceKey: "cell-test",
                    sourceFileName: "school.xlsx",
                    subjectName: "Biology",
                    courseLevel: "HL",
                    sourceClassLabel: "IB Biology HL",
                    assessmentDate: Date(),
                    title: "Cell theory test",
                    assessmentType: "Test",
                    category: "Summative",
                    status: "Graded",
                    percentage: 90
                ))
            },
            verify: { ctx in
                try ctx.fetch(FetchDescriptor<AcademicAssessment>()).isEmpty
            },
            summaryContains: ["Deleted"]
        ))

        out.append(ToolScenario(
            id: "chat-01", name: "delete_old_chats removes stale sessions and their messages",
            userMessage: "Delete ARIA chats older than 30 days",
            modelJSON: #"[{"type":"delete_old_chats","olderThanDays":30}]"#,
            seed: { ctx in
                try standardSeed(ctx)
                let oldSession = ARIAChatSession(title: "Old planning chat")
                oldSession.updatedAt = Date().addingTimeInterval(-60 * 86_400)
                ctx.insert(oldSession)
                ctx.insert(ChatMessage(role: .user, content: "Old message", sessionID: oldSession.id))
                let recentSession = ARIAChatSession(title: "Recent planning chat")
                ctx.insert(recentSession)
            },
            verify: { ctx in
                let sessions = try ctx.fetch(FetchDescriptor<ARIAChatSession>())
                let messages = try ctx.fetch(FetchDescriptor<ChatMessage>())
                return sessions.count == 1
                    && sessions.first?.title == "Recent planning chat"
                    && messages.isEmpty
            },
            summaryContains: ["Deleted 1 ARIA chat"]
        ))

        out.append(ToolScenario(
            id: "card-11", name: "create_flashcard with subtopic and skill",
            userMessage: "Add an Apply-level card on eukaryotic ultrastructure",
            modelJSON: #"[{"type":"create_flashcard","subjectName":"Biology","topics":["Cells and Cell Structure"],"subtopics":["Eukaryotic cell ultrastructure"],"frontText":"Role of mitochondria?","backText":"ATP production","cognitiveSkill":"Apply","difficulty":"Stretch"}]"#,
            seed: standardSeed,
            verify: { ctx in
                let bio = try ctx.fetch(FetchDescriptor<Subject>()).first { $0.name == "Biology" }!
                return bio.cards.contains { $0.front == "Role of mitochondria?" && $0.cognitiveSkill == .apply && $0.difficulty == .stretch }
            }
        ))

        out.append(ToolScenario(
            id: "card-12", name: "edit_flashcard by topic and subtopic",
            userMessage: "Update the prokaryote card back text",
            modelJSON: #"[{"type":"edit_flashcard","subjectName":"Biology","topics":["Cells and Cell Structure"],"subtopics":["Prokaryotes"],"backText":"Single-celled organism without a nucleus"}]"#,
            seed: standardSeed,
            verify: { ctx in
                let bio = try ctx.fetch(FetchDescriptor<Subject>()).first { $0.name == "Biology" }!
                return bio.cards.contains { $0.back == "Single-celled organism without a nucleus" }
            },
            summaryContains: ["Updated"]
        ))

        out.append(ToolScenario(
            id: "card-13", name: "delete_flashcards by search text",
            userMessage: "Delete the Mendel card",
            modelJSON: #"[{"type":"delete_flashcards","subjectName":"Biology","searchText":"Mendel"}]"#,
            seed: standardSeed,
            verify: { ctx in
                let bio = try ctx.fetch(FetchDescriptor<Subject>()).first { $0.name == "Biology" }!
                return bio.cards.count == 2 && !bio.cards.contains { $0.front.contains("Mendel") }
            },
            summaryContains: ["Deleted"]
        ))

        out.append(ToolScenario(
            id: "grade-11", name: "add_grade clamps score to 1-7",
            userMessage: "Record a Biology score of 9",
            modelJSON: #"[{"type":"add_grade","subjectName":"Biology","component":"Paper 3","score":9}]"#,
            seed: standardSeed,
            verify: { ctx in
                let bio = try ctx.fetch(FetchDescriptor<Subject>()).first { $0.name == "Biology" }!
                return bio.grades.contains { $0.component == "Paper 3" && $0.score == 7 }
            }
        ))

        out.append(ToolScenario(
            id: "grade-12", name: "edit_grade marks and weight",
            userMessage: "Update my Biology paper to 17/20 with 30% weight",
            modelJSON: #"[{"type":"edit_grade","subjectName":"Biology","component":"Paper 1","assessmentTitle":"Term 1 Paper 1","achievedPoints":17,"maxPoints":20,"weightPercent":30}]"#,
            seed: standardSeed,
            verify: { ctx in
                let bio = try ctx.fetch(FetchDescriptor<Subject>()).first { $0.name == "Biology" }!
                return bio.grades.contains { $0.achievedPoints == 17 && $0.maxPoints == 20 && $0.weightPercent == 30 }
            }
        ))

        out.append(ToolScenario(
            id: "grade-13", name: "delete_grade by search",
            userMessage: "Delete the grade called Term 1 Paper 1",
            modelJSON: #"[{"type":"delete_grade","subjectName":"Biology","searchText":"Term 1 Paper 1"}]"#,
            seed: standardSeed,
            verify: { ctx in
                let bio = try ctx.fetch(FetchDescriptor<Subject>()).first { $0.name == "Biology" }!
                return bio.grades.isEmpty
            }
        ))

        out.append(ToolScenario(
            id: "grade-14", name: "import_grades points format",
            userMessage: "Import these marks: 18/25 and 22/25",
            modelJSON: #"[{"type":"import_grades","subjectName":"Biology","notes":"Biology Paper 1 18/25\nBiology Paper 2 22/25"}]"#,
            seed: standardSeed,
            verify: { ctx in
                let bio = try ctx.fetch(FetchDescriptor<Subject>()).first { $0.name == "Biology" }!
                return bio.grades.contains { $0.achievedPoints == 18 && $0.maxPoints == 25 }
                    && bio.grades.contains { $0.achievedPoints == 22 && $0.maxPoints == 25 }
            },
            summaryContains: ["Imported"]
        ))

        out.append(ToolScenario(
            id: "mastery-09", name: "set_mastery multiple subtopics",
            userMessage: "Mark both prokaryote and eukaryote structure as mastered",
            modelJSON: #"[{"type":"set_mastery","subjectName":"Biology","topics":["Cells and Cell Structure"],"subtopics":["Prokaryotic cell structure","Eukaryotic cell ultrastructure"],"masteryLevel":"mastered"}]"#,
            seed: { ctx in
                try standardSeed(ctx)
                let existing = try ctx.fetch(FetchDescriptor<CurriculumNode>())
                guard existing.count == 1 else { return }
                contextInsertNode(ctx, subject: "Biology", level: "HL", topic: "Cells and Cell Structure", subtopic: "Eukaryotic cell ultrastructure")
            },
            verify: { ctx in
                let nodes = try ctx.fetch(FetchDescriptor<CurriculumNode>())
                return nodes.filter { $0.recordedProficiency == .mastered }.count == 2
            },
            summaryContains: ["mastered"]
        ))

        out.append(ToolScenario(
            id: "mastery-10", name: "set_mastery rejects unknown card id on real subject",
            userMessage: "Mark card with id XYZ as novice",
            modelJSON: #"[{"type":"set_mastery","subjectName":"Biology","cardID":"CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC","masteryLevel":"novice"}]"#,
            seed: cardIDSeed,
            expectedCompleted: 0, expectedFailed: 1,
            verify: { ctx in
                let bio = try ctx.fetch(FetchDescriptor<Subject>()).first { $0.name == "Biology" }!
                return bio.cards.count == 4
            }
        ))

        out.append(ToolScenario(
            id: "progress-05", name: "update_progress minutes without topic scope",
            userMessage: "I studied Biology for 25 minutes today",
            modelJSON: #"[{"type":"update_progress","subjectName":"Biology","minutesStudied":25}]"#,
            seed: standardSeed,
            verify: { ctx in
                let activities = try ctx.fetch(FetchDescriptor<StudyActivity>())
                return !activities.isEmpty && (activities.first?.minutesStudied ?? 0) >= 25
            }
        ))

        out.append(ToolScenario(
            id: "progress-06", name: "update_progress minutes and mastery together",
            userMessage: "Logged 30 min on prokaryotes and rate it developing",
            modelJSON: #"[{"type":"update_progress","subjectName":"Biology","topics":["Cells and Cell Structure"],"subtopics":["Prokaryotic cell structure"],"minutesStudied":30,"masteryLevel":"developing"}]"#,
            seed: standardSeed,
            verify: { ctx in
                let nodes = try ctx.fetch(FetchDescriptor<CurriculumNode>())
                let sessions = try ctx.fetch(FetchDescriptor<StudySession>())
                return nodes.first?.recordedProficiency == .developing && !sessions.isEmpty
            }
        ))

        out.append(ToolScenario(
            id: "profile-09", name: "update_profile rejects invalid notification hour",
            userMessage: "Set reminder at hour 99",
            modelJSON: #"[{"type":"update_profile","notificationHour":99}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            summaryContains: ["supported profile change"]
        ))

        out.append(ToolScenario(
            id: "profile-10", name: "update_profile rejects invalid intensity",
            userMessage: "Set intensity to turbo",
            modelJSON: #"[{"type":"update_profile","studyIntensity":"turbo"}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1
        ))

        out.append(ToolScenario(
            id: "subject-09", name: "update_subject empty change",
            userMessage: "Update my Biology subject settings",
            modelJSON: #"[{"type":"update_subject","subjectName":"Biology"}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            summaryContains: ["supported subject change"]
        ))

        out.append(ToolScenario(
            id: "subject-10", name: "update_subject accent colour",
            userMessage: "Make Biology teal",
            modelJSON: ##"[{"type":"update_subject","subjectName":"Biology","accentColorHex":"#14B8A6"}]"##,
            seed: standardSeed,
            verify: { ctx in
                let bio = try ctx.fetch(FetchDescriptor<Subject>()).first { $0.name == "Biology" }!
                return bio.accentColorHex == "#14B8A6"
            }
        ))

        out.append(ToolScenario(
            id: "memory-07", name: "save_memory tagged to subject",
            userMessage: "Remember Economics exam is in March",
            modelJSON: #"[{"type":"save_memory","subjectName":"Economics","memoryCategory":"grades","notes":"Economics exam in March"}]"#,
            seed: standardSeed,
            verify: { ctx in
                let memories = try ctx.fetch(FetchDescriptor<ARIAMemory>())
                return memories.contains { $0.subjectName == "Economics" && $0.category == .grades }
            }
        ))

        out.append(ToolScenario(
            id: "memory-08", name: "delete_memory no match",
            userMessage: "Delete my memory about the pyramids",
            modelJSON: #"[{"type":"delete_memory","searchText":"pyramids"}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            summaryContains: ["could not find a saved memory"]
        ))

        out.append(ToolScenario(
            id: "session-14", name: "create_study_session with subtopics",
            userMessage: "Create a session on prokaryotes",
            modelJSON: #"[{"type":"create_study_session","subjectName":"Biology","topics":["Cells and Cell Structure"],"subtopics":["Prokaryotic cell structure"],"durationMinutes":30}]"#,
            seed: standardSeed,
            verify: { ctx in
                let plans = try ctx.fetch(FetchDescriptor<StudyPlan>())
                return plans.contains { $0.subtopicName.contains("Prokaryotic cell structure") }
            }
        ))

        out.append(ToolScenario(
            id: "session-15", name: "complete_study_session clamps duration",
            userMessage: "Complete my Biology session, I did 300 minutes",
            modelJSON: #"[{"type":"complete_study_session","subjectName":"Biology","topics":["Cells and Cell Structure"],"durationMinutes":300}]"#,
            seed: standardSeed,
            verify: { ctx in
                let sessions = try ctx.fetch(FetchDescriptor<StudySession>())
                return sessions.contains { $0.duration / 60 >= 100 } // 180m clamp means >= 100m logged
            },
            summaryContains: ["Completed"]
        ))

        out.append(ToolScenario(
            id: "gate-07", name: "destructive blocked while non-destructive runs",
            userMessage: "Create a session and tell me about my weak cards",
            modelJSON: #"[{"type":"create_study_session","subjectName":"Biology","topics":["Genetics"]},{"type":"delete_flashcards","subjectName":"Biology","topics":["Genetics"]}]"#,
            seed: standardSeed,
            expectedCompleted: 1, expectedFailed: 1,
            verify: { ctx in
                let plans = try ctx.fetch(FetchDescriptor<StudyPlan>())
                let bio = try ctx.fetch(FetchDescriptor<Subject>()).first { $0.name == "Biology" }!
                return plans.count == 2 && bio.cards.count == 3
            },
            summaryContains: ["skipped"]
        ))

        out.append(ToolScenario(
            id: "gate-08", name: "two non-destructive actions both execute",
            userMessage: "Create two different study sessions",
            modelJSON: #"[{"type":"create_study_session","subjectName":"Biology","topics":["Genetics"]},{"type":"create_study_session","subjectName":"Economics","topics":["Demand"]}]"#,
            seed: standardSeed,
            expectedCompleted: 2, expectedFailed: 0,
            verify: { ctx in
                let plans = try ctx.fetch(FetchDescriptor<StudyPlan>())
                return plans.count == 3 && plans.contains { $0.subjectName == "Economics" }
            }
        ))

        out.append(ToolScenario(
            id: "gate-09", name: "delete_flashcards blocked when the learner says NOT to delete",
            userMessage: "Do not delete my Genetics flashcards",
            modelJSON: #"[{"type":"delete_flashcards","subjectName":"Biology","topics":["Genetics"]}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            verify: { ctx in
                let bio = try ctx.fetch(FetchDescriptor<Subject>()).first { $0.name == "Biology" }!
                return bio.cards.count == 3
            },
            summaryContains: ["skipped"]
        ))

        out.append(ToolScenario(
            id: "gate-10", name: "cancel_study_session blocked on a negated request",
            userMessage: "Please don't cancel my Biology session",
            modelJSON: #"[{"type":"cancel_study_session","subjectName":"Biology","topics":["Cells and Cell Structure"]}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            verify: { ctx in (try ctx.fetch(FetchDescriptor<StudyPlan>())).count == 1 },
            summaryContains: ["skipped"]
        ))

        out.append(ToolScenario(
            id: "gate-12", name: "a confirmed delete_memory runs while a non-destructive add_grade also executes",
            userMessage: "Delete the memory about cell membrane transport and record my new Paper 2 grade",
            modelJSON: #"[{"type":"delete_memory","searchText":"cell membrane transport"},{"type":"add_grade","subjectName":"Biology","component":"Paper 2","score":6}]"#,
            seed: standardSeed,
            expectedCompleted: 2, expectedFailed: 0,
            verify: { ctx in
                let memories = try ctx.fetch(FetchDescriptor<ARIAMemory>())
                let bio = try ctx.fetch(FetchDescriptor<Subject>()).first { $0.name == "Biology" }!
                return memories.isEmpty && bio.grades.contains { $0.component == "Paper 2" && $0.score == 6 }
            },
            summaryContains: ["Deleted"]
        ))

        out.append(ToolScenario(
            id: "cross-01", name: "profile persists across action context save",
            userMessage: "Set my target to 42",
            modelJSON: #"[{"type":"update_profile","targetIBScore":42}]"#,
            seed: standardSeed,
            verify: { ctx in
                let profile = try ctx.fetch(FetchDescriptor<UserProfile>()).first
                return profile?.targetIBScore == 42
            }
        ))

        out.append(ToolScenario(
            id: "cross-02", name: "subject card insertion persists",
            userMessage: "Create two cards in Biology",
            modelJSON: #"[{"type":"create_flashcard","subjectName":"Biology","topics":["Genetics"],"frontText":"Define gene","backText":"Unit of heredity"},{"type":"create_flashcard","subjectName":"Biology","topics":["Genetics"],"frontText":"Define allele","backText":"Gene variant"}]"#,
            seed: standardSeed,
            expectedCompleted: 2, expectedFailed: 0,
            verify: { ctx in
                let bio = try ctx.fetch(FetchDescriptor<Subject>()).first { $0.name == "Biology" }!
                return bio.cards.count == 5 && bio.cards.contains { $0.front == "Define gene" } && bio.cards.contains { $0.front == "Define allele" }
            }
        ))
    }

    private static func contextInsertNode(_ ctx: ModelContext, subject: String, level: String, topic: String, subtopic: String) {
        let node = CurriculumNode(
            subjectName: subject, level: level, unitName: topic, topicName: topic, subtopicName: subtopic,
            catalogVersion: "2026.1", sourceTitle: "IB Biology", sourceURLString: "https://www.ibo.org/"
        )
        ctx.insert(node)
    }

    // MARK: - Profile

    static func profileScenarios(_ out: inout [ToolScenario]) {
        out.append(ToolScenario(
            id: "profile-01", name: "update_profile target score",
            userMessage: "Set my IB target to 40/45",
            modelJSON: #"[{"type":"update_profile","targetIBScore":40}]"#,
            seed: standardSeed,
            verify: { ctx in
                let profile = try ctx.fetch(FetchDescriptor<UserProfile>()).first
                return profile?.targetIBScore == 40
            },
            summaryContains: ["target score"]
        ))

        out.append(ToolScenario(
            id: "profile-02", name: "update_profile rejects out-of-range score",
            userMessage: "Set my target to 60",
            modelJSON: #"[{"type":"update_profile","targetIBScore":60}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            summaryContains: ["supported profile change"]
        ))

        out.append(ToolScenario(
            id: "profile-03", name: "update_profile daily goal",
            userMessage: "Change my daily card goal to 35",
            modelJSON: #"[{"type":"update_profile","dailyGoal":35}]"#,
            seed: standardSeed,
            verify: { ctx in
                let profile = try ctx.fetch(FetchDescriptor<UserProfile>()).first
                return profile?.dailyGoal == 35
            },
            summaryContains: ["daily goal"]
        ))

        out.append(ToolScenario(
            id: "profile-04", name: "update_profile name",
            userMessage: "My name is Alex Rivera",
            modelJSON: #"[{"type":"update_profile","studentName":"Alex Rivera"}]"#,
            seed: standardSeed,
            verify: { ctx in
                let profile = try ctx.fetch(FetchDescriptor<UserProfile>()).first
                return profile?.studentName == "Alex Rivera"
            }
        ))

        out.append(ToolScenario(
            id: "profile-05", name: "update_profile study intensity",
            userMessage: "Set my study intensity to intensive",
            modelJSON: #"[{"type":"update_profile","studyIntensity":"Intensive"}]"#,
            seed: standardSeed,
            verify: { ctx in
                let profile = try ctx.fetch(FetchDescriptor<UserProfile>()).first
                return profile?.studyIntensity == .intensive
            }
        ))

        out.append(ToolScenario(
            id: "profile-06", name: "update_profile programme year",
            userMessage: "I'm in DP2 now",
            modelJSON: #"[{"type":"update_profile","ibYear":"DP2 (Year 2)"}]"#,
            seed: standardSeed,
            verify: { ctx in
                let profile = try ctx.fetch(FetchDescriptor<UserProfile>()).first
                return profile?.ibYear == .dp2
            }
        ))

        out.append(ToolScenario(
            id: "profile-07", name: "update_profile notification time",
            userMessage: "Remind me at 20:30",
            modelJSON: #"[{"type":"update_profile","notificationHour":20,"notificationMinute":30}]"#,
            seed: standardSeed,
            verify: { ctx in
                let profile = try ctx.fetch(FetchDescriptor<UserProfile>()).first
                return profile?.notificationHour == 20 && profile?.notificationMinute == 30
            }
        ))

        out.append(ToolScenario(
            id: "profile-08", name: "update_profile empty change",
            userMessage: "Update my profile please",
            modelJSON: #"[{"type":"update_profile"}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            summaryContains: ["supported profile change"]
        ))
    }

    // MARK: - Subjects

    static func subjectScenarios(_ out: inout [ToolScenario]) {
        out.append(ToolScenario(
            id: "subject-01", name: "create_subject happy path",
            userMessage: "Add Chemistry at SL to my subjects",
            modelJSON: ##"[{"type":"create_subject","name":"Chemistry","level":"SL","accentColorHex":"#3B82F6"}]"##,
            seed: standardSeed,
            verify: { ctx in
                let subjects = try ctx.fetch(FetchDescriptor<Subject>())
                return subjects.contains { $0.name == "Chemistry" && $0.level == "SL" }
            },
            summaryContains: ["Added"]
        ))

        out.append(ToolScenario(
            id: "subject-02", name: "create_subject duplicate rejected",
            userMessage: "Add Biology again",
            modelJSON: #"[{"type":"create_subject","name":"Biology","level":"HL"}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            verify: { ctx in (try ctx.fetch(FetchDescriptor<Subject>())).count == 2 },
            summaryContains: ["already exists"]
        ))

        out.append(ToolScenario(
            id: "subject-03", name: "create_subject no name",
            userMessage: "Add a subject",
            modelJSON: #"[{"type":"create_subject"}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            summaryContains: ["subject name"]
        ))

        out.append(ToolScenario(
            id: "subject-04", name: "update_subject rename",
            userMessage: "Rename Biology to Biology HL",
            modelJSON: #"[{"type":"update_subject","subjectName":"Biology","name":"Biology HL"}]"#,
            seed: standardSeed,
            verify: { ctx in
                let subjects = try ctx.fetch(FetchDescriptor<Subject>())
                return subjects.contains { $0.name == "Biology HL" }
            },
            summaryContains: ["Updated"]
        ))

        out.append(ToolScenario(
            id: "subject-05", name: "update_subject level",
            userMessage: "Change Economics to SL",
            modelJSON: #"[{"type":"update_subject","subjectName":"Economics","level":"SL"}]"#,
            seed: standardSeed,
            verify: { ctx in
                let subjects = try ctx.fetch(FetchDescriptor<Subject>())
                return subjects.first { $0.name == "Economics" }?.level == "SL"
            }
        ))

        out.append(ToolScenario(
            id: "subject-06", name: "update_subject unknown subject",
            userMessage: "Update my Physics subject",
            modelJSON: #"[{"type":"update_subject","subjectName":"Physics","level":"HL"}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1
        ))

        out.append(ToolScenario(
            id: "subject-07", name: "delete_subject confirmed removes cards and grades",
            userMessage: "Delete Economics please",
            modelJSON: #"[{"type":"delete_subject","subjectName":"Economics"}]"#,
            seed: standardSeed,
            verify: { ctx in
                let subjects = try ctx.fetch(FetchDescriptor<Subject>())
                return !subjects.contains { $0.name == "Economics" }
            },
            summaryContains: ["Deleted"]
        ))

        out.append(ToolScenario(
            id: "subject-08", name: "delete_subject blocked without confirmation",
            userMessage: "What is Economics about?",
            modelJSON: #"[{"type":"delete_subject","subjectName":"Economics"}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            verify: { ctx in
                let subjects = try ctx.fetch(FetchDescriptor<Subject>())
                return subjects.contains { $0.name == "Economics" }
            },
            summaryContains: ["skipped"]
        ))
    }

    // MARK: - Memory

    static func memoryScenarios(_ out: inout [ToolScenario]) {
        out.append(ToolScenario(
            id: "memory-01", name: "save_memory happy path",
            userMessage: "Remember that I prefer studying in the morning",
            modelJSON: #"[{"type":"save_memory","memoryCategory":"studyHabits","notes":"Prefers studying in the morning"}]"#,
            seed: standardSeed,
            verify: { ctx in
                let memories = try ctx.fetch(FetchDescriptor<ARIAMemory>())
                return memories.contains { $0.content.contains("morning") }
            },
            summaryContains: ["Saved"]
        ))

        out.append(ToolScenario(
            id: "memory-02", name: "save_memory requires content",
            userMessage: "Remember something",
            modelJSON: #"[{"type":"save_memory"}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            summaryContains: ["note content"]
        ))

        out.append(ToolScenario(
            id: "memory-03", name: "edit_memory content",
            userMessage: "Update my memory to say I struggle with DNA replication",
            modelJSON: #"[{"type":"edit_memory","searchText":"cell membrane transport","notes":"Struggles with DNA replication"}]"#,
            seed: standardSeed,
            verify: { ctx in
                let memories = try ctx.fetch(FetchDescriptor<ARIAMemory>())
                return memories.contains { $0.content.contains("DNA replication") }
            },
            summaryContains: ["Updated"]
        ))

        out.append(ToolScenario(
            id: "memory-04", name: "edit_memory no match",
            userMessage: "Update my memory about llamas",
            modelJSON: #"[{"type":"edit_memory","searchText":"llamas","notes":"New content"}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            summaryContains: ["could not find a saved memory"]
        ))

        out.append(ToolScenario(
            id: "memory-05", name: "delete_memory confirmed",
            userMessage: "Delete the memory about cell membrane transport",
            modelJSON: #"[{"type":"delete_memory","searchText":"cell membrane transport"}]"#,
            seed: standardSeed,
            verify: { ctx in
                let memories = try ctx.fetch(FetchDescriptor<ARIAMemory>())
                return memories.isEmpty
            },
            summaryContains: ["Deleted"]
        ))

        out.append(ToolScenario(
            id: "memory-06", name: "delete_memory blocked without confirmation",
            userMessage: "Summarise my memories for me",
            modelJSON: #"[{"type":"delete_memory","searchText":"cell membrane transport"}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            verify: { ctx in (try ctx.fetch(FetchDescriptor<ARIAMemory>())).count == 1 },
            summaryContains: ["skipped"]
        ))
    }

    // MARK: - Plan delete

    static func planDeleteScenarios(_ out: inout [ToolScenario]) {
        out.append(ToolScenario(
            id: "plan-01", name: "delete_study_plan confirmed",
            userMessage: "Delete my Biology study session",
            modelJSON: #"[{"type":"delete_study_plan","subjectName":"Biology","topics":["Cells and Cell Structure"]}]"#,
            seed: standardSeed,
            verify: { ctx in (try ctx.fetch(FetchDescriptor<StudyPlan>())).isEmpty },
            summaryContains: ["Deleted"]
        ))

        out.append(ToolScenario(
            id: "plan-02", name: "delete_study_plan blocked without confirmation",
            userMessage: "Show me my study sessions",
            modelJSON: #"[{"type":"delete_study_plan","subjectName":"Biology","topics":["Cells and Cell Structure"]}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            verify: { ctx in (try ctx.fetch(FetchDescriptor<StudyPlan>())).count == 1 },
            summaryContains: ["skipped"]
        ))

        out.append(ToolScenario(
            id: "plan-03", name: "delete_study_plan no match",
            userMessage: "Delete my German study session",
            modelJSON: #"[{"type":"delete_study_plan","subjectName":"German"}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            summaryContains: ["could not find"]
        ))
    }

    // MARK: - Gates and scoping

    static func gateScenarios(_ out: inout [ToolScenario]) {
        out.append(ToolScenario(
            id: "gate-01", name: "empty plan returns no-op",
            userMessage: "What should I study today?",
            modelJSON: "[]",
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 0,
            verify: { ctx in
                let subjects = try ctx.fetch(FetchDescriptor<Subject>())
                let plans = try ctx.fetch(FetchDescriptor<StudyPlan>())
                return subjects.count == 2 && plans.count == 1
            }
        ))

        out.append(ToolScenario(
            id: "gate-02", name: "malformed JSON is ignored safely",
            userMessage: "Plan something",
            modelJSON: "this is not json",
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 0,
            verify: { ctx in (try ctx.fetch(FetchDescriptor<StudyPlan>())).count == 1 }
        ))

        out.append(ToolScenario(
            id: "gate-03", name: "dedupes identical actions",
            userMessage: "Create two identical Biology sessions",
            modelJSON: #"[{"type":"create_study_session","subjectName":"Biology","topics":["Genetics"]},{"type":"create_study_session","subjectName":"Biology","topics":["Genetics"]}]"#,
            seed: standardSeed,
            expectedCompleted: 1, expectedFailed: 0,
            verify: { ctx in (try ctx.fetch(FetchDescriptor<StudyPlan>())).count == 2 }
        ))

        out.append(ToolScenario(
            id: "gate-04", name: "caps at two actions and reports truncation",
            userMessage: "Create three sessions for me",
            modelJSON: #"[{"type":"create_study_session","subjectName":"Biology","topics":["Genetics"]},{"type":"create_study_session","subjectName":"Biology","topics":["Cells and Cell Structure"]},{"type":"create_study_session","subjectName":"Economics","topics":["Demand"]}]"#,
            seed: standardSeed,
            expectedCompleted: 2, expectedFailed: 0,
            verify: { ctx in (try ctx.fetch(FetchDescriptor<StudyPlan>())).count == 3 },
            summaryContains: ["limited this turn"]
        ))

        out.append(ToolScenario(
            id: "gate-05", name: "unknown action type is skipped silently",
            userMessage: "Do the special action",
            modelJSON: #"[{"type":"melt_down_reactor","subjectName":"Biology"}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 0,
            verify: { ctx in
                let subjects = try ctx.fetch(FetchDescriptor<Subject>())
                return subjects.count == 2
            }
        ))

        out.append(ToolScenario(
            id: "gate-06", name: "single subject fallback resolution",
            userMessage: "Create a session for cells",
            modelJSON: #"[{"type":"create_study_session","topics":["Genetics"]}]"#,
            seed: { ctx in
                try standardSeed(ctx)
                let subjects = try ctx.fetch(FetchDescriptor<Subject>())
                for subject in subjects where subject.name != "Biology" {
                    ctx.delete(subject)
                }
            },
            verify: { ctx in
                let plans = try ctx.fetch(FetchDescriptor<StudyPlan>())
                return plans.contains { $0.subjectName == "Biology" && $0.topicName.contains("Genetics") }
            }
        ))
    }

    // MARK: - Mastery / progress / unit state

    static let knownCardUUID = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"

    @Sendable static func cardIDSeed(_ context: ModelContext) throws {
        try standardSeed(context)
        let subjects = try context.fetch(FetchDescriptor<Subject>())
        let bio = subjects.first { $0.name == "Biology" }!
        let card = StudyCard(topicName: "Cell Division", subtopic: "", front: "Mitosis?", back: "Nuclear division", subject: bio)
        card.id = UUID(uuidString: knownCardUUID)!
        context.insert(card)
    }

    static func masteryScenarios(_ out: inout [ToolScenario]) {
        out.append(ToolScenario(
            id: "mastery-01", name: "set_mastery on curriculum node",
            userMessage: "I have mastered prokaryotic cell structure in Biology",
            modelJSON: #"[{"type":"set_mastery","subjectName":"Biology","topics":["Cells and Cell Structure"],"subtopics":["Prokaryotic cell structure"],"masteryLevel":"mastered","notes":"Confident in prokaryote structure"}]"#,
            seed: standardSeed,
            verify: { ctx in
                let nodes = try ctx.fetch(FetchDescriptor<CurriculumNode>())
                return nodes.contains { $0.recordedProficiency == .mastered && $0.masterySource == "ARIA" }
            },
            summaryContains: ["mastered"]
        ))

        out.append(ToolScenario(
            id: "mastery-02", name: "set_mastery rejects whole-subject mastery",
            userMessage: "Mark all of Biology as proficient",
            modelJSON: #"[{"type":"set_mastery","subjectName":"Biology","masteryLevel":"proficient"}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            summaryContains: ["specific real topic"]
        ))

        out.append(ToolScenario(
            id: "mastery-03", name: "set_mastery rejects invented topic",
            userMessage: "Mark Pseudoscience topic as mastered",
            modelJSON: #"[{"type":"set_mastery","subjectName":"Biology","topics":["Pseudoscience"],"masteryLevel":"mastered"}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            summaryContains: ["could not match"]
        ))

        out.append(ToolScenario(
            id: "mastery-04", name: "set_mastery rejects bad level",
            userMessage: "Mark Cell theory as legendary",
            modelJSON: #"[{"type":"set_mastery","subjectName":"Biology","topics":["Cells and Cell Structure"],"subtopics":["Cell theory"],"masteryLevel":"legendary"}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            summaryContains: ["unsupported mastery"]
        ))

        out.append(ToolScenario(
            id: "mastery-05", name: "set_mastery clear",
            userMessage: "Clear my mastery on prokaryotic cell structure",
            modelJSON: #"[{"type":"set_mastery","subjectName":"Biology","topics":["Cells and Cell Structure"],"subtopics":["Prokaryotic cell structure"],"clearMastery":true}]"#,
            seed: { ctx in
                try standardSeed(ctx)
                let nodes = try ctx.fetch(FetchDescriptor<CurriculumNode>())
                nodes.first?.recordedProficiency = .proficient
            },
            verify: { ctx in
                let nodes = try ctx.fetch(FetchDescriptor<CurriculumNode>())
                return nodes.first?.recordedProficiency == nil
            },
            summaryContains: ["Cleared"]
        ))

        out.append(ToolScenario(
            id: "mastery-06", name: "set_mastery on individual card by id",
            userMessage: "Mark the mitosis card as mastered",
            modelJSON: #"[{"type":"set_mastery","subjectName":"Biology","cardID":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA","masteryLevel":"mastered"}]"#,
            seed: cardIDSeed,
            verify: { ctx in
                let subjects = try ctx.fetch(FetchDescriptor<Subject>())
                let bio = subjects.first { $0.name == "Biology" }!
                let card = bio.cards.first { $0.id == UUID(uuidString: knownCardUUID) }
                return card?.proficiency == .mastered
            },
            summaryContains: ["mastered"]
        ))

        out.append(ToolScenario(
            id: "mastery-07", name: "set_mastery card not found",
            userMessage: "Mark card BBBBBBBB as mastered",
            modelJSON: #"[{"type":"set_mastery","subjectName":"Biology","cardID":"BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB","masteryLevel":"mastered"}]"#,
            seed: cardIDSeed,
            expectedCompleted: 0, expectedFailed: 1
        ))

        out.append(ToolScenario(
            id: "mastery-08", name: "set_mastery unknown subject",
            userMessage: "Mark Chemistry as mastered",
            modelJSON: #"[{"type":"set_mastery","subjectName":"Chemistry","topics":["Bonding"],"masteryLevel":"mastered"}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            summaryContains: ["could not find the subject"]
        ))

        out.append(ToolScenario(
            id: "progress-01", name: "update_progress logs minutes and XP",
            userMessage: "I studied Biology Cells and Cell Structure for 40 minutes",
            modelJSON: #"[{"type":"update_progress","subjectName":"Biology","topics":["Cells and Cell Structure"],"minutesStudied":40}]"#,
            seed: standardSeed,
            verify: { ctx in
                let sessions = try ctx.fetch(FetchDescriptor<StudySession>())
                let profile = try ctx.fetch(FetchDescriptor<UserProfile>()).first
                let activities = try ctx.fetch(FetchDescriptor<StudyActivity>())
                return !sessions.isEmpty
                    && (profile?.totalXP ?? 0) > 0
                    && !activities.isEmpty
                    && (activities.first?.minutesStudied ?? 0) >= 40
            },
            summaryContains: ["Updated"]
        ))

        out.append(ToolScenario(
            id: "progress-02", name: "update_progress with mastery level",
            userMessage: "Rate myself as developing on prokaryotic cell structure",
            modelJSON: #"[{"type":"update_progress","subjectName":"Biology","topics":["Cells and Cell Structure"],"subtopics":["Prokaryotic cell structure"],"masteryLevel":"developing"}]"#,
            seed: standardSeed,
            verify: { ctx in
                let nodes = try ctx.fetch(FetchDescriptor<CurriculumNode>())
                return nodes.first?.recordedProficiency == .developing
            },
            summaryContains: ["Updated"]
        ))

        out.append(ToolScenario(
            id: "progress-03", name: "update_progress empty payload",
            userMessage: "Update my Biology progress",
            modelJSON: #"[{"type":"update_progress","subjectName":"Biology"}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            summaryContains: ["mastery level or minutes"]
        ))

        out.append(ToolScenario(
            id: "progress-04", name: "update_progress rejects invented subtopic",
            userMessage: "Log 10 minutes studying imaginary stuff in Biology",
            modelJSON: #"[{"type":"update_progress","subjectName":"Biology","topics":["Cells and Cell Structure"],"subtopics":["Quantum bioflux"],"minutesStudied":10}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1
        ))

        out.append(ToolScenario(
            id: "unit-01", name: "update_unit_state taught",
            userMessage: "Mark the Cells and Cell Structure unit as taught",
            modelJSON: #"[{"type":"update_unit_state","subjectName":"Biology","unitName":"Cells and Cell Structure","isTaught":true}]"#,
            seed: standardSeed,
            verify: { ctx in
                let states = try ctx.fetch(FetchDescriptor<UnitState>())
                return states.contains { $0.unitName == "Cells and Cell Structure" && $0.isTaught }
            },
            summaryContains: ["taught"]
        ))

        out.append(ToolScenario(
            id: "unit-02", name: "update_unit_state not taught",
            userMessage: "Mark the Genetics unit as not yet taught",
            modelJSON: #"[{"type":"update_unit_state","subjectName":"Biology","unitName":"Genetics","isTaught":false}]"#,
            seed: standardSeed,
            verify: { ctx in
                let states = try ctx.fetch(FetchDescriptor<UnitState>())
                return states.contains { $0.unitName == "Genetics" && !$0.isTaught }
            }
        ))

        out.append(ToolScenario(
            id: "unit-03", name: "update_unit_state no unit name",
            userMessage: "Mark the unit as taught",
            modelJSON: #"[{"type":"update_unit_state","subjectName":"Biology"}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            summaryContains: ["unit name"]
        ))
    }


    static func gradeScenarios(_ out: inout [ToolScenario]) {
        out.append(ToolScenario(
            id: "grade-01", name: "add_grade with score",
            userMessage: "Record my Paper 2 Biology score of 6",
            modelJSON: #"[{"type":"add_grade","subjectName":"Biology","component":"Paper 2","score":6,"assessmentTitle":"Term 2 Paper 2"}]"#,
            seed: standardSeed,
            verify: { ctx in
                let subjects = try ctx.fetch(FetchDescriptor<Subject>())
                let bio = subjects.first { $0.name == "Biology" }!
                return bio.grades.contains { $0.component == "Paper 2" && $0.score == 6 }
            },
            summaryContains: ["Recorded"]
        ))

        out.append(ToolScenario(
            id: "grade-02", name: "add_grade with points",
            userMessage: "Add my IA grade: 21/24 for Biology",
            modelJSON: #"[{"type":"add_grade","subjectName":"Biology","component":"IA","achievedPoints":21,"maxPoints":24,"weightPercent":20}]"#,
            seed: standardSeed,
            verify: { ctx in
                let subjects = try ctx.fetch(FetchDescriptor<Subject>())
                let bio = subjects.first { $0.name == "Biology" }!
                return bio.grades.contains { $0.component == "IA" && $0.achievedPoints == 21 && $0.maxPoints == 24 }
            }
        ))

        out.append(ToolScenario(
            id: "grade-03", name: "add_grade with predicted grade",
            userMessage: "Add a predicted grade of 7 for my Biology paper",
            modelJSON: #"[{"type":"add_grade","subjectName":"Biology","component":"Paper 2","score":6,"predictedGrade":7}]"#,
            seed: standardSeed,
            verify: { ctx in
                let subjects = try ctx.fetch(FetchDescriptor<Subject>())
                let bio = subjects.first { $0.name == "Biology" }!
                return bio.grades.contains { $0.predictedGrade == 7 }
            }
        ))

        out.append(ToolScenario(
            id: "grade-04", name: "add_grade unknown subject",
            userMessage: "Add a grade for Computer Science",
            modelJSON: #"[{"type":"add_grade","subjectName":"Computer Science","component":"Paper 1","score":5}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1
        ))

        out.append(ToolScenario(
            id: "grade-05", name: "edit_grade score",
            userMessage: "Change my Biology Term 1 Paper 1 grade to 6",
            modelJSON: #"[{"type":"edit_grade","subjectName":"Biology","component":"Paper 1","assessmentTitle":"Term 1 Paper 1","score":6}]"#,
            seed: standardSeed,
            verify: { ctx in
                let subjects = try ctx.fetch(FetchDescriptor<Subject>())
                let bio = subjects.first { $0.name == "Biology" }!
                return bio.grades.contains { $0.score == 6 && $0.component == "Paper 1" }
            },
            summaryContains: ["Updated"]
        ))

        out.append(ToolScenario(
            id: "grade-06", name: "edit_grade predicted grade",
            userMessage: "Update the predicted grade to 7 on my Biology paper",
            modelJSON: #"[{"type":"edit_grade","subjectName":"Biology","component":"Paper 1","predictedGrade":7}]"#,
            seed: standardSeed,
            verify: { ctx in
                let subjects = try ctx.fetch(FetchDescriptor<Subject>())
                let bio = subjects.first { $0.name == "Biology" }!
                return bio.grades.contains { $0.predictedGrade == 7 }
            }
        ))

        out.append(ToolScenario(
            id: "grade-07", name: "edit_grade no match",
            userMessage: "Change my chemistry grade to 5",
            modelJSON: #"[{"type":"edit_grade","subjectName":"Biology","component":"Paper 9","score":5}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            summaryContains: ["could not find a grade"]
        ))

        out.append(ToolScenario(
            id: "grade-08", name: "delete_grade confirmed",
            userMessage: "Delete my Biology Term 1 Paper 1 grade",
            modelJSON: #"[{"type":"delete_grade","subjectName":"Biology","component":"Paper 1","assessmentTitle":"Term 1 Paper 1"}]"#,
            seed: standardSeed,
            verify: { ctx in
                let subjects = try ctx.fetch(FetchDescriptor<Subject>())
                let bio = subjects.first { $0.name == "Biology" }!
                return bio.grades.isEmpty
            },
            summaryContains: ["Deleted"]
        ))

        out.append(ToolScenario(
            id: "grade-09", name: "delete_grade blocked without confirmation",
            userMessage: "What does my Biology grade average look like?",
            modelJSON: #"[{"type":"delete_grade","subjectName":"Biology","component":"Paper 1"}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            verify: { ctx in
                let subjects = try ctx.fetch(FetchDescriptor<Subject>())
                let bio = subjects.first { $0.name == "Biology" }!
                return bio.grades.count == 1
            },
            summaryContains: ["skipped"]
        ))

        out.append(ToolScenario(
            id: "grade-10", name: "import_grades paste",
            userMessage: "Import my grades: Biology Paper 1 grade 6, Paper 2 grade 5",
            modelJSON: #"[{"type":"import_grades","subjectName":"Biology","notes":"Biology Paper 1 grade: 6\nBiology Paper 2 grade: 5"}]"#,
            seed: standardSeed,
            verify: { ctx in
                let subjects = try ctx.fetch(FetchDescriptor<Subject>())
                let bio = subjects.first { $0.name == "Biology" }!
                return bio.grades.count >= 2
            },
            summaryContains: ["Imported"]
        ))

        out.append(ToolScenario(
            id: "grade-15", name: "add_grade is non-destructive and runs without a consent phrase",
            userMessage: "Give me a snapshot of my Biology progress",
            modelJSON: #"[{"type":"add_grade","subjectName":"Biology","component":"Paper 3","score":4}]"#,
            seed: standardSeed,
            verify: { ctx in
                let subjects = try ctx.fetch(FetchDescriptor<Subject>())
                let bio = subjects.first { $0.name == "Biology" }!
                return bio.grades.contains { $0.component == "Paper 3" && $0.score == 4 }
            },
            summaryContains: ["Recorded"]
        ))

        out.append(ToolScenario(
            id: "grade-16", name: "edit_grade is non-destructive and runs without a consent phrase",
            userMessage: "What should I review next?",
            modelJSON: #"[{"type":"edit_grade","subjectName":"Biology","component":"Paper 1","assessmentTitle":"Term 1 Paper 1","score":6}]"#,
            seed: standardSeed,
            verify: { ctx in
                let subjects = try ctx.fetch(FetchDescriptor<Subject>())
                let bio = subjects.first { $0.name == "Biology" }!
                return bio.grades.contains { $0.component == "Paper 1" && $0.score == 6 }
            },
            summaryContains: ["Updated"]
        ))
    }


    static func flashcardScenarios(_ out: inout [ToolScenario]) {
        out.append(ToolScenario(
            id: "card-01", name: "create_flashcard happy path",
            userMessage: "Create a flashcard for Biology on Genetics: front 'What is an allele?' back 'A variant of a gene'",
            modelJSON: #"[{"type":"create_flashcard","subjectName":"Biology","topics":["Genetics"],"frontText":"What is an allele?","backText":"A variant of a gene","hint":"Think of variants","difficulty":"Exam","cognitiveSkill":"Recall"}]"#,
            seed: standardSeed,
            verify: { ctx in
                let subjects = try ctx.fetch(FetchDescriptor<Subject>())
                let bio = subjects.first { $0.name == "Biology" }!
                let newCard = bio.cards.first { $0.front == "What is an allele?" }
                return newCard != nil && newCard?.difficulty == .exam && newCard?.cognitiveSkill == .recall && newCard?.hint == "Think of variants"
            },
            summaryContains: ["Created"]
        ))

        out.append(ToolScenario(
            id: "card-02", name: "create_flashcard defaults topic from existing cards",
            userMessage: "Add a card: front 'Define enzyme' back 'A biological catalyst'",
            modelJSON: #"[{"type":"create_flashcard","subjectName":"Biology","frontText":"Define enzyme","backText":"A biological catalyst"}]"#,
            seed: standardSeed,
            verify: { ctx in
                let subjects = try ctx.fetch(FetchDescriptor<Subject>())
                let bio = subjects.first { $0.name == "Biology" }!
                return bio.cards.contains { $0.front == "Define enzyme" && $0.topicName == "Cells and Cell Structure" }
            }
        ))

        out.append(ToolScenario(
            id: "card-03", name: "create_flashcard rejects missing back text",
            userMessage: "Create a card with only a front",
            modelJSON: #"[{"type":"create_flashcard","subjectName":"Biology","frontText":"Only a front"}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            verify: { ctx in
                let subjects = try ctx.fetch(FetchDescriptor<Subject>())
                let bio = subjects.first { $0.name == "Biology" }!
                return bio.cards.count == 3
            },
            summaryContains: ["both front and back"]
        ))

        out.append(ToolScenario(
            id: "card-04", name: "create_flashcard rejects unknown subject",
            userMessage: "Make a flashcard for Philosophy",
            modelJSON: #"[{"type":"create_flashcard","subjectName":"Philosophy","frontText":"Q","backText":"A"}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1
        ))

        out.append(ToolScenario(
            id: "card-05", name: "edit_flashcard by search text",
            userMessage: "Update the prokaryote card to say 'A cell lacking a membrane-bound nucleus'",
            modelJSON: #"[{"type":"edit_flashcard","subjectName":"Biology","searchText":"prokaryote","backText":"A cell lacking a membrane-bound nucleus"}]"#,
            seed: standardSeed,
            verify: { ctx in
                let subjects = try ctx.fetch(FetchDescriptor<Subject>())
                let bio = subjects.first { $0.name == "Biology" }!
                return bio.cards.contains { $0.back == "A cell lacking a membrane-bound nucleus" }
            },
            summaryContains: ["Updated"]
        ))

        out.append(ToolScenario(
            id: "card-06", name: "edit_flashcard marks custom",
            userMessage: "Change the front of the Mendel card to 'Who is Gregor Mendel?'",
            modelJSON: #"[{"type":"edit_flashcard","subjectName":"Biology","searchText":"Mendel","frontText":"Who is Gregor Mendel?"}]"#,
            seed: standardSeed,
            verify: { ctx in
                let subjects = try ctx.fetch(FetchDescriptor<Subject>())
                let bio = subjects.first { $0.name == "Biology" }!
                guard let card = bio.cards.first(where: { $0.front == "Who is Gregor Mendel?" }) else { return false }
                return card.isCustom && card.generationSource == "ARIA Edited"
            }
        ))

        out.append(ToolScenario(
            id: "card-07", name: "edit_flashcard no match",
            userMessage: "Update the card about quantum mechanics",
            modelJSON: #"[{"type":"edit_flashcard","subjectName":"Biology","searchText":"quantum mechanics","frontText":"X"}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            summaryContains: ["could not find a flashcard"]
        ))

        out.append(ToolScenario(
            id: "card-08", name: "delete_flashcards confirmed by topic",
            userMessage: "Delete all my Genetics flashcards",
            modelJSON: #"[{"type":"delete_flashcards","subjectName":"Biology","topics":["Genetics"]}]"#,
            seed: standardSeed,
            verify: { ctx in
                let subjects = try ctx.fetch(FetchDescriptor<Subject>())
                let bio = subjects.first { $0.name == "Biology" }!
                return bio.cards.count == 2 && !bio.cards.contains { $0.topicName == "Genetics" }
            },
            summaryContains: ["Deleted"]
        ))

        out.append(ToolScenario(
            id: "card-09", name: "delete_flashcards blocked without confirmation",
            userMessage: "Can you explain my Biology cards to me?",
            modelJSON: #"[{"type":"delete_flashcards","subjectName":"Biology","topics":["Genetics"]}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            verify: { ctx in
                let subjects = try ctx.fetch(FetchDescriptor<Subject>())
                let bio = subjects.first { $0.name == "Biology" }!
                return bio.cards.count == 3
            },
            summaryContains: ["skipped"]
        ))

        out.append(ToolScenario(
            id: "card-10", name: "delete_flashcards no match",
            userMessage: "Delete the flashcard about astrophysics",
            modelJSON: #"[{"type":"delete_flashcards","subjectName":"Biology","searchText":"astrophysics"}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            summaryContains: ["could not find flashcards"]
        ))
    }

    // MARK: - Study sessions and plans

    static func studySessionScenarios(_ out: inout [ToolScenario]) {
        out.append(ToolScenario(
            id: "session-01", name: "create_study_session happy path",
            userMessage: "Create a study session for Biology on Cells and Cell Structure tomorrow at 4pm",
            modelJSON: #"[{"type":"create_study_session","subjectName":"Biology","topics":["Cells and Cell Structure"],"scheduledAt":"2026-08-10T16:00:00Z","durationMinutes":45,"notes":"Focus on cell theory"}]"#,
            seed: standardSeed,
            verify: { ctx in
                let plans = try ctx.fetch(FetchDescriptor<StudyPlan>())
                return plans.count == 2 && plans.contains { $0.durationMinutes == 45 && $0.subjectName == "Biology" }
            },
            summaryContains: ["Created"]
        ))

        out.append(ToolScenario(
            id: "session-02", name: "create_study_session clamps long duration",
            userMessage: "Schedule a 500 minute Biology session",
            modelJSON: #"[{"type":"create_study_session","subjectName":"Biology","topics":["Genetics"],"durationMinutes":500}]"#,
            seed: standardSeed,
            verify: { ctx in
                let plans = try ctx.fetch(FetchDescriptor<StudyPlan>())
                return plans.contains { $0.durationMinutes == 180 }
            }
        ))

        out.append(ToolScenario(
            id: "session-03", name: "create_study_session rejects unknown subject",
            userMessage: "Make a study session for Alchemy",
            modelJSON: #"[{"type":"create_study_session","subjectName":"Alchemy","topics":["Anything"]}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            verify: { ctx in (try ctx.fetch(FetchDescriptor<StudyPlan>())).count == 1 },
            summaryContains: ["could not find"]
        ))

        out.append(ToolScenario(
            id: "session-04", name: "create_study_session rejects non-curriculum topic",
            userMessage: "Create a session for Biology on Fake Topic 9000",
            modelJSON: #"[{"type":"create_study_session","subjectName":"Biology","topics":["Fake Topic 9000"]}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            summaryContains: ["valid topic"]
        ))

        out.append(ToolScenario(
            id: "session-05", name: "assign_weakest_study_session",
            userMessage: "Assign me a study session on my weakest Biology topic",
            modelJSON: #"[{"type":"assign_weakest_study_session","subjectName":"Biology","durationMinutes":50}]"#,
            seed: standardSeed,
            verify: { ctx in (try ctx.fetch(FetchDescriptor<StudyPlan>())).count == 2 },
            summaryContains: ["weakest"]
        ))

        out.append(ToolScenario(
            id: "session-06", name: "assign_weakest_study_session unknown subject",
            userMessage: "Assign a session for Physics",
            modelJSON: #"[{"type":"assign_weakest_study_session","subjectName":"Physics"}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1
        ))

        out.append(ToolScenario(
            id: "session-07", name: "create_review_session",
            userMessage: "Set up a review session for my Biology cards",
            modelJSON: #"[{"type":"create_review_session","subjectName":"Biology","topics":["Cells and Cell Structure"],"durationMinutes":30}]"#,
            seed: standardSeed,
            verify: { ctx in
                let plans = try ctx.fetch(FetchDescriptor<StudyPlan>())
                let subjects = try ctx.fetch(FetchDescriptor<Subject>())
                let biology = subjects.first { $0.name == "Biology" }
                let queued = biology?.cards.filter { $0.nextReviewDate <= Date() } ?? []
                return !plans.contains(where: \.isFollowUpReview) && !queued.isEmpty
            },
            summaryContains: ["review"]
        ))

        out.append(ToolScenario(
            id: "session-08", name: "reschedule_study_session",
            userMessage: "Move my Biology session to Wednesday 6pm",
            modelJSON: #"[{"type":"reschedule_study_session","subjectName":"Biology","scheduledAt":"2026-08-12T18:00:00Z"}]"#,
            seed: standardSeed,
            verify: { ctx in
                let plans = try ctx.fetch(FetchDescriptor<StudyPlan>())
                guard let plan = plans.first(where: { $0.subjectName == "Biology" && $0.topicName.contains("Cells and Cell Structure") }) else { return false }
                let formatter = ISO8601DateFormatter()
                return formatter.string(from: plan.scheduledDate).hasPrefix("2026-08-12T18:00:00")
            },
            summaryContains: ["Rescheduled"]
        ))

        out.append(ToolScenario(
            id: "session-09", name: "reschedule_study_session no match",
            userMessage: "Reschedule my French session",
            modelJSON: #"[{"type":"reschedule_study_session","subjectName":"French","scheduledAt":"2026-08-12T18:00:00Z"}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            summaryContains: ["could not find"]
        ))

        out.append(ToolScenario(
            id: "session-10", name: "complete_study_session logs work",
            userMessage: "Mark my Biology session complete, I worked 30 minutes",
            modelJSON: #"[{"type":"complete_study_session","subjectName":"Biology","topics":["Cells and Cell Structure"],"durationMinutes":30}]"#,
            seed: standardSeed,
            verify: { ctx in
                let plans = try ctx.fetch(FetchDescriptor<StudyPlan>())
                let sessions = try ctx.fetch(FetchDescriptor<StudySession>())
                let profile = try ctx.fetch(FetchDescriptor<UserProfile>()).first
                return plans.first(where: { $0.subjectName == "Biology" })?.isCompleted == true
                    && !sessions.isEmpty
                    && (profile?.totalXP ?? 0) > 0
            },
            summaryContains: ["Completed"]
        ))

        out.append(ToolScenario(
            id: "session-11", name: "complete_study_session no match",
            userMessage: "Complete my Chemistry session",
            modelJSON: #"[{"type":"complete_study_session","subjectName":"Chemistry"}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1
        ))

        out.append(ToolScenario(
            id: "session-12", name: "cancel_study_session confirmed",
            userMessage: "Please cancel my Biology study session",
            modelJSON: #"[{"type":"cancel_study_session","subjectName":"Biology","topics":["Cells and Cell Structure"]}]"#,
            seed: standardSeed,
            verify: { ctx in
                let plans = try ctx.fetch(FetchDescriptor<StudyPlan>())
                return !plans.contains { $0.subjectName == "Biology" }
            },
            summaryContains: ["Cancelled"]
        ))

        out.append(ToolScenario(
            id: "session-13", name: "cancel_study_session not confirmed is blocked",
            userMessage: "Tell me about my Biology session",
            modelJSON: #"[{"type":"cancel_study_session","subjectName":"Biology","topics":["Cells and Cell Structure"]}]"#,
            seed: standardSeed,
            expectedCompleted: 0, expectedFailed: 1,
            verify: { ctx in (try ctx.fetch(FetchDescriptor<StudyPlan>())).count == 1 },
            summaryContains: ["skipped"]
        ))
    }
}
