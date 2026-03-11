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
            .padding()
            .navigationTitle(filterSubject?.name ?? "Review Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Guide") { showStudyGuide = true }
                }
            }
        }
        .onAppear { loadCards() }
        .sheet(isPresented: $showStudyGuide) {
            StudyGuideView(subject: filterSubject, mode: sessionComplete ? .weakTopics : .preSession)
        }
    }

    private func activeSession(card: StudyCard) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Card \(currentIndex + 1) of \(cards.count)")
                Spacer()
                Text("+\(sessionXP) XP")
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress)

            if let subject = card.subject {
                LabeledContent("Subject", value: "\(subject.name) • \(subject.level)")
            }

            GroupBox("Prompt") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(card.topicName)
                        .font(.headline)
                    Text(card.front)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isFlipped {
                GroupBox("Answer") {
                    Text(card.back)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Rate your recall")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("Again") { rateCard(.again) }
                        Button("Hard") { rateCard(.hard) }
                        Button("Good") { rateCard(.good) }
                            .buttonStyle(.borderedProminent)
                        Button("Easy") { rateCard(.easy) }
                    }
                }
            } else {
                Button("Reveal Answer") {
                    isFlipped = true
                    IBHaptics.light()
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
    }

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
        else { currentIndex += 1 }
    }

    private func completeSession() {
        if let p = profiles.first { p.addXP(sessionXP); p.checkAndUpdateStreak() }
        let today = Calendar.current.startOfDay(for: Date())
        let pred = #Predicate<StudyActivity> { $0.date == today }
        if let a = try? context.fetch(FetchDescriptor(predicate: pred)).first {
            a.cardsReviewed += cards.count; a.xpEarned += sessionXP; a.minutesStudied += Date().timeIntervalSince(sessionStartTime) / 60
        } else {
            context.insert(StudyActivity(date: today, cardsReviewed: cards.count, minutesStudied: Date().timeIntervalSince(sessionStartTime) / 60, xpEarned: sessionXP))
        }
        try? context.save()
        withAnimation(.spring) { sessionComplete = true }; IBHaptics.success()
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("All Caught Up", systemImage: "checkmark.circle")
        } description: {
            Text("No cards are due for review right now.")
        } actions: {
            Button("Close") { dismiss() }
        }
    }

    private var completionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Session Complete")
                .font(.title)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Cards reviewed", value: "\(cards.count)")
                    LabeledContent("XP earned", value: "+\(sessionXP)")
                    LabeledContent("Retention", value: "\(cards.isEmpty ? 0 : sessionCorrect * 100 / cards.count)%")
                }
            }

            HStack {
                Button("ARIA Post-Session Analysis") {
                    showStudyGuide = true
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
    }
}
