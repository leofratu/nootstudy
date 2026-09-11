import SwiftUI
import SwiftData

struct SmartRecommendationsView: View {
    @Query private var subjects: [Subject]
    @Query private var profiles: [UserProfile]
    @Query(sort: \StudySession.startDate, order: .reverse) private var sessions: [StudySession]
    @Query(sort: \StudyCard.nextReviewDate) private var allCards: [StudyCard]
    
    @State private var selectedRecommendation: StudyRecommendation?

    private var studiedScopes: [StudyScope] {
        StudySession.uniqueStudyScopes(from: sessions)
    }

    private var reviewableDueCards: [StudyCard] {
        guard !studiedScopes.isEmpty else { return [] }
        return allCards.filter { card in
            card.isDue && studiedScopes.contains { $0.matches(card) }
        }
    }

    private func recommendations(from dueCards: [StudyCard]) -> [StudyRecommendation] {
        generateRecommendations(dueCards: dueCards)
    }

    private var weakSubjectCount: Int {
        subjects.filter { $0.masteryProgress < 0.4 }.count
    }
    
    var body: some View {
        let dueCards = reviewableDueCards
        let recs = recommendations(from: dueCards)
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                StudioPageHeader(
                    eyebrow: "Decision support",
                    title: "What to study",
                    subtitle: "A practical sequence based on due cards, current mastery, and the work most likely to move you forward.",
                    symbol: "lightbulb.fill",
                    tint: IBColors.inkTertiary
                ) {
                    StudioPill(title: "\(recs.count) ACTIONS", tint: IBColors.inkTertiary)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: 12)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    StudioMetricTile(value: "\(dueCards.count)", label: "Due cards", symbol: "clock.badge.exclamationmark", tint: dueCards.count > 0 ? IBColors.inkTertiary : IBColors.success, detail: dueCards.count > 0 ? "Schedule first" : "Queue clear")
                    StudioMetricTile(value: "\(weakSubjectCount)", label: "Focus areas", symbol: "scope", tint: IBColors.englishColor, detail: "Below 40% mastery")
                    StudioMetricTile(value: profiles.first.map { "\($0.targetIBScore)" } ?? "-", label: "IB target", symbol: "target", tint: IBColors.accent, detail: "Your current goal")
                }

                if recs.isEmpty {
                    emptyState
                } else {
                    recommendationsSection(recs)
                    dueCardsSection(dueCards: dueCards)
                    weakTopicsSection
                }
            }
            .frame(maxWidth: 1120, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(IBColors.canvas)
        .navigationTitle("What to Study")
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(IBColors.success)
            
            Text("All caught up!")
                .font(.headline)
            
            Text("No specific recommendations right now. Keep up the good work!")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Recommendations
    private func recommendationsSection(_ recs: [StudyRecommendation]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(IBColors.inkTertiary)
                Text("Recommended Actions")
                    .font(.headline)
            }
            
            ForEach(recs) { rec in
                recommendationCard(rec)
            }
        }
    }
    
    private func recommendationCard(_ rec: StudyRecommendation) -> some View {
        Button {
            selectedRecommendation = rec
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(rec.priorityColor.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: rec.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(rec.priorityColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(rec.title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(rec.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(rec.impactLabel)
                        .font(.caption2.bold())
                        .foregroundStyle(rec.priorityColor)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(rec.priorityColor.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Due Cards
    private func dueCardsSection(dueCards: [StudyCard]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundStyle(IBColors.warning)
                Text("Due for Review")
                    .font(.headline)
                Spacer()
                Text("\(dueCards.count) cards")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if dueCards.count > 0 {
                let bySubject = Dictionary(grouping: dueCards, by: { $0.subject?.name ?? "Unknown" })
                
                ForEach(bySubject.keys.sorted(), id: \.self) { subjectName in
                    let cards = bySubject[subjectName] ?? []
                    HStack(spacing: 10) {
                        Circle()
                            .fill(IBColors.inkTertiary)
                            .frame(width: 8, height: 8)
                        
                        Text(subjectName)
                            .font(.callout)
                        
                        Spacer()
                        
                        Text("\(cards.count)")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(IBColors.warning.opacity(0.15)))
                            .foregroundStyle(IBColors.warning)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                HStack {
                    Spacer()
                    Label("All caught up!", systemImage: "checkmark.circle")
                        .font(.callout)
                        .foregroundStyle(IBColors.success)
                    Spacer()
                }
                .padding(.vertical, 12)
            }
        }
        .padding(16)
        .glassCard()
    }
    
    // MARK: - Weak Topics
    private var weakTopicsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(IBColors.danger)
                Text("Focus Areas")
                    .font(.headline)
            }
            
            let weakSubjects = subjects
                .map { subject -> (subject: Subject, mastery: Double) in
                    (subject: subject, mastery: subject.masteryProgress)
                }
                .filter { $0.mastery < 0.5 }
                .sorted { $0.mastery < $1.mastery }
            
            if weakSubjects.isEmpty {
                HStack {
                    Spacer()
                    Label("No weak areas!", systemImage: "star.fill")
                        .font(.callout)
                        .foregroundStyle(IBColors.success)
                    Spacer()
                }
                .padding(.vertical, 12)
            } else {
                ForEach(weakSubjects.prefix(4), id: \.subject.id) { item in
                    weakTopicRow(item.subject, mastery: item.mastery)
                }
            }
        }
        .padding(16)
        .glassCard()
    }
    
    private func weakTopicRow(_ subject: Subject, mastery: Double) -> some View {
        let color = IBColors.inkTertiary
        
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                
                Text(subject.name)
                    .font(.callout.weight(.medium))
                
                Spacer()
                
                Text("\(Int(mastery * 100))%")
                    .font(.caption.bold())
                    .foregroundStyle(color)
                
                MasteryBar(progress: mastery, height: 4, color: color)
                    .frame(width: 60)
            }
            
            if let weakestTopic = findWeakestTopic(for: subject) {
                HStack {
                    Text("Weakest: \(weakestTopic.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(weakestTopic.mastery * 100))%")
                        .font(.caption2)
                        .foregroundStyle(IBColors.danger)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Helpers
    private func generateRecommendations(dueCards: [StudyCard]) -> [StudyRecommendation] {
        var recs: [StudyRecommendation] = []
        
        if dueCards.count > 20 {
            recs.append(StudyRecommendation(
                id: "review.urgent",
                title: "Urgent: \(dueCards.count) cards overdue",
                description: "Your review pile is growing. Start a review session now to prevent knowledge decay.",
                priority: .critical,
                type: .reviewDue,
                icon: "clock.badge.exclamationmark",
                subjectName: nil,
                impact: 0.9
            ))
        } else if dueCards.count > 0 {
            recs.append(StudyRecommendation(
                id: "review.due",
                title: "\(dueCards.count) cards due now",
                description: "Regular reviews strengthen memory. Start a quick review session.",
                priority: .high,
                type: .reviewDue,
                icon: "clock",
                subjectName: nil,
                impact: 0.7
            ))
        }
        
        let weakSubjects = subjects
            .map { ($0, $0.masteryProgress) }
            .filter { $0.1 < 0.4 }
            .sorted { $0.1 < $1.1 }
        
        if let weakest = weakSubjects.first {
            recs.append(StudyRecommendation(
                id: "weak.\(weakest.0.name)",
                title: "Focus on \(weakest.0.name)",
                description: "This is your weakest subject at \(Int(weakest.1 * 100))% mastery. Prioritize this for biggest score gains.",
                priority: .high,
                type: .weakSubject,
                icon: "exclamationmark.triangle",
                subjectName: weakest.0.name,
                impact: 0.8
            ))
        }
        
        let profile = profiles.first
        if profile?.ibYear == .dp2 {
            let monthsToExam = 2
            if monthsToExam < 3 {
                recs.append(StudyRecommendation(
                    id: "exam.prep",
                    title: "DP2: Exam prep mode",
                    description: "Focus on highest-yield topics. Target your weakest areas that appear frequently in exams.",
                    priority: .critical,
                    type: .examPrep,
                    icon: "calendar.badge.clock",
                    subjectName: nil,
                    impact: 0.9
                ))
            }
        }
        
        if let profile = profile, profile.currentStreak < 3 {
            recs.append(StudyRecommendation(
                id: "streak.build",
                title: "Build your streak",
                description: "You're on a \(profile.currentStreak)-day streak. Keep it going for bonus XP and better retention!",
                priority: .medium,
                type: .streak,
                icon: "flame",
                subjectName: nil,
                impact: 0.4
            ))
        }
        
        return recs.sorted { $0.priority.rawValue > $1.priority.rawValue }
    }
    
    private func findWeakestTopic(for subject: Subject) -> (name: String, mastery: Double)? {
        let byTopic = Dictionary(grouping: subject.cards, by: { $0.topicName })

        var weakest: (name: String, mastery: Double)?

        for (topicName, cards) in byTopic {
            let mastery = ProficiencyTracker.masteryPercentage(for: cards)
            if let existing = weakest {
                if mastery < existing.mastery {
                    weakest = (topicName, mastery)
                }
            } else {
                weakest = (topicName, mastery)
            }
        }

        return weakest
    }
}

// MARK: - Model
struct StudyRecommendation: Identifiable {
    /// Stable, render-independent identity derived from the recommendation's
    /// kind (and subject) so `ForEach` identity never changes between renders.
    let id: String
    let title: String
    let description: String
    let priority: RecommendationPriority
    let type: RecommendationType
    let icon: String
    let subjectName: String?
    let impact: Double
    
    var impactLabel: String {
        switch impact {
        case 0.8...: return "High impact"
        case 0.5..<0.8: return "Medium impact"
        default: return "Low impact"
        }
    }
    
    var priorityColor: Color {
        switch priority {
        case .critical: return IBColors.danger
        case .high: return IBColors.warning
        case .medium: return IBColors.accent
        case .low: return .secondary
        }
    }
}

enum RecommendationPriority: Int, Comparable {
    case critical = 4
    case high = 3
    case medium = 2
    case low = 1
    
    static func < (lhs: RecommendationPriority, rhs: RecommendationPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum RecommendationType {
    case reviewDue
    case weakSubject
    case examPrep
    case streak
    case newContent
}

#Preview {
    NavigationStack {
        SmartRecommendationsView()
    }
}
