import Foundation
import SwiftData

// MARK: - Curriculum Structure
nonisolated enum IBCourseLevel: String, CaseIterable, Codable, Hashable, Sendable {
    case sl = "SL"
    case hl = "HL"

    init(_ rawValue: String) {
        self = rawValue.uppercased() == "HL" ? .hl : .sl
    }
}

nonisolated struct CurriculumUnit {
    let name: String
    let topics: [CurriculumTopic]
}

nonisolated struct CurriculumTopic {
    let name: String
    let subtopics: [String]
    let levels: Set<IBCourseLevel>

    init(
        name: String,
        subtopics: [String],
        levels: Set<IBCourseLevel> = Set(IBCourseLevel.allCases)
    ) {
        self.name = name
        self.subtopics = subtopics
        self.levels = levels
    }
}

nonisolated struct CurriculumMetadata: Sendable {
    let catalogVersion: String
    let firstAssessment: String
    let sourceTitle: String
    let sourceURL: URL
}

nonisolated struct SyllabusSeeder {
    static let lifeCourseName = "Life"

    @discardableResult
    static func seedIfNeeded(context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<Subject>()
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        if existingCount == 0 {
            let subjects = createSubjects()
            for subject in subjects {
                context.insert(subject)
            }
        }
        migratePersonalCurriculum(context: context)
        migrateRetiredTopics(context: context)
        return synchronizeCurriculum(context: context)
    }

    /// The per-subject curriculum trees are large computed properties that
    /// would be rebuilt on every access. They are immutable value types, so
    /// cache them once per subject instead of re-allocating hundreds of structs
    /// in hot loops (ARIA builds its prompt per message).
    private static let curriculumCacheLock = NSLock()
    nonisolated(unsafe) private static var curriculumCache: [String: [CurriculumUnit]] = [:]

    /// Returns the curriculum tree for a subject (used by TopicBrowserView)
    static func curriculum(for subjectName: String) -> [CurriculumUnit] {
        let key = subjectName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        curriculumCacheLock.lock()
        if let cached = curriculumCache[key] {
            curriculumCacheLock.unlock()
            return cached
        }
        curriculumCacheLock.unlock()

        let result: [CurriculumUnit]
        switch subjectName {
        case "English B": result = englishBCurriculum
        case "Russian A Literature": result = russianLitCurriculum
        case "Biology": result = biologyCurriculum
        case "Mathematics AA": result = mathAACurriculum
        case "Economics": result = economicsCurriculum
        case "Business Management": result = businessCurriculum
        case "Advanced Mathematics": result = advancedMathCurriculum
        case "Fundamentals of the Universe": result = universeCurriculum
        case lifeCourseName: result = lifeCurriculum
        // Read-only aliases keep older backups and in-flight migrations legible.
        case "Founder Academy", "Startups & Venture Capital": result = lifeCurriculum
        default: result = []
        }

        curriculumCacheLock.lock()
        curriculumCache[key] = result
        curriculumCacheLock.unlock()
        return result
    }

    static func curriculum(for subjectName: String, level: String) -> [CurriculumUnit] {
        let selectedLevel = IBCourseLevel(level)
        return curriculum(for: subjectName).compactMap { unit in
            let topics = unit.topics.compactMap { topic -> CurriculumTopic? in
                guard topic.levels.contains(selectedLevel) else { return nil }
                let subtopics = topic.subtopics.compactMap { rawValue -> String? in
                    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasPrefix("HL:") {
                        guard selectedLevel == .hl else { return nil }
                        return trimmed.replacingOccurrences(of: "HL:", with: "", options: [.anchored])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    return trimmed
                }
                guard !subtopics.isEmpty else { return nil }
                return CurriculumTopic(name: topic.name, subtopics: subtopics, levels: topic.levels)
            }
            guard !topics.isEmpty else { return nil }
            return CurriculumUnit(name: unit.name, topics: topics)
        }
    }

    static func metadata(for subjectName: String) -> CurriculumMetadata {
        switch subjectName {
        case "Biology":
            return metadata(
                firstAssessment: "2025",
                title: "IB Diploma Programme Biology",
                path: "programmes/diploma-programme/curriculum/sciences/biology/"
            )
        case "Mathematics AA":
            return metadata(
                firstAssessment: "2021",
                title: "IB Mathematics: analysis and approaches",
                path: "programmes/diploma-programme/curriculum/mathematics/"
            )
        case "Economics":
            return metadata(
                firstAssessment: "2022",
                title: "IB Diploma Programme Economics",
                path: "programmes/diploma-programme/curriculum/individuals-and-societies/economics/"
            )
        case "Business Management":
            return metadata(
                firstAssessment: "2024",
                title: "IB Diploma Programme Business management",
                path: "programmes/diploma-programme/curriculum/individuals-and-societies/business-management/"
            )
        case "English B":
            return metadata(
                firstAssessment: "2020",
                title: "IB Diploma Programme Language acquisition",
                path: "programmes/diploma-programme/curriculum/language-acquisition/"
            )
        case "Russian A Literature":
            return metadata(
                firstAssessment: "2021",
                title: "IB Diploma Programme Language and literature",
                path: "programmes/diploma-programme/curriculum/language-and-literature/"
            )
        case "Advanced Mathematics":
            return CurriculumMetadata(
                catalogVersion: "2026.1 / personal course",
                firstAssessment: "Self-paced",
                sourceTitle: "Advanced Mathematics — Proofs and Foundations",
                sourceURL: URL(string: "https://www.ibo.org/") ?? URL(fileURLWithPath: "/")
            )
        case "Fundamentals of the Universe":
            return CurriculumMetadata(
                catalogVersion: "2026.1 / personal course",
                firstAssessment: "Self-paced",
                sourceTitle: "Fundamentals of the Universe",
                sourceURL: URL(string: "https://www.ibo.org/") ?? URL(fileURLWithPath: "/")
            )
        case lifeCourseName, "Founder Academy", "Startups & Venture Capital":
            return CurriculumMetadata(
                catalogVersion: "2026.2 / personal course",
                firstAssessment: "Self-paced",
                sourceTitle: lifeCourseName,
                sourceURL: URL(string: "https://www.ibo.org/") ?? URL(fileURLWithPath: "/")
            )
        default:
            return metadata(firstAssessment: "Current", title: "IB Diploma Programme", path: "programmes/diploma-programme/curriculum/")
        }
    }

    @discardableResult
    static func synchronizeCurriculum(context: ModelContext) -> Bool {
        guard
            let subjects = try? context.fetch(FetchDescriptor<Subject>()),
            let existingNodes = try? context.fetch(FetchDescriptor<CurriculumNode>())
        else { return false }
        var nodesByKey: [String: CurriculumNode] = [:]
        for node in existingNodes {
            if nodesByKey[node.stableKey] == nil {
                nodesByKey[node.stableKey] = node
            } else {
                context.delete(node)
            }
        }
        var expectedKeys = Set<String>()

        for subject in subjects {
            let metadata = metadata(for: subject.name)
            for unit in curriculum(for: subject.name, level: subject.level) {
                for topic in unit.topics {
                    for subtopic in topic.subtopics {
                        let key = CurriculumNode.stableKey(
                            subjectName: subject.name,
                            level: subject.level,
                            unitName: unit.name,
                            topicName: topic.name,
                            subtopicName: subtopic
                        )
                        expectedKeys.insert(key)
                        if let node = nodesByKey.removeValue(forKey: key) {
                            // Only touch rows whose metadata actually changed, so
                            // launching the app does not churn every node row.
                            let urlString = metadata.sourceURL.absoluteString
                            if node.catalogVersion != metadata.catalogVersion ||
                                node.sourceTitle != metadata.sourceTitle ||
                                node.sourceURLString != urlString {
                                node.catalogVersion = metadata.catalogVersion
                                node.sourceTitle = metadata.sourceTitle
                                node.sourceURLString = urlString
                                node.updatedAt = Date()
                            }
                        } else {
                            context.insert(CurriculumNode(
                                subjectName: subject.name,
                                level: subject.level,
                                unitName: unit.name,
                                topicName: topic.name,
                                subtopicName: subtopic,
                                catalogVersion: metadata.catalogVersion,
                                sourceTitle: metadata.sourceTitle,
                                sourceURLString: metadata.sourceURL.absoluteString
                            ))
                        }
                    }
                }
            }
        }

        for (key, node) in nodesByKey where !expectedKeys.contains(key) {
            // A catalog correction must not erase a user's recorded evidence.
            // Keep retired rows with mastery data; current curriculum views
            // resolve against the new canonical paths, while old records and
            // backups remain readable.
            if node.recordedMasteryRaw == nil && node.masteryUpdatedAt == nil &&
                node.masterySource == nil && node.masteryNote == nil {
                context.delete(node)
            }
        }

        // Existing cards are user data. Do not remove or deduplicate them
        // during curriculum synchronization; older builds stored useful cards
        // under generic prompts, and users must be able to recover that work.

        do {
            try context.save()
            return true
        } catch {
            // Non-fatal: curriculum stays unsynchronized but the app keeps
            // working. A Debug build surfaces it loudly; Release logs once.
            #if DEBUG
            assertionFailure("Failed to synchronize curriculum: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    /// Consolidates the retired TOK and startup subjects into the single
    /// personal course. Relationship reassignment happens before deletion so
    /// existing flashcards and grades survive the migration.
    private static func migratePersonalCurriculum(context: ModelContext) {
        let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        let legacyNames = ["Founder Academy", "Startups & Venture Capital", "Theory of Knowledge"]
        let lifeSubject = subjects.first { $0.name == lifeCourseName }
            ?? subjects.first { $0.name == "Founder Academy" }
            ?? subjects.first { $0.name == "Startups & Venture Capital" }
            ?? subjects.first { $0.name == "Theory of Knowledge" }
            ?? {
                let created = Subject(name: lifeCourseName, level: "HL", accentColorHex: "0EA5E9")
                context.insert(created)
                return created
            }()

        lifeSubject.name = lifeCourseName
        lifeSubject.level = "HL"
        lifeSubject.accentColorHex = "0EA5E9"

        for legacy in subjects where legacy.id != lifeSubject.id && legacyNames.contains(legacy.name) {
            for card in legacy.cards {
                card.subject = lifeSubject
            }
            for grade in legacy.grades {
                grade.subject = lifeSubject
            }
            context.delete(legacy)
        }

        // Follow-up plans were synthetic 30-minute calendar sessions. Reviews
        // now live exclusively in the bounded card queue, so pending blocks are
        // obsolete and safe to remove while completed history remains intact.
        let plans = (try? context.fetch(FetchDescriptor<StudyPlan>())) ?? []
        for plan in plans where plan.isFollowUpReview && !plan.isCompleted {
            context.delete(plan)
        }
    }

    // MARK: - Retired Topics

    private nonisolated struct RetiredTopic: Sendable {
        /// Where cards go when their subtopic does not name a better home.
        let fallback: String
        let subtopics: [String: (topic: String, subtopic: String)]

        func target(forSubtopic subtopic: String) -> (topic: String, subtopic: String) {
            subtopics[subtopic] ?? (fallback, subtopic)
        }

        /// Every topic this one split into, so a saved scope still covers its cards.
        var topics: [String] {
            var result = [fallback]
            for topic in subtopics.values.map(\.topic).sorted() where !result.contains(topic) {
                result.append(topic)
            }
            return result
        }
    }

    /// Topics the curriculum rework renamed or split. A card keeps its schedule
    /// and history; only where it is filed changes.
    private static let retiredTopics: [String: [String: RetiredTopic]] = [
        "Biology": [
            "Ecosystems": .init(fallback: "C4.1 Populations and communities", subtopics: [
                "Biotic and abiotic factors": ("B4.1 Adaptation to environment", "Abiotic factors, distribution and adaptations"),
                "Habitat and ecological niches": ("B4.2 Ecological niches", "Nutrition, resource use and ecological niches"),
                "Trophic levels and food webs": ("C4.2 Transfers of energy and matter", "Food webs, trophic levels and ecological energy flow")
            ]),
            "Energy Flow in Ecosystems": .init(fallback: "C4.2 Transfers of energy and matter", subtopics: [
                "Energy flow through trophic levels": ("C4.2 Transfers of energy and matter", "Food webs, trophic levels and ecological energy flow"),
                "Energy pyramids": ("C4.2 Transfers of energy and matter", "Food webs, trophic levels and ecological energy flow"),
                "Photosynthesis — light-dependent and light-independent reactions": ("C1.3 Photosynthesis", "Photosynthetic pigments and limiting factors")
            ]),
            "Genetics": .init(fallback: "D3.2 Inheritance", subtopics: [
                "Chromosomes and karyotypes": ("A3.1 Diversity of organisms", "Chromosomes, karyograms and genome diversity"),
                "DNA profiling and biotechnology": ("D1.1 DNA replication", "PCR and DNA profiling"),
                "Gene mutations": ("D1.3 Mutation and gene editing", "Gene mutations, causes and consequences"),
                "Genes, alleles and the genome": ("D3.2 Inheritance", "Genes, alleles, Mendelian inheritance and Punnett squares")
            ]),
            "Inheritance": .init(fallback: "D3.2 Inheritance", subtopics: [
                "Codominance and multiple alleles": ("D3.2 Inheritance", "Codominance, sex linkage and pedigree analysis"),
                "Mendel's laws of inheritance": ("D3.2 Inheritance", "Genes, alleles, Mendelian inheritance and Punnett squares"),
                "Monohybrid crosses and Punnett squares": ("D3.2 Inheritance", "Genes, alleles, Mendelian inheritance and Punnett squares"),
                "Sex-linked inheritance": ("D3.2 Inheritance", "Codominance, sex linkage and pedigree analysis")
            ]),
            "Population Biology": .init(fallback: "C4.1 Populations and communities", subtopics: [
                "Carrying capacity and limiting factors": ("C4.1 Populations and communities", "Population growth and limiting factors"),
                "Population growth curves (S and J curves)": ("C4.1 Populations and communities", "Population growth and limiting factors"),
                "Predator-prey relationships": ("C4.1 Populations and communities", "Sampling, species interactions and community ecology"),
                "Sampling techniques for populations": ("C4.1 Populations and communities", "Sampling, species interactions and community ecology")
            ]),
            "Sustainability": .init(fallback: "D4.2 Stability and change", subtopics: [
                "Carbon cycling and climate change": ("D4.3 Climate change", "Greenhouse gases, evidence and biological consequences"),
                "Human impact on ecosystems": ("D4.2 Stability and change", "Ecosystem stability, resilience and human impacts"),
                "Nitrogen cycling": ("C4.2 Transfers of energy and matter", "Carbon cycling, biomass and productivity"),
                "Sustainable development and resource management": ("A4.2 Conservation of biodiversity", "Conservation strategies and evaluating their success")
            ]),
            "Water and Biomolecules": .init(fallback: "A1.1 Water", subtopics: [
                "Hydrogen bonding in water": ("A1.1 Water", "Polarity, hydrogen bonding, cohesion and adhesion")
            ])
        ],
        "Mathematics AA": [
            "Differentiation": .init(fallback: "5.6 Differentiation rules", subtopics: [
                "Chain rule": ("5.6 Differentiation rules", "Chain, product and quotient rules"),
                "Derivatives of exponential and logarithmic functions": ("5.6 Differentiation rules", "Derivatives of powers, trigonometric, exponential and logarithmic functions"),
                "Derivatives of trigonometric functions": ("5.6 Differentiation rules", "Derivatives of powers, trigonometric, exponential and logarithmic functions"),
                "First principles of differentiation": ("5.1 Limits and derivatives", "Limits and the gradient of a curve"),
                "Power rule": ("5.3 Polynomial differentiation", "Power rule"),
                "Product and quotient rules": ("5.6 Differentiation rules", "Chain, product and quotient rules")
            ])
        ]
    ]

    /// Runs every launch so a restored backup gets the same treatment; it finds
    /// nothing to do once the names are current.
    private static func migrateRetiredTopics(context: ModelContext) {
        var topicByCard: [UUID: String] = [:]
        for card in (try? context.fetch(FetchDescriptor<StudyCard>())) ?? [] {
            guard let retired = card.subject.flatMap({ retiredTopics[$0.name]?[card.topicName] }) else { continue }
            let target = retired.target(forSubtopic: card.subtopic)
            card.topicName = target.topic
            card.subtopic = target.subtopic
            topicByCard[card.id] = target.topic
        }
        for review in (try? context.fetch(FetchDescriptor<ReviewSession>())) ?? [] {
            guard let retired = retiredTopics[review.subjectName]?[review.topicName] else { continue }
            review.topicName = topicByCard[review.cardID] ?? retired.fallback
        }
        for plan in (try? context.fetch(FetchDescriptor<StudyPlan>())) ?? [] {
            guard let retired = retiredTopics[plan.subjectName] else { continue }
            if let topics = migratedTopics(plan.topicName, retired: retired) {
                plan.topicName = topics
                // Old subtopics no longer name any card; the topics still cover them.
                plan.subtopicName = ""
            }
            let tasks = plan.planTasks
            if tasks.contains(where: { retired[$0.topicName] != nil }) {
                plan.planTasks = tasks.map { task in
                    guard let target = retired[task.topicName]?.target(forSubtopic: task.subtopicName) else { return task }
                    return StudyPlanTask(
                        id: task.id, title: task.title, minutes: task.minutes, activityType: task.activityType,
                        topicName: target.topic, subtopicName: target.subtopic, instructions: task.instructions,
                        successCriterion: task.successCriterion, flashcardTarget: task.flashcardTarget
                    )
                }
            }
        }
        for session in (try? context.fetch(FetchDescriptor<StudySession>())) ?? [] {
            guard let retired = retiredTopics[session.subjectName] else { continue }
            if let topics = migratedTopics(session.topicsCovered, retired: retired) {
                session.topicsCovered = topics
                session.subtopicsCovered = nil
            }
            let evidence = session.subunitEvidence
            if evidence.contains(where: { retired[$0.topicName] != nil }) {
                session.subunitEvidence = evidence.map { entry in
                    guard let target = retired[entry.topicName]?.target(forSubtopic: entry.subtopicName) else { return entry }
                    return StudySessionSubunitEvidence(
                        topicName: target.topic, subtopicName: target.subtopic, minutes: entry.minutes,
                        confidenceRating: entry.confidenceRating, cardsReviewed: entry.cardsReviewed,
                        correctCount: entry.correctCount
                    )
                }
            }
        }
    }

    private static func migratedTopics(_ topics: String, retired: [String: RetiredTopic]) -> String? {
        let current = StudyScope.parseList(topics)
        guard current.contains(where: { retired[$0] != nil }) else { return nil }
        var result: [String] = []
        for topic in current.flatMap({ retired[$0]?.topics ?? [$0] }) where !result.contains(topic) {
            result.append(topic)
        }
        return result.joined(separator: ", ")
    }

    static func unitName(for subjectName: String, level: String? = nil, topicName: String) -> String? {
        (level.map { curriculum(for: subjectName, level: $0) } ?? curriculum(for: subjectName))
            .first { unit in unit.topics.contains { $0.name == topicName } }?
            .name
    }

    static func unitNames(for subjectName: String, topicNames: [String]) -> [String] {
        var names: [String] = []
        for topicName in topicNames {
            guard let unitName = unitName(for: subjectName, topicName: topicName), !names.contains(unitName) else { continue }
            names.append(unitName)
        }
        return names
    }

    static func topic(named topicName: String, in subjectName: String, level: String? = nil) -> CurriculumTopic? {
        let units = level.map { curriculum(for: subjectName, level: $0) } ?? curriculum(for: subjectName)
        for unit in units {
            if let topic = unit.topics.first(where: { $0.name == topicName }) {
                return topic
            }
        }
        return nil
    }

    static func subtopics(for subjectName: String, level: String? = nil, topicName: String) -> [String] {
        topic(named: topicName, in: subjectName, level: level)?.subtopics ?? []
    }

    private static func metadata(firstAssessment: String, title: String, path: String) -> CurriculumMetadata {
        let url = URL(string: "https://www.ibo.org/\(path)")
            ?? URL(string: "https://www.ibo.org/")
            ?? URL(fileURLWithPath: "/")
        return CurriculumMetadata(
            catalogVersion: "2026.2 / first assessment \(firstAssessment)",
            firstAssessment: firstAssessment,
            sourceTitle: title,
            sourceURL: url
        )
    }

    // MARK: - Create Subjects with Seed Cards

    private static func createSubjects() -> [Subject] {
        var subjects: [Subject] = []

        let english = Subject(name: "English B", level: "HL", accentColorHex: "8B5CF6")
        subjects.append(english)

        let russian = Subject(name: "Russian A Literature", level: "SL", accentColorHex: "EC4899")
        subjects.append(russian)

        let biology = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        subjects.append(biology)

        let math = Subject(name: "Mathematics AA", level: "SL", accentColorHex: "3B82F6")
        subjects.append(math)

        let economics = Subject(name: "Economics", level: "HL", accentColorHex: "F59E0B")
        subjects.append(economics)

        let business = Subject(name: "Business Management", level: "HL", accentColorHex: "EF4444")
        subjects.append(business)

        // Personal-development courses beyond the IB syllabus.
        let advancedMath = Subject(name: "Advanced Mathematics", level: "HL", accentColorHex: "8B5CF6")
        subjects.append(advancedMath)

        let universe = Subject(name: "Fundamentals of the Universe", level: "SL", accentColorHex: "6366F1")
        subjects.append(universe)

        let life = Subject(name: lifeCourseName, level: "HL", accentColorHex: "0EA5E9")
        subjects.append(life)

        return subjects
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - IB Economics HL (First assessment 2022)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private static var economicsCurriculum: [CurriculumUnit] {
        [
            CurriculumUnit(name: "Unit 1 — Introduction to Economics", topics: [
                CurriculumTopic(name: "What is Economics", subtopics: [
                    "Definition and scope of economics",
                    "Positive and normative economics",
                    "Microeconomics vs macroeconomics",
                    "Economic methodology and models"
                ]),
                CurriculumTopic(name: "Economic Models and Assumptions", subtopics: [
                    "Ceteris paribus",
                    "Rational economic decision-making",
                    "The role of models in economics",
                    "Limitations of economic models"
                ]),
                CurriculumTopic(name: "Scarcity, Choice and Opportunity Cost", subtopics: [
                    "The basic economic problem",
                    "Factors of production",
                    "Opportunity cost in decision-making",
                    "Free goods vs economic goods"
                ]),
                CurriculumTopic(name: "Production Possibility Curves", subtopics: [
                    "Drawing and interpreting PPCs",
                    "Opportunity cost on the PPC",
                    "Shifts of the PPC",
                    "Efficiency and the PPC",
                    "Economic growth and the PPC"
                ]),
            ]),

            CurriculumUnit(name: "Unit 2 — Microeconomics", topics: [
                CurriculumTopic(name: "Demand", subtopics: [
                    "The law of demand",
                    "Individual and market demand curves",
                    "Movements along vs shifts of demand",
                    "Determinants of demand",
                    "Exceptions to the law of demand"
                ]),
                CurriculumTopic(name: "Supply", subtopics: [
                    "The law of supply",
                    "Individual and market supply curves",
                    "Movements along vs shifts of supply",
                    "Determinants of supply"
                ]),
                CurriculumTopic(name: "Market Equilibrium", subtopics: [
                    "Equilibrium price and quantity",
                    "Excess demand and excess supply",
                    "Changes in equilibrium",
                    "Consumer and producer surplus",
                    "Allocative efficiency"
                ]),
                CurriculumTopic(name: "Elasticities", subtopics: [
                    "Price elasticity of demand (PED)",
                    "Income elasticity of demand (YED)",
                    "Cross-price elasticity of demand (XED)",
                    "Price elasticity of supply (PES)",
                    "Determinants and calculations of each",
                    "Applications and significance of elasticity",
                    "HL: advanced elasticity calculations"
                ]),
                CurriculumTopic(name: "Government Intervention", subtopics: [
                    "Indirect taxes and their effects",
                    "Subsidies and their effects",
                    "Price ceilings (maximum prices)",
                    "Price floors (minimum prices)",
                    "Consequences of government intervention",
                    "Diagrams for tax and subsidy analysis"
                ]),
                CurriculumTopic(name: "Market Failure", subtopics: [
                    "Negative externalities (production and consumption)",
                    "Positive externalities (production and consumption)",
                    "Public goods and free-rider problem",
                    "Common pool resources",
                    "Asymmetric information",
                    "Government responses to market failure"
                ]),
                CurriculumTopic(name: "Market Power and Monopoly", subtopics: [
                    "Characteristics of monopoly",
                    "Barriers to entry",
                    "Monopoly vs perfect competition",
                    "Price-setting power",
                    "HL: profit maximisation (MC=MR)",
                    "HL: efficiency in different market structures"
                ]),
                CurriculumTopic(name: "Equity and Income Distribution", subtopics: [
                    "Equity vs equality",
                    "Lorenz curve and Gini coefficient",
                    "Causes of income inequality",
                    "Government policies to redistribute income"
                ]),
            ]),

            CurriculumUnit(name: "Unit 3 — Macroeconomics", topics: [
                CurriculumTopic(name: "Measuring Economic Activity", subtopics: [
                    "Gross domestic product (GDP)",
                    "Nominal vs real GDP",
                    "GDP per capita",
                    "Green GDP and limitations of GDP",
                    "Business cycle"
                ]),
                CurriculumTopic(name: "Aggregate Demand and Aggregate Supply", subtopics: [
                    "Components of aggregate demand",
                    "The AD curve and shifts",
                    "Short-run aggregate supply (SRAS)",
                    "Long-run aggregate supply (LRAS)",
                    "Keynesian vs neo-classical AS model",
                    "Shifts in SRAS and LRAS",
                    "Short-run and long-run equilibrium"
                ]),
                CurriculumTopic(name: "Inflation", subtopics: [
                    "Measuring inflation (CPI)",
                    "Demand-pull inflation",
                    "Cost-push inflation",
                    "Consequences of inflation",
                    "Deflation and its consequences",
                    "Disinflation"
                ]),
                CurriculumTopic(name: "Unemployment", subtopics: [
                    "Measuring unemployment",
                    "Types: cyclical, structural, frictional, seasonal",
                    "Natural rate of unemployment",
                    "Consequences of unemployment",
                    "Phillips curve (HL)"
                ]),
                CurriculumTopic(name: "Economic Growth", subtopics: [
                    "Short-run vs long-run growth",
                    "Sources of economic growth",
                    "Costs and benefits of growth",
                    "Sustainable development"
                ]),
                CurriculumTopic(name: "Equity in Macroeconomics", subtopics: [
                    "Taxation (progressive, regressive, proportional)",
                    "Transfer payments",
                    "Universal basic income debate"
                ]),
                CurriculumTopic(name: "Fiscal Policy", subtopics: [
                    "Government spending and taxation",
                    "Expansionary and contractionary fiscal policy",
                    "Budget deficits and surpluses",
                    "Automatic stabilisers",
                    "HL: the multiplier effect and calculations"
                ]),
                CurriculumTopic(name: "Monetary Policy", subtopics: [
                    "Interest rates and money supply",
                    "Central bank tools",
                    "Expansionary vs contractionary monetary policy",
                    "Quantitative easing",
                    "Limitations of monetary policy"
                ]),
                CurriculumTopic(name: "Supply-Side Policies", subtopics: [
                    "Market-based supply-side policies",
                    "Interventionist supply-side policies",
                    "Strengths and limitations of each approach"
                ]),
            ]),

            CurriculumUnit(name: "Unit 4 — The Global Economy", topics: [
                CurriculumTopic(name: "International Trade", subtopics: [
                    "Absolute and comparative advantage",
                    "Benefits of international trade",
                    "World Trade Organisation (WTO)",
                    "HL: terms of trade calculations"
                ]),
                CurriculumTopic(name: "Trade Protection", subtopics: [
                    "Tariffs — diagrams and effects",
                    "Quotas — diagrams and effects",
                    "Subsidies for domestic producers",
                    "Administrative barriers",
                    "Arguments for and against protection"
                ]),
                CurriculumTopic(name: "Exchange Rates", subtopics: [
                    "Floating exchange rate system",
                    "Fixed exchange rate system",
                    "Managed exchange rates",
                    "Causes and consequences of exchange rate changes",
                    "HL: exchange rate calculations"
                ]),
                CurriculumTopic(name: "Balance of Payments", subtopics: [
                    "Current account components",
                    "Capital and financial account",
                    "Current account deficit and surplus",
                    "Correction methods"
                ]),
                CurriculumTopic(name: "Economic Integration", subtopics: [
                    "Preferential trade agreements",
                    "Trading blocs (EU, USMCA, ASEAN)",
                    "Monetary union",
                    "Advantages and disadvantages of integration"
                ]),
                CurriculumTopic(name: "Economic Development and Growth Strategies", subtopics: [
                    "Economic growth vs economic development",
                    "Measuring development (HDI, MPI)",
                    "Barriers to development",
                    "Growth and development strategies",
                    "Role of foreign aid and FDI",
                    "HL: deeper analysis of development models"
                ]),
            ]),
        ]
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - IB Business Management HL (First assessment 2024)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private static var businessCurriculum: [CurriculumUnit] {
        [
            CurriculumUnit(name: "Unit 1 — Business Organisation and Environment", topics: [
                CurriculumTopic(name: "Nature of Business Activity", subtopics: [
                    "Business sectors (primary, secondary, tertiary, quaternary)",
                    "Entrepreneurship and reasons for starting a business",
                    "Business plans and challenges",
                    "Intrapreneurship"
                ]),
                CurriculumTopic(name: "Business Objectives", subtopics: [
                    "Vision, mission and objectives",
                    "Strategic vs tactical objectives",
                    "CSR and ethical objectives",
                    "SWOT analysis"
                ]),
                CurriculumTopic(name: "Stakeholders", subtopics: [
                    "Internal and external stakeholders",
                    "Stakeholder conflict",
                    "Stakeholder mapping",
                    "CSR and stakeholder relationships"
                ]),
                CurriculumTopic(name: "Business Growth", subtopics: [
                    "Internal (organic) growth",
                    "External growth (mergers and acquisitions)",
                    "Economies and diseconomies of scale",
                    "The role of globalisation"
                ]),
                CurriculumTopic(name: "Multinational Companies", subtopics: [
                    "Characteristics of MNCs",
                    "Impact of MNCs on host countries",
                    "Impact of MNCs on home countries",
                    "Ethical considerations of MNCs"
                ]),
            ]),

            CurriculumUnit(name: "Unit 2 — Human Resource Management", topics: [
                CurriculumTopic(name: "Organisational Structure", subtopics: [
                    "Organisational charts",
                    "Span of control and chain of command",
                    "Delegation and delayering",
                    "Flat vs tall structures",
                    "Matrix and project-based structures"
                ]),
                CurriculumTopic(name: "Leadership and Management Styles", subtopics: [
                    "Management vs leadership",
                    "Autocratic, democratic, laissez-faire",
                    "Situational and paternalistic leadership",
                    "Impact of leadership style on motivation"
                ]),
                CurriculumTopic(name: "Motivation Theories", subtopics: [
                    "Taylor's Scientific Management",
                    "Maslow's Hierarchy of Needs",
                    "Herzberg's Two-Factor Theory",
                    "Adams' Equity Theory",
                    "Financial motivation methods",
                    "Non-financial motivation methods"
                ]),
                CurriculumTopic(name: "Organisational Culture (HL)", subtopics: [
                    "Types of organisational culture",
                    "Handy's cultural typology",
                    "Impact of culture on performance",
                    "Changing organisational culture"
                ]),
                CurriculumTopic(name: "Communication", subtopics: [
                    "Internal and external communication",
                    "Formal and informal communication",
                    "Barriers to communication",
                    "Communication channels and networks"
                ]),
                CurriculumTopic(name: "Employee Relations", subtopics: [
                    "Recruitment and selection",
                    "Training and development",
                    "Dismissal and redundancy",
                    "Trade unions and collective bargaining",
                    "Employer-employee conflict resolution"
                ]),
            ]),

            CurriculumUnit(name: "Unit 3 — Finance and Accounts", topics: [
                CurriculumTopic(name: "Sources of Finance", subtopics: [
                    "Internal sources (retained profit, sale of assets)",
                    "External sources (loans, share capital, venture capital)",
                    "Short-term vs long-term finance",
                    "Crowdfunding and microfinance"
                ]),
                CurriculumTopic(name: "Costs and Revenues", subtopics: [
                    "Fixed and variable costs",
                    "Total, average and marginal cost",
                    "Revenue streams and calculations",
                    "Profit and loss"
                ]),
                CurriculumTopic(name: "Break-Even Analysis", subtopics: [
                    "Break-even point calculation",
                    "Break-even charts",
                    "Margin of safety",
                    "Limitations of break-even"
                ]),
                CurriculumTopic(name: "Profitability Ratios", subtopics: [
                    "Gross profit margin (GPM)",
                    "Net profit margin (NPM)",
                    "Return on capital employed (ROCE)",
                    "Interpreting profitability"
                ]),
                CurriculumTopic(name: "Liquidity Ratios", subtopics: [
                    "Current ratio",
                    "Acid test (quick) ratio",
                    "Working capital management",
                    "Interpreting liquidity ratios"
                ]),
                CurriculumTopic(name: "Cash Flow", subtopics: [
                    "Cash flow forecasts",
                    "Cash vs profit",
                    "Causes and solutions for cash flow problems",
                    "Cash flow management strategies"
                ]),
                CurriculumTopic(name: "Investment Appraisal", subtopics: [
                    "Payback period",
                    "Average rate of return (ARR)",
                    "Net present value (NPV)",
                    "Strengths and limitations of each method"
                ]),
                CurriculumTopic(name: "Budgets (HL)", subtopics: [
                    "Types of budgets",
                    "Budget setting and variance analysis",
                    "Advantages of budgeting",
                    "Limitations of budgeting"
                ]),
            ]),

            CurriculumUnit(name: "Unit 4 — Marketing", topics: [
                CurriculumTopic(name: "Marketing Planning", subtopics: [
                    "Market orientation vs product orientation",
                    "Marketing objectives and strategies",
                    "Market segmentation and targeting",
                    "Positioning and USP"
                ]),
                CurriculumTopic(name: "Market Research", subtopics: [
                    "Primary and secondary research",
                    "Qualitative and quantitative data",
                    "Sampling methods",
                    "Reliability and bias in research"
                ]),
                CurriculumTopic(name: "Marketing Mix (7Ps)", subtopics: [
                    "Product: features, branding, packaging, product life cycle",
                    "Price: pricing strategies (cost-plus, penetration, skimming, etc.)",
                    "Place: distribution channels, e-commerce",
                    "Promotion: advertising, sales promotion, PR, direct marketing",
                    "People, Process, Physical evidence (services)"
                ]),
                CurriculumTopic(name: "Sales Forecasting (HL)", subtopics: [
                    "Time series analysis",
                    "Moving averages",
                    "Extrapolation and limitations",
                    "Seasonal and cyclical variations"
                ]),
                CurriculumTopic(name: "International Marketing", subtopics: [
                    "Pan-global vs geocentric marketing",
                    "Entry into international markets",
                    "Cultural considerations in marketing",
                    "Localisation vs standardisation"
                ]),
            ]),

            CurriculumUnit(name: "Unit 5 — Operations Management", topics: [
                CurriculumTopic(name: "Production Methods", subtopics: [
                    "Job, batch and mass production",
                    "Cell production",
                    "Lean production and Just-in-Time (JIT)",
                    "Kaizen (continuous improvement)"
                ]),
                CurriculumTopic(name: "Quality Management", subtopics: [
                    "Quality control vs quality assurance",
                    "Total Quality Management (TQM)",
                    "ISO standards and benchmarking",
                    "National and international quality awards"
                ]),
                CurriculumTopic(name: "Capacity Utilisation", subtopics: [
                    "Measuring capacity utilisation",
                    "Under-utilisation and over-utilisation",
                    "Strategies to improve efficiency",
                    "Outsourcing and subcontracting"
                ]),
                CurriculumTopic(name: "Location Decisions", subtopics: [
                    "Factors influencing location",
                    "Quantitative location techniques",
                    "Offshoring and reshoring",
                    "Impact of globalisation on location"
                ]),
                CurriculumTopic(name: "Stock Control", subtopics: [
                    "Stock control charts",
                    "Buffer stock, lead time, reorder level",
                    "Just-in-Time (JIT) vs Just-in-Case (JIC)",
                    "Waste minimisation"
                ]),
                CurriculumTopic(name: "HL Advanced Tools", subtopics: [
                    "Decision trees and expected values",
                    "Critical path analysis",
                    "Regression analysis and forecasting",
                    "Porter's generic strategies",
                    "Ansoff matrix and Boston matrix"
                ]),
            ]),
        ]
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - IB Biology SL (First assessment 2025)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    // Topic codes follow the IB guides. Subtopics are concise study summaries,
    // not substitutes for the full syllabus statements. HL-only material stays
    // in its theme so it cannot accidentally appear in an SL selection.
    private static var biologyCurriculum: [CurriculumUnit] {
        [
            CurriculumUnit(name: "Theme A — Unity and Diversity", topics: [
                CurriculumTopic(name: "A1.1 Water", subtopics: [
                    "Polarity, hydrogen bonding, cohesion and adhesion",
                    "Water as a solvent and an aquatic habitat",
                    "HL: Water's origins and the search for life"
                ]),
                CurriculumTopic(name: "A1.2 Nucleic acids", subtopics: [
                    "Nucleotides, DNA structure and complementary base pairing",
                    "RNA structure and the genetic code",
                    "HL: DNA packaging, directionality and genome comparisons"
                ]),
                CurriculumTopic(name: "A2.1 Origins of cells", subtopics: [
                    "Prebiotic chemistry and the emergence of cells",
                    "Evidence for the last universal common ancestor"
                ], levels: [.hl]),
                CurriculumTopic(name: "A2.2 Cell structure", subtopics: [
                    "Prokaryotic and eukaryotic cells",
                    "Microscopy, magnification and cell ultrastructure",
                    "HL: Endosymbiosis and multicellular organization"
                ]),
                CurriculumTopic(name: "A2.3 Viruses", subtopics: [
                    "Viral structure, replication and host specificity",
                    "Lytic and lysogenic infection cycles"
                ], levels: [.hl]),
                CurriculumTopic(name: "A3.1 Diversity of organisms", subtopics: [
                    "Species, variation and binomial nomenclature",
                    "Chromosomes, karyograms and genome diversity"
                ]),
                CurriculumTopic(name: "A3.2 Classification and cladistics", subtopics: [
                    "Classification using evolutionary relationships",
                    "Cladograms and molecular evidence"
                ], levels: [.hl]),
                CurriculumTopic(name: "A4.1 Evolution and speciation", subtopics: [
                    "Evidence for evolution and common ancestry",
                    "Reproductive isolation and speciation"
                ]),
                CurriculumTopic(name: "A4.2 Conservation of biodiversity", subtopics: [
                    "Biodiversity loss, extinction and human impacts",
                    "Conservation strategies and evaluating their success"
                ])
            ]),
            CurriculumUnit(name: "Theme B — Form and Function", topics: [
                CurriculumTopic(name: "B1.1 Carbohydrates and lipids", subtopics: [
                    "Carbohydrate structure, condensation and hydrolysis",
                    "Triglycerides, phospholipids and energy storage"
                ]),
                CurriculumTopic(name: "B1.2 Proteins", subtopics: [
                    "Amino acids, peptide bonds and protein function",
                    "HL: Protein structure, folding and denaturation"
                ]),
                CurriculumTopic(name: "B2.1 Membranes and membrane transport", subtopics: [
                    "Phospholipid bilayers and the fluid mosaic model",
                    "Diffusion, osmosis and active transport",
                    "HL: Membrane fluidity, channels and transport regulation"
                ]),
                CurriculumTopic(name: "B2.2 Organelles and compartmentalization", subtopics: [
                    "Organelle functions and intracellular compartments",
                    "HL: Endomembrane transport and organelle adaptations"
                ]),
                CurriculumTopic(name: "B2.3 Cell specialization", subtopics: [
                    "Differentiation, stem cells and specialized cells",
                    "Cell size, surface area and volume"
                ]),
                CurriculumTopic(name: "B3.1 Gas exchange", subtopics: [
                    "Gas exchange surfaces and concentration gradients",
                    "Ventilation, alveoli and leaf adaptations"
                ]),
                CurriculumTopic(name: "B3.2 Transport", subtopics: [
                    "Blood vessels, circulation and the heart",
                    "Water transport in xylem and transpiration",
                    "HL: Phloem transport and tissue fluid"
                ]),
                CurriculumTopic(name: "B3.3 Muscle and motility", subtopics: [
                    "Sliding filaments, sarcomeres and muscle contraction",
                    "Movement, joints and antagonistic muscles"
                ], levels: [.hl]),
                CurriculumTopic(name: "B4.1 Adaptation to environment", subtopics: [
                    "Abiotic factors, distribution and adaptations",
                    "Terrestrial and aquatic biomes"
                ]),
                CurriculumTopic(name: "B4.2 Ecological niches", subtopics: [
                    "Nutrition, resource use and ecological niches",
                    "Competition and adaptations for feeding"
                ])
            ]),
            CurriculumUnit(name: "Theme C — Interaction and Interdependence", topics: [
                CurriculumTopic(name: "C1.1 Enzymes and metabolism", subtopics: [
                    "Enzyme specificity, activation energy and metabolic pathways",
                    "Temperature, pH and substrate concentration",
                    "HL: Inhibition and regulation of metabolic pathways"
                ]),
                CurriculumTopic(name: "C1.2 Cell respiration", subtopics: [
                    "ATP production, aerobic and anaerobic respiration",
                    "HL: Glycolysis, Krebs cycle and oxidative phosphorylation"
                ]),
                CurriculumTopic(name: "C1.3 Photosynthesis", subtopics: [
                    "Photosynthetic pigments and limiting factors",
                    "HL: Light-dependent reactions and carbon fixation"
                ]),
                CurriculumTopic(name: "C2.1 Chemical signalling", subtopics: [
                    "Receptors, ligands and signal transduction",
                    "Second messengers and cellular responses"
                ], levels: [.hl]),
                CurriculumTopic(name: "C2.2 Neural signalling", subtopics: [
                    "Neurons, action potentials and synaptic transmission",
                    "HL: Ion movements and modulation of signalling"
                ]),
                CurriculumTopic(name: "C3.1 Integration of body systems", subtopics: [
                    "Coordination by nervous and endocrine systems",
                    "Brain, spinal cord and reflex pathways"
                ]),
                CurriculumTopic(name: "C3.2 Defence against disease", subtopics: [
                    "Barriers, blood clotting and innate immunity",
                    "Lymphocytes, antibodies and vaccination",
                    "HL: Immune specificity and monoclonal antibodies"
                ]),
                CurriculumTopic(name: "C4.1 Populations and communities", subtopics: [
                    "Population growth and limiting factors",
                    "Sampling, species interactions and community ecology"
                ]),
                CurriculumTopic(name: "C4.2 Transfers of energy and matter", subtopics: [
                    "Food webs, trophic levels and ecological energy flow",
                    "Carbon cycling, biomass and productivity"
                ])
            ]),
            CurriculumUnit(name: "Theme D — Continuity and Change", topics: [
                CurriculumTopic(name: "D1.1 DNA replication", subtopics: [
                    "Semi-conservative replication and complementary base pairing",
                    "PCR and DNA profiling",
                    "HL: Replication enzymes, directionality and proofreading"
                ]),
                CurriculumTopic(name: "D1.2 Protein synthesis", subtopics: [
                    "D1.2.1 Transcribing RNA from a DNA template",
                    "D1.2.2 Base pairing during transcription",
                    "D1.2.3 Conservation of the DNA template",
                    "D1.2.4 Transcription and gene expression",
                    "D1.2.5 Translating mRNA into a polypeptide",
                    "D1.2.6 Functions of mRNA, ribosomes and tRNA",
                    "D1.2.7 Pairing codons with anticodons",
                    "D1.2.8 Triplets, degeneracy and universality",
                    "D1.2.9 Reading a codon table",
                    "D1.2.10 Ribosome movement and peptide formation",
                    "D1.2.11 How mutations alter proteins",
                    "HL: D1.2.12 Direction of transcription and translation",
                    "HL: D1.2.13 Promoters and transcription initiation",
                    "HL: D1.2.14 Functions of non-coding DNA",
                    "HL: D1.2.15 RNA processing in eukaryotes",
                    "HL: D1.2.16 Alternative exon splicing",
                    "HL: D1.2.17 Starting translation",
                    "HL: D1.2.18 Processing polypeptides into functional proteins",
                    "HL: D1.2.19 Proteasomes and amino acid recycling"
                ]),
                CurriculumTopic(name: "D1.3 Mutation and gene editing", subtopics: [
                    "Gene mutations, causes and consequences",
                    "HL: Gene editing and CRISPR applications"
                ]),
                CurriculumTopic(name: "D2.1 Cell and nuclear division", subtopics: [
                    "Cell cycle, mitosis and cytokinesis",
                    "Meiosis, chromosome segregation and genetic variation"
                ]),
                CurriculumTopic(name: "D2.2 Gene expression", subtopics: [
                    "Regulation of transcription and translation",
                    "Epigenetics and environmental influences"
                ], levels: [.hl]),
                CurriculumTopic(name: "D2.3 Water potential", subtopics: [
                    "Osmosis and water movement in cells",
                    "HL: Solute potential, pressure potential and water potential"
                ]),
                CurriculumTopic(name: "D3.1 Reproduction", subtopics: [
                    "Sexual and asexual reproduction",
                    "Human reproductive systems, fertilization and plant reproduction",
                    "HL: Hormonal control, pregnancy and development"
                ]),
                CurriculumTopic(name: "D3.2 Inheritance", subtopics: [
                    "Genes, alleles, Mendelian inheritance and Punnett squares",
                    "Codominance, sex linkage and pedigree analysis",
                    "HL: Dihybrid crosses, linked genes and recombination"
                ]),
                CurriculumTopic(name: "D3.3 Homeostasis", subtopics: [
                    "Homeostasis and negative feedback",
                    "Blood glucose and body temperature regulation",
                    "HL: Kidney function and osmoregulation"
                ]),
                CurriculumTopic(name: "D4.1 Natural selection", subtopics: [
                    "Heritable variation, selection and reproductive success",
                    "Evolution of antibiotic resistance"
                ]),
                CurriculumTopic(name: "D4.2 Stability and change", subtopics: [
                    "Ecosystem stability, resilience and human impacts",
                    "HL: Ecological succession and alternative stable states"
                ]),
                CurriculumTopic(name: "D4.3 Climate change", subtopics: [
                    "Greenhouse gases, evidence and biological consequences",
                    "Feedback cycles, mitigation and conservation"
                ])
            ]),
            CurriculumUnit(name: "Additional Components", topics: [
                CurriculumTopic(name: "Scientific investigation", subtopics: [
                    "Experimental design, variables and controls",
                    "Data analysis, uncertainty, conclusions and evaluation"
                ]),
                CurriculumTopic(name: "Collaborative sciences project", subtopics: [
                    "Interdisciplinary investigation and collaboration",
                    "Communicating evidence and scientific reasoning"
                ])
            ])
        ]
    }

    // MARK: - IB Mathematics: Analysis & Approaches (first assessment 2021)
    // All 51 SL sections are represented individually. Additional HL content
    // is grouped under its official parent topic and filtered by course level.
    private static var mathAACurriculum: [CurriculumUnit] {
        [
            CurriculumUnit(name: "Topic 1 — Number and Algebra", topics: [
                CurriculumTopic(name: "1.1 Scientific notation", subtopics: ["Calculating with powers of ten", "Representing large and small numbers"]),
                CurriculumTopic(name: "1.2 Arithmetic sequences and series", subtopics: ["Common differences and nth terms", "Finite sums and sigma notation"]),
                CurriculumTopic(name: "1.3 Geometric sequences and series", subtopics: ["Common ratios and nth terms", "Finite geometric sums"]),
                CurriculumTopic(name: "1.4 Financial applications", subtopics: ["Compound interest and depreciation", "Inflation and investment value"]),
                CurriculumTopic(name: "1.5 Exponents and introductory logarithms", subtopics: ["Integer exponent laws", "Base ten and natural logarithms"]),
                CurriculumTopic(name: "1.6 Deductive proof", subtopics: ["Numerical and algebraic proof", "Equality, identity and checking results"]),
                CurriculumTopic(name: "1.7 Exponent and logarithm laws", subtopics: ["Rational exponents and change of base", "Solving exponential and logarithmic equations"]),
                CurriculumTopic(name: "1.8 Infinite geometric series", subtopics: ["Convergence conditions", "Calculating sums to infinity"]),
                CurriculumTopic(name: "1.9 Binomial theorem", subtopics: ["Expanding positive integer powers", "Binomial coefficients and Pascal's triangle"]),
                CurriculumTopic(name: "1.10–1.16 Additional algebra", subtopics: [
                    "Counting principles and generalized binomial expansions",
                    "Partial fractions and complex numbers",
                    "Modulus, argument, polar form and De Moivre's theorem",
                    "Proof by induction, contradiction and counterexample",
                    "Systems of linear equations"
                ], levels: [.hl])
            ]),
            CurriculumUnit(name: "Topic 2 — Functions", topics: [
                CurriculumTopic(name: "2.1 Straight lines", subtopics: ["Gradient and equations of lines", "Parallel and perpendicular lines"]),
                CurriculumTopic(name: "2.2 Functions and inverses", subtopics: ["Function notation, domain and range", "Inverse graphs and one-to-one functions"]),
                CurriculumTopic(name: "2.3 Graphing functions", subtopics: ["Sketching and interpreting graphs", "Using graphing technology"]),
                CurriculumTopic(name: "2.4 Key graph features", subtopics: ["Intercepts, extrema and asymptotes", "Intersections using technology"]),
                CurriculumTopic(name: "2.5 Composite and inverse functions", subtopics: ["Function composition and identity", "Finding and restricting inverse functions"]),
                CurriculumTopic(name: "2.6 Quadratic functions", subtopics: ["Expanded, factored and vertex forms", "Axis of symmetry and graph features"]),
                CurriculumTopic(name: "2.7 Quadratic equations and inequalities", subtopics: ["Factorization, completing the square and quadratic formula", "Discriminant and the nature of roots"]),
                CurriculumTopic(name: "2.8 Reciprocal and rational functions", subtopics: ["Reciprocal graphs", "Rational functions and asymptotes"]),
                CurriculumTopic(name: "2.9 Exponential and logarithmic functions", subtopics: ["Exponential growth and decay models", "Exponential and logarithmic graphs as inverses"]),
                CurriculumTopic(name: "2.10 Solving equations", subtopics: ["Analytical and graphical solutions", "Numerical solutions using technology"]),
                CurriculumTopic(name: "2.11 Transformations", subtopics: ["Translations, reflections and stretches", "Combining graph transformations"]),
                CurriculumTopic(name: "2.12–2.16 Additional functions", subtopics: [
                    "Polynomial division, factor theorem and roots",
                    "Odd, even, self-inverse and rational functions",
                    "Function inequalities and modulus equations"
                ], levels: [.hl])
            ]),
            CurriculumUnit(name: "Topic 3 — Geometry and Trigonometry", topics: [
                CurriculumTopic(name: "3.1 Three-dimensional geometry", subtopics: ["Distance, midpoints and angles", "Surface areas and volumes of solids"]),
                CurriculumTopic(name: "3.2 Triangle trigonometry", subtopics: ["Sine rule, cosine rule and triangle area", "Angles of elevation and depression"]),
                CurriculumTopic(name: "3.3 Applications of trigonometry", subtopics: ["Bearings and diagrams", "Solving two- and three-dimensional problems"]),
                CurriculumTopic(name: "3.4 Radians, arcs and sectors", subtopics: ["Converting degrees and radians", "Arc lengths and sector areas"]),
                CurriculumTopic(name: "3.5 Unit circle", subtopics: ["Sine, cosine and tangent on the unit circle", "Exact values and signs"]),
                CurriculumTopic(name: "3.6 Trigonometric identities", subtopics: ["Pythagorean identity", "Double-angle identities for sine and cosine"]),
                CurriculumTopic(name: "3.7 Trigonometric functions", subtopics: ["Graphs of sin, cos and tan", "Amplitude, period, phase and transformations"]),
                CurriculumTopic(name: "3.8 Trigonometric equations", subtopics: ["Solving within a specified interval", "Using identities and quadratic forms"]),
                CurriculumTopic(name: "3.9–3.20 Additional trigonometry and vectors", subtopics: [
                    "Reciprocal and inverse trigonometric functions",
                    "Compound angle formulae and symmetry identities",
                    "Position vectors, scalar and vector products",
                    "Vector equations of lines and planes",
                    "Intersections, angles, distances and geometric proofs"
                ], levels: [.hl])
            ]),
            CurriculumUnit(name: "Topic 4 — Statistics and Probability", topics: [
                CurriculumTopic(name: "4.1 Sampling", subtopics: ["Populations, samples and sampling bias", "Discrete and continuous data"]),
                CurriculumTopic(name: "4.2 Presenting data", subtopics: ["Frequency tables, histograms and cumulative frequency", "Box plots and identifying outliers"]),
                CurriculumTopic(name: "4.3 Descriptive statistics", subtopics: ["Mean, median and mode", "Range, interquartile range and standard deviation"]),
                CurriculumTopic(name: "4.4 Correlation and regression", subtopics: ["Scatter diagrams and Pearson's correlation coefficient", "Regression of y on x, interpolation and extrapolation"]),
                CurriculumTopic(name: "4.5 Probability", subtopics: ["Sample spaces and complementary events", "Expected frequency"]),
                CurriculumTopic(name: "4.6 Combined events", subtopics: ["Venn diagrams, tree diagrams and addition rules", "Conditional probability and independence"]),
                CurriculumTopic(name: "4.7 Discrete random variables", subtopics: ["Probability distributions", "Expected value and applications"]),
                CurriculumTopic(name: "4.8 Binomial distribution", subtopics: ["Binomial conditions and probabilities", "Mean and variance of a binomial distribution"]),
                CurriculumTopic(name: "4.9 Normal distribution", subtopics: ["Normal curve and its properties", "Probabilities and inverse normal calculations"]),
                CurriculumTopic(name: "4.10 Regression of x on y", subtopics: ["Choosing the appropriate regression line", "Predictions and limits of regression"]),
                CurriculumTopic(name: "4.11 Conditional probability", subtopics: ["Formal conditional probability formula", "Testing events for independence"]),
                CurriculumTopic(name: "4.12 Standardized normal variables", subtopics: ["Z-scores and standardization", "Finding unknown means and standard deviations"]),
                CurriculumTopic(name: "4.13–4.14 Additional probability", subtopics: [
                    "Bayes' theorem and conditional probability",
                    "Continuous random variables and probability density",
                    "Expectation, variance and linear transformations"
                ], levels: [.hl])
            ]),
            CurriculumUnit(name: "Topic 5 — Calculus", topics: [
                CurriculumTopic(name: "5.1 Limits and derivatives", subtopics: ["Limits and the gradient of a curve", "Interpreting derivatives as rates of change"]),
                CurriculumTopic(name: "5.2 Increasing and decreasing functions", subtopics: ["Sign of the first derivative", "Intervals of increasing and decreasing behavior"]),
                CurriculumTopic(name: "5.3 Polynomial differentiation", subtopics: ["Power rule", "Differentiating sums of integer powers"]),
                CurriculumTopic(name: "5.4 Tangents and normals", subtopics: ["Finding tangent gradients and equations", "Finding normal gradients and equations"]),
                CurriculumTopic(name: "5.5 Introductory integration", subtopics: ["Antiderivatives and the constant of integration", "Definite integrals using technology"]),
                CurriculumTopic(name: "5.6 Differentiation rules", subtopics: ["Derivatives of powers, trigonometric, exponential and logarithmic functions", "Chain, product and quotient rules"]),
                CurriculumTopic(name: "5.7 Second derivatives", subtopics: ["Relationships between f, f' and f''", "Interpreting derivative graphs"]),
                CurriculumTopic(name: "5.8 Optimization and curve behavior", subtopics: ["Local extrema and optimization", "Concavity and points of inflexion"]),
                CurriculumTopic(name: "5.9 Kinematics", subtopics: ["Displacement, velocity and acceleration", "Distance travelled and speed"]),
                CurriculumTopic(name: "5.10 Integration techniques", subtopics: ["Standard antiderivatives and reverse chain rule", "Integration by substitution"]),
                CurriculumTopic(name: "5.11 Definite integration and areas", subtopics: ["Fundamental theorem of calculus", "Area under and between curves"]),
                CurriculumTopic(name: "5.12–5.19 Additional calculus", subtopics: [
                    "Continuity, differentiability and limits",
                    "Implicit differentiation and related rates",
                    "Integration by parts and partial fractions",
                    "Volumes of revolution",
                    "First-order differential equations and Euler's method",
                    "Maclaurin series and approximation"
                ], levels: [.hl])
            ]),
            CurriculumUnit(name: "Internal Assessment", topics: [
                CurriculumTopic(name: "Mathematical Exploration (IA)", subtopics: [
                    "Choosing and developing a mathematical investigation",
                    "Mathematical communication, reflection and personal engagement",
                    "Interpreting results and evaluating limitations"
                ])
            ])
        ]
    }

    // MARK: - IB English B HL

    private static var englishBCurriculum: [CurriculumUnit] {
        [
            CurriculumUnit(name: "Themes", topics: [
                CurriculumTopic(name: "Identities", subtopics: [
                    "Personal identity", "Beliefs, values and customs", "Subcultures",
                    "Language and identity", "Health and well-being", "Lifestyle choices"
                ]),
                CurriculumTopic(name: "Experiences", subtopics: [
                    "Leisure, hobbies and interests", "Holidays and travel", "Life stories",
                    "Rites of passage", "Customs and traditions", "Migration"
                ]),
                CurriculumTopic(name: "Human Ingenuity", subtopics: [
                    "Entertainment", "Artistic expressions", "Communication and media",
                    "Technology", "Scientific innovation", "Social entrepreneurship"
                ]),
                CurriculumTopic(name: "Social Organisation", subtopics: [
                    "Social relationships", "Community", "Social engagement",
                    "Education", "The working world", "Law and order"
                ]),
                CurriculumTopic(name: "Sharing the Planet", subtopics: [
                    "The environment", "Human impact on the environment", "Rights and responsibilities",
                    "Peace and conflict", "Equality", "Globalisation"
                ]),
            ]),
            CurriculumUnit(name: "Skills", topics: [
                CurriculumTopic(name: "Receptive Skills (Paper 2)", subtopics: [
                    "Reading comprehension strategies", "Text handling exercises",
                    "Inferring meaning from context", "Identifying text type and purpose",
                    "Listening for gist and detail", "Summarising and synthesising information"
                ]),
                CurriculumTopic(name: "Productive Skills (Paper 1)", subtopics: [
                    "Text types: article, blog, report, letter, speech, review",
                    "Register and audience awareness", "Structural conventions",
                    "Persuasive writing techniques", "Descriptive and narrative writing"
                ]),
                CurriculumTopic(name: "Individual Oral", subtopics: [
                    "Literary extract analysis", "Linking to prescribed themes",
                    "Presentation structure", "Discussion and Q&A strategies",
                    "Using evidence from the text"
                ]),
                CurriculumTopic(name: "Higher Level Extension", subtopics: [
                    "Literary analysis and criticism", "Responding to literature",
                    "Comparative literary discussion", "Cultural context and texts"
                ], levels: [.hl]),
            ]),
        ]
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - IB Russian A Literature SL
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private static var russianLitCurriculum: [CurriculumUnit] {
        [
            CurriculumUnit(name: "Areas of Exploration", topics: [
                CurriculumTopic(name: "Readers, Writers and Texts", subtopics: [
                    "Why and how we study literature", "Reader response theory",
                    "The role of the author", "Narrative techniques and style",
                    "Authorial intent vs reader interpretation"
                ]),
                CurriculumTopic(name: "Time and Space", subtopics: [
                    "Literature in its cultural context", "Historical influences on texts",
                    "Setting as narrative device", "Chronology and time shifts",
                    "Place and displacement in literature"
                ]),
                CurriculumTopic(name: "Intertextuality", subtopics: [
                    "Connections between texts", "Genre conventions and subversion",
                    "Literary allusions and references", "Comparative analysis techniques",
                    "Transformation of themes across texts"
                ]),
            ]),
            CurriculumUnit(name: "Assessment", topics: [
                CurriculumTopic(name: "Guided Literary Analysis (Paper 1)", subtopics: [
                    "Analysing unseen prose passages", "Analysing unseen poetry",
                    "Structure and form analysis", "Tone, mood and atmosphere",
                    "Literary devices identification and effect"
                ]),
                CurriculumTopic(name: "Comparative Essay (Paper 2)", subtopics: [
                    "Comparative essay structure", "Thematic connections between works",
                    "Technique comparison across texts", "Using quotations effectively",
                    "Evaluative and analytical writing"
                ]),
                CurriculumTopic(name: "Individual Oral", subtopics: [
                    "Connecting text to global issues", "Close textual analysis",
                    "Presentation and discussion skills", "Evidence-based argumentation"
                ]),
                CurriculumTopic(name: "Higher Level Essay", subtopics: [
                    "HL: Formulating a focused line of inquiry",
                    "HL: Sustaining a literary argument across 1,200-1,500 words",
                    "HL: Integrating close analysis and broader authorial choices",
                    "HL: Academic referencing and independent drafting"
                ], levels: [.hl]),
                CurriculumTopic(name: "Literary Analysis Skills", subtopics: [
                    "Figurative language and imagery", "Narrative voice and perspective",
                    "Characterisation techniques", "Symbolism and motifs",
                    "Irony, satire and tone"
                ]),
            ]),
        ]
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Advanced Mathematics (personal course, beyond IB)
    // Proof-first foundations for students who finished Mathematics AA/HL.
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private static var advancedMathCurriculum: [CurriculumUnit] {
        [
            CurriculumUnit(name: "Unit 1 — Course Overview", topics: [
                CurriculumTopic(name: "How This Course Fits After IB Mathematics", subtopics: [
                    "What this course covers",
                    "How to use the materials",
                    "The proof-first mindset",
                    "Suggested study path",
                    "Notation and terminology refresher"
                ]),
                CurriculumTopic(name: "Mathematical Writing", subtopics: [
                    "Structuring a proof",
                    "Quantifiers and logical notation",
                    "Common logical fallacies",
                    "Clear exposition and signposting",
                    "Writing for the reader"
                ]),
            ]),
            CurriculumUnit(name: "Unit 2 — Proof Techniques", topics: [
                CurriculumTopic(name: "Direct Proof", subtopics: [
                    "The structure of a direct proof",
                    "Proving algebraic identities",
                    "Proving divisibility statements",
                    "Proving inequalities",
                    "Worked examples and practice"
                ]),
                CurriculumTopic(name: "Proof by Contradiction", subtopics: [
                    "The strategy of contradiction",
                    "Proving the irrationality of √2",
                    "The infinitude of primes",
                    "Contradiction in geometry",
                    "When contradiction is the natural tool"
                ]),
                CurriculumTopic(name: "Proof by Induction", subtopics: [
                    "The principle of mathematical induction",
                    "Strong induction",
                    "Induction with inequalities",
                    "Induction with divisibility",
                    "Structural induction"
                ]),
                CurriculumTopic(name: "Contrapositive and Exhaustion", subtopics: [
                    "The contrapositive equivalence",
                    "Proof by exhaustion and cases",
                    "Without loss of generality",
                    "Combining proof techniques",
                    "Choosing the right technique"
                ]),
                CurriculumTopic(name: "Advanced Proof Methods", subtopics: [
                    "The pigeonhole principle",
                    "Existence proofs by construction",
                    "Uniqueness proofs",
                    "Epsilon-delta fundamentals",
                    "A proof-writing workshop"
                ]),
            ]),
            CurriculumUnit(name: "Unit 3 — Number Theory and Algebra", topics: [
                CurriculumTopic(name: "Modular Arithmetic", subtopics: [
                    "Congruences",
                    "Modular inverses",
                    "The Chinese remainder theorem",
                    "Fermat's little theorem",
                    "Applications of modular arithmetic"
                ]),
                CurriculumTopic(name: "Classical Number Theory", subtopics: [
                    "Division algorithm and GCD",
                    "The Euclidean algorithm",
                    "The fundamental theorem of arithmetic",
                    "Diophantine equations",
                    "Prime distribution intuition"
                ]),
                CurriculumTopic(name: "Algebraic Structures", subtopics: [
                    "Groups",
                    "Rings",
                    "Fields",
                    "Homomorphisms",
                    "Isomorphisms"
                ]),
                CurriculumTopic(name: "Complex Numbers, Deeper", subtopics: [
                    "Polar form and Euler's formula",
                    "Roots of unity",
                    "Complex functions",
                    "Complex sums and series",
                    "Applications of complex numbers"
                ]),
            ]),
            CurriculumUnit(name: "Unit 4 — Real Analysis Foundations", topics: [
                CurriculumTopic(name: "Sequences and Limits", subtopics: [
                    "Definition of convergence",
                    "Monotone convergence",
                    "Subsequences",
                    "Limit laws",
                    "Cauchy sequences"
                ]),
                CurriculumTopic(name: "Continuity", subtopics: [
                    "The limit definition of continuity",
                    "The intermediate value theorem",
                    "The extreme value theorem",
                    "Uniform continuity",
                    "Continuity and topology intuition"
                ]),
                CurriculumTopic(name: "Differentiation", subtopics: [
                    "The definition of the derivative",
                    "The mean value theorem",
                    "Rolle's theorem",
                    "Taylor's theorem",
                    "L'Hôpital's rule"
                ]),
                CurriculumTopic(name: "Integration", subtopics: [
                    "Riemann sums",
                    "The fundamental theorem of calculus",
                    "Integration techniques",
                    "Improper integrals",
                    "Applications of integration"
                ]),
                CurriculumTopic(name: "Series", subtopics: [
                    "Convergence tests",
                    "Power series",
                    "Taylor series",
                    "Radius of convergence",
                    "Series in applications"
                ]),
            ]),
            CurriculumUnit(name: "Unit 5 — Linear Algebra and Applications", topics: [
                CurriculumTopic(name: "Vector Spaces", subtopics: [
                    "Definitions and axioms",
                    "Subspaces",
                    "Span and linear independence",
                    "Basis and dimension",
                    "Examples from IB topics"
                ]),
                CurriculumTopic(name: "Linear Transformations", subtopics: [
                    "Matrix representations",
                    "Kernel and image",
                    "The rank-nullity theorem",
                    "Change of basis",
                    "Transformations in geometry"
                ]),
                CurriculumTopic(name: "Eigenvalues and Diagonalization", subtopics: [
                    "The characteristic polynomial",
                    "Eigenvectors and eigenspaces",
                    "Diagonalizability",
                    "The Cayley-Hamilton theorem",
                    "Applications to recurrence systems"
                ]),
                CurriculumTopic(name: "Geometry of Linear Algebra", subtopics: [
                    "Dot and cross products",
                    "Orthogonality",
                    "Projections",
                    "Least squares",
                    "Applications in physics and economics"
                ]),
            ]),
        ]
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Fundamentals of the Universe (personal course)
    // Cosmology, stellar evolution and fundamental physics for curious minds.
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private static var universeCurriculum: [CurriculumUnit] {
        [
            CurriculumUnit(name: "Unit 1 — Course Overview", topics: [
                CurriculumTopic(name: "What This Course Covers", subtopics: [
                    "The scope of the universe",
                    "Why it matters",
                    "The journey map",
                    "Key tools and methods",
                    "How to use this course"
                ]),
                CurriculumTopic(name: "Cosmic Scales", subtopics: [
                    "Units: AU, light-years and parsecs",
                    "Powers of ten",
                    "The observable universe",
                    "Orders of magnitude",
                    "Estimating the unobservable"
                ]),
            ]),
            CurriculumUnit(name: "Unit 2 — Fundamental Physics", topics: [
                CurriculumTopic(name: "The Four Forces of Nature", subtopics: [
                    "Gravity",
                    "Electromagnetism",
                    "The strong nuclear force",
                    "The weak nuclear force",
                    "The search for unification"
                ]),
                CurriculumTopic(name: "Special Relativity", subtopics: [
                    "The two postulates",
                    "Time dilation",
                    "Length contraction",
                    "E = mc²",
                    "Relativistic momentum and energy"
                ]),
                CurriculumTopic(name: "General Relativity", subtopics: [
                    "Spacetime curvature",
                    "The equivalence principle",
                    "Gravitational lensing",
                    "Gravitational waves",
                    "Black hole spacetime"
                ]),
                CurriculumTopic(name: "Quantum Essentials", subtopics: [
                    "Wave-particle duality",
                    "The uncertainty principle",
                    "Quantisation of energy",
                    "The standard model",
                    "Matter and antimatter"
                ]),
            ]),
            CurriculumUnit(name: "Unit 3 — Stars and Stellar Evolution", topics: [
                CurriculumTopic(name: "Nuclear Fusion in Stars", subtopics: [
                    "Stellar fusion reactions",
                    "The proton-proton chain",
                    "The CNO cycle",
                    "Synthesising heavier elements",
                    "Stellar mass and luminosity"
                ]),
                CurriculumTopic(name: "The Stellar Life Cycle", subtopics: [
                    "Nebulae and star formation",
                    "The main sequence",
                    "Red giants",
                    "White dwarfs",
                    "Supernovae"
                ]),
                CurriculumTopic(name: "Compact Objects", subtopics: [
                    "Neutron stars",
                    "Pulsars",
                    "Black holes",
                    "The event horizon",
                    "Hawking radiation"
                ]),
            ]),
            CurriculumUnit(name: "Unit 4 — Cosmology", topics: [
                CurriculumTopic(name: "The Big Bang", subtopics: [
                    "Observational evidence",
                    "Expansion and Hubble's law",
                    "The cosmic microwave background",
                    "Big Bang nucleosynthesis",
                    "A timeline of the universe"
                ]),
                CurriculumTopic(name: "Dark Matter and Dark Energy", subtopics: [
                    "Evidence for dark matter",
                    "Galaxy rotation curves",
                    "Gravitational lensing evidence",
                    "The accelerating universe",
                    "The cosmological constant"
                ]),
                CurriculumTopic(name: "The Structure of the Universe", subtopics: [
                    "Galaxies and clusters",
                    "Large-scale structure",
                    "The cosmic web",
                    "Cosmic inflation",
                    "The fate of the universe"
                ]),
            ]),
            CurriculumUnit(name: "Unit 5 — Planets and Life", topics: [
                CurriculumTopic(name: "Planetary Systems", subtopics: [
                    "Formation of the solar system",
                    "Planet types",
                    "Exoplanet detection methods",
                    "Kepler and TESS",
                    "Planetary atmospheres"
                ]),
                CurriculumTopic(name: "Habitability and Life", subtopics: [
                    "The habitable zone",
                    "Requirements for life",
                    "The Fermi paradox",
                    "The search for life",
                    "SETI"
                ]),
                CurriculumTopic(name: "Human Exploration", subtopics: [
                    "The space race",
                    "Rocket science basics",
                    "Satellites and orbits",
                    "Missions to Mars",
                    "The future of space travel"
                ]),
            ]),
        ]
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Life (personal course)
    // A practical, non-IB curriculum for a teenage founder. Each unit is large
    // enough to function as a standalone course and ends in applied founder work.
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private static var lifeCurriculum: [CurriculumUnit] {
        [
            CurriculumUnit(name: "Unit 1 - Startup Fundamentals", topics: [
                CurriculumTopic(name: "How Startups Work", subtopics: [
                    "Startup vs small business vs scale-up", "The startup lifecycle from idea to exit",
                    "Founder, co-founder, employee, advisor, angel and VC roles", "Equity, ownership and incentives",
                    "Risk, uncertainty and asymmetric outcomes", "Common startup failure modes"
                ]),
                CurriculumTopic(name: "Finding a Real Problem", subtopics: [
                    "Problem selection and founder-market fit", "Market pain, frequency and urgency",
                    "Customer segments and ideal customer profiles", "Customer discovery interviews",
                    "Avoiding leading questions and false validation", "Turning observations into testable hypotheses"
                ]),
                CurriculumTopic(name: "Product Foundations", subtopics: [
                    "Problem-solution fit", "Minimum viable product (MVP)", "Prototype vs MVP vs production product",
                    "Build-measure-learn loops", "Product requirements and scope discipline",
                    "Product-market fit signals", "Pivot, persevere or stop decisions"
                ]),
                CurriculumTopic(name: "Startup Language", subtopics: [
                    "TAM, SAM and SOM", "B2B, B2C, B2B2C and marketplaces", "SaaS and recurring revenue",
                    "ARR, MRR and annual contract value", "DAU, WAU and MAU", "Activation, retention and churn",
                    "CAC, LTV and payback period", "Gross margin and contribution margin"
                ]),
                CurriculumTopic(name: "Founder Operating System", subtopics: [
                    "Setting weekly priorities", "Decision logs and reversible decisions", "Managing school and startup energy",
                    "Working with adults as a young founder", "Building credibility without pretending expertise",
                    "Ethics, privacy and duty of care", "Resilience without glorifying burnout"
                ])
            ]),
            CurriculumUnit(name: "Unit 2 - Machine Learning and LLMs", topics: [
                CurriculumTopic(name: "Computing and Data Foundations", subtopics: [
                    "Bits, files, memory and computation", "Algorithms and data structures", "Python and notebooks",
                    "APIs, databases and cloud services", "Structured vs unstructured data", "Data cleaning and labeling",
                    "Training, validation and test sets", "Correlation, causation and leakage"
                ]),
                CurriculumTopic(name: "Machine Learning from Zero", subtopics: [
                    "What machine learning is", "Supervised, unsupervised and reinforcement learning",
                    "Features, labels, parameters and hyperparameters", "Regression and classification",
                    "Loss functions and optimization", "Gradient descent intuition", "Overfitting and underfitting",
                    "Bias-variance trade-off", "Precision, recall, F1 and confusion matrices"
                ]),
                CurriculumTopic(name: "Neural Networks", subtopics: [
                    "Neurons, weights, biases and activations", "Layers and representations", "Forward propagation",
                    "Backpropagation intuition", "Embeddings and vector similarity", "Attention mechanisms",
                    "Transformers", "Compute, memory and batching", "Pre-training, fine-tuning and inference"
                ]),
                CurriculumTopic(name: "Large Language Models", subtopics: [
                    "Tokens and tokenization", "Next-token prediction", "Context windows", "Prompts and system instructions",
                    "Temperature and sampling", "Hallucinations and calibration", "Retrieval-augmented generation (RAG)",
                    "Tool use and function calling", "Agents and workflows", "Fine-tuning, adapters and distillation",
                    "Multimodal models", "Evaluation datasets and human evaluation"
                ]),
                CurriculumTopic(name: "Building an AI Product", subtopics: [
                    "Choosing a model and provider", "Prototype architecture", "Prompt and output contracts",
                    "Latency, reliability and fallbacks", "Token costs and unit economics", "Caching and rate limits",
                    "Guardrails and content safety", "Privacy, consent and data retention", "Observability and evaluations",
                    "Shipping an AI MVP", "When not to use an LLM"
                ]),
                CurriculumTopic(name: "LLM Systems in Production", subtopics: [
                    "Inference endpoints and model serving", "Throughput, latency and tail latency",
                    "Batching, streaming and the KV cache", "Quantization and memory trade-offs",
                    "Structured outputs and schema validation", "Semantic caching and request deduplication",
                    "Routing, fallbacks and graceful degradation", "Tracing prompts, tools and model calls",
                    "Offline evals, golden sets and regression gates", "Red-teaming and prompt-injection testing",
                    "SLOs, cost budgets and incident response", "Data retention and deletion in AI systems"
                ]),
                CurriculumTopic(name: "AI Strategy and Responsible Use", subtopics: [
                    "Open-source vs hosted models", "Model commoditization and durable moats", "Data network effects",
                    "Copyright and training data", "Bias and fairness", "Security threats and prompt injection",
                    "Regulatory awareness", "Human oversight", "Communicating AI limitations honestly"
                ])
            ]),
            CurriculumUnit(name: "Unit 3 - Human Behavior and Influence", topics: [
                CurriculumTopic(name: "Behavior Foundations", subtopics: [
                    "Attention, memory and cognitive load", "Motivation and incentives", "Identity and status",
                    "Social proof and conformity", "Loss aversion and framing", "Anchoring and contrast effects",
                    "Confirmation bias", "Trust, reciprocity and consistency", "Ethical influence vs manipulation"
                ]),
                CurriculumTopic(name: "Presence and Communication", subtopics: [
                    "Clear thinking before speaking", "Voice, pace and pauses", "Body language and eye contact",
                    "Listening for interests and constraints", "Asking high-leverage questions", "Mirroring and labeling",
                    "Concise explanations", "Story structure", "Reading the room", "Presenting with calm authority"
                ]),
                CurriculumTopic(name: "Steering Conversations", subtopics: [
                    "Setting the frame and desired outcome", "Building an agenda collaboratively", "Finding shared ground",
                    "Redirecting without evasion", "Using summaries to regain control", "Handling interruptions",
                    "Responding to hostility", "Saying no while preserving the relationship", "Closing with a concrete next step"
                ]),
                CurriculumTopic(name: "Debate and Argument", subtopics: [
                    "Claims, evidence and warrants", "Validity, soundness and burden of proof", "Steel-manning",
                    "Common logical fallacies", "Cross-examination questions", "Rebuttal and counter-rebuttal",
                    "Concessions that strengthen credibility", "Handling uncertainty", "Persuading an audience vs defeating an opponent",
                    "Knowing when not to debate"
                ]),
                CurriculumTopic(name: "Negotiation", subtopics: [
                    "Positions vs interests", "BATNA, reservation point and ZOPA", "Anchoring responsibly",
                    "Information gathering", "Tradeable variables", "Calibrated questions", "Handling objections",
                    "Multi-issue offers", "Documenting agreements", "Long-term reputation and repeat games"
                ])
            ]),
            CurriculumUnit(name: "Unit 4 - Build, Sell and Fund", topics: [
                CurriculumTopic(name: "Go-to-Market", subtopics: [
                    "Positioning and category", "Value propositions", "Beachhead markets", "Founder-led sales",
                    "Sales discovery and qualification", "Demos that prove value", "Pricing and packaging",
                    "Acquisition channels", "Content, community and partnerships", "Growth loops and referrals"
                ]),
                CurriculumTopic(name: "Metrics and Finance", subtopics: [
                    "Cohort retention", "North-star and counter-metrics", "Funnel conversion", "Revenue models",
                    "Burn rate and runway", "Cash-flow forecasting", "Budgeting and scenario planning",
                    "Cap tables and option pools", "Dilution modeling", "Basic startup accounting and tax hygiene"
                ]),
                CurriculumTopic(name: "Pitching", subtopics: [
                    "Audience and pitch objective", "Problem, insight and urgency", "Product and live demo",
                    "Market and competition", "Traction and proof", "Business model and economics", "Why this team",
                    "The ask and use of funds", "Pitch deck narrative", "Two-minute, five-minute and investor pitches",
                    "Question handling and follow-up"
                ]),
                CurriculumTopic(name: "Fundraising and Venture Capital", subtopics: [
                    "Bootstrapping, grants, angels and venture capital", "Pre-seed, seed and Series A milestones",
                    "How venture funds make money", "Investor sourcing and warm introductions", "Fundraising process and momentum",
                    "SAFE notes and convertible instruments", "Valuation and dilution", "Liquidation preferences",
                    "Pro-rata, anti-dilution and control rights", "Term-sheet negotiation", "Due diligence and data rooms"
                ]),
                CurriculumTopic(name: "Team, Legal and Execution", subtopics: [
                    "Co-founder selection and equity splits", "Vesting and cliffs", "Hiring the first team",
                    "Feedback, conflict and accountability", "Company formation and founder agreements",
                    "Contracts, intellectual property and confidentiality", "Board updates and investor relations",
                    "Security and privacy basics", "Launch readiness", "Post-launch learning and iteration"
                ])
            ])
        ]
    }
}
