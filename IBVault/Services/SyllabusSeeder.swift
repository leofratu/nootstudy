import Foundation
import SwiftData

// MARK: - Curriculum Structure
struct CurriculumUnit {
    let name: String
    let topics: [CurriculumTopic]
}

struct CurriculumTopic {
    let name: String
    let subtopics: [String]
}

struct SyllabusSeeder {
    static func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<Subject>()
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        guard existingCount == 0 else { return }

        let subjects = createSubjects()
        for subject in subjects {
            context.insert(subject)
        }
        try? context.save()
    }

    /// Returns the curriculum tree for a subject (used by TopicBrowserView)
    static func curriculum(for subjectName: String) -> [CurriculumUnit] {
        switch subjectName {
        case "English B": return englishBCurriculum
        case "Russian A Literature": return russianLitCurriculum
        case "Biology": return biologyCurriculum
        case "Mathematics AA": return mathAACurriculum
        case "Economics": return economicsCurriculum
        case "Business Management": return businessCurriculum
        default: return []
        }
    }

    // MARK: - Create Subjects with Seed Cards

    private static func createSubjects() -> [Subject] {
        var subjects: [Subject] = []

        let english = Subject(name: "English B", level: "HL", accentColorHex: "8B5CF6")
        seedFromCurriculum(english, curriculum: englishBCurriculum)
        subjects.append(english)

        let russian = Subject(name: "Russian A Literature", level: "SL", accentColorHex: "EC4899")
        seedFromCurriculum(russian, curriculum: russianLitCurriculum)
        subjects.append(russian)

        let biology = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        seedFromCurriculum(biology, curriculum: biologyCurriculum)
        subjects.append(biology)

        let math = Subject(name: "Mathematics AA", level: "SL", accentColorHex: "3B82F6")
        seedFromCurriculum(math, curriculum: mathAACurriculum)
        subjects.append(math)

        let economics = Subject(name: "Economics", level: "HL", accentColorHex: "F59E0B")
        seedFromCurriculum(economics, curriculum: economicsCurriculum)
        subjects.append(economics)

        let business = Subject(name: "Business Management", level: "HL", accentColorHex: "EF4444")
        seedFromCurriculum(business, curriculum: businessCurriculum)
        subjects.append(business)

        return subjects
    }

    /// Seed one starter card per topic from the curriculum
    private static func seedFromCurriculum(_ subject: Subject, curriculum: [CurriculumUnit]) {
        for unit in curriculum {
            for topic in unit.topics {
                let card = StudyCard(
                    topicName: topic.name,
                    subtopic: unit.name,
                    front: "What are the key concepts and learning objectives for \(topic.name) in IB \(subject.name)?",
                    back: "This topic covers: \(topic.subtopics.joined(separator: ", ")). Use ARIA to generate detailed flashcards for each subtopic.",
                    subject: subject
                )
                subject.cards.append(card)
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - IB Economics HL (First assessment 2025)
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
    // MARK: - IB Business Management HL (First assessment 2025)
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
                    "Hormonal regulation (endocrine system)"
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
    // MARK: - IB Mathematics: Analysis & Approaches SL (2025)
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
                CurriculumTopic(name: "Receptive Skills (Paper 1)", subtopics: [
                    "Reading comprehension strategies", "Text handling exercises",
                    "Inferring meaning from context", "Identifying text type and purpose",
                    "Summarising and synthesising information"
                ]),
                CurriculumTopic(name: "Productive Skills (Paper 2)", subtopics: [
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
                ]),
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
                CurriculumTopic(name: "Literary Analysis Skills", subtopics: [
                    "Figurative language and imagery", "Narrative voice and perspective",
                    "Characterisation techniques", "Symbolism and motifs",
                    "Irony, satire and tone"
                ]),
            ]),
        ]
    }
}
