import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Color Palette — Light, native macOS
struct IBColors {
    // Backgrounds
#if os(macOS)
    static let navy = Color(nsColor: .windowBackgroundColor)
    static let deepNavy = Color(nsColor: .underPageBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let surfaceHover = Color(nsColor: .controlBackgroundColor)
    static let overlay = Color(nsColor: .textBackgroundColor)
#else
    static let navy = Color(hex: "F6F7FB")
    static let deepNavy = Color(hex: "EFF2F7")
    static let surface = Color.white
    static let surfaceHover = Color(hex: "F2F4F8")
    static let overlay = Color(hex: "FBFCFE")
#endif

    // Accents
    static let electricBlue = Color(hex: "5BA4FF")
    static let electricBlueLight = Color(hex: "8BC4FF")
    static let electricBlueMuted = Color(hex: "3A6CA8")

    // Text
#if os(macOS)
    static let softWhite = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let mutedGray = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
#else
    static let softWhite = Color(hex: "1C2434")
    static let secondaryText = Color(hex: "556070")
    static let mutedGray = Color(hex: "6E7785")
    static let tertiaryText = Color(hex: "8A93A3")
#endif

    // Cards
    static let cardBackground = Color.white.opacity(0.96)
    static let cardBorder = Color.black.opacity(0.08)
    static let cardInnerShadow = Color.black.opacity(0.04)

    // Semantic
    static let success = Color(hex: "34D399")
    static let warning = Color(hex: "FCD34D")
    static let danger = Color(hex: "FB7185")
    static let streakOrange = Color(hex: "FF7A45")

    // Subject accents — richer, more saturated
    static let englishColor = Color(hex: "9B72FF")
    static let russianColor = Color(hex: "F472B6")
    static let biologyColor = Color(hex: "22D3A3")
    static let mathColor = Color(hex: "4F94FF")
    static let economicsColor = Color(hex: "FBB940")
    static let businessColor = Color(hex: "F06060")

    // Gradients kept intentionally subtle
    static let blueGradient = LinearGradient(
        colors: [electricBlue, electricBlue],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let surfaceGradient = LinearGradient(
        colors: [surface, surface],
        startPoint: .top, endPoint: .bottom
    )
    static let meshGlow = RadialGradient(
        colors: [Color.clear, Color.clear],
        center: .topTrailing, startRadius: 0, endRadius: 400
    )

    static func subjectColor(for name: String) -> Color {
        switch name.lowercased() {
        case let n where n.contains("english"): return englishColor
        case let n where n.contains("russian"): return russianColor
        case let n where n.contains("biology"): return biologyColor
        case let n where n.contains("math"): return mathColor
        case let n where n.contains("economics"): return economicsColor
        case let n where n.contains("business"): return businessColor
        default: return electricBlue
        }
    }
}

// MARK: - Color Hex Initializer
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// MARK: - Typography — simpler, more native macOS
struct IBTypography {
    static let largeTitle = Font.system(.largeTitle, design: .default, weight: .bold)
    static let title = Font.system(.title2, design: .default, weight: .semibold)
    static let title3 = Font.system(.title3, design: .default, weight: .medium)
    static let headline = Font.system(.headline, design: .default, weight: .semibold)
    static let body = Font.system(.body, design: .default, weight: .regular)
    static let callout = Font.system(.callout, design: .default, weight: .medium)
    static let caption = Font.system(.caption, design: .default, weight: .regular)
    static let captionBold = Font.system(.caption, design: .default, weight: .semibold)
    static let mono = Font.system(.footnote, design: .monospaced, weight: .medium)
    static let stat = Font.system(size: 28, weight: .bold, design: .default)
    static let bigStat = Font.system(size: 42, weight: .heavy, design: .default)
}

// MARK: - Spacing
struct IBSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

// MARK: - Corner Radii
struct IBRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 10
    static let lg: CGFloat = 14
    static let xl: CGFloat = 18
    static let card: CGFloat = 12
}

// MARK: - Simple Card Modifier
struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = IBRadius.card
    var borderOpacity: Double = 0.5
    var backgroundOpacity: Double = 0.75

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(IBColors.cardBackground.opacity(backgroundOpacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(IBColors.cardBorder.opacity(borderOpacity), lineWidth: 1)
                    )
            )
            .shadow(color: IBColors.cardInnerShadow, radius: 2, x: 0, y: 1)
    }
}

// MARK: - Glow Modifier
struct GlowModifier: ViewModifier {
    var color: Color = IBColors.electricBlue
    var radius: CGFloat = 12
    func body(content: Content) -> some View {
        content
    }
}

// MARK: - Shimmer Effect
struct ShimmerModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = IBRadius.card) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    func glow(color: Color = IBColors.electricBlue, radius: CGFloat = 12) -> some View {
        modifier(GlowModifier(color: color, radius: radius))
    }

    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }

    func premiumShadow() -> some View {
        self.shadow(color: IBColors.cardInnerShadow, radius: 2, x: 0, y: 1)
    }
}

// MARK: - Haptics
struct IBHaptics {
#if os(macOS)
    static func light() { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default) }
    static func medium() { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default) }
    static func soft() { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default) }
    static func rigid() { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
    static func success() { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
    static func warning() { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
    static func error() { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
#else
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func rigid() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
#endif
}

// MARK: - Premium Spring Animations
struct IBAnimation {
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.7)
    static let smooth = Animation.spring(response: 0.5, dampingFraction: 0.85)
    static let gentle = Animation.spring(response: 0.6, dampingFraction: 0.9)
    static let bounce = Animation.spring(response: 0.4, dampingFraction: 0.6)
    static let premium = Animation.interpolatingSpring(stiffness: 250, damping: 22)
}
