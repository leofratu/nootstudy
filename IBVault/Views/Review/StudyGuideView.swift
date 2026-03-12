import SwiftUI
import SwiftData

struct StudyGuideView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let subject: Subject?
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
            ScrollView {
                VStack(spacing: 16) {
                    // Context header
                    contextCard
                        .padding(.horizontal, 24)
                        .padding(.top, 20)

                    if isGenerating && guideText.isEmpty {
                        loadingCard
                            .padding(.horizontal, 24)
                    }

                    if let err = error {
                        errorCard(err)
                            .padding(.horizontal, 24)
                    }

                    if !guideText.isEmpty {
                        guideContent
                            .padding(.horizontal, 24)
                    }

                    if !isGenerating && guideText.isEmpty && error == nil {
                        modeSelector
                            .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, 24)
            }
            .background(.background)
            .navigationTitle("Study Guide")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }

    // MARK: - Context
    private var contextCard: some View {
        HStack(spacing: 16) {
            if let s = subject {
                ZStack {
                    Circle()
                        .fill(Color(hex: s.accentColorHex).opacity(0.1))
                        .frame(width: 48, height: 48)
                    Image(systemName: "book.fill")
                        .foregroundStyle(Color(hex: s.accentColorHex))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(s.name)
                            .font(.headline)
                        Text(s.level)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(hex: s.accentColorHex).opacity(0.1)))
                            .foregroundStyle(Color(hex: s.accentColorHex))
                    }
                    HStack(spacing: 12) {
                        Label("\(s.cards.count) topics", systemImage: "square.stack")
                        Label("\(s.dueCardsCount) due", systemImage: "clock")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else {
                ZStack {
                    Circle()
                        .fill(IBColors.electricBlue.opacity(0.1))
                        .frame(width: 48, height: 48)
                    Image(systemName: "books.vertical.fill")
                        .foregroundStyle(IBColors.electricBlue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("All Subjects")
                        .font(.headline)
                    Text("Guide will use info from all enrolled subjects")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(16)
        .glassCard()
    }

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("ARIA is building your \(mode.rawValue)…")
                    .font(.callout.weight(.medium))
                Text("Analysing \(subject?.cards.count ?? 0) cards, session history, and IB difficulty data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .glassCard()
    }

    private func errorCard(_ err: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(err).foregroundStyle(.red)
        }
        .padding(16)
        .glassCard()
    }

    // MARK: - Guide Content
    private var guideContent: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "book.closed.fill")
                        .foregroundStyle(subject.map { Color(hex: $0.accentColorHex) } ?? IBColors.electricBlue)
                    Text(mode.rawValue)
                        .font(.headline)
                }

                FormattedMessageContent(text: guideText)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .glassCard()

            Button {
                guideText = ""; error = nil
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Generate New Guide")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    // MARK: - Mode Selector
    private var modeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Guide Type")
                .font(.headline)
                .padding(.horizontal, 4)

            let modes: [(mode: GuideMode, icon: String, color: Color, title: String, desc: String)] = [
                (.preSession, "bolt.fill", .orange, "Pre-Session Brief", "Quick summary of what to focus on right now"),
                (.fullGuide, "book.fill", IBColors.electricBlue, "Full Study Guide", "Comprehensive topic-by-topic review guide"),
                (.weakTopics, "target", .red, "Weak Topics Focus", "Target the areas with the biggest payoff"),
                (.examPrep, "flame.fill", .purple, "Exam Prep Sprint", "Maximum score improvement in minimum time")
            ]

            ForEach(modes, id: \.title) { m in
                Button { generateGuide(mode: m.mode) } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(m.color.opacity(0.1))
                                .frame(width: 40, height: 40)
                            Image(systemName: m.icon)
                                .foregroundStyle(m.color)
                                .font(.system(size: 16, weight: .semibold))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.title)
                                .font(.callout.weight(.semibold))
                            Text(m.desc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.03)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Generate
    private func generateGuide(mode: GuideMode) {
        guard let apiKey = KeychainService.loadAPIKey(), !apiKey.isEmpty else {
            error = "No Gemini API key configured. Add one in Settings."; return
        }
        isGenerating = true; error = nil; guideText = ""; IBHaptics.light()
        Task {
            do {
                let prompt = buildGuidePrompt(mode: mode)
                let systemPrompt = await ariaService.buildSystemPrompt(context: context, seedQuery: guideSeedQuery(for: mode))
                let stream = GeminiService.streamContent(
                    messages: [GeminiMessage(role: "user", text: prompt)],
                    systemInstruction: systemPrompt, apiKey: apiKey
                )
                var fullGuide = ""
                for try await token in stream {
                    fullGuide += token
                    await MainActor.run { guideText = fullGuide }
                }

                let normalizedGuide = fullGuide.trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalizedGuide.isEmpty {
                    ARIAService.recordStudyGuide(
                        subjectName: subject?.name ?? "All Subjects",
                        mode: mode.rawValue,
                        guideText: normalizedGuide
                    )
                }

                await MainActor.run {
                    guideText = normalizedGuide
                    isGenerating = false
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; isGenerating = false }
            }
        }
    }

    private func guideSeedQuery(for mode: GuideMode) -> String {
        if let subject {
            return "\(mode.rawValue) for \(subject.name) \(subject.level)"
        }
        return "\(mode.rawValue) across all enrolled IB subjects"
    }

    private func buildGuidePrompt(mode: GuideMode) -> String {
        let subjectContext: String
        if let s = subject {
            let weak = ProficiencyTracker.weakTopics(for: s).map(\.topicName).joined(separator: ", ")
            let mastery = Int(ProficiencyTracker.masteryPercentage(for: s) * 100)
            let gradeInfo = s.grades.sorted { $0.date > $1.date }.prefix(3).map { "\($0.component): \($0.score)/7" }.joined(separator: ", ")
            subjectContext = """
            Subject: \(s.name) \(s.level)
            Mastery: \(mastery)%
            Due cards: \(s.dueCardsCount)
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
            Format requirements:
            - Use `###` headers with blank lines between sections
            - Keep each bullet to one actionable idea
            - Include an explicit time estimate in minutes
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
            Format requirements:
            - Use `###` headers with blank lines between sections
            - Use short paragraphs and bullet lists, not one giant block
            - Include realistic time estimates in minutes or hours
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
            Format requirements:
            - Use `###` headers with blank lines between sections
            - Use bullets for interventions and practice ideas
            - Include expected time-to-improve estimates
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
            Format requirements:
            - Use `###` headers with blank lines between sections
            - Use a clear schedule with dedicated time per block
            - Keep the plan terse, specific, and exam-focused
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
