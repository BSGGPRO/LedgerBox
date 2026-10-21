import Combine
import Foundation
import SwiftUI

// All colors, radii, spacing and type styles live here. Views must not contain
// Color(red:green:blue:) or literal hex colors. [铁律3-adjacent UI rule] [边界12]
enum ThemeMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var symbolName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon.stars"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum ThemeAccent: String, CaseIterable, Identifiable {
    case blue
    case green
    case orange
    case red
    case purple

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blue: return "蓝色"
        case .green: return "绿色"
        case .orange: return "橙色"
        case .red: return "红色"
        case .purple: return "紫色"
        }
    }

    var hex: String {
        switch self {
        case .blue: return "2F6FED"
        case .green: return "248A5B"
        case .orange: return "B87400"
        case .red: return "C9454F"
        case .purple: return "7B61FF"
        }
    }
}

struct Theme {
    let background: Color
    let surface: Color
    let surfaceElevated: Color
    let primaryText: Color
    let secondaryText: Color
    let separator: Color
    let accent: Color
    let onAccent: Color
    let income: Color
    let expense: Color
    let warning: Color

    let cardRadius: CGFloat
    let pagePadding: CGFloat
    let cardPadding: CGFloat
    let spacing: CGFloat
    let smallSpacing: CGFloat

    static func palette(for scheme: ColorScheme, accentHex: String = "2F6FED") -> Theme {
        let isDark = scheme == .dark

        return Theme(
            background: Color(hex: isDark ? "0E1013" : "F4F5F7"),
            surface: Color(hex: isDark ? "181B20" : "FFFFFF"),
            surfaceElevated: Color(hex: isDark ? "22262D" : "EDEFF3"),
            primaryText: Color(hex: isDark ? "F5F7FA" : "16181D"),
            secondaryText: Color(hex: isDark ? "A8AFBA" : "6C7480"),
            separator: Color(hex: isDark ? "2C313A" : "E2E5EA"),
            accent: Color(hex: accentHex),
            onAccent: Color(hex: "FFFFFF"),
            income: Color(hex: isDark ? "4CC38A" : "248A5B"),
            expense: Color(hex: isDark ? "F07178" : "C9454F"),
            warning: Color(hex: isDark ? "F2B84B" : "B87400"),
            cardRadius: 18,
            pagePadding: 16,
            cardPadding: 16,
            spacing: 16,
            smallSpacing: 8
        )
    }

    var largeTitleFont: Font {
        .system(size: 28, weight: .bold, design: .rounded)
    }

    var sectionTitleFont: Font {
        .system(size: 17, weight: .semibold, design: .rounded)
    }

    var bodyFont: Font {
        .system(size: 15, weight: .regular, design: .default)
    }

    var captionFont: Font {
        .system(size: 12, weight: .medium, design: .default)
    }

    var moneyFont: Font {
        .system(size: 30, weight: .semibold, design: .rounded).monospacedDigit()
    }

    var amountFont: Font {
        .system(size: 38, weight: .semibold, design: .rounded).monospacedDigit()
    }

    var currencySymbolFont: Font {
        .system(size: 28, weight: .medium, design: .rounded)
    }

    var rowMoneyFont: Font {
        .system(size: 16, weight: .semibold, design: .rounded).monospacedDigit()
    }

    var headerActionFont: Font {
        .system(size: 16, weight: .bold)
    }

    var buttonLabelFont: Font {
        .system(size: 16, weight: .semibold, design: .rounded)
    }

    var emptyStateIconFont: Font {
        .system(size: 28, weight: .medium)
    }

    var rowIconFont: Font {
        .system(size: 15, weight: .semibold)
    }

    var controlIconFont: Font {
        .system(size: 14, weight: .semibold)
    }

    var chartLabelFont: Font {
        .system(size: 10, weight: .medium)
    }

    var badgeFont: Font {
        .system(size: 10, weight: .semibold)
    }

    var controlRadius: CGFloat {
        11
    }

    var segmentRadius: CGFloat {
        15
    }

    var iconCircleSize: CGFloat {
        36
    }
}

struct LedgerThemeKey: EnvironmentKey {
    static let defaultValue = Theme.palette(for: .light)
}

extension EnvironmentValues {
    var ledgerTheme: Theme {
        get { self[LedgerThemeKey.self] }
        set { self[LedgerThemeKey.self] = newValue }
    }
}

final class ThemeManager: ObservableObject {
    @Published var mode: ThemeMode {
        didSet { defaults.set(mode.rawValue, forKey: Keys.mode) }
    }

    @Published var accentHex: String {
        didSet { defaults.set(accentHex, forKey: Keys.accentHex) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let mode = "ledgerbox.theme.mode"
        static let accentHex = "ledgerbox.theme.accentHex"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedMode = defaults.string(forKey: Keys.mode) ?? ThemeMode.system.rawValue
        self.mode = ThemeMode(rawValue: storedMode) ?? .system
        self.accentHex = defaults.string(forKey: Keys.accentHex) ?? "2F6FED"
    }

    var preferredColorScheme: ColorScheme? {
        mode.colorScheme
    }

    func theme(for systemScheme: ColorScheme) -> Theme {
        let resolvedScheme: ColorScheme
        switch mode {
        case .system:
            resolvedScheme = systemScheme
        case .light:
            resolvedScheme = .light
        case .dark:
            resolvedScheme = .dark
        }
        return Theme.palette(for: resolvedScheme, accentHex: accentHex)
    }
}

// MARK: - Reusable visual components

struct LedgerCard<Content: View>: View {
    @Environment(\.ledgerTheme) private var theme
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
                    .fill(theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
                    .stroke(theme.separator.opacity(0.55), lineWidth: 1)
            )
    }
}

struct LedgerSectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    @Environment(\.ledgerTheme) private var theme

    init(title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(theme.sectionTitleFont)
                .foregroundStyle(theme.primaryText)

            Spacer(minLength: theme.smallSpacing)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.accent)
            }
        }
    }
}

// MARK: - Hex color parser

extension Color {
    init(hex: String, opacity: Double = 1) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        _ = Scanner(string: cleaned).scanHexInt64(&value)

        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        switch cleaned.count {
        case 6:
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
            alpha = 1
        case 8:
            red = Double((value >> 24) & 0xFF) / 255
            green = Double((value >> 16) & 0xFF) / 255
            blue = Double((value >> 8) & 0xFF) / 255
            alpha = Double(value & 0xFF) / 255
        default:
            red = 0.5
            green = 0.5
            blue = 0.5
            alpha = 1
        }

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity * alpha)
    }
}
