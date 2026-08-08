import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Subject.name) private var seededSubjects: [Subject]
    @Query private var academicAssessments: [AcademicAssessment]
    @Query private var academicMappings: [AcademicAssessmentMapping]
    @Query private var academicReports: [AcademicReportSnapshot]
    @State private var currentPage = 0
    @State private var isCompleting = false
    @State private var onboardingError: String?

    private var safePageIndex: Int {
        min(max(currentPage, 0), pages.count - 1)
    }

    private let pages = [
        (icon: "books.vertical.fill", title: "Your IB Study Hub", subtitle: "Everything you need in one place"),
        (icon: "brain.head.profile", title: "Science-Backed Learning", subtitle: "Spaced repetition meets active recall"),
        (icon: "chart.bar.doc.horizontal", title: "Your Starting Point", subtitle: "Mastery calibrated from your school evidence"),
        (icon: "sparkles", title: "Ready to Begin", subtitle: "Your subjects and starting data are loaded")
    ]

    private struct EvidenceRow: Identifiable {
        let subject: Subject
        let progress: ProgressEvidence

        var id: UUID { subject.id }
        var mastery: Double { progress.blendedMastery ?? progress.assessmentEvidence ?? 0 }
    }

    private var evidenceRows: [EvidenceRow] {
        seededSubjects.map { subject in
            EvidenceRow(
                subject: subject,
                progress: ProgressEvidenceService.score(
                    subjectName: subject.name,
                    courseLevel: subject.level,
                    cards: subject.cards,
                    assessments: academicAssessments,
                    mappings: academicMappings,
                    reports: academicReports
                )
            )
        }
    }

    private var scoredEvidenceCount: Int {
        evidenceRows.reduce(0) { $0 + $1.progress.scoredAssessmentCount }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero icon
            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(IBGradient.accent)
                    .frame(width: 96, height: 96)
                    .shadow(color: IBColors.electricBlue.opacity(0.4), radius: 24, x: 0, y: 10)
                Image(systemName: pages[safePageIndex].icon)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 24)
            .animation(IBAnimation.smooth, value: currentPage)

            // Title
            VStack(spacing: 8) {
                Text("IB Vault")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(IBColors.electricBlue)
                    .textCase(.uppercase)
                    .tracking(2)

                Text(pages[safePageIndex].title)
                    .font(.system(size: 32, weight: .bold))
                    .animation(IBAnimation.smooth, value: currentPage)

                Text(pages[safePageIndex].subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .animation(IBAnimation.smooth, value: currentPage)
            }
            .padding(.bottom, 32)

            // Page content
            Group {
                switch currentPage {
                case 0: welcomeContent
                case 1: scienceContent
                case 2: masteryContent
                default: subjectContent
                }
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 40)
            .animation(IBAnimation.smooth, value: currentPage)

            Spacer()

            // Step dots + buttons
            VStack(spacing: 20) {
                // Step indicators
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? IBColors.electricBlue : Color.secondary.opacity(0.3))
                            .frame(width: index == currentPage ? 10 : 7, height: index == currentPage ? 10 : 7)
                            .animation(IBAnimation.snappy, value: currentPage)
                    }
                }

                HStack(spacing: 12) {
                    if currentPage > 0 {
                        Button("Back") {
                            withAnimation(IBAnimation.smooth) { currentPage -= 1 }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }

                    Button(currentPage < pages.count - 1 ? "Continue" : "Start Studying") {
                        if currentPage < pages.count - 1 {
                            withAnimation(IBAnimation.smooth) { currentPage += 1 }
                            IBHaptics.light()
                        } else {
                            completeOnboarding()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isCompleting)
                }
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [IBColors.canvas, IBColors.surface],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .alert("Onboarding Incomplete", isPresented: Binding(
            get: { onboardingError != nil },
            set: { if !$0 { onboardingError = nil } }
        )) {
            Button("OK", role: .cancel) { onboardingError = nil }
        } message: {
            Text(onboardingError ?? "Your progress could not be saved. Please try again.")
        }
    }

    // MARK: - Welcome Content
    private var welcomeContent: some View {
        VStack(spacing: 12) {
            featureRow(icon: "clock.arrow.circlepath", color: .blue,
                      title: "Smart Scheduling",
                      desc: "Cards appear when you're about to forget them")
            featureRow(icon: "sparkles", color: .purple,
                      title: "AI Study Companion",
                      desc: "ARIA generates guides and analyses your progress")
            featureRow(icon: "books.vertical", color: .orange,
                      title: "Subject Library",
                      desc: "All IB materials in one searchable workspace")
        }
    }

    private var scienceContent: some View {
        VStack(spacing: 12) {
            featureRow(icon: "arrow.triangle.2.circlepath", color: .green,
                      title: "Spaced Repetition",
                      desc: "Reviews scheduled at optimal intervals for long-term memory")
            featureRow(icon: "brain.head.profile", color: .blue,
                      title: "Active Recall",
                      desc: "Retrieval practice makes you produce an answer instead of only re-reading it")
            featureRow(icon: "chart.line.uptrend.xyaxis", color: .purple,
                      title: "Adaptive Difficulty",
                      desc: "FSRS adapts review timing to your recall history")
        }
    }

    private var subjectContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Your loaded subjects", systemImage: "checkmark.seal.fill")
                .font(.callout.weight(.bold))
                .foregroundStyle(IBColors.success)
            if seededSubjects.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Preparing your subjects…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                ForEach(seededSubjects, id: \.id) { subject in
                    subjectRow(subject.name, subject.level, IBColors.subjectColor(for: subject.name))
                }
            }
        }
    }

    private var masteryContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(IBColors.teal.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(IBColors.teal)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(scoredEvidenceCount) scored school records loaded")
                        .font(.callout.weight(.bold))
                    Text("These values establish your starting mastery before recall reviews begin.")
                        .font(.caption)
                        .foregroundStyle(IBColors.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: IBRadius.md)
                    .fill(IBGradient.tint(IBColors.teal))
                    .overlay(
                        RoundedRectangle(cornerRadius: IBRadius.md)
                            .stroke(IBColors.teal.opacity(0.18), lineWidth: 1)
                    )
            )

            if evidenceRows.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Loading your school evidence...")
                        .font(.callout)
                        .foregroundStyle(IBColors.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(evidenceRows) { row in
                            assessmentMasteryRow(row)
                            if row.id != evidenceRows.last?.id {
                                Divider().padding(.leading, 12)
                            }
                        }
                    }
                }
                .frame(maxHeight: 260)
                .glassCard(cornerRadius: IBRadius.md)
            }
        }
    }

    private func assessmentMasteryRow(_ row: EvidenceRow) -> some View {
        let tint = IBColors.subjectColor(for: row.subject.name)
        return HStack(spacing: 12) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(row.subject.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(IBColors.ink)
                    Spacer(minLength: 8)
                    Text("\(Int(row.mastery * 100))%")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(tint)
                }
                MasteryBar(progress: row.mastery, height: 5, color: tint)
                Text(row.progress.scoredAssessmentCount == 0 ? "No scored evidence yet" : "\(row.progress.scoredAssessmentCount) scored report or assessment records")
                    .font(.caption2)
                    .foregroundStyle(IBColors.secondaryText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func featureRow(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(IBGradient.tint(color))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(color.opacity(0.16), lineWidth: 1)
                        )
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(IBColors.ink)
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(IBColors.secondaryText)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard(cornerRadius: IBRadius.md)
    }

    private func subjectRow(_ name: String, _ level: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 4, height: 24)
            Text(name)
                .font(.callout)
            Spacer()
            Text(level)
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(color.opacity(0.1)))
                .foregroundStyle(color)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }

    private func completeOnboarding() {
        guard !isCompleting else { return }
        isCompleting = true
        IBHaptics.success()
        SyllabusSeeder.seedIfNeeded(context: context)

        // Fetch directly instead of relying on the @Query snapshot so a profile
        // inserted by the app launch path is always seen (avoids duplicates).
        let existingProfiles: [UserProfile]
        do {
            existingProfiles = try context.fetch(FetchDescriptor<UserProfile>())
        } catch {
            onboardingError = error.localizedDescription
            isCompleting = false
            return
        }

        var createdProfile: UserProfile?
        if existingProfiles.isEmpty {
            let profile = UserProfile()
            profile.onboardingCompleted = true
            context.insert(profile)
            createdProfile = profile
        } else {
            for profile in existingProfiles {
                profile.onboardingCompleted = true
            }
        }

        do {
            try context.save()
        } catch {
            // Undo only the profile we just created; a failed save must not
            // roll back unrelated pending work in the shared context.
            if let createdProfile {
                context.delete(createdProfile)
            }
            onboardingError = error.localizedDescription
        }
        isCompleting = false
    }
}
