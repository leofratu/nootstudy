import SwiftUI

// MARK: - Surface Card
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

// MARK: - Page Shell

/// Page title and one line of context. `eyebrow`, `symbol` and `tint` stay in
/// the signature so existing call sites keep compiling, but a page earns its
/// hierarchy from type alone: no icon, no shouting label.
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
        HStack(alignment: .firstTextBaseline, spacing: IBSpacing.lg) {
            VStack(alignment: .leading, spacing: 6) {
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
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
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

/// A number with its label. Deliberately not a card: a row of these reads as
/// one sentence of facts instead of four more boxes.
struct StudioMetricTile: View {
    let value: String
    let label: String
    let symbol: String
    var tint: Color? = nil
    var detail: String? = nil

    init(value: String, label: String, symbol: String, tint: Color, detail: String? = nil) {
        self.value = value
        self.label = label
        self.symbol = symbol
        self.tint = tint
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
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(IBTypography.stat)
                .foregroundStyle(IBColors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(IBColors.inkSecondary)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(IBTypography.caption11)
                    .foregroundStyle(IBColors.inkTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var resolved: (fg: Color, bg: Color) {
        switch semantic {
        case .success: return (IBColors.success, IBColors.success.opacity(0.12))
        case .warning: return (IBColors.warning, IBColors.warning.opacity(0.14))
        case .danger: return (IBColors.danger, IBColors.danger.opacity(0.12))
        case .neutral: return (IBColors.inkSecondary, IBColors.surfaceHover)
        }
    }

    var body: some View {
        let r = resolved
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(r.fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(r.bg))
    }
}

// MARK: - Progress Ring
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
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(IBAnimation.smooth, value: progress)
            Text("\(Int(clampedProgress * 100))")
                .font(.system(size: size * 0.28, weight: .semibold).monospacedDigit())
                .foregroundStyle(IBColors.ink)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Animated Counter
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

// MARK: - Coach mark
struct PulseOrb: View {
    var size: CGFloat = 44
    var color: Color = IBColors.inkTertiary

    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(IBColors.accent)
            .frame(width: size, height: size)
    }
}

// MARK: - Subject Badge
struct SubjectBadge: View {
    let name: String
    let level: String
    var compact: Bool = false

    var body: some View {
        HStack(spacing: IBSpacing.xs) {
            Circle()
                .fill(IBColors.subjectColor(for: name))
                .frame(width: 6, height: 6)
            Text(compact ? String(name.prefix(3)).uppercased() : name)
                .font(compact ? IBTypography.captionBold : IBTypography.caption)
                .foregroundStyle(IBColors.inkSecondary)
            if !compact {
                Text(level)
                    .font(IBTypography.caption)
                    .foregroundStyle(IBColors.inkTertiary)
            }
        }
    }
}

// MARK: - Mastery Bar
struct MasteryBar: View {
    let progress: Double
    var height: CGFloat = 6
    var color: Color = IBColors.accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(IBColors.surfaceHover)
                Capsule()
                    .fill(color)
                    .frame(width: max(0, geo.size.width * min(max(progress, 0), 1.0)))
            }
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : IBAnimation.smooth, value: progress)
    }
}

// MARK: - Streak
struct StreakFire: View {
    let streakCount: Int

    var body: some View {
        HStack(spacing: IBSpacing.xs) {
            Image(systemName: "flame.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(IBColors.streakOrange)
            AnimatedCounter(value: streakCount, font: IBTypography.headline, color: IBColors.ink)
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
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(IBColors.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(IBColors.inkTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .hoverHighlight()
        }
        .buttonStyle(IBPressStyle())
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

// MARK: - Quality Rating Button
struct QualityButton: View {
    let label: String
    var color: Color = IBColors.ink
    var detail: String? = nil
    var isSelected: Bool = false
    let action: () -> Void

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
        Button(action: action) {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(IBColors.inkTertiary)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 72, maxWidth: .infinity)
            .padding(.vertical, detail == nil ? 12 : 8)
            .background(
                RoundedRectangle(cornerRadius: IBRadius.md)
                    .fill(isSelected ? color.opacity(0.14) : IBColors.surfaceRaised)
            )
            .contentShape(Rectangle())
            .hoverHighlight(cornerRadius: IBRadius.md)
        }
        .buttonStyle(IBPressStyle())
    }
}

// MARK: - Empty State
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(IBColors.inkTertiary)
                .padding(.bottom, 4)
            Text(title)
                .font(IBTypography.sectionTitle)
                .foregroundStyle(IBColors.ink)
            Text(message)
                .font(IBTypography.body13)
                .foregroundStyle(IBColors.inkSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 380)
        }
        .padding(IBSpacing.xl)
    }
}

// MARK: - Divider
struct PremiumDivider: View {
    var body: some View {
        Rectangle()
            .fill(IBColors.border)
            .frame(height: 1)
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let value: String
    let label: String
    var color: Color = IBColors.ink
    var icon: String? = nil

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(IBTypography.stat)
                .foregroundStyle(IBColors.ink)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(IBColors.inkSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Button Styles

/// Press feedback without any chrome, for rows and bespoke buttons.
struct IBPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(IBAnimation.press, value: configuration.isPressed)
    }
}

/// Tints a row while the pointer is over it, so everything clickable answers
/// the moment the pointer arrives instead of only on click.
struct HoverHighlightModifier: ViewModifier {
    var cornerRadius: CGFloat = IBRadius.sm
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isHovered && isEnabled ? IBColors.ink.opacity(0.05) : Color.clear)
            )
            .onHover { isHovered = $0 }
            .animation(IBAnimation.hover, value: isHovered)
    }
}

extension View {
    func hoverHighlight(cornerRadius: CGFloat = IBRadius.sm) -> some View {
        modifier(HoverHighlightModifier(cornerRadius: cornerRadius))
    }
}

private struct IBFilledButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let fill: Color
    let hoverFill: Color
    let foreground: Color
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: IBRadius.sm + 1).fill(isHovered ? hoverFill : fill))
            .contentShape(RoundedRectangle(cornerRadius: IBRadius.sm + 1))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .onHover { isHovered = $0 }
            .animation(IBAnimation.hover, value: isHovered)
            .animation(IBAnimation.press, value: configuration.isPressed)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        IBFilledButtonBody(
            configuration: configuration,
            fill: isEnabled ? IBColors.accentFill : IBColors.surfaceHover,
            hoverFill: isEnabled ? IBColors.accentFill.opacity(0.88) : IBColors.surfaceHover,
            foreground: isEnabled ? Color.white : IBColors.inkTertiary
        )
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        IBFilledButtonBody(
            configuration: configuration,
            fill: IBColors.surfaceRaised,
            hoverFill: isEnabled ? IBColors.surfaceHover : IBColors.surfaceRaised,
            foreground: isEnabled ? IBColors.ink : IBColors.inkTertiary
        )
    }
}
