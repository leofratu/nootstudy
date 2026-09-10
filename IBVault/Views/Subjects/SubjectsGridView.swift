import SwiftUI
import SwiftData

struct SubjectsGridView: View {
    @Query private var subjects: [Subject]
    @Query(sort: \StudySession.endDate, order: .reverse) private var studySessions: [StudySession]
    @Query private var academicAssessments: [AcademicAssessment]
    @Query private var academicMappings: [AcademicAssessmentMapping]
    @Query private var academicReports: [AcademicReportSnapshot]
    @State private var searchText = ""

    private var sortedSubjects: [Subject] {
        subjects
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.name < $1.name }
    }

    /// Whole-subject mastery is derived from review performance and imported
    /// school evidence. Legacy curriculum flags are intentionally excluded.
    private var masteryBySubject: [UUID: Double] {
        var result: [UUID: Double] = [:]
        for subject in subjects {
            result[subject.id] = ProgressEvidenceService.score(
                subjectName: subject.name,
                courseLevel: subject.level,
                cards: subject.cards,
                assessments: academicAssessments,
                mappings: academicMappings,
                reports: academicReports,
                workSessions: studySessions
            ).blendedMastery ?? 0
        }
        return result
    }

    private var averageMastery: Int {
        guard !subjects.isEmpty else { return 0 }
        let total = subjects.reduce(0.0) { $0 + (masteryBySubject[$1.id] ?? 0) }
        return Int((total / Double(subjects.count) * 100).rounded())
    }

    var body: some View {
        // Hoisted so the indexes are built once per render instead of
        // re-derived once per subject tile / metric (computed properties re-run
        // on every access).
        let dueCounts = dueCountBySubject
        let mastery = masteryBySubject
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    StudioPageHeader(
                        eyebrow: "Knowledge library",
                        title: "Subjects",
                        subtitle: "Open a subject to see its curriculum, recall progress, and the next work worth doing.",
                        symbol: "books.vertical.fill",
                        tint: IBColors.englishColor
                    ) {
                        StudioPill(title: "\(subjects.count) SUBJECTS", tint: IBColors.englishColor)
                    }

                    HStack(spacing: 12) {
                        StudioMetricTile(value: "\(subjects.count)", label: "Enrolled", symbol: "books.vertical.fill", tint: IBColors.englishColor, detail: "Your IB syllabus")
                        StudioMetricTile(value: "\(averageMastery)%", label: "Average mastery", symbol: "chart.bar.fill", tint: IBColors.inkTertiary, detail: "Across active subjects")
                        StudioMetricTile(value: "\(subjects.reduce(0) { $0 + (dueCounts[$1.id] ?? 0) })", label: "Due today", symbol: "clock.badge.exclamationmark", tint: IBColors.inkTertiary, detail: "Within studied scopes")
                    }

                    StudioSectionHeader(
                        searchText.isEmpty ? "Subject portfolio" : "Search results",
                        subtitle: searchText.isEmpty ? "Mastery reflects recall and imported assessment results." : "\(sortedSubjects.count) matching subjects",
                        symbol: "square.grid.2x2.fill",
                        tint: IBColors.accent
                    ) {
                        EmptyView()
                    }

                    if sortedSubjects.isEmpty {
                        EmptyStateView(
                            icon: searchText.isEmpty ? "books.vertical" : "magnifyingglass",
                            title: searchText.isEmpty ? "No subjects yet" : "No matching subjects",
                            message: searchText.isEmpty ? "Complete onboarding or seed the syllabus to add your study subjects." : "Try a different subject name."
                        )
                        .frame(maxWidth: .infinity)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(sortedSubjects, id: \.id) { subject in
                                NavigationLink {
                                    SubjectDetailView(subject: subject)
                                } label: {
                                    SubjectWorkspaceRow(subject: subject, dueCount: dueCounts[subject.id] ?? 0, mastery: mastery[subject.id] ?? 0)
                                }
                                .buttonStyle(.plain)
                                if subject.id != sortedSubjects.last?.id {
                                    Divider().padding(.leading, 72)
                                }
                            }
                        }
                        .glassCard()
                    }
                }
                .frame(maxWidth: 1240, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(IBColors.canvas)
            .navigationTitle("Subjects")
            .searchable(text: $searchText, placement: .toolbar, prompt: "Find a subject")
        }
    }

    /// Subject due-card counts keyed by subject id. Built once per render and
    /// hoisted into `body`, so per-tile lookups stay O(1) instead of re-deriving
    /// studied scopes and re-scanning every card set once per tile (and again in
    /// the metric row).
    private var dueCountBySubject: [UUID: Int] {
        let scopes = StudySession.uniqueStudyScopes(from: studySessions)
        guard !scopes.isEmpty else { return [:] }
        let scopesBySubject = Dictionary(grouping: scopes, by: \.subjectName)
        var counts: [UUID: Int] = [:]
        for subject in subjects {
            guard let subjectScopes = scopesBySubject[subject.name], !subjectScopes.isEmpty else { continue }
            var count = 0
            for card in subject.cards where card.isDue {
                if subjectScopes.contains(where: { $0.matches(card) }) {
                    count += 1
                }
            }
            counts[subject.id] = count
        }
        return counts
    }
}

struct SubjectWorkspaceRow: View {
    let subject: Subject
    let dueCount: Int
    let mastery: Double

    private var tint: Color { IBColors.inkTertiary }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(IBGradient.tint(tint))
                    .frame(width: 40, height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(tint.opacity(0.16), lineWidth: 1)
                    )
                Image(systemName: subjectSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(subject.name)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(IBColors.ink)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .help(subject.name)
                    .layoutPriority(1)
                HStack(spacing: 7) {
                    StudioPill(title: subject.level, tint: tint)
                    Text(subject.cards.isEmpty ? "No recall cards" : "\(subject.cards.count) cards")
                        .font(.caption)
                        .foregroundStyle(IBColors.inkSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Mastery")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(IBColors.inkSecondary)
                    Spacer()
                    Text("\(Int(mastery * 100))%")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                }
                MasteryBar(progress: mastery, height: 5, color: tint)
            }
            .frame(minWidth: 120, maxWidth: 220, alignment: .leading)

            VStack(alignment: .trailing, spacing: 3) {
                Text(dueCount == 0 ? "Clear" : "\(dueCount) due")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(dueCount == 0 ? IBColors.success : IBColors.inkTertiary)
                    .lineLimit(1)
                    .fixedSize()
                Text(masteryLabel)
                    .font(.caption2)
                    .foregroundStyle(IBColors.inkSecondary)
                    .lineLimit(1)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(IBColors.inkTertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private var masteryLabel: String {
        switch mastery {
        case 0..<0.25: return "Starting"
        case 0.25..<0.6: return "Building"
        case 0.6..<0.85: return "Reliable"
        default: return "Strong"
        }
    }

    private var subjectSymbol: String {
        switch subject.name {
        case let name where name.contains("Math"): return "function"
        case let name where name.contains("Biology"): return "leaf.fill"
        case let name where name.contains("Economics"): return "chart.line.uptrend.xyaxis"
        case let name where name.contains("Business"): return "briefcase.fill"
        case let name where name.contains("English"): return "text.book.closed.fill"
        default: return "book.closed.fill"
        }
    }
}
