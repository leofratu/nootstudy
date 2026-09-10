import SwiftUI
import SwiftData

struct ReviewSessionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ProgressionEventCenter.self) private var progressionEvents
    @Environment(ReviewQueueManager.self) private var queueManager
    @Query private var profiles: [UserProfile]
    @Query(sort: \StudyCard.nextReviewDate) private var allReviewCards: [StudyCard]
    @Query(sort: \StudySession.endDate, order: .reverse) private var studySessions: [StudySession]
    // `var` + defaults so the memberwise initializer keeps its arguments —
    // callers pass `filterSubject:`/`filterPlan:`/`reviewScopeSession:` — and
    // never mutates them after init.
    var filterSubject: Subject? = nil
    var filterPlan: StudyPlan? = nil
    var reviewScopeSession: StudySession? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var cardFlipNamespace
    @State private var cards: [StudyCard] = []
    @State private var currentIndex = 0
    @State private var isFlipped = false
    @State private var sessionComplete = false
    @State private var sessionXP = 0
    @State private var sessionQualities: [RecallQuality] = []
    @State private var sessionCorrect = 0
    @State private var sessionStartTime = Date()
    @State private var studySessionID = UUID()
    @State private var showStudyGuide = false
    @State private var generationError: String?
    // Snapshot captured at completion: the reviewed cards are rescheduled on
    // save, so reading cards.count live would show 0 on the completion screen.
    @State private var completedCardCount = 0
    @State private var completedRetentionPercent = 0

    private var currentCard: StudyCard? {
        currentIndex < cards.count ? cards[currentIndex] : nil
    }
    private var activeScope: StudyScope? {
        reviewScopeSession?.studyScope ?? filterPlan?.studyScope
    }
    private var studiedScopes: [StudyScope] {
        StudySession.uniqueStudyScopes(from: studySessions)
    }
    private var scopeSummary: String? {
        let summary = activeScope?.summary.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return summary.isEmpty ? nil : summary
    }
    private var progress: Double {
        guard !cards.isEmpty else { return 0 }
        return Double(min(currentIndex + 1, cards.count)) / Double(cards.count)
    }
    private var dedicatedMinutesDouble: Double {
        Double(ARIAService.normalizedDurationMinutes(Date().timeIntervalSince(sessionStartTime) / 60))
    }
    /// Running total for the in-session counter, priced by the same engine
    /// that awards the XP at completion.
    private var liveSessionXP: Int {
        XPCalculator.xp(forQualities: sessionQualities, intensity: profiles.first?.studyIntensity ?? .average)
    }
    private var reloadSignature: String {
        // Cheap change fingerprint. Uses counts rather than boundary ids: a
        // rated card jumps to the end of the nextReviewDate sort, so a boundary
        // id flips on EVERY rating and would trigger a full queue rebuild
        // (resetting the progress header to "Card 1 of N" and re-filtering the
        // whole store per rating). Counts only change on card add/remove —
        // exactly the cases that need a rebuild (generate-more, external edits).
        let latestSessionID = studySessions.first?.id.uuidString ?? ""
        let planID = filterPlan?.id.uuidString ?? ""
        let scopeSessionID = reviewScopeSession?.id.uuidString ?? ""
        let subjectName = filterSubject?.name ?? ""
        return "\(allReviewCards.count)|\(studySessions.count)|\(latestSessionID)|\(planID)|\(scopeSessionID)|\(subjectName)"
    }
    private var fsrsPreviews: [RecallQuality: FSRSReviewPreview] {
        guard let currentCard else { return [:] }
        return Dictionary(
            uniqueKeysWithValues: FSRSScheduler.previews(for: currentCard).map { ($0.quality, $0) }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if sessionComplete {
                    completionView
                } else if cards.isEmpty {
                    emptyState
                } else if let card = currentCard {
                    activeSession(card: card)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(IBColors.canvas)
            .navigationTitle(filterSubject?.name ?? activeScope?.subjectName ?? "Flashcard Review")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showStudyGuide = true } label: {
                        Label("Guide", systemImage: "book")
                    }
                }
            }
        }
        .onAppear { loadCards() }
        .onChange(of: reloadSignature) { _, _ in
            loadCards()
        }
        .onDisappear {
            // Closing the sheet mid-session must commit the reviewed cards'
            // FSRS reschedule together with their ReviewSession logs, or the
            // cards would be pushed into the future while the analytics engine
            // (which reads ReviewSession) never saw the reviews.
            if !sessionComplete && !sessionQualities.isEmpty {
                do {
                    try context.save()
                } catch {
                    // The sheet is already dismissing, so there is nowhere to
                    // surface the error. The pending reschedules stay in the
                    // context and are flushed by a later save or autosave.
                }
            }
        }
        .sheet(isPresented: $showStudyGuide) {
            StudyGuideView(subject: filterSubject, mode: sessionComplete ? .weakTopics : .preSession)
        }
        .frame(minWidth: 600, minHeight: 500)
    }

    // MARK: - Active Session
    private func activeSession(card: StudyCard) -> some View {
        VStack(spacing: 0) {
            // Progress header
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ACTIVE RECALL")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(IBColors.electricBlue)
                        Text("Card \(currentIndex + 1) of \(cards.count)")
                            .font(.callout.weight(.bold))
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        Text("+\(liveSessionXP) XP")
                            .font(.callout.bold())
                            .foregroundStyle(IBColors.electricBlue)
                    }
                }

                ProgressView(value: progress)
                    .tint(IBColors.electricBlue)

                HStack(spacing: 8) {
                    Label("\(queueManager.totalDueBacklogCount) flashcards due", systemImage: "rectangle.stack")
                    Spacer()
                    Text("All due cards available")
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

                if let subject = card.subject {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: subject.accentColorHex))
                            .frame(width: 8, height: 8)
                        Text(subject.name)
                            .font(.caption.weight(.medium))
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(subject.level)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(card.proficiency.emoji + " " + card.proficiency.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let scopeSummary {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.caption2)
                            .foregroundStyle(IBColors.electricBlue)
                        Text(scopeSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer()
                    }
                }
            }
            .padding(24)

            Divider()

            // Card area
            ScrollView {
                VStack(spacing: 20) {
                    // The flashcard
                    VStack(alignment: .leading, spacing: 16) {
                        // Topic name
                        HStack(spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(.yellow)
                            Text(card.topicName)
                                .font(.headline)
                            Text(card.difficulty.rawValue)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(IBColors.electricBlue.opacity(0.1)))
                                .foregroundStyle(IBColors.electricBlue)
                            Text(card.cognitiveSkill.rawValue)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        if isFlipped {
                            // Back side
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(spacing: 6) {
                                    Image(systemName: "questionmark.circle.fill")
                                        .foregroundStyle(.tint)
                                    Text("Question")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                }
                                FormattedMessageContent(text: card.front)
                                    .font(.system(size: 20, weight: .medium, design: .serif))
                                    .textSelection(.enabled)

                                Divider()

                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Answer")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                }
                                FormattedMessageContent(text: card.back)
                                    .font(.system(size: 19, weight: .regular, design: .serif))
                                    .textSelection(.enabled)

                                if let hint = card.hint, !hint.isEmpty {
                                    Label {
                                        FormattedMessageContent(text: hint)
                                    } icon: {
                                        Image(systemName: "lightbulb")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                if let sourceTitle = card.sourceTitle, !sourceTitle.isEmpty {
                                    HStack(spacing: 6) {
                                        Image(systemName: "link")
                                        if let sourceURL = card.sourceURL {
                                            Link(sourceTitle, destination: sourceURL)
                                        } else {
                                            Text(sourceTitle)
                                        }
                                        if let reference = card.syllabusReference, !reference.isEmpty {
                                            Text("· \(reference)")
                                                .lineLimit(1)
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            // Front side
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "questionmark.circle.fill")
                                        .foregroundStyle(.tint)
                                    Text("Question")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                }
                                FormattedMessageContent(text: card.front)
                                    .font(.system(size: 28, weight: .medium, design: .serif))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 820, minHeight: 300, alignment: .leading)
                    .glassCard()
                    .matchedGeometryEffect(id: "card-\(card.id.uuidString)", in: cardFlipNamespace)
                    .animation(reduceMotion ? nil : IBAnimation.snappy, value: isFlipped)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            }

            Divider()

            // Action bar
            HStack(spacing: 12) {
                if isFlipped {
                    Text("How well did you recall?")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    QualityButton(label: "Again", color: IBColors.danger, detail: fsrsPreviews[.again]?.intervalLabel) { rateCard(.again) }
                        .keyboardShortcut("1", modifiers: [])
                    QualityButton(label: "Hard", color: IBColors.warning, detail: fsrsPreviews[.hard]?.intervalLabel) { rateCard(.hard) }
                        .keyboardShortcut("2", modifiers: [])
                    QualityButton(label: "Good", color: IBColors.electricBlue, detail: fsrsPreviews[.good]?.intervalLabel) { rateCard(.good) }
                        .keyboardShortcut("3", modifiers: [])
                    QualityButton(label: "Easy", color: IBColors.success, detail: fsrsPreviews[.easy]?.intervalLabel) { rateCard(.easy) }
                        .keyboardShortcut("4", modifiers: [])
                } else {
                    Spacer()
                    Button {
                        if reduceMotion { isFlipped = true } else { withAnimation(IBAnimation.snappy) { isFlipped = true } }
                        IBHaptics.light()
                    } label: {
                        HStack {
                            Image(systemName: "eye.fill")
                            Text("Reveal Answer")
                        }
                        .frame(minWidth: 180)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.space, modifiers: [])
                    Spacer()
                }
            }
            .padding(20)
            .background(IBColors.surface)
        }
    }

    // MARK: - Logic
    private func loadCards() {
        // Once a session is complete the queue has been consumed; ignore the
        // post-save @Query reload so the completion screen keeps its snapshot
        // instead of being replaced by an empty state.
        guard !sessionComplete else { return }
        // Every load rebuilds the queue from scratch, so park the cursor on the
        // first card. Keeping an old index can point beyond a shorter queue.
        currentIndex = 0
        isFlipped = false
        let now = Date()
        let startingEmpty = cards.isEmpty
        // The global session must display exactly the cards counted by the
        // sidebar and dashboard. Scoped sessions keep their explicit filter
        // and fallback behavior below.
        if filterSubject == nil, activeScope == nil {
            cards = queueManager.dueCards
            if startingEmpty { sessionStartTime = Date() }
            return
        }
        let allCandidates: [StudyCard]
        if let subject = filterSubject {
            allCandidates = subject.cards
        } else {
            allCandidates = allReviewCards
        }

        let eligibleCandidates: [StudyCard]
        if let activeScope {
            eligibleCandidates = allCandidates.filter { activeScope.matches($0) }
        } else if studiedScopes.isEmpty {
            // The dashboard and queue manager treat all cards as eligible
            // before the learner has created a scoped study session. The
            // review sheet must make the same cards available.
            eligibleCandidates = allCandidates
        } else {
            eligibleCandidates = allCandidates.filter { card in
                studiedScopes.contains { $0.matches(card) }
            }
        }

        let dueCards = eligibleCandidates.filter { $0.nextReviewDate <= now }
        let scopedDueCards = filteredCards(from: dueCards)

        if !scopedDueCards.isEmpty {
            cards = scopedDueCards
        } else if activeScope?.hasFilters == true {
            cards = fallbackScopedCards(from: eligibleCandidates, now: now)
        } else {
            cards = []
        }

        // The session timer starts with the first load.
        if startingEmpty { sessionStartTime = Date() }
    }

    private func filteredCards(from candidates: [StudyCard]) -> [StudyCard] {
        let scopedCards: [StudyCard]
        if let activeScope, activeScope.hasFilters {
            scopedCards = candidates.filter { activeScope.matches($0) }
        } else {
            scopedCards = candidates
        }

        return scopedCards.sorted { $0.nextReviewDate < $1.nextReviewDate }
    }

    private func fallbackScopedCards(from candidates: [StudyCard], now: Date) -> [StudyCard] {
        let scopedCards = filteredCards(from: candidates)
        return scopedCards.sorted { lhs, rhs in
            let lhsIsDue = lhs.nextReviewDate <= now
            let rhsIsDue = rhs.nextReviewDate <= now
            if lhsIsDue != rhsIsDue {
                return lhsIsDue && !rhsIsDue
            }
            if lhs.proficiency != rhs.proficiency {
                return lhs.proficiency.sortOrder < rhs.proficiency.sortOrder
            }
            if lhs.nextReviewDate != rhs.nextReviewDate {
                return lhs.nextReviewDate < rhs.nextReviewDate
            }
            return lhs.createdDate > rhs.createdDate
        }
    }

    private func rateCard(_ quality: RecallQuality) {
        guard let card = currentCard else { return }
        do {
            try FSRSScheduler.applyReview(to: card, quality: quality)
        } catch {
            generationError = "Could not schedule this review: \(error.localizedDescription)"
            return
        }
        sessionQualities.append(quality)
        if quality == .good || quality == .easy { sessionCorrect += 1 }
        let review = ReviewSession(
            cardID: card.id,
            subjectName: card.subject?.name ?? "",
            topicName: card.topicName,
            qualityRating: quality.rawValue,
            studySessionID: studySessionID
        )
        FSRSScheduler.configure(review, quality: quality)
        context.insert(review)
        switch quality { case .again: IBHaptics.warning(); case .hard: IBHaptics.light(); case .good: IBHaptics.medium(); case .easy: IBHaptics.success() }
        isFlipped = false
        if currentIndex + 1 >= cards.count { completeSession() }
        else { withAnimation(IBAnimation.snappy) { currentIndex += 1 } }
    }

    private func completeSession() {
        if let p = profiles.first {
            sessionXP = XPCalculator.xp(forQualities: sessionQualities, intensity: p.studyIntensity)
            p.recordXP(sessionXP)
            p.checkAndUpdateStreak()
        }
        // Snapshot before the cards are rescheduled on save so the completion
        // screen shows the real numbers, not the emptied due queue.
        completedCardCount = cards.count
        completedRetentionPercent = cards.isEmpty ? 0 : sessionCorrect * 100 / cards.count
        filterPlan?.isCompleted = true
        let today = Calendar.current.startOfDay(for: Date())
        let pred = #Predicate<StudyActivity> { $0.date == today }
        if let a = try? context.fetch(FetchDescriptor(predicate: pred)).first {
            a.cardsReviewed += cards.count; a.xpEarned += sessionXP; a.minutesStudied += dedicatedMinutesDouble
        } else {
            context.insert(StudyActivity(date: today, cardsReviewed: cards.count, minutesStudied: dedicatedMinutesDouble, xpEarned: sessionXP))
        }

        // Log StudySession
        let topics = if let activeScope, !activeScope.topicNames.isEmpty {
            activeScope.topicNames.joined(separator: ", ")
        } else {
            Set(cards.compactMap { $0.topicName }).sorted().joined(separator: ", ")
        }
        let subjectName = filterSubject?.name ?? activeScope?.subjectName ?? cards.first?.subject?.name ?? "Mixed"
        let groupedRatings = Dictionary(grouping: Array(zip(cards, sessionQualities))) {
            "\($0.0.topicName)|\($0.0.subtopic)"
        }
        let evidence = groupedRatings.values.map { entries in
            let reviewed = entries.count
            let correct = entries.filter { $0.1 == .good || $0.1 == .easy }.count
            let averageConfidence = entries.isEmpty ? 1 : Int(
                round(entries.reduce(0.0) {
                    let value: Double = switch $1.1 {
                    case .again: 1
                    case .hard: 2
                    case .good: 4
                    case .easy: 5
                    }
                    return $0 + value
                } / Double(entries.count))
            )
            return StudySessionSubunitEvidence(
                topicName: entries.first?.0.topicName ?? "",
                subtopicName: entries.first?.0.subtopic ?? "",
                minutes: dedicatedMinutesDouble * Double(reviewed) / Double(max(cards.count, 1)),
                confidenceRating: averageConfidence,
                cardsReviewed: reviewed,
                correctCount: correct
            )
        }
        let session = StudySession(
            id: studySessionID,
            subjectName: subjectName,
            topicsCovered: topics,
            subtopicsCovered: activeScope?.subtopicNames.joined(separator: ", ") ?? "",
            startDate: sessionStartTime,
            endDate: Date(),
            cardsReviewed: cards.count,
            correctCount: sessionCorrect,
            xpEarned: sessionXP,
            sourcePlanID: filterPlan?.id,
            subunitEvidence: evidence,
            reviewedCardIDs: cards.map(\.id)
        )
        context.insert(session)

        ARIAService.recordReviewSession(
            subjectName: subjectName,
            topics: topics.components(separatedBy: ", ").filter { !$0.isEmpty },
            cardsReviewed: cards.count,
            correctCount: sessionCorrect,
            xpEarned: sessionXP,
            durationMinutes: dedicatedMinutesDouble
        )

        do {
            try context.save()
            generationError = nil
        } catch {
            // A failed save must not be swallowed: roll back the pending
            // reschedules/logs so a retry cannot double-log, and stop short of
            // the completion screen (the reviewed card stays on the last card
            // and can be re-rated to retry).
            context.rollback()
            generationError = "Could not save your review session: \(error.localizedDescription)"
            return
        }

        // Must run after the ReviewSession, StudyActivity and StudySession records
        // are in the context, or this session's work is invisible to the engine.
        progressionEvents.enqueue(ProgressionService.recompute(context: context))
        queueManager.refreshDueCardsSynchronously(context: context)

        withAnimation(IBAnimation.smooth) { sessionComplete = true }; IBHaptics.success()

        // Schedule due card reminders
        NotificationService.scheduleDueCardReminders(context: context)
    }

    // MARK: - Empty State
    private var emptyState: some View {
            VStack(spacing: 20) {
                if let generationError, !generationError.isEmpty {
                    errorBanner(generationError)
                }
                Spacer()
                ZStack {
                Circle()
                    .fill(emptyStateTint.opacity(0.08))
                    .frame(width: 100, height: 100)
                Image(systemName: emptyStateSymbol)
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(emptyStateTint)
            }
            Text(emptyStateTitle)
                .font(.title2.bold())
            Text(emptyStateMessage)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 350)
            Button("Close") { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.large)
            Spacer()
        }
    }

    private var emptyStateTitle: String {
        return studySessions.isEmpty ? "No Revision Yet" : "All Caught Up"
    }

    private var emptyStateSymbol: String {
        return studySessions.isEmpty ? "book.closed.fill" : "checkmark.circle.fill"
    }

    private var emptyStateTint: Color {
        return studySessions.isEmpty ? IBColors.electricBlue : .green
    }

    // MARK: - Completion View
    private var completionView: some View {
        VStack(spacing: 24) {
            Spacer()

            if let generationError, !generationError.isEmpty {
                errorBanner(generationError)
                    .frame(maxWidth: 500)
            }

            ZStack {
                Circle()
                    .fill(IBColors.electricBlue.opacity(0.08))
                    .frame(width: 100, height: 100)
                Image(systemName: "trophy.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.yellow)
            }
            .glow(color: .yellow, radius: 20)

            Text("Session Complete!")
                .font(.title.bold())

            // Stats
            HStack(spacing: 0) {
                StatCard(value: "\(completedCardCount)", label: "Cards", color: IBColors.electricBlue, icon: "square.stack.fill")
                Divider().frame(height: 50)
                StatCard(value: "+\(sessionXP)", label: "XP Earned", color: .yellow, icon: "star.fill")
                Divider().frame(height: 50)
                StatCard(value: "\(completedRetentionPercent)%", label: "Retention", color: IBColors.success, icon: "brain.head.profile")
            }
            .padding(.vertical, 16)
            .glassCard()
            .frame(maxWidth: 500)

            HStack(spacing: 12) {
                Button {
                    showStudyGuide = true
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("ARIA Analysis")
                    }
                    .frame(minWidth: 140)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "checkmark")
                        Text("Done")
                    }
                    .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Spacer()
        }
        .padding(24)
    }

    private var emptyStateMessage: String {
        if studySessions.isEmpty {
            return "No revision yet. Complete a study session first, then spaced repetition will use that material."
        }
        if let scopeSummary {
            return "No saved flashcards match \(scopeSummary) yet. Study that scope first and useful cards will be added automatically."
        }
        return "No studied flashcards are due for review right now. Come back after your next study session or when those cards become due."
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.06))
        )
        .padding(.horizontal, 24)
    }

}
