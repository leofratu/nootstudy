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

// MARK: - Study Studio Shell
struct StudioPageHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let trailing: Trailing

    init(
        eyebrow: String,
        title: String,
        subtitle: String,
        symbol: String,
        tint: Color = IBColors.electricBlue,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: IBSpacing.lg) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: IBRadius.md)
                        .fill(tint.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(IBColors.ink)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(IBColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            trailing
        }
    }
}

struct StudioSectionHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let symbol: String
    let tint: Color
    let trailing: Trailing

    init(
        _ title: String,
        subtitle: String? = nil,
        symbol: String,
        tint: Color = IBColors.electricBlue,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(IBColors.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(IBColors.secondaryText)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

struct StudioMetricTile: View {
    let value: String
    let label: String
    let symbol: String
    let tint: Color
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Spacer()
                Circle()
                    .fill(tint.opacity(0.13))
                    .frame(width: 8, height: 8)
            }
            Text(value)
                .font(IBTypography.stat)
                .foregroundStyle(IBColors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(IBColors.ink)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(IBColors.secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: IBRadius.card)
                .fill(IBColors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: IBRadius.card)
                        .stroke(IBColors.cardBorder, lineWidth: 1)
                )
        )
    }
}

struct StudioPill: View {
    let title: String
    var tint: Color = IBColors.electricBlue

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.11)))
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
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(IBColors.electricBlue)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(IBColors.electricBlue.opacity(0.1))
                    )
                Text(text)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(IBColors.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(IBColors.tertiaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(IBColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(IBColors.cardBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
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
