import SwiftUI
import SwiftData

struct SubjectsGridView: View {
    @Query private var subjects: [Subject]
    @Query(sort: \StudySession.endDate, order: .reverse) private var studySessions: [StudySession]
    @State private var searchText = ""

    private let columns = [
        GridItem(.adaptive(minimum: 270, maximum: 420), spacing: 14)
    ]

    private var sortedSubjects: [Subject] {
        subjects
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.name < $1.name }
    }

    private var averageMastery: Int {
        guard !subjects.isEmpty else { return 0 }
        return Int(subjects.map(\.masteryProgress).reduce(0, +) / Double(subjects.count) * 100)
    }

    var body: some View {
        NavigationStack {
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
                        StudioMetricTile(value: "\(averageMastery)%", label: "Average mastery", symbol: "chart.bar.fill", tint: IBColors.teal, detail: "Across active subjects")
                        StudioMetricTile(value: "\(subjects.reduce(0) { $0 + scopedDueCount(for: $1) })", label: "Due today", symbol: "clock.badge.exclamationmark", tint: IBColors.coral, detail: "Within studied scopes")
                    }

                    StudioSectionHeader(
                        searchText.isEmpty ? "Subject portfolio" : "Search results",
                        subtitle: searchText.isEmpty ? "Mastery reflects active recall, not time spent." : "\(sortedSubjects.count) matching subjects",
                        symbol: "square.grid.2x2.fill",
                        tint: IBColors.electricBlue
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
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(sortedSubjects, id: \.id) { subject in
                                NavigationLink {
                                    SubjectDetailView(subject: subject)
                                } label: {
                                    SubjectGridCard(subject: subject, dueCount: scopedDueCount(for: subject))
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
            .navigationTitle("Subjects")
            .searchable(text: $searchText, placement: .toolbar, prompt: "Find a subject")
        }
    }

    private func scopedDueCount(for subject: Subject) -> Int {
        let studiedScopes = StudySession.uniqueStudyScopes(from: studySessions)
            .filter { $0.subjectName == subject.name }
        guard !studiedScopes.isEmpty else { return 0 }
        return subject.cards.filter { card in
            card.isDue && studiedScopes.contains { $0.matches(card) }
        }.count
    }
}

struct SubjectGridCard: View {
    let subject: Subject
    let dueCount: Int

    private var tint: Color { Color(hex: subject.accentColorHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(tint.opacity(0.13))
                        .frame(width: 42, height: 42)
                    Image(systemName: subjectSymbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(subject.name)
                        .font(.headline)
                        .foregroundStyle(IBColors.ink)
                        .lineLimit(1)
                    StudioPill(title: subject.level, tint: tint)
                }
                Spacer()
                Text("\(Int(subject.masteryProgress * 100))%")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Mastery")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(IBColors.secondaryText)
                    Spacer()
                    Text(masteryLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                }
                MasteryBar(progress: subject.masteryProgress, height: 6, color: tint)
            }

            HStack(spacing: 14) {
                Label("\(subject.cards.count) cards", systemImage: "square.stack")
                Spacer()
                Label(dueCount == 0 ? "Clear" : "\(dueCount) due", systemImage: dueCount == 0 ? "checkmark.circle.fill" : "clock.badge.exclamationmark")
                    .foregroundStyle(dueCount == 0 ? IBColors.success : IBColors.coral)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(IBColors.secondaryText)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: IBRadius.card)
                .fill(IBColors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: IBRadius.card)
                        .stroke(IBColors.cardBorder, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
    }

    private var masteryLabel: String {
        switch subject.masteryProgress {
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
