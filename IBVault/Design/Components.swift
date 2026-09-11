import SwiftUI

// MARK: - Glass Card View -> flat SurfaceCard (API preserved)
struct GlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = IBRadius.card
    var padding: CGFloat = IBSpacing.md
    var prominent: Bool = false

    init(cornerRadius: CGFloat = IBRadius.card, padding: CGFloat = IBSpacing.md, prominent: Bool = false, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.prominent = prominent
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .modifier(SurfaceCardModifier(cornerRadius: cornerRadius, isProminent: prominent))
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
        tint: Color = IBColors.inkTertiary,
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
        HStack(alignment: .center, spacing: IBSpacing.lg) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(IBColors.inkTertiary)
                    Text(eyebrow.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(IBColors.inkTertiary)
                }

                Text(title)
                    .font(IBTypography.pageTitle)
                    .foregroundStyle(IBColors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(IBTypography.body13)
                    .foregroundStyle(IBColors.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        tint: Color = IBColors.inkTertiary,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(IBColors.inkTertiary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(IBTypography.sectionTitle)
                    .foregroundStyle(IBColors.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(IBTypography.caption11)
                        .foregroundStyle(IBColors.inkSecondary)
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
    var tint: Color? = nil
    var detail: String? = nil

    // Legacy tint initializer compat
    init(value: String, label: String, symbol: String, tint: Color, detail: String? = nil) {
        self.value = value
        self.label = label
        self.symbol = symbol
        self.tint = nil
        self.detail = detail
    }
    init(value: String, label: String, symbol: String, detail: String? = nil) {
        self.value = value
        self.label = label
        self.symbol = symbol
        self.tint = nil
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value)
                    .font(.system(size: 23, weight: .semibold).monospacedDigit())
                    .foregroundStyle(IBColors.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(IBColors.inkTertiary)
            }
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(IBColors.ink)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(IBTypography.caption11)
                    .foregroundStyle(IBColors.inkTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .surfaceCard(cornerRadius: IBRadius.md)
    }
}

struct StudioPill: View {
    let title: String
    var tint: Color? = nil
    var semantic: Semantic = .neutral
    enum Semantic { case neutral, success, warning, danger }

    init(title: String, tint: Color? = nil) {
        self.title = title
        self.tint = tint
        self.semantic = .neutral
    }
    init(title: String, semantic: Semantic) {
        self.title = title
        self.semantic = semantic
    }

    private var resolved: (fg: Color, bg: Color, border: Color) {
        switch semantic {
        case .success: return (IBColors.success, IBColors.success.opacity(0.12), IBColors.success.opacity(0.20))
        case .warning: return (IBColors.warning, IBColors.warning.opacity(0.12), IBColors.warning.opacity(0.20))
        case .danger: return (IBColors.danger, IBColors.danger.opacity(0.12), IBColors.danger.opacity(0.20))
        case .neutral: return (IBColors.inkSecondary, IBColors.surfaceHover, IBColors.border)
        }
    }

    var body: some View {
        let r = resolved
        Text(title)
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(r.fg)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(r.bg)
                    .overlay(Capsule().stroke(r.border, lineWidth: 1))
            )
    }
}

// MARK: - Progress Ring — single accent
struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 5
    var size: CGFloat = 60
    var color: Color = IBColors.accent

    private var clampedProgress: Double { min(max(progress, 0.0), 1.0) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(IBColors.border, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(IBColors.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(IBAnimation.smooth, value: progress)
            Text("\(Int(clampedProgress * 100))")
                .font(.system(size: size * 0.28, weight: .bold).monospacedDigit())
                .foregroundStyle(IBColors.ink)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Animated Counter — with spring
struct AnimatedCounter: View {
    let value: Int
    var font: Font = IBTypography.stat
    var color: Color = IBColors.ink

    var body: some View {
        Text("\(value)")
            .font(font)
            .foregroundStyle(color)
            .contentTransition(.numericText(value: Double(value)))
            .animation(IBAnimation.snappy, value: value)
    }
}

// MARK: - Pulse Orb — flat neutral
struct PulseOrb: View {
    var size: CGFloat = 44
    var color: Color = IBColors.inkTertiary

    var body: some View {
        ZStack {
            Circle()
                .fill(IBColors.surfaceHover)
                .frame(width: size, height: size)
                .overlay(Circle().stroke(IBColors.border, lineWidth: 1))
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(IBColors.inkTertiary)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Subject Badge — neutral
struct SubjectBadge: View {
    let name: String
    let level: String
    var compact: Bool = false

    var body: some View {
        HStack(spacing: IBSpacing.xs) {
            Image(systemName: "book.closed")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(IBColors.inkTertiary)
            Text(compact ? String(name.prefix(3)).uppercased() : name)
                .font(compact ? IBTypography.captionBold : IBTypography.caption)
                .foregroundStyle(IBColors.inkSecondary)
            if !compact {
                Text(level)
                    .font(IBTypography.caption)
                    .foregroundStyle(IBColors.inkTertiary)
            }
        }
        .padding(.horizontal, compact ? 8 : 12)
        .padding(.vertical, compact ? 4 : 6)
        .background(
            Capsule()
                .fill(IBColors.surfaceHover)
                .overlay(Capsule().stroke(IBColors.border, lineWidth: 1))
        )
    }
}

// MARK: - Mastery Bar — single accent fill, neutral track
struct MasteryBar: View {
    let progress: Double
    var height: CGFloat = 6
    var color: Color = IBColors.accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(IBColors.border)
                Capsule()
                    .fill(IBColors.accent)
                    .frame(width: max(0, geo.size.width * min(progress, 1.0)))
            }
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : IBAnimation.smooth, value: progress)
    }
}

// MARK: - Streak Fire — monochrome
struct StreakFire: View {
    let streakCount: Int

    var body: some View {
        HStack(spacing: IBSpacing.xs) {
            Image(systemName: "flame.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(IBColors.inkTertiary)
            AnimatedCounter(value: streakCount, font: IBTypography.headline, color: IBColors.ink)
        }
    }
}

// MARK: - Prompt Chip — flat neutral
struct PromptChip: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: { action(); IBHaptics.soft() }) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(IBColors.inkTertiary)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(IBColors.surfaceHover)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(IBColors.border, lineWidth: 1))
                    )
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(IBColors.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(IBColors.inkTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceCard(cornerRadius: IBRadius.md)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Thinking Indicator
struct ThinkingDots: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .tint(IBColors.inkTertiary)
    }
}

// MARK: - Quality Rating Button — neutral until selected
struct QualityButton: View {
    let label: String
    var color: Color = IBColors.border
    var detail: String? = nil
    var isSelected: Bool = false
    let action: () -> Void
    @State private var isPressed = false

    // Compat initializer with color param
    init(label: String, color: Color, detail: String? = nil, isSelected: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.color = color
        self.detail = detail
        self.isSelected = isSelected
        self.action = action
    }
    init(label: String, detail: String? = nil, isSelected: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.detail = detail
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button {
            isPressed = true
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { isPressed = false }
        } label: {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                if let detail {
                    Text(detail)
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isSelected ? IBColors.accent : IBColors.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, detail == nil ? 14 : 9)
            .background(
                RoundedRectangle(cornerRadius: IBRadius.md)
                    .fill(isSelected ? IBColors.accent.opacity(0.12) : IBColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: IBRadius.md)
                            .stroke(isSelected ? IBColors.accent : IBColors.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.98 : 1)
        .animation(IBAnimation.snappy, value: isPressed)
    }
}

// MARK: - Empty State View — refined neutral
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: IBSpacing.md) {
            ZStack {
                Circle()
                    .fill(IBColors.surfaceHover)
                    .frame(width: 84, height: 84)
                    .overlay(Circle().stroke(IBColors.border, lineWidth: 1))
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(IBColors.inkTertiary)
            }
            .padding(.bottom, 2)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(IBColors.ink)
            Text(message)
                .font(IBTypography.body13)
                .foregroundStyle(IBColors.inkSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 380)
        }
        .padding(IBSpacing.xl)
    }
}

// MARK: - Premium Divider — sharp 1px
struct PremiumDivider: View {
    var body: some View {
        Rectangle()
            .fill(IBColors.border)
            .frame(height: 1)
    }
}

// MARK: - Stat Card — neutral
struct StatCard: View {
    let value: String
    let label: String
    var color: Color = IBColors.ink
    var icon: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(IBColors.inkTertiary)
            }
            Text(value)
                .font(IBTypography.stat)
                .foregroundStyle(IBColors.ink)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(IBColors.inkTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(IBColors.accentFill))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(IBColors.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(IBColors.surface)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(IBColors.border, lineWidth: 1))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
