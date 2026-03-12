import SwiftUI
import SwiftData

struct SmartRecommendationsView: View {
    @Environment(\.modelContext) private var context
    @Query private var subjects: [Subject]
    @Query private var profiles: [UserProfile]
    @Query(sort: \StudySession.startDate, order: .reverse) private var sessions: [StudySession]
    @Query(sort: \StudyCard.nextReviewDate) private var allCards: [StudyCard]
    
    @State private var selectedRecommendation: StudyRecommendation?
    
    private var recommendations: [StudyRecommendation] {
        generateRecommendations()
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerCard
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                
                if recommendations.isEmpty {
                    emptyState
                        .padding(.horizontal, 28)
                } else {
                    recommendationsSection
                        .padding(.horizontal, 28)
                    
                    dueCardsSection
                        .padding(.horizontal, 28)
                    
                    weakTopicsSection
                        .padding(.horizontal, 28)
                        .padding(.bottom, 24)
                }
            }
        }
        .background(.background)
        .navigationTitle("What to Study")
    }
    
    // MARK: - Header
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(IBColors.electricBlue.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "sparkles")
                        .font(.system(size: 18))
                        .foregroundStyle(IBColors.electricBlue)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Smart Recommendations")
                        .font(.headline)
                    Text("Based on your mastery, due cards, and exam timeline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            if let profile = profiles.first {
                HStack(spacing: 16) {
                    Label("\(profile.targetIBScore) target", systemImage: "target")
                    Label("\(dueCardsCount) cards due", systemImage: "clock.badge.exclamationmark")
                        .foregroundStyle(dueCardsCount > 10 ? .orange : .secondary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .glassCard()
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
    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                Text("Recommended Actions")
                    .font(.headline)
            }
            
            ForEach(recommendations) { rec in
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
    private var dueCardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
                Text("Due for Review")
                    .font(.headline)
                Spacer()
                Text("\(dueCardsCount) cards")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if dueCardsCount > 0 {
                let bySubject = Dictionary(grouping: allCards.filter { $0.isDue }, by: { $0.subject?.name ?? "Unknown" })
                
                ForEach(bySubject.keys.sorted(), id: \.self) { subjectName in
                    let cards = bySubject[subjectName] ?? []
                    let subject = subjects.first { $0.name == subjectName }
                    
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(hex: subject?.accentColorHex ?? "#888888"))
                            .frame(width: 8, height: 8)
                        
                        Text(subjectName)
                            .font(.callout)
                        
                        Spacer()
                        
                        Text("\(cards.count)")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(.orange.opacity(0.15)))
                            .foregroundStyle(.orange)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                HStack {
                    Spacer()
                    Label("All caught up!", systemImage: "checkmark.circle")
                        .font(.callout)
                        .foregroundStyle(.green)
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
                    .foregroundStyle(.red)
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
        let color = Color(hex: subject.accentColorHex)
        
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
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Helpers
    private var dueCardsCount: Int {
        allCards.filter { $0.isDue }.count
    }
    
    private func generateRecommendations() -> [StudyRecommendation] {
        var recs: [StudyRecommendation] = []
        
        let dueCards = allCards.filter { $0.isDue }
        if dueCards.count > 20 {
            recs.append(StudyRecommendation(
                id: UUID(),
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
                id: UUID(),
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
                id: UUID(),
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
                    id: UUID(),
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
                id: UUID(),
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
        
        for (topicName, _) in byTopic {
            let mastery = ProficiencyTracker.masteryPercentage(for: subject, topicName: topicName)
            if weakest == nil || mastery < weakest!.mastery {
                weakest = (topicName, mastery)
            }
        }
        
        return weakest
    }
}

// MARK: - Model
struct StudyRecommendation: Identifiable {
    let id: UUID
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
        case .critical: return .red
        case .high: return .orange
        case .medium: return IBColors.electricBlue
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
