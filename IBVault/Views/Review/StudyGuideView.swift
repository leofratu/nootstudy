import SwiftUI
import SwiftData

struct StudyGuideView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let subject: Subject?  // nil = all subjects
    let mode: GuideMode

    @State private var ariaService = ARIAService()
    @State private var guideText = ""
    @State private var isGenerating = false
    @State private var error: String?

    enum GuideMode: String {
        case preSession = "Pre-Session Brief"
        case fullGuide = "Study Guide"
        case weakTopics = "Weak Topics Focus"
        case examPrep = "Exam Prep Sprint"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                IBColors.navy.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: IBSpacing.lg) {
                        headerSection
                        if isGenerating && guideText.isEmpty { loadingSection }
                        if !guideText.isEmpty { guideContent }
                        if let err = error { errorSection(err) }
                        if !isGenerating && guideText.isEmpty && error == nil { modeSelector }
                    }.padding(IBSpacing.md).padding(.bottom, 60)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: IBSpacing.sm) {
            HStack(spacing: IBSpacing.sm) {
                PulseOrb(size: 28)
                Text("ARIA Study Guide").font(IBTypography.title).foregroundColor(IBColors.softWhite)
            }
            if let s = subject {
                HStack(spacing: IBSpacing.xs) {
                    Circle().fill(Color(hex: s.accentColorHex)).frame(width: 8, height: 8)
                    Text(s.name).font(IBTypography.captionBold).foregroundColor(Color(hex: s.accentColorHex))
                    Text(s.level).font(IBTypography.caption).foregroundColor(IBColors.mutedGray)
                }
            } else {
                Text("All Subjects").font(IBTypography.caption).foregroundColor(IBColors.mutedGray)
            }
        }
    }

    private var loadingSection: some View {
        GlassCard {
            VStack(spacing: IBSpacing.md) {
                ThinkingDots()
                Text("ARIA is building your \(mode.rawValue)...")
                    .font(IBTypography.caption).foregroundColor(IBColors.mutedGray)
                Text("Analysing \(subject?.cards.count ?? 0) cards, session history, and IB difficulty data")
                    .font(.system(size: 11)).foregroundColor(IBColors.mutedGray.opacity(0.7))
            }
        }
    }

    private var guideContent: some View {
        VStack(alignment: .leading, spacing: IBSpacing.md) {
            // Render the guide as styled blocks
            ForEach(parseGuideBlocks(guideText), id: \.id) { block in
                guideBlock(block)
            }

            // Action buttons
            HStack(spacing: IBSpacing.md) {
                Button {
                    guideText = ""; error = nil
                } label: {
                    HStack { Image(systemName: "arrow.counterclockwise"); Text("New Guide") }
                        .font(IBTypography.captionBold).foregroundColor(IBColors.electricBlue)
                }
                Spacer()
                if isGenerating {
                    HStack(spacing: 4) {
                        ProgressView().tint(IBColors.electricBlue).scaleEffect(0.7)
                        Text("Generating...").font(IBTypography.caption).foregroundColor(IBColors.mutedGray)
                    }
                }
            }
        }
    }

    private func guideBlock(_ block: GuideBlock) -> some View {
        GlassCard(cornerRadius: 14, padding: IBSpacing.md) {
            VStack(alignment: .leading, spacing: IBSpacing.sm) {
                if let title = block.title {
                    HStack(spacing: IBSpacing.xs) {
                        Image(systemName: block.icon).foregroundColor(block.iconColor)
                        Text(title).font(IBTypography.headline).foregroundColor(IBColors.softWhite)
                    }
                }
                Text(block.content).font(IBTypography.body).foregroundColor(IBColors.softWhite.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func errorSection(_ err: String) -> some View {
        GlassCard {
            HStack {
                Image(systemName: "exclamationmark.triangle").foregroundColor(IBColors.danger)
                Text(err).font(IBTypography.caption).foregroundColor(IBColors.danger)
            }
        }
    }

    // MARK: - Mode Selector
    private var modeSelector: some View {
        VStack(alignment: .leading, spacing: IBSpacing.md) {
            Text("Choose guide type").font(IBTypography.headline).foregroundColor(IBColors.softWhite)

            guideOption(mode: .preSession, icon: "bolt.fill", color: IBColors.warning,
                        title: "Pre-Session Brief", desc: "Quick summary of what to focus on right now — prioritised by weakness × IB weighting")

            guideOption(mode: .fullGuide, icon: "book.fill", color: IBColors.electricBlue,
                        title: "Full Study Guide", desc: "Comprehensive topic-by-topic guide with difficulty ratings, time estimates, and exam tips")

            guideOption(mode: .weakTopics, icon: "target", color: IBColors.danger,
                        title: "Weak Topics Focus", desc: "Zero in on your weakest areas — ranked by how much score improvement they'd yield")

            guideOption(mode: .examPrep, icon: "flame.fill", color: IBColors.streakOrange,
                        title: "Exam Prep Sprint", desc: "High-intensity plan for maximum score gain in minimum time")
        }
    }

    private func guideOption(mode: GuideMode, icon: String, color: Color, title: String, desc: String) -> some View {
        Button {
            generateGuide(mode: mode)
        } label: {
            GlassCard(cornerRadius: 14, padding: IBSpacing.md) {
                HStack(spacing: IBSpacing.md) {
                    Image(systemName: icon).font(.title2).foregroundColor(color).frame(width: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(IBTypography.captionBold).foregroundColor(IBColors.softWhite)
                        Text(desc).font(.system(size: 11)).foregroundColor(IBColors.mutedGray).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundColor(IBColors.mutedGray)
                }
            }
        }
    }

    // MARK: - Generate
    private func generateGuide(mode: GuideMode) {
        guard let apiKey = KeychainService.loadAPIKey(), !apiKey.isEmpty else {
            error = "No Gemini API key configured. Add one in Settings."
            return
        }

        isGenerating = true; error = nil; guideText = ""; IBHaptics.light()

        Task {
            do {
                let prompt = buildGuidePrompt(mode: mode)
                let systemPrompt = await ariaService.buildSystemPrompt(context: context)

                let stream = GeminiService.streamContent(
                    messages: [GeminiMessage(role: "user", text: prompt)],
                    systemInstruction: systemPrompt,
                    apiKey: apiKey
                )

                for try await token in stream {
                    await MainActor.run { guideText += token }
                }

                await MainActor.run { isGenerating = false }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }

    private func buildGuidePrompt(mode: GuideMode) -> String {
        let subjectContext: String
        if let s = subject {
            let weak = ProficiencyTracker.weakTopics(for: s).map(\.topicName).joined(separator: ", ")
            let mastery = Int(ProficiencyTracker.masteryPercentage(for: s) * 100)
            let dueCards = s.dueCardsCount
            let gradeInfo = s.grades.sorted { $0.date > $1.date }.prefix(3).map { "\($0.component): \($0.score)/7" }.joined(separator: ", ")
            subjectContext = """
            Subject: \(s.name) \(s.level)
            Mastery: \(mastery)%
            Due cards: \(dueCards)
            Weak topics: \(weak.isEmpty ? "None identified yet" : weak)
            Latest grades: \(gradeInfo.isEmpty ? "No grades recorded" : gradeInfo)
            Total cards: \(s.cards.count)
            """
        } else {
            subjectContext = "All subjects (see app state for details)"
        }

        switch mode {
        case .preSession:
            return """
            Generate a PRE-SESSION BRIEF for my upcoming review.
            \(subjectContext)
            Tell me:
            1. Top 3 topics to focus on (ranked by weakness × IB weighting)
            2. Key concepts to refresh before starting
            3. Common exam pitfalls for these topics
            4. Estimated session time needed
            Keep it concise and actionable. Use bullet points.
            """
        case .fullGuide:
            return """
            Generate a FULL STUDY GUIDE.
            \(subjectContext)
            For each topic, include:
            1. Topic name and IB difficulty rating (1-5 stars)
            2. Current mastery status
            3. Key concepts to know
            4. Common exam questions and mark scheme expectations
            5. Estimated study time needed
            6. Recommended study technique (flashcards, practice questions, essays, etc.)
            Order topics by priority: (difficulty × weakness × exam weight).
            """
        case .weakTopics:
            return """
            Generate a WEAK TOPICS ANALYSIS.
            \(subjectContext)
            For my weakest topics:
            1. Why this topic is hard (common misconceptions)
            2. The fastest way to improve (specific strategies)
            3. How many IB points this could gain me if mastered
            4. Practice questions I should attempt
            5. Key facts/formulas to memorise
            Rank by potential score improvement per hour of study.
            """
        case .examPrep:
            return """
            Generate an EXAM PREP SPRINT plan.
            \(subjectContext)
            I need maximum score improvement in minimum time:
            1. Triage: which topics to master vs. skip vs. just-know-basics
            2. Hour-by-hour or day-by-day schedule
            3. Specific techniques (past paper timing, mark scheme analysis, etc.)
            4. Predicted score impact if I follow this plan
            5. Mental preparation and exam strategy tips
            Be ruthlessly efficient. Focus on the 20% effort that yields 80% results.
            """
        }
    }
}

// MARK: - Guide Block Parser
struct GuideBlock: Identifiable {
    let id = UUID()
    let title: String?
    let content: String
    let icon: String
    let iconColor: Color
}

func parseGuideBlocks(_ text: String) -> [GuideBlock] {
    let lines = text.components(separatedBy: "\n")
    var blocks: [GuideBlock] = []
    var currentTitle: String?
    var currentContent: [String] = []

    let icons = ["bolt.fill", "book.fill", "target", "flame.fill", "lightbulb.fill", "chart.bar.fill", "star.fill", "brain.head.profile"]
    let colors: [Color] = [IBColors.warning, IBColors.electricBlue, IBColors.danger, IBColors.streakOrange, IBColors.success, IBColors.electricBlueLight, IBColors.warning, IBColors.electricBlue]
    var blockIndex = 0

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("##") || trimmed.hasPrefix("**") && trimmed.hasSuffix("**") {
            // Save previous block
            if !currentContent.isEmpty || currentTitle != nil {
                let idx = blockIndex % icons.count
                blocks.append(GuideBlock(title: currentTitle, content: currentContent.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), icon: icons[idx], iconColor: colors[idx]))
                blockIndex += 1
            }
            currentTitle = trimmed.replacingOccurrences(of: "#", with: "").replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
            currentContent = []
        } else if !trimmed.isEmpty {
            currentContent.append(trimmed)
        }
    }

    // Last block
    if !currentContent.isEmpty {
        let idx = blockIndex % icons.count
        blocks.append(GuideBlock(title: currentTitle, content: currentContent.joined(separator: "\n"), icon: icons[idx], iconColor: colors[idx]))
    }

    // If no headers found, return as single block
    if blocks.isEmpty && !text.isEmpty {
        blocks.append(GuideBlock(title: nil, content: text, icon: "book.fill", iconColor: IBColors.electricBlue))
    }

    return blocks
}
