import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @State private var currentPage = 0
    @State private var examDates: [String: Date] = [:]

    private let subjectNames = ["English B", "Russian A Literature", "Biology", "Mathematics AA", "Economics", "Business Management"]

    var body: some View {
        ZStack {
            IBColors.navy.ignoresSafeArea()

            TabView(selection: $currentPage) {
                welcomePage.tag(0)
                sciencePage.tag(1)
                subjectPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)

            // Page dots
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(i == currentPage ? IBColors.electricBlue : IBColors.mutedGray.opacity(0.4))
                            .frame(width: i == currentPage ? 10 : 6, height: i == currentPage ? 10 : 6)
                            .animation(.spring, value: currentPage)
                    }
                }
                .padding(.bottom, 100)
            }
        }
    }

    // MARK: - Page 1: Welcome
    private var welcomePage: some View {
        VStack(spacing: IBSpacing.xl) {
            Spacer()

            ZStack {
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(IBColors.electricBlue.opacity(0.2 - Double(i) * 0.05), lineWidth: 1)
                        .frame(width: CGFloat(120 + i * 60), height: CGFloat(120 + i * 60))
                }
                PulseOrb(size: 80, color: IBColors.electricBlue)
            }

            VStack(spacing: IBSpacing.md) {
                Text("IB Vault")
                    .font(.system(size: 40, weight: .bold, design: .default))
                    .foregroundColor(IBColors.softWhite)

                Text("Your science-backed IB study companion")
                    .font(IBTypography.body)
                    .foregroundColor(IBColors.mutedGray)
            }

            Spacer()

            Button {
                withAnimation { currentPage = 1 }
                IBHaptics.light()
            } label: {
                Text("Get Started")
                    .font(IBTypography.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(IBColors.electricBlue)
                    )
            }
            .padding(.horizontal, IBSpacing.xl)
            .padding(.bottom, IBSpacing.xxl)
        }
    }

    // MARK: - Page 2: Science
    private var sciencePage: some View {
        VStack(spacing: IBSpacing.xl) {
            Spacer()

            VStack(spacing: IBSpacing.lg) {
                Image(systemName: "brain")
                    .font(.system(size: 56))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [IBColors.electricBlue, IBColors.electricBlueLight],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Powered by Learning Science")
                    .font(IBTypography.title)
                    .foregroundColor(IBColors.softWhite)

                VStack(alignment: .leading, spacing: IBSpacing.md) {
                    sciencePoint(icon: "arrow.triangle.2.circlepath", title: "Spaced Repetition", desc: "Review at optimal intervals to beat the forgetting curve")
                    sciencePoint(icon: "brain.head.profile", title: "Active Recall", desc: "Retrieve from memory to strengthen neural pathways")
                    sciencePoint(icon: "chart.line.uptrend.xyaxis", title: "Smart Scheduling", desc: "SM-2 algorithm adapts to your performance")
                }
                .padding(.horizontal, IBSpacing.lg)
            }

            Spacer()

            Button {
                withAnimation { currentPage = 2 }
                IBHaptics.light()
            } label: {
                Text("Continue")
                    .font(IBTypography.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(IBColors.electricBlue))
            }
            .padding(.horizontal, IBSpacing.xl)
            .padding(.bottom, IBSpacing.xxl)
        }
    }

    private func sciencePoint(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: IBSpacing.md) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(IBColors.electricBlue)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(IBTypography.headline)
                    .foregroundColor(IBColors.softWhite)
                Text(desc)
                    .font(IBTypography.caption)
                    .foregroundColor(IBColors.mutedGray)
            }
        }
    }

    // MARK: - Page 3: Subjects
    private var subjectPage: some View {
        VStack(spacing: IBSpacing.lg) {
            Text("Your IB Subjects")
                .font(IBTypography.title)
                .foregroundColor(IBColors.softWhite)
                .padding(.top, IBSpacing.xxl)

            Text("These subjects will be pre-loaded with IB syllabus topics")
                .font(IBTypography.caption)
                .foregroundColor(IBColors.mutedGray)

            ScrollView {
                VStack(spacing: IBSpacing.sm) {
                    subjectRow("English B", "HL", IBColors.englishColor)
                    subjectRow("Russian A Literature", "SL", IBColors.russianColor)
                    subjectRow("Biology", "SL", IBColors.biologyColor)
                    subjectRow("Mathematics AA", "SL", IBColors.mathColor)
                    subjectRow("Economics", "HL", IBColors.economicsColor)
                    subjectRow("Business Management", "HL", IBColors.businessColor)
                }
                .padding(.horizontal, IBSpacing.md)
            }

            Spacer()

            Button {
                completeOnboarding()
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Start Studying")
                }
                .font(IBTypography.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [IBColors.success, IBColors.success.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .padding(.horizontal, IBSpacing.xl)
            .padding(.bottom, IBSpacing.xxl)
        }
    }

    private func subjectRow(_ name: String, _ level: String, _ color: Color) -> some View {
        GlassCard(cornerRadius: 12) {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                Text(name)
                    .font(IBTypography.body)
                    .foregroundColor(IBColors.softWhite)
                Spacer()
                Text(level)
                    .font(IBTypography.captionBold)
                    .foregroundColor(IBColors.mutedGray)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(color.opacity(0.15)))
            }
        }
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
