import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            // Ambient background mesh
            IBColors.navy.ignoresSafeArea()
                .overlay(IBColors.meshGlow.ignoresSafeArea())

            TabView(selection: $selectedTab) {
                DashboardView().tag(0)
                SubjectsGridView().tag(1)
                ReviewLaunchView().tag(2)
                ARIAChatView().tag(3)
                ProfileView().tag(4)
            }
            .tabViewStyle(.automatic)

            // Premium Tab Bar
            PremiumTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(.keyboard)
    }
}

// MARK: - Premium Tab Bar
struct PremiumTabBar: View {
    @Binding var selectedTab: Int

    let tabs: [(icon: String, label: String)] = [
        ("house.fill", "Home"),
        ("books.vertical.fill", "Subjects"),
        ("brain.head.profile", "Review"),
        ("sparkles", "ARIA"),
        ("person.fill", "Profile")
    ]

    var body: some View {
        HStack {
            ForEach(0..<tabs.count, id: \.self) { index in
                Spacer()
                tabButton(index: index)
                Spacer()
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 26)
        .background(
            ZStack {
                // Frosted glass base
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)

                // Gradient overlay for depth
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                IBColors.deepNavy.opacity(0.7),
                                IBColors.deepNavy.opacity(0.85)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Top edge highlight
                VStack {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.clear, Color.white.opacity(0.04), Color.clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 0.5)
                    Spacer()
                }

                // Fade vignette above
                VStack {
                    LinearGradient(
                        colors: [Color.clear, IBColors.deepNavy.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 24)
                    .offset(y: -24)
                    Spacer()
                }
            }
        )
    }

    @ViewBuilder
    private func tabButton(index: Int) -> some View {
        let isSelected = selectedTab == index
        let isReview = index == 2

        Button {
            withAnimation(IBAnimation.snappy) {
                selectedTab = index
                IBHaptics.soft()
            }
        } label: {
            VStack(spacing: 5) {
                if isReview {
                    ZStack {
                        // Glow ring
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [IBColors.electricBlue.opacity(isSelected ? 0.3 : 0.1), Color.clear],
                                    center: .center, startRadius: 18, endRadius: 36
                                )
                            )
                            .frame(width: 56, height: 56)

                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [IBColors.electricBlue, Color(hex: "4A7CF7")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 46, height: 46)
                            .overlay(
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.2), Color.clear],
                                            startPoint: .top, endPoint: .center
                                        )
                                    )
                            )
                            .shadow(color: IBColors.electricBlue.opacity(isSelected ? 0.5 : 0.2), radius: isSelected ? 12 : 6)

                        Image(systemName: tabs[index].icon)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .offset(y: -10)
                } else {
                    Image(systemName: tabs[index].icon)
                        .font(.system(size: 19, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? IBColors.electricBlue : IBColors.mutedGray)
                        .scaleEffect(isSelected ? 1.05 : 1.0)
                        .animation(IBAnimation.snappy, value: isSelected)

                    // Active indicator dot
                    if isSelected {
                        Circle()
                            .fill(IBColors.electricBlue)
                            .frame(width: 4, height: 4)
                            .shadow(color: IBColors.electricBlue.opacity(0.5), radius: 3)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                Text(tabs[index].label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular, design: .rounded))
                    .foregroundColor(isSelected ? IBColors.softWhite : IBColors.mutedGray)
            }
        }
    }
}

// MARK: - Review Launch — premium start screen
struct ReviewLaunchView: View {
    @Environment(\.modelContext) private var context
    @State private var showReview = false
    @State private var showGuide = false
    @State private var buttonGlow = false

    var body: some View {
        NavigationStack {
            ZStack {
                IBColors.navy.ignoresSafeArea()
                IBColors.meshGlow.ignoresSafeArea()

                VStack(spacing: IBSpacing.xl) {
                    Spacer()

                    PulseOrb(size: 88, color: IBColors.electricBlue)

                    Text("Start Review")
                        .font(IBTypography.largeTitle)
                        .foregroundColor(IBColors.softWhite)

                    Text("Tap below to begin your spaced retrieval session")
                        .font(IBTypography.body)
                        .foregroundColor(IBColors.secondaryText)
                        .multilineTextAlignment(.center)

                    VStack(spacing: IBSpacing.md) {
                        Button {
                            IBHaptics.medium()
                            showReview = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "play.fill")
                                Text("Begin Session")
                            }
                            .font(IBTypography.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: IBRadius.md)
                                    .fill(IBColors.blueGradient)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: IBRadius.md)
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color.white.opacity(0.15), Color.clear],
                                                    startPoint: .top, endPoint: .center
                                                )
                                            )
                                    )
                            )
                            .shadow(color: IBColors.electricBlue.opacity(buttonGlow ? 0.4 : 0.2), radius: buttonGlow ? 16 : 8, y: 4)
                        }

                        Button {
                            IBHaptics.soft()
                            showGuide = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                Text("Get Study Guide First")
                            }
                            .font(IBTypography.captionBold)
                            .foregroundColor(IBColors.electricBlue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: IBRadius.sm)
                                    .stroke(
                                        LinearGradient(
                                            colors: [IBColors.electricBlue.opacity(0.4), IBColors.electricBlue.opacity(0.15)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 0.8
                                    )
                            )
                        }
                    }
                    .padding(.horizontal, IBSpacing.xl)

                    Spacer()
                }
            }
            .fullScreenCover(isPresented: $showReview) { ReviewSessionView() }
            .sheet(isPresented: $showGuide) { StudyGuideView(subject: nil, mode: .preSession) }
            .onAppear {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    buttonGlow = true
                }
            }
        }
    }
}
