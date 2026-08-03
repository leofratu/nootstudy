import Foundation

/// Subject-specific domain knowledge used to ground ARIA's subject coaching and
/// enrich the subject detail screens. This is curated exam-relevant knowledge
/// (key concepts, high-yield topics, common misconceptions, exam technique and
/// command terms) that is stable enough to live in code rather than in a prompt.
struct SubjectKnowledge: Sendable {
    let subjectName: String
    let keyConcepts: [String]
    let highYieldTopics: [String]
    let commonMisconceptions: [String]
    let examTechnique: [String]
    let commandTerms: [String]

    /// Compact markdown summary used when injecting knowledge into an ARIA prompt.
    var promptBlock: String {
        func bulletList(_ items: [String]) -> String {
            items.map { "  - \($0)" }.joined(separator: "\n")
        }
        var lines: [String] = ["\(subjectName) domain knowledge:"]
        if !keyConcepts.isEmpty {
            lines.append("Key concepts:")
            lines.append(bulletList(keyConcepts))
        }
        if !highYieldTopics.isEmpty {
            lines.append("High-yield topics:")
            lines.append(bulletList(highYieldTopics))
        }
        if !commonMisconceptions.isEmpty {
            lines.append("Common misconceptions to correct:")
            lines.append(bulletList(commonMisconceptions))
        }
        if !examTechnique.isEmpty {
            lines.append("Exam technique:")
            lines.append(bulletList(examTechnique))
        }
        if !commandTerms.isEmpty {
            lines.append("Command terms: \(commandTerms.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    static func knowledge(for subjectName: String) -> SubjectKnowledge? {
        let trimmed = subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.first { $0.subjectName.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    static let all: [SubjectKnowledge] = [
        biology,
        mathematicsAA,
        economics,
        businessManagement,
        englishB,
        russianALiterature,
        advancedMathematics,
        universe,
        startupsAndVC
    ]

    static let biology = SubjectKnowledge(
        subjectName: "Biology",
        keyConcepts: [
            "Cell structure and function, including membrane transport",
            "Molecular biology: DNA, RNA, proteins, enzymes and metabolism",
            "Genetics and inheritance, including linkage and pedigree analysis",
            "Evolution, biodiversity and natural selection",
            "Human physiology: homeostasis, gas exchange, circulation",
            "Ecology: ecosystems, energy flow and sustainability"
        ],
        highYieldTopics: [
            "Membranes and transport",
            "DNA replication, transcription and translation",
            "Photosynthesis and cellular respiration",
            "Mendelian and linked inheritance",
            "Homeostasis and feedback mechanisms"
        ],
        commonMisconceptions: [
            "ATP is stored in cells — it is produced on demand and used immediately",
            "All bacteria are harmful — many are mutualistic or beneficial",
            "DNA mutations are always harmful — many are neutral or beneficial",
            "Bigger organisms have bigger cells — cell size is not tied to body size",
            "Evolution is 'just a theory' — a theory is a well-supported explanatory framework"
        ],
        examTechnique: [
            "Match the depth of your answer to the command term (state vs explain vs evaluate)",
            "Label diagrams accurately with the exact biological terms",
            "Include units on all quantitative answers",
            "For extended-response questions, plan the chain of reasoning before writing"
        ],
        commandTerms: ["State", "Outline", "Describe", "Explain", "Compare", "Contrast", "Evaluate", "Draw", "Label", "Annotate", "Calculate", "Predict"]
    )

    static let mathematicsAA = SubjectKnowledge(
        subjectName: "Mathematics AA",
        keyConcepts: [
            "Algebra: sequences, exponents, logarithms, binomial theorem",
            "Functions: quadratics, rationals, exponentials, logarithms and transformations",
            "Trigonometry: identities, equations, and non-right triangles",
            "Calculus: limits, differentiation and integration with applications",
            "Statistics and probability: distributions, hypothesis testing",
            "Vectors and geometry"
        ],
        highYieldTopics: [
            "Differentiation rules and their applications (tangents, optimisation)",
            "Integration by substitution and parts, areas under curves",
            "Normal distribution and probability",
            "Sketching and transforming functions",
            "Proof techniques: induction, contradiction, contrapositive"
        ],
        commonMisconceptions: [
            "The calculator does all the work — method marks are still required",
            "ln(x) and log(x) are interchangeable — they differ by a constant base",
            "Integration is just 'reverse differentiation' — remember the +C and boundary conditions",
            "A derivative is zero only at maxima — it is also zero at minima and stationary inflection points",
            "Rounding early is fine — round only at the final answer to preserve accuracy"
        ],
        examTechnique: [
            "Show working for method marks even when using the GDC",
            "Round only at the final step",
            "Annotate GDC output and state assumptions",
            "Check the domain and range of every function you use",
            "Use correct notation throughout: d/dx, integral signs, modulus bars"
        ],
        commandTerms: ["Find", "Solve", "Show that", "Prove", "Evaluate", "Sketch", "Interpret", "Justify", "Hence", "Hence or otherwise"]
    )

    static let economics = SubjectKnowledge(
        subjectName: "Economics",
        keyConcepts: [
            "Microeconomics: demand, supply, elasticity, market failure and government intervention",
            "Macroeconomics: aggregate demand/supply, inflation, unemployment, growth",
            "International trade: tariffs, quotas, exchange rates, balance of payments",
            "Economic development: indicators and growth strategies"
        ],
        highYieldTopics: [
            "Elasticity calculations and their determinants",
            "Market failure diagrams (externalities, public goods)",
            "AD/AS shifts and demand- vs supply-side policy",
            "Monetary versus fiscal policy evaluation",
            "Exchange rate movements and their effects on trade"
        ],
        commonMisconceptions: [
            "Higher price always reduces demand — it depends on price elasticity",
            "GDP growth equals development — it ignores distribution and wellbeing",
            "Deflation is always good for consumers — it can delay spending",
            "Free trade benefits everyone equally — gains are unevenly distributed"
        ],
        examTechnique: [
            "Draw and fully label diagrams: axes, curves, equilibrium, and shifts",
            "Explain the full chain of reasoning, not just the first step",
            "Evaluate every policy: strengths, limitations, and stakeholders",
            "Support arguments with real-world examples"
        ],
        commandTerms: ["Define", "Explain", "Analyse", "Evaluate", "Discuss", "Distinguish", "Compare", "Contrast"]
    )

    static let businessManagement = SubjectKnowledge(
        subjectName: "Business Management",
        keyConcepts: [
            "Business organisation and environment, including stakeholders",
            "Human resource management: motivation, organisational structure, leadership",
            "Finance: sources of finance, break-even, ratio analysis",
            "Marketing: the 7Ps, market research, positioning",
            "Operations management: production methods, quality, stock control",
            "Strategy: SWOT, Ansoff matrix, Porter's forces"
        ],
        highYieldTopics: [
            "Motivation theories (Maslow, Herzberg, Taylor) applied to case studies",
            "Break-even analysis and profit/loss calculations",
            "Financial ratio analysis (profitability, liquidity)",
            "Marketing mix decisions and the 7Ps",
            "Strategic tools: SWOT and Ansoff"
        ],
        commonMisconceptions: [
            "Profit and cash flow are the same — timing matters",
            "A higher price always means higher profit — volume and demand change",
            "Money is the only motivator — recognition and autonomy matter",
            "Describing a framework is enough — you must apply it to the case"
        ],
        examTechnique: [
            "Use case-study data and quote figures",
            "Apply frameworks explicitly rather than naming them",
            "Structure long answers: point, explanation, example, evaluation",
            "Give a justified recommendation, not just a description"
        ],
        commandTerms: ["Explain", "Analyse", "Evaluate", "Discuss", "Compare", "Contrast", "Justify", "Recommend"]
    )

    static let englishB = SubjectKnowledge(
        subjectName: "English B",
        keyConcepts: [
            "Paper 1: written productive skills across text types",
            "Paper 2: receptive skills through reading and listening",
            "Individual Oral: exploring a cultural stimulus",
            "Text types, register, tone and audience awareness"
        ],
        highYieldTopics: [
            "Mastering text types: article, blog, speech, review, letter",
            "Connecting ideas with clear paragraph structure",
            "Register and tone appropriate to the audience",
            "Listening and reading for gist and detail"
        ],
        commonMisconceptions: [
            "Memorising essays works — examiners reward relevant, adapted writing",
            "Only vocabulary matters — grammar and coherence are marked",
            "Translate literally from the home language — natural target-language phrasing scores higher"
        ],
        examTechnique: [
            "Answer the actual task, not a prepared topic",
            "Use evidence from the text in receptive tasks",
            "Vary sentence structure and use cohesive devices",
            "Manage time across papers and word counts"
        ],
        commandTerms: ["Describe", "Compare", "Explain", "Express", "Justify", "Relate"]
    )

    static let russianALiterature = SubjectKnowledge(
        subjectName: "Russian A Literature",
        keyConcepts: [
            "Paper 1: guided analysis of an unseen text",
            "Paper 2: comparative essay on works studied",
            "Individual Oral and the learner portfolio",
            "Literary devices, authorial choices, and cultural context"
        ],
        highYieldTopics: [
            "Analysing unseen prose and poetry",
            "Comparative essays across two works",
            "Authorial choices: imagery, symbolism, narrative voice",
            "Context: historical and cultural background"
        ],
        commonMisconceptions: [
            "Paraphrasing is analysis — focus on authorial choices and their effects",
            "Longer essays score higher — depth and relevance matter more",
            "Context replaces textual evidence — both are required"
        ],
        examTechnique: [
            "Use the point-evidence-analysis structure",
            "Address the guiding question directly",
            "Discuss authorial choices and their effects, not just what happens",
            "Balance commentary with quotation"
        ],
        commandTerms: ["Comment on", "Discuss", "Analyse", "Compare", "Evaluate"]
    )

    static let advancedMathematics = SubjectKnowledge(
        subjectName: "Advanced Mathematics",
        keyConcepts: [
            "Proof techniques: direct, contradiction, induction, contrapositive, exhaustion",
            "Number theory: modular arithmetic, primes, GCD and Diophantine equations",
            "Algebraic structures: groups, rings, fields",
            "Real analysis: limits, continuity, differentiation and integration foundations",
            "Linear algebra: vector spaces, transformations, eigenvalues and diagonalization"
        ],
        highYieldTopics: [
            "Proof by induction on sums and divisibility",
            "Proof by contradiction (√2 irrationality, infinitude of primes)",
            "Epsilon-delta definitions",
            "The mean value theorem and Taylor's theorem",
            "Rank-nullity and diagonalization"
        ],
        commonMisconceptions: [
            "A proof is 'done' when the algebra checks out — you must state and justify each logical step",
            "Induction only works on integers — it also applies to structured objects",
            "The converse of a true statement is true — it must be proved separately",
            "Continuity and differentiability are the same — differentiable implies continuous, not vice versa",
            "A counterexample 'proves' a statement false — yes, that is the point of a counterexample"
        ],
        examTechnique: [
            "State what you will prove and which technique you are using before the algebra",
            "Every variable you introduce must be quantified and defined",
            "For inequalities, state why the direction of the inequality is preserved at each step",
            "When a theorem is invoked, name it and check its hypotheses are satisfied",
            "End with a clear conclusion that restates the claim"
        ],
        commandTerms: ["Prove", "Show that", "Disprove", "Find a counterexample", "Derive", "Verify", "Generalize"]
    )

    static let universe = SubjectKnowledge(
        subjectName: "Fundamentals of the Universe",
        keyConcepts: [
            "Cosmic scales: AU, light-years, parsecs and orders of magnitude",
            "The four fundamental forces and their role in the universe",
            "Special and general relativity",
            "Stellar evolution from nebula to white dwarf, neutron star or black hole",
            "Cosmology: the Big Bang, expansion, dark matter and dark energy",
            "Planetary systems and the search for habitable worlds"
        ],
        highYieldTopics: [
            "Hubble's law and the expanding universe",
            "The cosmic microwave background as the smoking gun for the Big Bang",
            "Time dilation and E = mc²",
            "Black hole structure: event horizon, singularity",
            "The evidence for dark matter and dark energy"
        ],
        commonMisconceptions: [
            "The universe is expanding into empty space — the space itself is expanding",
            "Black holes 'suck things in' — objects orbit them like any other mass until crossing the horizon",
            "Light always travels in straight lines — gravity bends spacetime and thus light",
            "The Big Bang happened 'somewhere' — it happened everywhere at once",
            "Time passes identically everywhere — it slows in stronger gravity"
        ],
        examTechnique: [
            "Distinguish evidence from interpretation when describing cosmology",
            "Keep track of units and orders of magnitude in any calculation",
            "Separate what is observed from what is inferred",
            "Use the standard names for phenomena (CMB, redshift, Hawking radiation)",
            "For essay questions, structure: phenomenon → evidence → model → implications"
        ],
        commandTerms: ["Explain", "Describe", "Compare", "Evaluate", "Calculate", "Justify", "Outline"]
    )

    static let startupsAndVC = SubjectKnowledge(
        subjectName: "Startups & Venture Capital",
        keyConcepts: [
            "Idea validation and product-market fit before anything scales",
            "Unit economics: CAC, LTV, margins, and the LTV/CAC ratio",
            "Fundraising stages from pre-seed to growth and what each round buys",
            "The term sheet: valuation, dilution, liquidation preference, vesting, anti-dilution",
            "Financial tools: cap table, runway, financial model, startup accounting",
            "How VCs think: fund economics, pattern recognition, and the 25-year playbook"
        ],
        highYieldTopics: [
            "Why product-market fit precedes the Series A",
            "Reading and modelling a cap table with an option pool",
            "The term sheet clauses that actually matter",
            "Runway math and when to raise",
            "The financial model VCs expect (realistic, sensitivity-tested, unit-driven)"
        ],
        commonMisconceptions: [
            "A great idea is the hard part — execution and distribution are where companies are won",
            "Raising money is the goal — it is a means to compound a durable advantage",
            "High revenue growth alone impresses investors — quality of revenue (retention, unit economics) matters more",
            "Dilution is bad — dilution that funds growth at a higher valuation can increase founder ownership",
            "A high valuation is always good — it sets the bar for the next round and can create a down round",
            "Investors want you to be 'nice' — they want you to be honest, coachable and decisive"
        ],
        examTechnique: [
            "Speak in metrics and cohorts, not adjectives: show retention curves and unit economics",
            "For fundraising, frame the story as: problem → product → traction → market → why this team",
            "Know your cap table cold, including option-pool dilution at every round",
            "Be prepared to defend the 18-month plan with a bottom-up model and sensitivities",
            "Negotiate term sheets on control and optionality, not just headline valuation"
        ],
        commandTerms: ["Evaluate", "Justify", "Recommend", "Model", "Compare", "Analyse", "Prioritise"]
    )
}
