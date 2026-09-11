import SwiftUI
import AppKit

nonisolated enum IBLocalClock: Sendable {
    static var now: Date {
        Date()
    }
    static var calendar: Calendar { Calendar.autoupdatingCurrent }
    static var timeZone: TimeZone { TimeZone.autoupdatingCurrent }
    static var locale: Locale { Locale.autoupdatingCurrent }

    private static let formatterCache = FormatterCache()

    static func formatter(dateFormat: String) -> DateFormatter {
        formatterCache.formatter(for: dateFormat, locale: locale, timeZone: timeZone, calendar: calendar)
    }

    private final class FormatterCache: @unchecked Sendable {
        private var cache: [String: DateFormatter] = [:]
        private let lock = NSLock()
        func formatter(for format: String, locale: Locale, timeZone: TimeZone, calendar: Calendar) -> DateFormatter {
            let key = "\(format)|\(locale.identifier)|\(timeZone.identifier)"
            lock.lock()
            defer { lock.unlock() }
            if let cached = cache[key] { return cached }
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.calendar = calendar
            formatter.dateFormat = format
            cache[key] = formatter
            return formatter
        }
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

// MARK: - Appearance

enum IBAppearance: String, CaseIterable, Identifiable {
    case system = "System"
    case dark = "Dark"
    case light = "Light"
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

// MARK: - Color Palette (dynamic light/dark; dark is default)

struct IBColors {
    // Helper: dynamic Color from light/dark hex pair
    private static func dynamic(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.name == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        }))
    }

    // Core surfaces — flat, no gradient/glass
    static let canvas = dynamic(light: "F5F6F8", dark: "0A0C10")
    static let canvasDeep = dynamic(light: "F5F6F8", dark: "07090C")
    static let surface = dynamic(light: "FFFFFF", dark: "12151C")
    static let surfaceRaised = dynamic(light: "FFFFFF", dark: "171B24")
    static let surfaceHover = dynamic(light: "EEF1F5", dark: "1E2430")
    static let border = dynamic(light: "E2E5EA", dark: "262D3A")
    static let borderStrong = dynamic(light: "E2E5EA", dark: "333C4D")
    static let cardBorder = border

    // Ink
    static let ink = dynamic(light: "12151A", dark: "E9EDF4")
    static let inkSecondary = dynamic(light: "5B6472", dark: "A2ADBE")
    static let inkTertiary = dynamic(light: "8A93A3", dark: "6B7688")
    static let secondaryText = inkSecondary
    static let tertiaryText = inkTertiary
    static let mutedGray = inkTertiary
    static let subduedInk = inkSecondary
    static let softWhite = ink

    // Accent — single accent system
    /// Accent used for text, tint, icons
    static let accent = dynamic(light: "2E5BE6", dark: "7FA8FF")
    /// Accent fill used for primary button backgrounds (white text)
    static let accentFill = dynamic(light: "2E5BE6", dark: "2F6BFF")
    static let electricBlue = accent
    static let electricBlueMuted = accentFill

    // Legacy semantic aliases kept neutral-compiled
    static let teal = dynamic(light: "5B6472", dark: "A2ADBE")
    static let coral = dynamic(light: "5B6472", dark: "A2ADBE")
    static let gold = dynamic(light: "5B6472", dark: "A2ADBE")
    static let streakOrange = dynamic(light: "5B6472", dark: "A2ADBE")

    // Semantic — only where meaning is real
    static let success = dynamic(light: "1F9D5C", dark: "3DD68C")
    static let warning = dynamic(light: "B7791F", dark: "F5B04C")
    static let danger = dynamic(light: "C0392B", dark: "FF6B6B")

    // Subject accents — now neutral (single accent discipline)
    static let englishColor = accent
    static let russianColor = accent
    static let biologyColor = accent
    static let mathColor = accent
    static let economicsColor = accent
    static let businessColor = accent
    static let advancedMathColor = accent
    static let universeColor = accent
    static let startupsColor = accent

    static func subjectColor(for name: String) -> Color {
        // Neutral discipline: all subjects share inkTertiary/surface treatment.
        // Keep API but return neutral/accent-adjacent rather than rainbow.
        accent
    }

    // Code block background for dark chat
    static let codeBlockBackground = dynamic(light: "F5F6F8", dark: "0E1219")
}

// MARK: - Color Hex Initializer + NSColor hex

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

extension NSColor {
    convenience init(hex: String) {
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
        self.init(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}

// MARK: - Typography — SF only
struct IBTypography {
    static let largeTitle = Font.system(size: 30, weight: .bold, design: .default)
    static let title = Font.system(.title2, design: .default, weight: .bold)
    static let title3 = Font.system(.title3, design: .default, weight: .semibold)
    static let headline = Font.system(.headline, design: .default, weight: .semibold)
    static let body = Font.system(size: 13, weight: .regular, design: .default)
    static let callout = Font.system(size: 13, weight: .regular, design: .default)
    static let caption = Font.system(size: 11, weight: .regular, design: .default)
    static let captionBold = Font.system(size: 11, weight: .semibold, design: .default)
    static let mono = Font.system(.footnote, design: .monospaced, weight: .medium)
    static let stat = Font.system(size: 26, weight: .bold, design: .default).monospacedDigit()
    static let bigStat = Font.system(size: 40, weight: .bold, design: .default).monospacedDigit()

    // Page title 24 semibold; eyebrow 11 semibold uppercase tracking ~0.8; section 15 semibold
    static let pageTitle = Font.system(size: 24, weight: .semibold, design: .default)
    static let eyebrow = Font.system(size: 11, weight: .semibold, design: .default)
    static let sectionTitle = Font.system(size: 15, weight: .semibold, design: .default)
    static let body13 = Font.system(size: 13, weight: .regular, design: .default)
    static let caption11 = Font.system(size: 11, weight: .regular, design: .default)

    /// Uppercase microcopy for eyebrows and section labels.
    static func eyebrow(size: CGFloat = 11) -> Font {
        .system(size: size, weight: .semibold, design: .default)
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

// MARK: - Corner Radii
struct IBRadius {
    static let sm: CGFloat = 5
    static let md: CGFloat = 7
    static let lg: CGFloat = 8
    static let xl: CGFloat = 8
    static let card: CGFloat = 10
}

// MARK: - Shadows — killed, flat system uses none
struct IBShadow {
    static let cardColor = Color.clear
    static let cardRadius: CGFloat = 0
    static let cardY: CGFloat = 0
    static let contactColor = Color.clear
    static let contactRadius: CGFloat = 0
    static let contactY: CGFloat = 0
}

// MARK: - Gradients — flat, no gradients except where explicitly allowed
struct IBGradient {
    static var accent: LinearGradient {
        LinearGradient(colors: [IBColors.accentFill, IBColors.accentFill], startPoint: .top, endPoint: .bottom)
    }
    static func tint(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color.opacity(0.0), color.opacity(0.0)], startPoint: .top, endPoint: .bottom)
    }
    static var cardSheen: LinearGradient {
        LinearGradient(colors: [IBColors.surface, IBColors.surface], startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Glass Card Modifier -> flat SurfaceCard
struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = IBRadius.card
    var isProminent: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isProminent ? IBColors.surfaceRaised : IBColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(IBColors.border, lineWidth: 1)
                    )
            )
    }
}

// Keep alias for API compat
struct SurfaceCardModifier: ViewModifier {
    var cornerRadius: CGFloat = IBRadius.card
    var isProminent: Bool = false
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isProminent ? IBColors.surfaceRaised : IBColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(IBColors.border, lineWidth: 1)
                    )
            )
    }
}

// MARK: - Glow Modifier — disabled in flat system
struct GlowModifier: ViewModifier {
    var color: Color = IBColors.accent
    var radius: CGFloat = 0
    func body(content: Content) -> some View {
        content
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = IBRadius.card) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }
    func surfaceCard(cornerRadius: CGFloat = IBRadius.card, prominent: Bool = false) -> some View {
        modifier(SurfaceCardModifier(cornerRadius: cornerRadius, isProminent: prominent))
    }
    func glow(color: Color = IBColors.accent, radius: CGFloat = 0) -> some View {
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
