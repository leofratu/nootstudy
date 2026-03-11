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
    @State private var cardAppear = false
    @State private var showStudyGuide = false

    private var currentCard: StudyCard? {
        currentIndex < cards.count ? cards[currentIndex] : nil
    }
    private var progress: Double {
        cards.isEmpty ? 0 : Double(currentIndex) / Double(cards.count)
    }

    var body: some View {
        ZStack {
            IBColors.navy.ignoresSafeArea()
            if cards.isEmpty { emptyState }
            else if sessionComplete { completionView }
            else if let card = currentCard {
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    cardView(card: card)
                    Spacer()
                    if isFlipped { ratingButtons } else { flipPrompt }
                }
            }
        }
        .onAppear { loadCards() }
        .sheet(isPresented: $showStudyGuide) {
            StudyGuideView(subject: filterSubject, mode: sessionComplete ? .weakTopics : .preSession)
        }
    }

    private var topBar: some View {
        VStack(spacing: IBSpacing.sm) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.title3).foregroundColor(IBColors.mutedGray)
                }
                Spacer()
                Text("\(currentIndex + 1) / \(cards.count)").font(IBTypography.captionBold).foregroundColor(IBColors.softWhite)
                Spacer()
                Button { showStudyGuide = true } label: {
                    Image(systemName: "sparkles").font(.title3).foregroundColor(IBColors.warning)
                }
                Text("+\(sessionXP) XP").font(IBTypography.captionBold).foregroundColor(IBColors.warning)
            }.padding(.horizontal, IBSpacing.md)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(IBColors.cardBorder)
                    RoundedRectangle(cornerRadius: 2).fill(IBColors.electricBlue)
                        .frame(width: geo.size.width * progress).animation(.easeInOut, value: progress)
                }
            }.frame(height: 4).padding(.horizontal, IBSpacing.md)
        }.padding(.top, IBSpacing.md)
    }

    private func cardView(card: StudyCard) -> some View {
        VStack(spacing: IBSpacing.md) {
            if let s = card.subject { SubjectBadge(name: s.name, level: s.level, compact: true) }
            VStack(spacing: IBSpacing.md) {
                if !isFlipped {
                    Text(card.topicName).font(IBTypography.title).foregroundColor(IBColors.softWhite)
                    Text(card.front).font(IBTypography.body).foregroundColor(IBColors.mutedGray).multilineTextAlignment(.center).padding(.horizontal)
                } else {
                    HStack { Image(systemName: "checkmark.circle").foregroundColor(IBColors.success); Text("Answer").font(IBTypography.captionBold).foregroundColor(IBColors.success) }
                    Text(card.back).font(IBTypography.body).foregroundColor(IBColors.softWhite).multilineTextAlignment(.center).padding(.horizontal)
                }
            }
            .padding(IBSpacing.xl).frame(maxWidth: .infinity, minHeight: 300).glassCard(cornerRadius: 20)
        }
        .padding(.horizontal, IBSpacing.md).opacity(cardAppear ? 1 : 0).scaleEffect(cardAppear ? 1 : 0.95)
        .onAppear { withAnimation(.spring(response: 0.4)) { cardAppear = true } }
    }

    private var flipPrompt: some View {
        Button { withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { isFlipped = true }; IBHaptics.light() } label: {
            HStack { Image(systemName: "arrow.uturn.right"); Text("Reveal Answer") }
                .font(IBTypography.headline).foregroundColor(.white).frame(maxWidth: .infinity).padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(IBColors.electricBlue))
        }.padding(.horizontal, IBSpacing.xl).padding(.bottom, IBSpacing.xl)
    }

    private var ratingButtons: some View {
        VStack(spacing: IBSpacing.sm) {
            Text("How well did you recall?").font(IBTypography.caption).foregroundColor(IBColors.mutedGray)
            HStack(spacing: IBSpacing.sm) {
                QualityButton(label: "Again", color: IBColors.danger) { rateCard(.again) }
                QualityButton(label: "Hard", color: IBColors.streakOrange) { rateCard(.hard) }
                QualityButton(label: "Good", color: IBColors.electricBlue) { rateCard(.good) }
                QualityButton(label: "Easy", color: IBColors.success) { rateCard(.easy) }
            }.padding(.horizontal, IBSpacing.md)
        }.padding(.bottom, IBSpacing.xl).transition(.move(edge: .bottom).combined(with: .opacity))
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
        isFlipped = false; cardAppear = false
        if currentIndex + 1 >= cards.count { completeSession() }
        else { withAnimation(.spring(response: 0.3)) { currentIndex += 1 }; DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { withAnimation(.spring(response: 0.4)) { cardAppear = true } } }
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
        VStack(spacing: IBSpacing.lg) {
            EmptyStateView(icon: "checkmark.circle", title: "All Caught Up!", message: "No cards due for review right now.")
            Button("Close") { dismiss() }.font(IBTypography.headline).foregroundColor(IBColors.electricBlue)
        }
    }

    private var completionView: some View {
        VStack(spacing: IBSpacing.xl) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 72)).foregroundColor(IBColors.success)
            Text("Session Complete!").font(IBTypography.largeTitle).foregroundColor(IBColors.softWhite)
            HStack(spacing: IBSpacing.xl) {
                VStack { Text("\(cards.count)").font(.system(size: 32, weight: .bold, design: .rounded)).foregroundColor(IBColors.softWhite); Text("Cards").font(IBTypography.caption).foregroundColor(IBColors.mutedGray) }
                VStack { Text("+\(sessionXP)").font(.system(size: 32, weight: .bold, design: .rounded)).foregroundColor(IBColors.warning); Text("XP").font(IBTypography.caption).foregroundColor(IBColors.mutedGray) }
                VStack { Text("\(cards.isEmpty ? 0 : sessionCorrect * 100 / cards.count)%").font(.system(size: 32, weight: .bold, design: .rounded)).foregroundColor(IBColors.electricBlue); Text("Retention").font(IBTypography.caption).foregroundColor(IBColors.mutedGray) }
            }.padding(IBSpacing.lg).glassCard()
            Spacer()
            Button { showStudyGuide = true } label: {
                HStack { Image(systemName: "sparkles"); Text("ARIA Post-Session Analysis") }
                    .font(IBTypography.captionBold).foregroundColor(IBColors.warning)
                    .padding(.horizontal, IBSpacing.lg).padding(.vertical, IBSpacing.sm)
                    .background(Capsule().stroke(IBColors.warning.opacity(0.5)))
            }
            Button { dismiss() } label: {
                Text("Done").font(IBTypography.headline).foregroundColor(.white).frame(maxWidth: .infinity).padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(IBColors.electricBlue))
            }.padding(.horizontal, IBSpacing.xl).padding(.bottom, IBSpacing.xxl)
        }
    }
}
