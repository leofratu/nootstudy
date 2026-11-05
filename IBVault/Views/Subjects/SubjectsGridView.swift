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
                        symbol: "books.vertical.fill",
                        tint: IBColors.englishColor
                    ) {
                        NavigationLink { CardStudioView() } label: {
                            Label("Create cards", systemImage: "plus")
                        }.buttonStyle(PrimaryButtonStyle())
                    }

                    HStack(spacing: 16) {
                        StudioMetricTile(value: "\(subjects.count)", label: "Subjects", symbol: "books.vertical.fill")
                        StudioMetricTile(value: "\(averageMastery(mastery))%", label: "Average mastery", symbol: "chart.bar.fill")
                        StudioMetricTile(value: "\(subjects.reduce(0) { $0 + (dueCounts[$1.id] ?? 0) })", label: "Cards due", symbol: "clock.badge.exclamationmark")
                    }

                    if sortedSubjects.isEmpty {
                        EmptyStateView(
                            icon: searchText.isEmpty ? "books.vertical" : "magnifyingglass",
                            title: searchText.isEmpty ? "No subjects yet" : "No matching subjects",
                            message: searchText.isEmpty ? "Complete onboarding or seed the syllabus to add your study subjects." : "Try a different subject name."
                        )
                        .frame(maxWidth: .infinity)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 12)], spacing: 12) {
                            ForEach(sortedSubjects, id: \.id) { subject in
                                NavigationLink {
                                    SubjectDetailView(subject: subject)
                                } label: {
                                    SubjectLibraryTile(subject: subject, dueCount: dueCounts[subject.id] ?? 0, mastery: mastery[subject.id] ?? 0)
                                }
                                .buttonStyle(IBPressStyle())
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
            .onAppear { queue.ensureLoaded(context: context) }
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
        HStack(spacing: 12) {
            Circle().fill(tint).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(subject.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(IBColors.ink)
                    .lineLimit(1)
                    .help(subject.name)
                Text("\(subject.level) · \(subject.cards.isEmpty ? "No cards yet" : "\(subject.cards.count) cards")")
                    .font(IBTypography.caption)
                    .foregroundStyle(IBColors.inkTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(dueCount == 0 ? "Nothing due" : "\(dueCount) due")
                .font(IBTypography.caption.monospacedDigit())
                .foregroundStyle(dueCount == 0 ? IBColors.inkTertiary : IBColors.inkSecondary)
                .lineLimit(1)
                .fixedSize()

            HStack(spacing: 8) {
                MasteryBar(progress: mastery, height: 4, color: tint)
                    .frame(width: 110)
                Text("\(Int(mastery * 100))%")
                    .font(IBTypography.caption.monospacedDigit())
                    .foregroundStyle(IBColors.inkSecondary)
                    .frame(width: 32, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Mastery \(Int(mastery * 100)) percent")

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(IBColors.inkTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

private struct SubjectLibraryTile: View {
    let subject: Subject
    let dueCount: Int
    let mastery: Double
    private var tint: Color { IBColors.subjectColor(for: subject.name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Circle().fill(tint).frame(width: 8, height: 8)
                    Text(subject.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(IBColors.ink)
                        .lineLimit(1)
                }
                Text("\(subject.level) · \(subject.cards.count) cards · \(dueCount > 0 ? "\(dueCount) due" : "nothing due")")
                    .font(IBTypography.caption)
                    .foregroundStyle(IBColors.inkSecondary)
                    .lineLimit(1)
            }
            HStack(spacing: 10) {
                MasteryBar(progress: mastery, height: 4, color: tint)
                Text("\(Int(mastery * 100))%")
                    .font(IBTypography.caption.monospacedDigit())
                    .foregroundStyle(IBColors.inkSecondary)
            }
        }
        .padding(18)
        .surfaceCard()
        .hoverHighlight(cornerRadius: IBRadius.card)
        .contentShape(Rectangle())
    }
}
