import SwiftUI
import SwiftData

struct SubjectsGridView: View {
    @Query private var subjects: [Subject]
    @Environment(\.modelContext) private var context
    @Environment(ReviewQueueManager.self) private var sharedQueue: ReviewQueueManager?
    @State private var localQueue = ReviewQueueManager()
    private var queue: ReviewQueueManager { sharedQueue ?? localQueue }
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
    /// Scored in one pre-grouped pass rather than re-scanning the whole store
    /// for each subject.
    private var masteryBySubject: [UUID: Double] {
        ProgressEvidenceService.scoreBySubject(
            subjects: subjects,
            assessments: academicAssessments,
            mappings: academicMappings,
            reports: academicReports,
            workSessions: studySessions
        ).mapValues { $0.blendedMastery ?? 0 }
    }

    private func averageMastery(_ mastery: [UUID: Double]) -> Int {
        guard !subjects.isEmpty else { return 0 }
        let total = subjects.reduce(0.0) { $0 + (mastery[$1.id] ?? 0) }
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
                        subtitle: "Your curriculum, one subject at a time.",
                        symbol: "books.vertical.fill",
                        tint: IBColors.englishColor
                    ) {
                        NavigationLink { CardStudioView() } label: {
                            Label("Create cards", systemImage: "plus")
                        }.buttonStyle(PrimaryButtonStyle())
                    }

                    HStack(spacing: 12) {
                        StudioMetricTile(value: "\(subjects.count)", label: "Enrolled", symbol: "books.vertical.fill", tint: IBColors.englishColor, detail: "Your IB syllabus")
                        StudioMetricTile(value: "\(averageMastery(mastery))%", label: "Average mastery", symbol: "chart.bar.fill", tint: IBColors.inkTertiary, detail: "Across active subjects")
                        StudioMetricTile(value: "\(subjects.reduce(0) { $0 + (dueCounts[$1.id] ?? 0) })", label: "Due today", symbol: "clock.badge.exclamationmark", tint: IBColors.inkTertiary, detail: "Within your daily allowance")
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
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 20)], spacing: 20) {
                            ForEach(sortedSubjects, id: \.id) { subject in
                                NavigationLink {
                                    SubjectDetailView(subject: subject)
                                } label: {
                                    SubjectLibraryTile(subject: subject, dueCount: dueCounts[subject.id] ?? 0, mastery: mastery[subject.id] ?? 0)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxWidth: 1240, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(IBColors.canvas)
            .onAppear { queue.refreshDueCards(context: context) }
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                if sharedQueue == nil { localQueue.refreshDueCards(context: context) }
            }
            .navigationTitle("Subjects")
            .searchable(text: $searchText, placement: .toolbar, prompt: "Find a subject")
        }
    }

    /// Subject due-card counts keyed by subject id. Built once per render and
    /// hoisted into `body`, so per-tile lookups stay O(1) instead of re-deriving
    /// studied scopes and re-scanning every card set once per tile (and again in
    /// the metric row).
    private var dueCountBySubject: [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for subject in subjects { counts[subject.id] = queue.dueCount(for: subject) }
        return counts
    }
}

struct SubjectWorkspaceRow: View {
    let subject: Subject
    let dueCount: Int
    let mastery: Double

    private var tint: Color { IBColors.subjectColor(for: subject.name) }

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

private struct SubjectLibraryTile: View {
    let subject: Subject
    let dueCount: Int
    let mastery: Double
    private var tint: Color { IBColors.subjectColor(for: subject.name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(subject.level).font(IBTypography.captionBold).tracking(1.5)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(tint.opacity(0.1), in: Capsule())
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 15, weight: .medium))
            }.foregroundStyle(tint)
            Text(subject.name).font(.custom("Georgia", size: 25))
                .foregroundStyle(IBColors.ink)
                .frame(height: 64, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
            HStack {
                Text("\(subject.cards.count) cards")
                Spacer()
                Text(dueCount > 0 ? "\(dueCount) due" : "Queue clear")
            }.font(IBTypography.caption).foregroundStyle(IBColors.inkSecondary)
            Divider()
            HStack {
                Text("Mastery").font(IBTypography.caption)
                Spacer()
                Text("\(Int(mastery * 100))%").font(IBTypography.mono).foregroundStyle(tint)
            }
            MasteryBar(progress: mastery, height: 5, color: tint)
        }
        .padding(24).surfaceCard()
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 2).fill(tint).frame(height: 3).padding(.horizontal, 24)
        }
        .contentShape(Rectangle())
    }
}
