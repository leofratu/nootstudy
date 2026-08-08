import Foundation

/// Subject-specific domain knowledge used to ground ARIA's subject coaching and
/// enrich the subject detail screens. This is curated exam-relevant knowledge
/// (key concepts, high-yield topics, common misconceptions, exam technique and
/// command terms) that is stable enough to live in code rather than in a prompt.
nonisolated struct SubjectKnowledge: Sendable {
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
        if trimmed.caseInsensitiveCompare("Startups & Venture Capital") == .orderedSame ||
            trimmed.caseInsensitiveCompare("Founder Academy") == .orderedSame {
            return life
        }
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
        life
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

    static let life = SubjectKnowledge(
        subjectName: "Life",
        keyConcepts: [
            "Problem selection, customer discovery and product-market fit before scaling",
            "Machine-learning foundations, transformers, LLM product architecture and responsible AI",
            "Human behavior, ethical influence, negotiation and evidence-based debate",
            "Unit economics: CAC, LTV, margins, and the LTV/CAC ratio",
            "Fundraising stages from pre-seed to growth and what each round buys",
            "The term sheet: valuation, dilution, liquidation preference, vesting, anti-dilution",
            "Financial tools: cap table, runway, financial model and startup accounting"
        ],
        highYieldTopics: [
            "Running customer interviews that test behavior rather than invite compliments",
            "How tokens, embeddings, attention, transformers, RAG and tool use fit together",
            "Using frames, calibrated questions and concessions without manipulating people",
            "Why product-market fit precedes scale",
            "Reading and modelling a cap table with an option pool",
            "Pitching problem, proof, market, business model, team and ask as one coherent story"
        ],
        commonMisconceptions: [
            "A great idea is the hard part — execution and distribution are where companies are won",
            "An LLM retrieves facts like a database — it predicts tokens and can produce plausible errors",
            "Winning a debate means humiliating the other person — durable persuasion protects trust and shared truth",
            "Raising money is the goal — it is a means to compound a durable advantage",
            "High revenue growth alone impresses investors — quality of revenue (retention, unit economics) matters more",
            "Dilution is bad — dilution that funds growth at a higher valuation can increase founder ownership",
            "A high valuation is always good — it can set an unhealthy bar for the next round"
        ],
        examTechnique: [
            "For decisions, state the assumption, evidence, downside and next measurable test",
            "For AI products, show evaluation results, latency, failure modes and unit cost rather than a polished demo alone",
            "For difficult conversations, summarize their interests before proposing your frame",
            "For fundraising, frame the story as: problem → insight → product → proof → market → team → ask",
            "Know your cap table cold, including option-pool dilution at every round",
            "Negotiate term sheets on control and optionality, not just headline valuation"
        ],
        commandTerms: ["Define", "Explain", "Model", "Test", "Evaluate", "Pitch", "Negotiate", "Prioritise"]
    )
}

nonisolated struct LearningResource: Identifiable, Hashable, Sendable {
    let title: String
    let provider: String
    let url: URL
    let purpose: String
    let subjects: Set<String>
    let topicKeywords: [String]
    let priority: Int

    var id: String { url.absoluteString }
}

nonisolated enum LearningResourceCatalog: Sendable {
    static func resources(for subjectName: String, topicNames: [String], limit: Int = 4) -> [LearningResource] {
        let normalizedSubject = subjectName.lowercased()
        let scope = topicNames.joined(separator: " ").lowercased()
        return all
            .filter { resource in resource.subjects.contains { $0.lowercased() == normalizedSubject } }
            .sorted { lhs, rhs in
                let lhsScore = matchScore(lhs, scope: scope)
                let rhsScore = matchScore(rhs, scope: scope)
                if lhsScore != rhsScore { return lhsScore > rhsScore }
                return lhs.priority > rhs.priority
            }
            .prefix(max(limit, 0))
            .map { $0 }
    }

    private static func matchScore(_ resource: LearningResource, scope: String) -> Int {
        resource.priority + resource.topicKeywords.reduce(0) { score, keyword in
            score + (scope.contains(keyword.lowercased()) ? 100 : 0)
        }
    }

    static let all: [LearningResource] = [
        LearningResource(
            title: "EcoNinja syllabus notes", provider: "EcoNinja", url: URL(string: "https://www.econinja.net/")!,
            purpose: "Concise IB Economics definitions, diagrams and syllabus notes.", subjects: ["Economics"],
            topicKeywords: ["microeconomics", "macroeconomics", "global economy", "demand", "supply"], priority: 90
        ),
        LearningResource(
            title: "IB Economics course brief", provider: "International Baccalaureate", url: URL(string: "https://www.ibo.org/programmes/diploma-programme/curriculum/individuals-and-societies/economics/")!,
            purpose: "Authoritative course scope, concepts and assessment structure.", subjects: ["Economics"],
            topicKeywords: [], priority: 100
        ),
        LearningResource(
            title: "Understanding our Economy", provider: "CORE Econ", url: URL(string: "https://books.core-econ.org/understanding-our-economy/")!,
            purpose: "Open-access explanations and real-world economic case studies.", subjects: ["Economics"],
            topicKeywords: ["scarcity", "inequality", "environment", "innovation", "institutions"], priority: 80
        ),
        LearningResource(
            title: "Economic data and evidence", provider: "Our World in Data", url: URL(string: "https://ourworldindata.org/economic-growth")!,
            purpose: "Current charts and evidence for evaluation and real-world examples.", subjects: ["Economics"],
            topicKeywords: ["growth", "development", "inequality", "global"], priority: 70
        ),
        LearningResource(
            title: "BioNinja IB Biology", provider: "BioNinja", url: URL(string: "https://ib.bioninja.com.au/")!,
            purpose: "Syllabus-organized explanations, diagrams and review material.", subjects: ["Biology"],
            topicKeywords: [], priority: 90
        ),
        LearningResource(
            title: "BioInteractive", provider: "HHMI", url: URL(string: "https://www.biointeractive.org/")!,
            purpose: "Research-grounded animations, data activities and case studies.", subjects: ["Biology"],
            topicKeywords: ["genetics", "evolution", "ecology", "cells"], priority: 80
        ),
        LearningResource(
            title: "Desmos graphing calculator", provider: "Desmos", url: URL(string: "https://www.desmos.com/calculator")!,
            purpose: "Explore functions, transformations and calculus visually.", subjects: ["Mathematics AA", "Advanced Mathematics"],
            topicKeywords: ["functions", "calculus", "trigonometry", "graphs"], priority: 85
        ),
        LearningResource(
            title: "Essence of linear algebra", provider: "3Blue1Brown", url: URL(string: "https://www.3blue1brown.com/topics/linear-algebra")!,
            purpose: "Visual intuition for vectors, matrices and transformations.", subjects: ["Advanced Mathematics"],
            topicKeywords: ["linear algebra", "vectors", "matrices", "eigenvalues"], priority: 90
        ),
        LearningResource(
            title: "Startup School", provider: "Y Combinator", url: URL(string: "https://www.startupschool.org/curriculum/")!,
            purpose: "Free founder curriculum on ideas, users, MVPs, launch, growth and fundraising.", subjects: ["Life"],
            topicKeywords: ["startup", "founder", "mvp", "product", "growth", "fundraising", "pitch"], priority: 95
        ),
        LearningResource(
            title: "Machine Learning Crash Course", provider: "Google", url: URL(string: "https://developers.google.com/machine-learning/crash-course")!,
            purpose: "Beginner-friendly ML concepts, exercises and practical models.", subjects: ["Life"],
            topicKeywords: ["machine learning", "regression", "classification", "neural", "data"], priority: 95
        ),
        LearningResource(
            title: "CS229 course notes", provider: "Stanford", url: URL(string: "https://cs229.stanford.edu/materials.html-full")!,
            purpose: "Deeper mathematical notes on supervised and unsupervised learning.", subjects: ["Life"],
            topicKeywords: ["machine learning", "optimization", "supervised", "unsupervised"], priority: 78
        ),
        LearningResource(
            title: "Neural networks", provider: "3Blue1Brown", url: URL(string: "https://www.3blue1brown.com/topics/neural-networks")!,
            purpose: "Visual intuition for neural networks, gradient descent and backpropagation.", subjects: ["Life"],
            topicKeywords: ["neural", "gradient", "backpropagation", "transformer"], priority: 88
        ),
        LearningResource(
            title: "Hugging Face LLM Course", provider: "Hugging Face", url: URL(string: "https://huggingface.co/learn/llm-course/chapter1/1")!,
            purpose: "Hands-on transformers, tokenization, fine-tuning and model use.", subjects: ["Life"],
            topicKeywords: ["llm", "language model", "transformer", "token", "fine-tuning"], priority: 90
        ),
        LearningResource(
            title: "Machine Learning Crash Course", provider: "Google", url: URL(string: "https://developers.google.com/machine-learning/crash-course")!,
            purpose: "Interactive foundations from regression and data through neural networks, LLMs and production ML.", subjects: ["Life"],
            topicKeywords: ["machine learning", "regression", "classification", "neural", "llm", "production", "evaluation"], priority: 94
        ),
        LearningResource(
            title: "Full Stack LLM Bootcamp", provider: "The Full Stack", url: URL(string: "https://fullstackdeeplearning.com/llm-bootcamp/")!,
            purpose: "End-to-end practice for defining, building, evaluating and deploying LLM-powered products.", subjects: ["Life"],
            topicKeywords: ["llm", "production", "deployment", "evaluation", "agents", "retrieval", "startup"], priority: 92
        ),
        LearningResource(
            title: "Social Psychology", provider: "OpenStax", url: URL(string: "https://openstax.org/books/psychology-2e/pages/12-introduction")!,
            purpose: "Open textbook coverage of social influence, attitudes, groups and behavior.", subjects: ["Life"],
            topicKeywords: ["behavior", "influence", "social proof", "bias", "conformity"], priority: 88
        ),
        LearningResource(
            title: "Program on Negotiation", provider: "Harvard Law School", url: URL(string: "https://www.pon.harvard.edu/category/daily/negotiation-skills-daily/")!,
            purpose: "Evidence-informed negotiation concepts, preparation and case analysis.", subjects: ["Life"],
            topicKeywords: ["negotiation", "batna", "zopa", "objection", "conversation"], priority: 86
        ),
        LearningResource(
            title: "Logic in argumentative writing", provider: "Purdue OWL", url: URL(string: "https://owl.purdue.edu/owl/general_writing/academic_writing/logic_in_argumentative_writing/index.html")!,
            purpose: "Claims, evidence, logical structure and common reasoning errors.", subjects: ["Life"],
            topicKeywords: ["debate", "argument", "logic", "fallacy", "rebuttal"], priority: 84
        ),
        LearningResource(
            title: "The Learning Scientists", provider: "Learning Scientists", url: URL(string: "https://www.learningscientists.org/downloadable-materials")!,
            purpose: "Practical guides to retrieval, spacing, interleaving and elaboration.", subjects: ["Life"],
            topicKeywords: ["learning", "memory", "recall", "study"], priority: 72
        )
    ]
}
