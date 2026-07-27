import SwiftUI
import AppKit

// MARK: - Color Palette
struct IBColors {
    // Neutral workspace surfaces
    static let navy = Color(hex: "F4F6FA")
    static let deepNavy = Color(hex: "E9EDF5")
    static let surface = Color.white
    static let surfaceHover = Color(hex: "EEF3FB")
    static let overlay = Color.white
    static let canvas = Color(hex: "F4F6FA")
    static let ink = Color(hex: "1C2536")
    static let subduedInk = Color(hex: "64708A")

    // Accents
    static let electricBlue = Color(hex: "2868E8")
    static let electricBlueLight = Color(hex: "8DB8FF")
    static let electricBlueMuted = Color(hex: "2956AB")
    static let teal = Color(hex: "10A89A")
    static let coral = Color(hex: "F06A4D")
    static let gold = Color(hex: "E39B16")

    // Text
    static let softWhite = ink
    static let secondaryText = subduedInk
    static let mutedGray = subduedInk
    static let tertiaryText = Color(hex: "909BB0")

    // Cards
    static let cardBackground = Color.white
    static let cardBorder = Color(hex: "DDE3EE")
    static let cardInnerShadow = Color(hex: "1C2536").opacity(0.04)

    // Semantic
    static let success = Color(hex: "34D399")
    static let warning = Color(hex: "FCD34D")
    static let danger = Color(hex: "FB7185")
    static let streakOrange = Color(hex: "FF7A45")

    // Subject accents
    static let englishColor = Color(hex: "9B72FF")
    static let russianColor = Color(hex: "F472B6")
    static let biologyColor = Color(hex: "22D3A3")
    static let mathColor = Color(hex: "4F94FF")
    static let economicsColor = Color(hex: "FBB940")
    static let businessColor = Color(hex: "F06060")

    // Kept for the handful of data visualizations that benefit from a range.
    static let blueGradient = LinearGradient(
        colors: [Color(hex: "5BA4FF"), Color(hex: "7B6CF6")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let surfaceGradient = LinearGradient(
        colors: [Color.white.opacity(0.95), Color(hex: "F0F4FA")],
        startPoint: .top, endPoint: .bottom
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

// MARK: - Typography
struct IBTypography {
    static let largeTitle = Font.system(.largeTitle, design: .default, weight: .bold)
    static let title = Font.system(.title2, design: .default, weight: .bold)
    static let title3 = Font.system(.title3, design: .default, weight: .medium)
    static let headline = Font.system(.headline, design: .default, weight: .semibold)
    static let body = Font.system(.body, design: .default, weight: .regular)
    static let callout = Font.system(.callout, design: .default, weight: .medium)
    static let caption = Font.system(.caption, design: .default, weight: .regular)
    static let captionBold = Font.system(.caption, design: .default, weight: .semibold)
    static let mono = Font.system(.footnote, design: .monospaced, weight: .medium)
    static let stat = Font.system(size: 26, weight: .bold, design: .rounded)
    static let bigStat = Font.system(size: 40, weight: .bold, design: .rounded)
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
    static let md: CGFloat = 8
    static let lg: CGFloat = 8
    static let xl: CGFloat = 8
    static let card: CGFloat = 8
}

// MARK: - Glass Card Modifier
struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = IBRadius.card
    var borderOpacity: Double = 0.5
    var backgroundOpacity: Double = 0.75

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(IBColors.surface)
                    .shadow(color: IBColors.ink.opacity(0.045), radius: 12, x: 0, y: 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(IBColors.cardBorder, lineWidth: 1)
                    )
            )
    }
}

// MARK: - Glow Modifier — subtle halo
struct GlowModifier: ViewModifier {
    var color: Color = IBColors.electricBlue
    var radius: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.2), radius: radius, x: 0, y: 0)
    }
}

// MARK: - Shimmer Effect
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.15), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .onAppear {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        phase = 300
                    }
                }
            )
            .clipped()
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
        self.shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Haptics
struct IBHaptics {
    static func light() { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default) }
    static func medium() { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default) }
    static func soft() { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default) }
    static func rigid() { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
    static func success() { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
    static func warning() { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
    static func error() { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
}

// MARK: - Animations
struct IBAnimation {
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.78)
    static let smooth = Animation.spring(response: 0.42, dampingFraction: 0.9)
    static let gentle = Animation.spring(response: 0.6, dampingFraction: 0.9)
    static let bounce = Animation.spring(response: 0.4, dampingFraction: 0.6)
    static let premium = Animation.interpolatingSpring(stiffness: 250, damping: 22)
}
