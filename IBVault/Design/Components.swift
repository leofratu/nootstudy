import SwiftUI

// MARK: - Glass Card View — Premium macOS
struct GlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = IBRadius.card
    var padding: CGFloat = IBSpacing.md

    init(cornerRadius: CGFloat = IBRadius.card, padding: CGFloat = IBSpacing.md, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .glassCard(cornerRadius: cornerRadius)
    }
}

// MARK: - Progress Ring — Gradient stroke with glow
struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 5
    var size: CGFloat = 60
    var color: Color = IBColors.electricBlue

    var body: some View {
        ZStack {
            Circle()
                .stroke(IBColors.cardBorder.opacity(0.4), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [color.opacity(0.3), color, color.opacity(0.8)]),
                        center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(IBAnimation.smooth, value: progress)
                .shadow(color: color.opacity(0.4), radius: 6)
            // Center percentage
            Text("\(Int(min(progress, 1.0) * 100))")
                .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                .foregroundColor(IBColors.softWhite)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Animated Counter — with spring
struct AnimatedCounter: View {
    let value: Int
    var font: Font = IBTypography.stat
    var color: Color = IBColors.softWhite

    var body: some View {
        Text("\(value)")
            .font(font)
            .foregroundColor(color)
            .contentTransition(.numericText(value: Double(value)))
            .animation(IBAnimation.snappy, value: value)
    }
}

// MARK: - Pulse Orb — ARIA Avatar (refined glow)
struct PulseOrb: View {
    @State private var isAnimating = false
    var size: CGFloat = 44
    var color: Color = IBColors.electricBlue

    var body: some View {
        ZStack {
            // Ambient glow
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [color.opacity(0.25), color.opacity(0)]),
                        center: .center, startRadius: size * 0.15, endRadius: size
                    )
                )
                .frame(width: size * 1.8, height: size * 1.8)
                .scaleEffect(isAnimating ? 1.15 : 0.85)
                .opacity(isAnimating ? 0.7 : 0.3)

            // Core orb — layered gradient
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            color.opacity(0.95), color.opacity(0.6),
                            Color(hex: "2A3070").opacity(0.8), IBColors.deepNavy
                        ]),
                        center: UnitPoint(x: 0.35, y: 0.35),
                        startRadius: 0, endRadius: size * 0.55
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: color.opacity(0.5), radius: 8)

            // Specular highlight — glass feel
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.25), Color.clear],
                        startPoint: .topLeading, endPoint: .center
                    )
                )
                .frame(width: size * 0.65, height: size * 0.65)
                .offset(x: -size * 0.08, y: -size * 0.08)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Subject Badge — pill with subtle gradient
struct SubjectBadge: View {
    let name: String
    let level: String
    var compact: Bool = false

    var color: Color { IBColors.subjectColor(for: name) }

    var body: some View {
        HStack(spacing: IBSpacing.xs) {
            Circle()
                .fill(
                    RadialGradient(colors: [color, color.opacity(0.6)], center: .center, startRadius: 0, endRadius: 6)
                )
                .frame(width: compact ? 7 : 9, height: compact ? 7 : 9)
                .shadow(color: color.opacity(0.5), radius: 3)
            Text(compact ? String(name.prefix(3)).uppercased() : name)
                .font(compact ? IBTypography.captionBold : IBTypography.caption)
                .foregroundColor(IBColors.softWhite)
            if !compact {
                Text(level)
                    .font(IBTypography.caption)
                    .foregroundColor(IBColors.mutedGray)
            }
        }
        .padding(.horizontal, compact ? 8 : 12)
        .padding(.vertical, compact ? 4 : 6)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
                .overlay(
                    Capsule().stroke(
                        LinearGradient(colors: [color.opacity(0.4), color.opacity(0.15)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 0.8
                    )
                )
        )
    }
}

// MARK: - Mastery Bar — gradient fill with glow tip
struct MasteryBar: View {
    let progress: Double
    var height: CGFloat = 6
    var color: Color = IBColors.electricBlue

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(IBColors.cardBorder.opacity(0.3))
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.5), color, color.opacity(0.85)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * min(progress, 1.0))
                    .shadow(color: color.opacity(0.4), radius: 4, x: 2, y: 0)
                    .animation(IBAnimation.smooth, value: progress)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Streak Fire — animated with gradient text
struct StreakFire: View {
    @State private var flicker = false
    let streakCount: Int

    var body: some View {
        HStack(spacing: IBSpacing.xs) {
            Text("🔥")
                .font(.title2)
                .scaleEffect(flicker ? 1.15 : 0.95)
                .rotationEffect(.degrees(flicker ? 3 : -3))
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: flicker)
            AnimatedCounter(value: streakCount, font: IBTypography.headline, color: IBColors.streakOrange)
        }
        .onAppear { flicker = true }
    }
}

// MARK: - Prompt Chip — premium pill
struct PromptChip: View {
    let text: String
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: { action(); IBHaptics.soft() }) {
            Text(text)
                .font(IBTypography.caption)
                .foregroundColor(IBColors.electricBlue)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(IBColors.electricBlue.opacity(0.08))
                        .overlay(
                            Capsule().stroke(
                                LinearGradient(
                                    colors: [IBColors.electricBlue.opacity(0.35), IBColors.electricBlue.opacity(0.12)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.8
                            )
                        )
                )
                .shadow(color: IBColors.electricBlue.opacity(0.1), radius: 4)
        }
        .scaleEffect(isPressed ? 0.95 : 1)
        .animation(IBAnimation.snappy, value: isPressed)
    }
}

// MARK: - Thinking Dots — smoother wave
struct ThinkingDots: View {
    @State private var dotOffset: [CGFloat] = [0, 0, 0]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [IBColors.electricBlue, IBColors.electricBlueLight],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 7, height: 7)
                    .offset(y: dotOffset[index])
                    .shadow(color: IBColors.electricBlue.opacity(0.4), radius: 3)
            }
        }
        .onAppear {
            for i in 0..<3 {
                withAnimation(
                    .easeInOut(duration: 0.55)
                    .repeatForever(autoreverses: true)
                    .delay(Double(i) * 0.12)
                ) {
                    dotOffset[i] = -8
                }
            }
        }
    }
}

// MARK: - Quality Rating Button — glassmorphic
struct QualityButton: View {
    let label: String
    let color: Color
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button {
            isPressed = true
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { isPressed = false }
        } label: {
            Text(label)
                .font(IBTypography.captionBold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: IBRadius.sm)
                        .fill(
                            LinearGradient(
                                colors: [color, color.opacity(0.75)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: IBRadius.sm)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.15), Color.clear],
                                        startPoint: .top, endPoint: .center
                                    )
                                )
                        )
                )
                .shadow(color: color.opacity(0.3), radius: 8, y: 4)
        }
        .scaleEffect(isPressed ? 0.93 : 1)
        .animation(IBAnimation.snappy, value: isPressed)
    }
}

// MARK: - Empty State View — refined
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: IBSpacing.lg) {
            ZStack {
                Circle()
                    .fill(IBColors.electricBlue.opacity(0.08))
                    .frame(width: 88, height: 88)
                Image(systemName: icon)
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [IBColors.mutedGray, IBColors.mutedGray.opacity(0.5)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            }
            Text(title)
                .font(IBTypography.headline)
                .foregroundColor(IBColors.softWhite)
            Text(message)
                .font(IBTypography.body)
                .foregroundColor(IBColors.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .padding(IBSpacing.xl)
    }
}

// MARK: - Premium Divider
struct PremiumDivider: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.clear, IBColors.cardBorder, Color.clear],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .frame(height: 0.5)
    }
}

// MARK: - Stat Card — for dashboard numbers
struct StatCard: View {
    let value: String
    let label: String
    var color: Color = IBColors.electricBlue
    var icon: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(color.opacity(0.7))
            }
            Text(value)
                .font(IBTypography.stat)
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(IBColors.mutedGray)
        }
        .frame(maxWidth: .infinity)
    }
}
