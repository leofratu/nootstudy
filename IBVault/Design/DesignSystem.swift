import SwiftUI
import AppKit

nonisolated enum IBLocalClock: Sendable {
    static var now: Date { Date() }
    static var calendar: Calendar { Calendar.autoupdatingCurrent }
    static var timeZone: TimeZone { TimeZone.autoupdatingCurrent }
    static var locale: Locale { Locale.autoupdatingCurrent }

    static func formatter(dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.calendar = calendar
        formatter.dateFormat = dateFormat
        return formatter
    }

    static func nextQuarterHour(after date: Date = now) -> Date {
        let calendar = self.calendar
        let minute = calendar.component(.minute, from: date)
        let second = calendar.component(.second, from: date)
        let elapsedInQuarter = minute % 15
        let minutesToAdd = elapsedInQuarter == 0 && second == 0 ? 0 : 15 - elapsedInQuarter
        let advanced = calendar.date(byAdding: .minute, value: minutesToAdd, to: date) ?? date
        return calendar.dateInterval(of: .minute, for: advanced)?.start ?? advanced
    }
}

// MARK: - Color Palette
struct IBColors {
    // Layered workspace surfaces — a deeper canvas lets elevated cards float.
    static let surface = Color(hex: "FFFFFF")
    static let surfaceHover = Color(hex: "F2F5FA")
    static let canvas = Color(hex: "EDF0F5")
    static let canvasDeep = Color(hex: "E4E9F1")
    static let ink = Color(hex: "131A2B")
    static let subduedInk = Color(hex: "525F78")

    // Accents
    static let electricBlue = Color(hex: "2E5BE6")
    static let electricBlueMuted = Color(hex: "2B4FAE")
    static let teal = Color(hex: "0C9D90")
    static let coral = Color(hex: "EC6141")
    static let gold = Color(hex: "DE9908")

    // Text
    static let softWhite = ink
    static let secondaryText = subduedInk
    static let mutedGray = subduedInk
    static let tertiaryText = Color(hex: "8B95AC")

    // Cards — the border is a faint keyline; elevation comes from shadow.
    static let cardBorder = Color(hex: "E2E7F0")

    // Semantic — deepened so they read on white without a wash.
    static let success = Color(hex: "27B183")
    static let warning = Color(hex: "EBA726")
    static let danger = Color(hex: "EE5068")
    static let streakOrange = Color(hex: "F5733D")

    // Subject accents
    static let englishColor = Color(hex: "8B63F5")
    static let russianColor = Color(hex: "EC5CA8")
    static let biologyColor = Color(hex: "19BE97")
    static let mathColor = Color(hex: "3E86F5")
    static let economicsColor = Color(hex: "F0AD2E")
    static let businessColor = Color(hex: "E85B5B")
    static let advancedMathColor = Color(hex: "7C4FDF")
    static let universeColor = Color(hex: "565BD8")
    static let startupsColor = Color(hex: "0A94D1")

    static func subjectColor(for name: String) -> Color {
        switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "advanced mathematics": return advancedMathColor
        case "fundamentals of the universe": return universeColor
        case "startups & venture capital": return startupsColor
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
    static let largeTitle = Font.system(size: 30, weight: .bold, design: .default)
    static let title = Font.system(.title2, design: .default, weight: .bold)
    static let title3 = Font.system(.title3, design: .default, weight: .semibold)
    static let headline = Font.system(.headline, design: .default, weight: .semibold)
    static let body = Font.system(.body, design: .default, weight: .regular)
    static let callout = Font.system(.callout, design: .default, weight: .medium)
    static let caption = Font.system(.caption, design: .default, weight: .regular)
    static let captionBold = Font.system(.caption, design: .default, weight: .semibold)
    static let mono = Font.system(.footnote, design: .monospaced, weight: .medium)
    static let stat = Font.system(size: 26, weight: .bold, design: .rounded)
    static let bigStat = Font.system(size: 40, weight: .bold, design: .rounded)
    /// Uppercase microcopy for eyebrows and section labels.
    static func eyebrow(size: CGFloat = 10.5) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
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

// MARK: - Corner Radii — varied scale so surfaces read as layered, not boxy.
struct IBRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 10
    static let lg: CGFloat = 14
    static let xl: CGFloat = 20
    static let card: CGFloat = 14
}

// MARK: - Shadows — two-stop elevation: tight contact shadow + diffuse ambient.
struct IBShadow {
    static let cardColor = Color.black.opacity(0.05)
    static let cardRadius: CGFloat = 14
    static let cardY: CGFloat = 5
    static let contactColor = Color.black.opacity(0.04)
    static let contactRadius: CGFloat = 2
    static let contactY: CGFloat = 1
}

// MARK: - Gradients
struct IBGradient {
    static var accent: LinearGradient {
        LinearGradient(
            colors: [IBColors.electricBlue, IBColors.electricBlueMuted],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func tint(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.16), color.opacity(0.08)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Barely-there vertical sheen applied to elevated cards.
    static var cardSheen: LinearGradient {
        LinearGradient(
            colors: [Color.white, Color(hex: "FBFCFE")],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Glass Card Modifier
struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = IBRadius.card

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(IBGradient.cardSheen)
                    .shadow(color: IBShadow.cardColor, radius: IBShadow.cardRadius, x: 0, y: IBShadow.cardY)
                    .shadow(color: IBShadow.contactColor, radius: IBShadow.contactRadius, x: 0, y: IBShadow.contactY)
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

extension View {
    func glassCard(cornerRadius: CGFloat = IBRadius.card) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    func glow(color: Color = IBColors.electricBlue, radius: CGFloat = 12) -> some View {
        modifier(GlowModifier(color: color, radius: radius))
    }
}

// MARK: - Haptics
struct IBHaptics {
    static func light() { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default) }
    static func medium() { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default) }
    static func soft() { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default) }
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
