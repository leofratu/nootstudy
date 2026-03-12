import SwiftUI

// MARK: - Glass Card View
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

// MARK: - Progress Ring
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
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(IBAnimation.smooth, value: progress)
            Text("\(Int(min(progress, 1.0) * 100))")
                .font(.system(size: size * 0.28, weight: .bold, design: .default))
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

// MARK: - Pulse Orb
struct PulseOrb: View {
    var size: CGFloat = 44
    var color: Color = IBColors.electricBlue

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.12))
                .frame(width: size * 1.5, height: size * 1.5)

            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(color.opacity(0.25), lineWidth: 1)
                )
        }
    }
}

// MARK: - Subject Badge
struct SubjectBadge: View {
    let name: String
    let level: String
    var compact: Bool = false

    var color: Color { IBColors.subjectColor(for: name) }

    var body: some View {
        HStack(spacing: IBSpacing.xs) {
            Circle()
                .fill(color)
                .frame(width: compact ? 7 : 9, height: compact ? 7 : 9)
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
                    Capsule().stroke(color.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Mastery Bar
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
                    .fill(color)
                    .frame(width: max(0, geo.size.width * min(progress, 1.0)))
            }
        }
        .frame(height: height)
        .animation(.easeInOut(duration: 0.3), value: progress)
    }
}

// MARK: - Streak Fire
struct StreakFire: View {
    let streakCount: Int

    var body: some View {
        HStack(spacing: IBSpacing.xs) {
            Text("🔥")
                .font(.title2)
            AnimatedCounter(value: streakCount, font: IBTypography.headline, color: IBColors.streakOrange)
        }
    }
}

// MARK: - Prompt Chip
struct PromptChip: View {
    let text: String
    let action: () -> Void

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
                            Capsule().stroke(IBColors.electricBlue.opacity(0.2), lineWidth: 1)
                        )
                )
        }
    }
}

// MARK: - Thinking Indicator
struct ThinkingDots: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .tint(IBColors.electricBlue)
    }
}

// MARK: - Quality Rating Button
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
                        .fill(color)
                )
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
                    .foregroundColor(IBColors.mutedGray)
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
            .fill(IBColors.cardBorder)
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
