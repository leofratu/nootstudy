import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @State private var currentPage = 0

    private let pages = [
        (icon: "books.vertical.fill", title: "Your IB Study Hub", subtitle: "Everything you need in one place"),
        (icon: "brain.head.profile", title: "Science-Backed Learning", subtitle: "Spaced repetition meets active recall"),
        (icon: "sparkles", title: "Ready to Begin", subtitle: "Your subjects are preloaded")
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero icon
            ZStack {
                Circle()
                    .fill(IBColors.electricBlue.opacity(0.08))
                    .frame(width: 120, height: 120)
                Image(systemName: pages[currentPage].icon)
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(IBColors.electricBlue)
            }
            .glow(color: IBColors.electricBlue, radius: 15)
            .padding(.bottom, 24)
            .animation(IBAnimation.smooth, value: currentPage)

            // Title
            VStack(spacing: 8) {
                Text("IB Vault")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(IBColors.electricBlue)
                    .textCase(.uppercase)
                    .tracking(2)

                Text(pages[currentPage].title)
                    .font(.system(size: 32, weight: .bold))
                    .animation(IBAnimation.smooth, value: currentPage)

                Text(pages[currentPage].subtitle)
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
                default: subjectContent
                }
            }
            .frame(maxWidth: 500)
            .padding(.horizontal, 40)
            .animation(IBAnimation.smooth, value: currentPage)

            Spacer()

            // Step dots + buttons
            VStack(spacing: 20) {
                // Step indicators
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
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

                    Button(currentPage < 2 ? "Continue" : "Start Studying") {
                        if currentPage < 2 {
                            withAnimation(IBAnimation.smooth) { currentPage += 1 }
                            IBHaptics.light()
                        } else {
                            completeOnboarding()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
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
                      desc: "Retrieval practice strengthens memory 1.7× vs re-reading")
            featureRow(icon: "chart.line.uptrend.xyaxis", color: .purple,
                      title: "Adaptive Difficulty",
                      desc: "SM-2 algorithm adjusts card intervals based on your performance")
        }
    }

    private var subjectContent: some View {
        VStack(spacing: 8) {
            subjectRow("English B", "HL", IBColors.englishColor)
            subjectRow("Russian A Literature", "SL", IBColors.russianColor)
            subjectRow("Biology", "SL", IBColors.biologyColor)
            subjectRow("Mathematics AA", "SL", IBColors.mathColor)
            subjectRow("Economics", "HL", IBColors.economicsColor)
            subjectRow("Business Management", "HL", IBColors.businessColor)
        }
    }

    private func featureRow(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 16, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.03)))
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
        IBHaptics.success()
        SyllabusSeeder.seedIfNeeded(context: context)
        NotificationService.requestPermission()
        if let profile = profiles.first {
            profile.onboardingCompleted = true
        } else {
            let profile = UserProfile()
            profile.onboardingCompleted = true
            context.insert(profile)
        }
        try? context.save()
    }
}
