import SwiftUI
import SwiftData

struct ReviewSessionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    var filterSubject: Subject? = nil

    @State private var cards: [StudyCard] = []
    @State private var currentIndex = 0
    @State private var isFlipped = false
    @State private var sessionComplete = false
    @State private var sessionXP = 0
    @State private var sessionCorrect = 0
    @State private var sessionStartTime = Date()
    @State private var showStudyGuide = false

    private var currentCard: StudyCard? {
        currentIndex < cards.count ? cards[currentIndex] : nil
    }
    private var progress: Double {
        cards.isEmpty ? 0 : Double(currentIndex) / Double(cards.count)
    }
    private var dedicatedMinutesDouble: Double {
        Double(ARIAService.normalizedDurationMinutes(Date().timeIntervalSince(sessionStartTime) / 60))
    }

    var body: some View {
        NavigationStack {
            Group {
                if cards.isEmpty {
                    emptyState
                } else if sessionComplete {
                    completionView
                } else if let card = currentCard {
                    activeSession(card: card)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
            .navigationTitle(filterSubject?.name ?? "Review Session")
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
        .sheet(isPresented: $showStudyGuide) {
            StudyGuideView(subject: filterSubject, mode: sessionComplete ? .weakTopics : .preSession)
        }
        .frame(minWidth: 600, minHeight: 500)
    }

    // MARK: - Active Session
    private func activeSession(card: StudyCard) -> some View {
        VStack(spacing: 0) {
            // Progress header
            VStack(spacing: 8) {
                HStack {
                    Text("Card \(currentIndex + 1) of \(cards.count)")
                        .font(.callout.weight(.medium))
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        Text("+\(sessionXP) XP")
                            .font(.callout.bold())
                            .foregroundStyle(IBColors.electricBlue)
                    }
                }

                ProgressView(value: progress)
                    .tint(IBColors.electricBlue)

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
                                Text(card.front)
                                    .textSelection(.enabled)

                                Divider()

                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Answer")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                }
                                Text(card.back)
                                    .textSelection(.enabled)
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
                                Text(card.front)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 600, alignment: .leading)
                    .glassCard()
                    .animation(IBAnimation.smooth, value: isFlipped)
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
                    QualityButton(label: "Again", color: IBColors.danger) { rateCard(.again) }
                    QualityButton(label: "Hard", color: IBColors.warning) { rateCard(.hard) }
                    QualityButton(label: "Good", color: IBColors.electricBlue) { rateCard(.good) }
                    QualityButton(label: "Easy", color: IBColors.success) { rateCard(.easy) }
                } else {
                    Spacer()
                    Button {
                        withAnimation(IBAnimation.smooth) { isFlipped = true }
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
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Logic
    private func loadCards() {
        let now = Date()
        if let subject = filterSubject {
            cards = subject.cards.filter { $0.nextReviewDate <= now }.sorted { $0.nextReviewDate < $1.nextReviewDate }
        } else {
            let pred = #Predicate<StudyCard> { $0.nextReviewDate <= now }
            var desc = FetchDescriptor(predicate: pred); desc.sortBy = [SortDescriptor(\.nextReviewDate)]
            cards = (try? context.fetch(desc)) ?? []
        }
        sessionStartTime = Date()
    }

    private func rateCard(_ quality: RecallQuality) {
        guard let card = currentCard else { return }
        SM2Engine.applyReview(to: card, quality: quality)
        let xp = SM2Engine.xpForReview(quality: quality); sessionXP += xp
        if quality == .good || quality == .easy { sessionCorrect += 1 }
        context.insert(ReviewSession(cardID: card.id, subjectName: card.subject?.name ?? "", topicName: card.topicName, qualityRating: quality.rawValue))
        switch quality { case .again: IBHaptics.warning(); case .hard: IBHaptics.light(); case .good: IBHaptics.medium(); case .easy: IBHaptics.success() }
        isFlipped = false
        if currentIndex + 1 >= cards.count { completeSession() }
        else { withAnimation(IBAnimation.snappy) { currentIndex += 1 } }
    }

    private func completeSession() {
        if let p = profiles.first { p.addXP(sessionXP); p.checkAndUpdateStreak() }
        let today = Calendar.current.startOfDay(for: Date())
        let pred = #Predicate<StudyActivity> { $0.date == today }
        if let a = try? context.fetch(FetchDescriptor(predicate: pred)).first {
            a.cardsReviewed += cards.count; a.xpEarned += sessionXP; a.minutesStudied += dedicatedMinutesDouble
        } else {
            context.insert(StudyActivity(date: today, cardsReviewed: cards.count, minutesStudied: dedicatedMinutesDouble, xpEarned: sessionXP))
        }

        // Log StudySession
        let topics = Set(cards.compactMap { $0.topicName }).joined(separator: ", ")
        let subjectName = filterSubject?.name ?? cards.first?.subject?.name ?? "Mixed"
        let session = StudySession(
            subjectName: subjectName,
            topicsCovered: topics,
            startDate: sessionStartTime,
            endDate: Date(),
            cardsReviewed: cards.count,
            correctCount: sessionCorrect,
            xpEarned: sessionXP
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

        try? context.save()
        withAnimation(IBAnimation.smooth) { sessionComplete = true }; IBHaptics.success()

        // Schedule due card reminders
        NotificationService.scheduleDueCardReminders(context: context)
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.08))
                    .frame(width: 100, height: 100)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.green)
            }
            Text("All Caught Up")
                .font(.title2.bold())
            Text("No cards are due for review right now. Come back later!")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 350)
            Button("Close") { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.large)
            Spacer()
        }
    }

    // MARK: - Completion View
    private var completionView: some View {
        VStack(spacing: 24) {
            Spacer()

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
                StatCard(value: "\(cards.count)", label: "Cards", color: IBColors.electricBlue, icon: "square.stack.fill")
                Divider().frame(height: 50)
                StatCard(value: "+\(sessionXP)", label: "XP Earned", color: .yellow, icon: "star.fill")
                Divider().frame(height: 50)
                StatCard(value: "\(cards.isEmpty ? 0 : sessionCorrect * 100 / cards.count)%", label: "Retention", color: IBColors.success, icon: "brain.head.profile")
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
}
