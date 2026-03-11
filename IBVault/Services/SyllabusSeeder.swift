import Foundation
import SwiftData

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

    private static func createSubjects() -> [Subject] {
        var subjects: [Subject] = []

        // 1. English B HL
        let english = Subject(name: "English B", level: "HL", accentColorHex: "8B5CF6")
        addCards(to: english, topics: [
            ("Identities", "Personal identity; beliefs, values and customs; subcultures; language and identity", "How does language shape personal and cultural identity? Consider the relationship between communication patterns and self-expression."),
            ("Experiences", "Leisure, hobbies and interests; holidays and travel; life stories; rites of passage", "Reflect on how different life experiences shape personal growth. What role do cultural traditions play in marking significant moments?"),
            ("Human Ingenuity", "Entertainment; artistic expressions; technology; scientific innovation", "Analyse how technological advancement intersects with artistic expression. What ethical considerations arise from human innovation?"),
            ("Social Organisation", "Social relationships; community; social engagement; education; the working world", "Evaluate the factors that contribute to effective social structures. How do educational systems vary across cultures?"),
            ("Sharing the Planet", "Environment; human impact; rights and responsibilities; peace and conflict; equality", "Discuss the balance between economic development and environmental sustainability. What responsibilities do individuals have?"),
            ("Paper 1: Productive Skills", "Writing task based on text types; 450-600 words; formal/informal registers", "You need to demonstrate the ability to write in various text types including articles, blogs, reports, and letters."),
            ("Paper 2: Receptive Skills", "Reading comprehension; text handling exercises; short answer questions", "Demonstrate comprehension of written texts through various question types including matching, gap-filling, and short answer."),
            ("Individual Oral", "Based on an extract from a literary work; linked to a prescribed theme", "Present an individual oral assessment linking a literary work extract to one of the course themes. 15 minutes total."),
        ])
        subjects.append(english)

        // 2. Russian A Literature SL
        let russian = Subject(name: "Russian A Literature", level: "SL", accentColorHex: "EC4899")
        addCards(to: russian, topics: [
            ("Readers, Writers and Texts", "Nature of literature; reader response; narrative techniques; authorial intent", "How do different readers interpret the same literary text differently? Consider the role of cultural context in shaping literary meaning."),
            ("Time and Space", "Literature in context; historical/cultural influences; setting; chronology in narrative", "Analyse how authors use temporal and spatial settings to enhance thematic meaning. How does historical context shape literary works?"),
            ("Intertextuality", "Connections between texts; literary allusions; comparative analysis; genre conventions", "Explore how texts reference and respond to each other. What role do genre conventions play in shaping reader expectations?"),
            ("Guided Literary Analysis", "Paper 1: unseen literary analysis; prose or poetry passage analysis", "Analyse an unseen passage focusing on literary techniques, style, structure, and their effects on meaning."),
            ("Comparative Essay", "Paper 2: comparative essay on two works studied; thematic connections", "Write a comparative essay connecting two literary works through themes, techniques, or contextual concerns."),
            ("Individual Oral", "15-minute oral connecting a literary work to a global issue; 10-min presentation + 5-min Q&A", "Connect a literary work to a global issue through close textual analysis and broader thematic exploration."),
            ("Literary Analysis Skills", "Figurative language; narrative voice; characterisation; tone and mood; symbolism", "Identify and analyse key literary devices: metaphor, symbolism, irony, narrative perspective, and their cumulative effect."),
        ])
        subjects.append(russian)

        // 3. Biology SL
        let biology = Subject(name: "Biology", level: "SL", accentColorHex: "10B981")
        addCards(to: biology, topics: [
            ("Cell Biology", "Cell theory; ultrastructure of cells; membrane structure; membrane transport; cell division", "What are the key differences between prokaryotic and eukaryotic cells? Explain the fluid mosaic model and its implications for membrane function."),
            ("Molecular Biology", "Molecules to metabolism; water; carbohydrates and lipids; proteins; enzymes; DNA structure and replication; transcription and translation; cell respiration; photosynthesis", "Describe the relationship between DNA structure and protein synthesis. How do enzymes catalyse biochemical reactions?"),
            ("Genetics", "Genes; chromosomes; meiosis; inheritance; genetic modification and biotechnology", "Explain Mendel's laws of inheritance using appropriate genetic crosses. What is the significance of meiosis for genetic variation?"),
            ("Ecology", "Species, communities and ecosystems; energy flow; carbon cycling; climate change", "How does energy flow through an ecosystem? Analyse the carbon cycle and its relationship to climate change."),
            ("Evolution and Biodiversity", "Evidence for evolution; natural selection; classification of biodiversity; cladistics", "What evidence supports the theory of evolution? How does natural selection drive speciation and adaptation?"),
            ("Human Physiology", "Digestion and absorption; the blood system; defence against infectious disease; gas exchange; neurons and synapses; hormones", "Explain the mechanism of synaptic transmission. How does the immune system distinguish between self and non-self?"),
            ("Nucleic Acids (AHL)", "DNA structure; DNA replication; transcription; gene expression; translation", "Detail the process of semi-conservative DNA replication and explain its significance for genetic continuity."),
            ("Practical Work & IA", "Experimental design; data collection and processing; conclusion and evaluation", "Design a controlled experiment with clear variables, appropriate methodology, and systematic data collection."),
        ])
        subjects.append(biology)

        // 4. Mathematics AA SL
        let math = Subject(name: "Mathematics AA", level: "SL", accentColorHex: "3B82F6")
        addCards(to: math, topics: [
            ("Number and Algebra", "Sequences and series; arithmetic & geometric; exponents and logarithms; binomial theorem; counting principles", "Find the sum of the first 20 terms of an arithmetic sequence. Apply the binomial theorem to expand (2x+3)⁴."),
            ("Functions", "Function concepts; domain and range; composite and inverse functions; transformations; quadratic, polynomial, rational functions", "Given f(x) = 2x²-3x+1, find the inverse function and describe the transformations applied."),
            ("Trigonometry", "Trigonometric ratios; unit circle; trigonometric identities; trigonometric equations; sine and cosine rules; area of triangles", "Solve the equation 2sin²x - sinx - 1 = 0 for 0 ≤ x ≤ 2π. Apply the cosine rule to find unknown sides."),
            ("Statistics and Probability", "Descriptive statistics; regression; probability; discrete and continuous distributions; normal distribution; binomial distribution", "Calculate the probability using the normal distribution. Interpret the correlation coefficient in context."),
            ("Calculus", "Limits and derivatives; differentiation rules; applications of differentiation; integration; areas and volumes; kinematics", "Find the maximum value of f(x) = x³-6x²+9x+2. Calculate the area between two curves using integration."),
            ("Paper 1: No Calculator", "Short and extended response questions without GDC; algebraic manipulation; exact values", "Demonstrate proficiency in algebraic techniques without calculator support. Show clear mathematical reasoning."),
            ("Paper 2: Calculator Allowed", "Extended response questions with GDC; real-world applications; modelling", "Apply mathematical concepts to real-world contexts. Use technology effectively to solve complex problems."),
            ("Mathematical Exploration (IA)", "Independent investigation; personal engagement; mathematical communication; reflection", "Conduct an independent mathematical investigation demonstrating personal engagement and rigorous mathematical thinking."),
        ])
        subjects.append(math)

        // 5. Economics HL
        let economics = Subject(name: "Economics", level: "HL", accentColorHex: "F59E0B")
        addCards(to: economics, topics: [
            ("Introduction to Economics", "Scarcity, choice and opportunity cost; economic methodology; economic systems; production possibilities", "Explain how the concept of opportunity cost applies to individual decision-making and government policy choices."),
            ("Microeconomics", "Demand and supply; market equilibrium; elasticity; government intervention; market failure; theory of the firm (HL)", "Analyse the effects of imposing a price ceiling below market equilibrium. How do different elasticities affect tax incidence?"),
            ("Macroeconomics", "GDP and economic growth; aggregate demand and supply; macroeconomic objectives; fiscal policy; monetary policy; supply-side policies", "Evaluate the effectiveness of fiscal policy in addressing unemployment versus inflation. What are the limitations?"),
            ("The Global Economy", "International trade; exchange rates; balance of payments; economic integration; terms of trade", "Analyse the impact of trade liberalisation on developing economies. How do exchange rate changes affect the current account?"),
            ("Development Economics", "Economic development; measuring development; barriers to development; strategies for development; foreign aid and debt", "Compare GDP per capita with the HDI as measures of development. Evaluate the role of foreign aid in promoting development."),
            ("Theory of the Firm (HL)", "Costs and revenues; perfect competition; monopoly; monopolistic competition; oligopoly; price discrimination", "Compare profit maximisation under perfect competition versus monopoly. Analyse the kinked demand curve model of oligopoly."),
            ("Paper 1: Extended Response", "Two sections; essay-style questions requiring diagrams and evaluation; one micro, one macro", "Write a well-structured response with clearly labelled diagrams, real-world examples, and balanced evaluation."),
            ("Paper 2: Data Response", "Two questions based on real-world data; quantitative and qualitative analysis required", "Analyse economic data, draw appropriate diagrams, and evaluate policy options based on the evidence provided."),
            ("Paper 3: HL Extension", "Quantitative questions; calculations involving economic concepts; HL only", "Apply quantitative techniques to economic analysis including elasticity calculations, multiplier effects, and trade diagrams."),
            ("Internal Assessment", "Portfolio of three commentaries; each 800 words max; based on news articles; micro, macro, global", "Write an insightful commentary linking a current news article to economic theory with appropriate diagrams."),
        ])
        subjects.append(economics)

        // 6. Business Management HL
        let business = Subject(name: "Business Management", level: "HL", accentColorHex: "EF4444")
        addCards(to: business, topics: [
            ("Business Organisation and Environment", "Nature of business activity; types of organisations; organisational objectives; stakeholders; external environment; STEEPLE analysis", "Evaluate how different stakeholder interests may conflict. Analyse the impact of STEEPLE factors on strategic decision-making."),
            ("Human Resource Management", "HR planning; organisational structure; leadership and management; motivation; organisational culture; employer-employee relations (HL)", "Compare Maslow's hierarchy with Herzberg's two-factor theory. How does organisational culture affect employee performance?"),
            ("Finance and Accounts", "Sources of finance; costs and revenues; break-even analysis; final accounts; profitability and liquidity ratios; efficiency ratios (HL); SWOT analysis of finances", "Calculate break-even point and margin of safety. Interpret profitability ratios and recommend financial strategies."),
            ("Marketing", "The role of marketing; marketing planning; sales forecasting; market research; the 4Ps; international marketing (HL); e-commerce", "Develop a marketing mix for a new product launch. Evaluate the effectiveness of different pricing strategies."),
            ("Operations Management", "The role of operations; production methods; lean production and quality management; location planning; production planning (HL); research and development; crisis management", "Compare just-in-time with just-in-case inventory management. How does quality management contribute to competitiveness?"),
            ("Paper 1: Pre-Seen Case Study", "Based on a pre-released case study; strategic analysis; 90 minutes at HL", "Apply business management concepts and tools to a real-world case study. Provide strategic recommendations supported by evidence."),
            ("Paper 2: Structured Questions", "Data response and essay-style questions based on unseen stimulus material; quantitative analysis", "Analyse business scenarios using appropriate frameworks, calculations, and evaluative discussion."),
            ("Internal Assessment", "Research project; business tool application to a real organisation; 2,000 words max", "Conduct a research project applying business management tools and theories to a real organisation's challenge."),
        ])
        subjects.append(business)

        return subjects
    }

    private static func addCards(to subject: Subject, topics: [(String, String, String)]) {
        for (topicName, description, reviewPrompt) in topics {
            let card = StudyCard(
                topicName: topicName,
                subtopic: "",
                front: description,
                back: reviewPrompt,
                subject: subject
            )
            subject.cards.append(card)
        }
    }
}
