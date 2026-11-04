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

// MARK: - Color Palette (dynamic light/dark)

/// Paper and ink with one pen-blue accent. Hue is reserved for meaning: blue is
/// "act here", green/amber/red are outcomes, and everything else stays neutral.
struct IBColors {
    // Helper: dynamic Color from light/dark hex pair
    private static func dynamic(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        }))
    }

    // Core surfaces
    static let canvas = dynamic(light: "F5F5F3", dark: "171717")
    static let canvasDeep = dynamic(light: "ECECE9", dark: "111111")
    static let surface = dynamic(light: "FFFFFF", dark: "212120")
    static let surfaceRaised = dynamic(light: "EEEEEB", dark: "2A2A29")
    static let surfaceHover = dynamic(light: "E5E5E1", dark: "343433")
    static let border = dynamic(light: "E2E2DE", dark: "2F2F2E")
    static let borderStrong = dynamic(light: "A6A6A0", dark: "5C5C59")
    static let cardBorder = border

    // Ink
    static let ink = dynamic(light: "1A1A19", dark: "EDEDEA")
    static let inkSecondary = dynamic(light: "5C5C58", dark: "B3B3AE")
    static let inkTertiary = dynamic(light: "71716C", dark: "90908B")
    static let secondaryText = inkSecondary
    static let tertiaryText = inkTertiary
    static let mutedGray = inkTertiary
    static let subduedInk = inkSecondary
    static let softWhite = ink

    // Accent
    /// Accent used for text, tint, icons
    static let accent = dynamic(light: "2348D2", dark: "8FAAFF")
    /// Accent fill used for primary button backgrounds (white text)
    static let accentFill = dynamic(light: "2348D2", dark: "3A5BE0")
    /// Quiet selected-state background
    static let highlight = dynamic(light: "E7ECFD", dark: "272E47")
    static let electricBlue = accent
    static let electricBlueMuted = accentFill

    // Muted hues that tell subjects apart
    static let teal = dynamic(light: "1F7A80", dark: "6CC4C9")
    static let coral = dynamic(light: "B4532F", dark: "E9976F")
    static let gold = dynamic(light: "8C6A12", dark: "DDB85A")
    static let plum = dynamic(light: "7A4A9E", dark: "BE98E0")
    static let streakOrange = coral

    // Semantic: only where the meaning is real
    static let success = dynamic(light: "1F7A4A", dark: "68C08F")
    static let warning = dynamic(light: "A8650F", dark: "EBA94A")
    static let danger = dynamic(light: "C4342B", dark: "F5736B")

    // Subject accents
    static let englishColor = coral
    static let russianColor = plum
    static let biologyColor = success
    static let mathColor = accent
    static let economicsColor = gold
    static let businessColor = teal
    static let advancedMathColor = accent
    static let universeColor = plum
    static let startupsColor = teal

    static func subjectColor(for name: String) -> Color {
        switch name {
        case let name where name.contains("Math"): mathColor
        case let name where name.contains("English"): englishColor
        case let name where name.contains("Business"): businessColor
        case let name where name.contains("Economics"): economicsColor
        case let name where name.contains("Russian"): russianColor
        case let name where name.contains("Biology"): biologyColor
        default: inkTertiary
        }
    }

    // Code block background for dark chat
    static let codeBlockBackground = dynamic(light: "F0F0ED", dark: "101010")
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

    static let pageTitle = Font.system(size: 26, weight: .semibold, design: .default)
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
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 10
    static let xl: CGFloat = 14
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
        LinearGradient(colors: [color.opacity(0.12), color.opacity(0.12)], startPoint: .top, endPoint: .bottom)
    }
    static var cardSheen: LinearGradient {
        LinearGradient(colors: [IBColors.surface, IBColors.surface], startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Surface

private struct SurfaceDepthKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    /// How many surfaces enclose this view. Only the outermost one paints, so a
    /// card placed inside another card can never read as a box in a box.
    var surfaceDepth: Int {
        get { self[SurfaceDepthKey.self] }
        set { self[SurfaceDepthKey.self] = newValue }
    }
}

struct SurfaceCardModifier: ViewModifier {
    var cornerRadius: CGFloat = IBRadius.card
    var isProminent: Bool = false
    @Environment(\.surfaceDepth) private var depth

    func body(content: Content) -> some View {
        content
            .environment(\.surfaceDepth, depth + 1)
            .background {
                if depth == 0 {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(isProminent ? IBColors.surfaceRaised : IBColors.surface)
                }
            }
    }
}

typealias GlassCardModifier = SurfaceCardModifier

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
    /// Pointer feedback must feel instant; anything slower reads as lag.
    static let hover = Animation.easeOut(duration: 0.1)
    static let press = Animation.easeOut(duration: 0.08)
    /// Moving between pages and tabs.
    static let page = Animation.easeOut(duration: 0.14)
}
