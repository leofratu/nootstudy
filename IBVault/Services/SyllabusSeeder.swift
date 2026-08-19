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
            context.delete(node)
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
            catalogVersion: "2026.1 / first assessment \(firstAssessment)",
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

    private static var biologyCurriculum: [CurriculumUnit] {
        [
            CurriculumUnit(name: "Theme A — Unity and Diversity", topics: [
                CurriculumTopic(name: "Water and Biomolecules", subtopics: [
                    "Hydrogen bonding in water",
                    "Thermal properties of water",
                    "Solvent properties of water",
                    "Carbohydrates — monosaccharides, disaccharides, polysaccharides",
                    "Lipids — triglycerides, phospholipids",
                    "Proteins — amino acids, peptide bonds, levels of structure"
                ]),
                CurriculumTopic(name: "DNA and Nucleic Acids", subtopics: [
                    "DNA structure and base pairing",
                    "RNA types and structure",
                    "Semi-conservative DNA replication",
                    "Transcription and translation",
                    "Gene expression and regulation"
                ]),
                CurriculumTopic(name: "Evolution", subtopics: [
                    "Evidence for evolution",
                    "Natural selection mechanism",
                    "Speciation (allopatric and sympatric)",
                    "Classification and taxonomy",
                    "Cladistics and phylogenetic trees"
                ]),
                CurriculumTopic(name: "Biodiversity", subtopics: [
                    "Measuring biodiversity",
                    "Threats to biodiversity",
                    "Conservation biology strategies",
                    "Keystone species and indicator species",
                    "In situ and ex situ conservation"
                ]),
            ]),

            CurriculumUnit(name: "Theme B — Form and Function", topics: [
                CurriculumTopic(name: "Cells and Cell Structure", subtopics: [
                    "Prokaryotic cell structure",
                    "Eukaryotic cell ultrastructure",
                    "Organelle functions (mitochondria, chloroplasts, ER, Golgi)",
                    "Comparing prokaryotes and eukaryotes",
                    "Origins of cells and endosymbiotic theory",
                    "Electron microscopy interpretation"
                ]),
                CurriculumTopic(name: "Membranes and Transport", subtopics: [
                    "Fluid mosaic model",
                    "Membrane proteins and their functions",
                    "Simple and facilitated diffusion",
                    "Osmosis",
                    "Active transport",
                    "Endocytosis and exocytosis"
                ]),
                CurriculumTopic(name: "Enzymes and Metabolism", subtopics: [
                    "Enzyme structure and function",
                    "Enzyme-substrate specificity",
                    "Factors affecting enzyme activity",
                    "Competitive and non-competitive inhibition",
                    "Metabolic pathways — anabolism and catabolism"
                ]),
                CurriculumTopic(name: "Human Physiology Systems", subtopics: [
                    "Digestion and absorption",
                    "The circulatory system",
                    "Gas exchange in the lungs",
                    "Defence against infectious disease",
                    "Neurons and synaptic transmission",
                    "Hormonal regulation (endocrine system)",
                    "Homeostasis and feedback mechanisms"
                ]),
            ]),

            CurriculumUnit(name: "Theme C — Interaction and Interdependence", topics: [
                CurriculumTopic(name: "Ecosystems", subtopics: [
                    "Species, communities and ecosystems",
                    "Biotic and abiotic factors",
                    "Trophic levels and food webs",
                    "Habitat and ecological niches"
                ]),
                CurriculumTopic(name: "Energy Flow in Ecosystems", subtopics: [
                    "Energy flow through trophic levels",
                    "Productivity (GPP, NPP)",
                    "Energy pyramids",
                    "Photosynthesis — light-dependent and light-independent reactions",
                    "Cell respiration — glycolysis, Krebs cycle, oxidative phosphorylation"
                ]),
                CurriculumTopic(name: "Population Biology", subtopics: [
                    "Population growth curves (S and J curves)",
                    "Carrying capacity and limiting factors",
                    "Predator-prey relationships",
                    "Sampling techniques for populations"
                ]),
                CurriculumTopic(name: "Sustainability", subtopics: [
                    "Carbon cycling and climate change",
                    "Nitrogen cycling",
                    "Human impact on ecosystems",
                    "Sustainable development and resource management"
                ]),
            ]),

            CurriculumUnit(name: "Theme D — Continuity and Change", topics: [
                CurriculumTopic(name: "Genetics", subtopics: [
                    "Genes, alleles and the genome",
                    "Chromosomes and karyotypes",
                    "DNA profiling and biotechnology",
                    "Gene mutations"
                ]),
                CurriculumTopic(name: "Inheritance", subtopics: [
                    "Mendel's laws of inheritance",
                    "Monohybrid crosses and Punnett squares",
                    "Codominance and multiple alleles",
                    "Sex-linked inheritance",
                    "Pedigree analysis",
                    "Dihybrid crosses"
                ]),
                CurriculumTopic(name: "Natural Selection", subtopics: [
                    "Variation within populations",
                    "Directional and stabilising selection",
                    "Antibiotic resistance as example",
                    "Sexual selection"
                ]),
                CurriculumTopic(name: "Evolutionary Change", subtopics: [
                    "Gradualism vs punctuated equilibrium",
                    "Adaptive radiation",
                    "Convergent and divergent evolution",
                    "Human evolution"
                ]),
            ]),

            CurriculumUnit(name: "Higher Level Extension", topics: [
                CurriculumTopic(name: "Advanced Molecular Biology", subtopics: [
                    "HL: DNA replication and the roles of polymerases",
                    "HL: Transcription regulation and RNA processing",
                    "HL: Translation, ribosome structure and polypeptide synthesis",
                    "HL: Gene expression, epigenetics and environmental influence"
                ], levels: [.hl]),
                CurriculumTopic(name: "Advanced Physiology", subtopics: [
                    "HL: Muscle contraction and the sliding filament model",
                    "HL: Kidney function, osmoregulation and hormonal control",
                    "HL: Reproduction, gametogenesis and hormonal regulation",
                    "HL: Immune response, antibody production and vaccination"
                ], levels: [.hl]),
                CurriculumTopic(name: "Advanced Ecology and Evolution", subtopics: [
                    "HL: Gene pools, allele frequencies and population change",
                    "HL: Speciation mechanisms and reproductive isolation",
                    "HL: Community succession and ecosystem stability",
                    "HL: Statistical testing and interpretation in biological investigations"
                ], levels: [.hl]),
            ]),

            CurriculumUnit(name: "Additional Components", topics: [
                CurriculumTopic(name: "Nature of Science", subtopics: [
                    "Observations and hypotheses",
                    "Experimental design",
                    "Variables and controls",
                    "Falsifiability and paradigm shifts"
                ]),
                CurriculumTopic(name: "Experimental Investigations", subtopics: [
                    "Planning and designing experiments",
                    "Data collection and processing",
                    "Conclusions and evaluation",
                    "Scientific report writing"
                ]),
                CurriculumTopic(name: "Collaborative Science Project", subtopics: [
                    "Group research project",
                    "Interdisciplinary approaches",
                    "Communication of findings"
                ]),
            ]),
        ]
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - IB Mathematics: Analysis & Approaches SL (2021)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private static var mathAACurriculum: [CurriculumUnit] {
        [
            CurriculumUnit(name: "Topic 1 — Number and Algebra", topics: [
                CurriculumTopic(name: "Indices and Logarithms", subtopics: [
                    "Laws of exponents",
                    "Logarithmic functions and laws",
                    "Natural logarithm (ln)",
                    "Solving equations with exponents and logs",
                    "Change of base formula"
                ]),
                CurriculumTopic(name: "Sequences and Series", subtopics: [
                    "Arithmetic sequences and series",
                    "Geometric sequences and series",
                    "Sum to infinity of geometric series",
                    "Sigma notation",
                    "Applications of sequences and series"
                ]),
                CurriculumTopic(name: "Exponential Functions", subtopics: [
                    "Exponential growth and decay models",
                    "Compound interest and depreciation",
                    "The number e and natural exponential",
                    "Graphs of exponential functions"
                ]),
            ]),

            CurriculumUnit(name: "Topic 2 — Functions", topics: [
                CurriculumTopic(name: "Function Notation", subtopics: [
                    "Domain and range",
                    "Function notation f(x)",
                    "Composite functions f∘g",
                    "Inverse functions f⁻¹",
                    "Self-inverse functions"
                ]),
                CurriculumTopic(name: "Graphs and Transformations", subtopics: [
                    "Translations (horizontal and vertical shifts)",
                    "Reflections in axes",
                    "Stretches and compressions",
                    "Combined transformations",
                    "Asymptotes"
                ]),
                CurriculumTopic(name: "Polynomial, Rational and Exponential Functions", subtopics: [
                    "Quadratic functions and completing the square",
                    "The discriminant and nature of roots",
                    "Polynomial division and the factor theorem",
                    "Rational functions and their graphs",
                    "Exponential and logarithmic function graphs"
                ]),
            ]),

            CurriculumUnit(name: "Topic 3 — Geometry and Trigonometry", topics: [
                CurriculumTopic(name: "Angles and Triangles", subtopics: [
                    "Sine rule",
                    "Cosine rule",
                    "Area of a triangle (½ab sin C)",
                    "Applications in 2D and 3D problems"
                ]),
                CurriculumTopic(name: "Trigonometric Functions", subtopics: [
                    "Unit circle and radian measure",
                    "Graphs of sin, cos, tan",
                    "Amplitude, period and phase shift",
                    "Trigonometric equations",
                    "Inverse trigonometric functions"
                ]),
                CurriculumTopic(name: "Trigonometric Identities", subtopics: [
                    "Pythagorean identities",
                    "Double angle formulae",
                    "Compound angle formulae",
                    "Proving trigonometric identities"
                ]),
            ]),

            CurriculumUnit(name: "Topic 4 — Statistics and Probability", topics: [
                CurriculumTopic(name: "Data Analysis", subtopics: [
                    "Measures of central tendency (mean, median, mode)",
                    "Measures of dispersion (range, IQR, standard deviation)",
                    "Box plots and cumulative frequency",
                    "Outliers and their treatment"
                ]),
                CurriculumTopic(name: "Probability Rules", subtopics: [
                    "Sample spaces and Venn diagrams",
                    "Combined events (AND/OR)",
                    "Conditional probability",
                    "Independent and mutually exclusive events",
                    "Tree diagrams"
                ]),
                CurriculumTopic(name: "Normal Distribution", subtopics: [
                    "Properties of the normal distribution",
                    "Z-scores and standardisation",
                    "Inverse normal calculations",
                    "Applications of the normal distribution"
                ]),
                CurriculumTopic(name: "Correlation and Regression", subtopics: [
                    "Scatter diagrams",
                    "Pearson's correlation coefficient (r)",
                    "Least squares regression line",
                    "Coefficient of determination (r²)",
                    "Interpolation and extrapolation"
                ]),
            ]),

            CurriculumUnit(name: "Topic 5 — Calculus", topics: [
                CurriculumTopic(name: "Limits", subtopics: [
                    "Concept of a limit",
                    "Limits at a point",
                    "Limits at infinity",
                    "Continuity"
                ]),
                CurriculumTopic(name: "Differentiation", subtopics: [
                    "First principles of differentiation",
                    "Power rule",
                    "Chain rule",
                    "Product and quotient rules",
                    "Derivatives of trigonometric functions",
                    "Derivatives of exponential and logarithmic functions"
                ]),
                CurriculumTopic(name: "Integration", subtopics: [
                    "Indefinite integrals and antiderivatives",
                    "Definite integrals",
                    "Integration by substitution",
                    "Area under a curve",
                    "Area between two curves"
                ]),
                CurriculumTopic(name: "Applications of Calculus", subtopics: [
                    "Tangent and normal lines",
                    "Maximum and minimum problems",
                    "Optimisation problems",
                    "Kinematics (displacement, velocity, acceleration)",
                    "Rates of change and related rates"
                ]),
            ]),

            CurriculumUnit(name: "Higher Level Extension", topics: [
                CurriculumTopic(name: "Proof, Complex Numbers and Advanced Algebra", subtopics: [
                    "HL: Proof by induction, contradiction and counterexample",
                    "HL: Complex numbers in Cartesian, polar and exponential form",
                    "HL: De Moivre's theorem and roots of complex numbers",
                    "HL: Polynomial roots, sums and products of roots",
                    "HL: Systems of linear equations and solution structure"
                ], levels: [.hl]),
                CurriculumTopic(name: "Vectors and Advanced Geometry", subtopics: [
                    "HL: Vector equations of lines and planes",
                    "HL: Intersections, angles and distances in three dimensions",
                    "HL: Scalar and vector products",
                    "HL: Geometric transformations using matrices"
                ], levels: [.hl]),
                CurriculumTopic(name: "Advanced Statistics and Probability", subtopics: [
                    "HL: Discrete and continuous random variables",
                    "HL: Binomial and Poisson distributions",
                    "HL: Expectation, variance and linear combinations",
                    "HL: Hypothesis testing and confidence intervals"
                ], levels: [.hl]),
                CurriculumTopic(name: "Advanced Calculus", subtopics: [
                    "HL: Implicit differentiation and related rates",
                    "HL: Integration by parts and partial fractions",
                    "HL: First-order differential equations and Euler's method",
                    "HL: Maclaurin series and local approximation",
                    "HL: Volumes of revolution and advanced optimisation"
                ], levels: [.hl]),
            ]),

            CurriculumUnit(name: "Internal Assessment", topics: [
                CurriculumTopic(name: "Mathematical Exploration (IA)", subtopics: [
                    "Choosing a topic with personal engagement",
                    "Mathematical communication and notation",
                    "Use of mathematics (beyond the syllabus encouraged)",
                    "Reflection and personal connection",
                    "Assessment criteria (worth ~20% of final grade)"
                ]),
            ]),
        ]
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - IB English B HL
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

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
