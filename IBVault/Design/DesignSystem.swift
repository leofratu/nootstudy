import SwiftUI

// MARK: - Color Palette — Premium macOS
struct IBColors {
    // Backgrounds — rich, layered depth
    static let navy = Color(hex: "0C1021")
    static let deepNavy = Color(hex: "070A14")
    static let surface = Color(hex: "12162B")         // Raised surface
    static let surfaceHover = Color(hex: "181D38")     // Hover state
    static let overlay = Color(hex: "1A1F3A")          // Modal/sheet overlay

    // Accents
    static let electricBlue = Color(hex: "5BA4FF")
    static let electricBlueLight = Color(hex: "8BC4FF")
    static let electricBlueMuted = Color(hex: "3A6CA8")

    // Text
    static let softWhite = Color(hex: "EDF0F7")
    static let secondaryText = Color(hex: "A0A8C4")
    static let mutedGray = Color(hex: "5E6687")
    static let tertiaryText = Color(hex: "3D4466")

    // Cards — macOS vibrancy
    static let cardBackground = Color(hex: "141933").opacity(0.85)
    static let cardBorder = Color(hex: "252B4A").opacity(0.6)
    static let cardInnerShadow = Color.black.opacity(0.15)

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

    // Gradients
    static let blueGradient = LinearGradient(
        colors: [Color(hex: "4A90F7"), Color(hex: "7C5CFC")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let surfaceGradient = LinearGradient(
        colors: [Color(hex: "141933").opacity(0.9), Color(hex: "0E1228").opacity(0.95)],
        startPoint: .top, endPoint: .bottom
    )
    static let meshGlow = RadialGradient(
        colors: [Color(hex: "5BA4FF").opacity(0.06), Color.clear],
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

// MARK: - Typography — SF Pro Rounded, premium weight hierarchy
struct IBTypography {
    static let largeTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let title = Font.system(.title2, design: .rounded, weight: .semibold)
    static let title3 = Font.system(.title3, design: .rounded, weight: .medium)
    static let headline = Font.system(.headline, design: .rounded, weight: .semibold)
    static let body = Font.system(.body, design: .default, weight: .regular)
    static let callout = Font.system(.callout, design: .default, weight: .medium)
    static let caption = Font.system(.caption, design: .default, weight: .regular)
    static let captionBold = Font.system(.caption, design: .rounded, weight: .semibold)
    static let mono = Font.system(.footnote, design: .monospaced, weight: .medium)
    static let stat = Font.system(size: 28, weight: .bold, design: .rounded)
    static let bigStat = Font.system(size: 42, weight: .heavy, design: .rounded)
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

// MARK: - Corner Radii — macOS-style
struct IBRadius {
    static let sm: CGFloat = 10
    static let md: CGFloat = 14
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let card: CGFloat = 18
}

// MARK: - Premium Glass Card Modifier
struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = IBRadius.card
    var borderOpacity: Double = 0.5
    var backgroundOpacity: Double = 0.75

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Base fill with gradient
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "161C38").opacity(backgroundOpacity),
                                    Color(hex: "0F1329").opacity(backgroundOpacity + 0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    // Top highlight — macOS-style inner light edge
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.06), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )

                    // Border
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.1 * borderOpacity),
                                    Color(hex: "252B4A").opacity(0.3 * borderOpacity),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                }
            )
            // Outer shadow — subtle depth
            .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 4)
            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Glow Modifier — refined
struct GlowModifier: ViewModifier {
    var color: Color = IBColors.electricBlue
    var radius: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.2), radius: radius, x: 0, y: 0)
            .shadow(color: color.opacity(0.1), radius: radius * 2, x: 0, y: 4)
    }
}

// MARK: - Shimmer Effect
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [Color.clear, Color.white.opacity(0.05), Color.clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .onAppear {
                    withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                        phase = UIScreen.main.bounds.width
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
        self.shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Haptics
struct IBHaptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func rigid() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

// MARK: - Premium Spring Animations
struct IBAnimation {
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.7)
    static let smooth = Animation.spring(response: 0.5, dampingFraction: 0.85)
    static let gentle = Animation.spring(response: 0.6, dampingFraction: 0.9)
    static let bounce = Animation.spring(response: 0.4, dampingFraction: 0.6)
    static let premium = Animation.interpolatingSpring(stiffness: 250, damping: 22)
}
