import Combine
import Foundation
import SwiftUI
import UIKit

// All colors, radii, spacing, type styles and shared chrome live here. Views must
// not contain Color(red:green:blue:) or literal hex colors. [铁律3-adjacent UI rule] [边界12]

// MARK: - Theme mode

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

// MARK: - Accent presets

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

    /// Fill color for buttons and selection states. Values stay identical to the
    /// shipped presets so previously saved accents still resolve to a preset.
    var hex: String {
        switch self {
        case .blue: return "2F6FED"
        case .green: return "248A5B"
        case .orange: return "B87400"
        case .red: return "C9454F"
        case .purple: return "7B61FF"
        }
    }

    var color: Color {
        Color(hex: hex)
    }

    /// Readable label color on top of `color` (dark ink on light accents, white on
    /// dark accents). Never hard-coded to white.
    var onColor: Color {
        LedgerAccent.onColor(for: hex)
    }
}

// MARK: - Color math

/// Small sRGB helper so the theme can reason about contrast instead of guessing.
/// Uses the WCAG relative-luminance formula (the same one VoiceOver tooling quotes).
struct LedgerRGB: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    /// Accepts `RRGGBB` and `RRGGBBAA` (alpha is ignored). Anything else, including
    /// empty strings or stray glyphs, returns nil so callers can fall back safely.
    init?(hex: String) {
        let cleaned = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .uppercased()

        guard cleaned.count == 6 || cleaned.count == 8,
              cleaned.allSatisfy({ $0.isHexDigit }),
              let value = UInt32(cleaned.prefix(6), radix: 16) else {
            return nil
        }

        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var hex: String {
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    var relativeLuminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    func contrast(with other: LedgerRGB) -> Double {
        let first = relativeLuminance
        let second = other.relativeLuminance
        let lighter = max(first, second)
        let darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    func mixed(toward target: LedgerRGB, amount: Double) -> LedgerRGB {
        let t = min(max(amount, 0), 1)
        return LedgerRGB(
            red: red + (target.red - red) * t,
            green: green + (target.green - green) * t,
            blue: blue + (target.blue - blue) * t
        )
    }
}

/// Resolves accent colors into (fill, readable label, readable text) without a
/// third-party dependency.
enum LedgerAccent {
    /// Used when a stored value cannot be parsed.
    static let fallbackHex = "2F6FED"
    /// Ink used on light accent fills; matches the light-mode background family.
    static let inkHex = "0B0D11"
    /// WCAG AA for normal text. Large/bold text may pass at 3.0, but buttons carry
    /// small labels too, so the stricter target is used for text tokens.
    static let minimumTextContrast: Double = 4.5

    static func normalizedHex(_ raw: String) -> String? {
        LedgerRGB(hex: raw)?.hex
    }

    static var fallbackColor: Color {
        Color(hex: fallbackHex)
    }

    /// Highest-contrast label color for a fill: white or near-black ink.
    static func onColor(for hex: String) -> Color {
        guard let fill = LedgerRGB(hex: hex) else { return .white }
        return onColor(for: fill)
    }

    static func onColor(for fill: LedgerRGB) -> Color {
        guard let white = LedgerRGB(hex: "FFFFFF"),
              let ink = LedgerRGB(hex: inkHex) else {
            return .white
        }
        return fill.contrast(with: white) >= fill.contrast(with: ink) ? white.color : ink.color
    }

    static func usesInk(for hex: String) -> Bool {
        guard let fill = LedgerRGB(hex: hex),
              let white = LedgerRGB(hex: "FFFFFF"),
              let ink = LedgerRGB(hex: inkHex) else {
            return false
        }
        return fill.contrast(with: ink) > fill.contrast(with: white)
    }

    /// Darkens (light mode) or lightens (dark mode) the accent until it is readable
    /// as text on `surfaceHex`. Returns the original color when it already passes.
    static func readableText(for hex: String, on surfaceHex: String, isDark: Bool)
        -> (color: Color, hex: String, wasToned: Bool) {
        guard let base = LedgerRGB(hex: hex),
              let surface = LedgerRGB(hex: surfaceHex) else {
            return (fallbackColor, fallbackHex, false)
        }

        if base.contrast(with: surface) >= minimumTextContrast {
            return (base.color, base.hex, false)
        }

        let target = isDark
            ? LedgerRGB(red: 1, green: 1, blue: 1)
            : LedgerRGB(red: 0, green: 0, blue: 0)

        var amount = 0.0
        while amount < 1.0 {
            amount = min(1.0, amount + 0.04)
            let candidate = base.mixed(toward: target, amount: amount)
            if candidate.contrast(with: surface) >= minimumTextContrast {
                return (candidate.color, candidate.hex, true)
            }
        }

        return (target.color, target.hex, true)
    }
}

// MARK: - Theme

private struct LedgerRamp {
    let background: String
    let surface: String
    let surfaceElevated: String
    let surfaceSunken: String
    let primaryText: String
    let secondaryText: String
    let tertiaryText: String
    let separator: String
    let borderStrong: String
    let income: String
    let expense: String
    let warning: String

    static let light = LedgerRamp(
        background: "F4F5F7",
        surface: "FFFFFF",
        surfaceElevated: "F0F2F5",
        surfaceSunken: "E9ECF1",
        primaryText: "14161B",
        secondaryText: "59616E",
        tertiaryText: "69737F",
        separator: "E4E7ED",
        borderStrong: "CFD5DE",
        income: "0F7B52",
        expense: "C0384B",
        warning: "9A6508"
    )

    static let dark = LedgerRamp(
        background: "0B0D11",
        surface: "15181E",
        surfaceElevated: "1E232B",
        surfaceSunken: "101318",
        primaryText: "F3F5F8",
        secondaryText: "A5ADBA",
        tertiaryText: "79828F",
        separator: "262C35",
        borderStrong: "343C48",
        income: "4FD1A0",
        expense: "FF8A92",
        warning: "F5C265"
    )
}

struct Theme {
    static let defaultAccentHex = LedgerAccent.fallbackHex

    // Scheme context, so views can align system chrome with a forced theme.
    let scheme: ColorScheme
    let isDark: Bool

    // Surface hierarchy: page -> card -> nested chip. No shadows, contrast only.
    let background: Color
    let surface: Color
    let surfaceElevated: Color
    let surfaceSunken: Color

    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let separator: Color
    let borderStrong: Color

    // Accent tokens. `accent` stays the user's color (fills), `accentText` is the
    // contrast-corrected variant for text and icons.
    let accent: Color
    let onAccent: Color
    let accentText: Color
    let accentSoft: Color
    let accentHex: String
    let accentTextHex: String
    let accentContrast: Double
    let accentTextContrast: Double
    let accentInkOnAccent: Bool
    let accentIsLowContrast: Bool
    let accentWasToned: Bool

    // Semantic money colors. Readable as text in both schemes.
    let income: Color
    let expense: Color
    let warning: Color
    let incomeSoft: Color
    let expenseSoft: Color
    let warningSoft: Color

    // Metrics: 8pt grid, 20pt cards, pill buttons.
    let cardRadius: CGFloat
    let controlRadius: CGFloat
    let segmentRadius: CGFloat
    let pagePadding: CGFloat
    let cardPadding: CGFloat
    let spacing: CGFloat
    let smallSpacing: CGFloat
    let tinySpacing: CGFloat
    let sectionSpacing: CGFloat
    let cardSpacing: CGFloat
    let minTapTarget: CGFloat
    let rowMinHeight: CGFloat
    let iconCircleSize: CGFloat
    let hairline: CGFloat

    static func palette(for scheme: ColorScheme, accentHex rawAccentHex: String = Theme.defaultAccentHex) -> Theme {
        let isDark = scheme == .dark
        let ramp = isDark ? LedgerRamp.dark : LedgerRamp.light

        // Illegal or empty stored hex falls back instead of rendering gray.
        let accentRGB = LedgerRGB(hex: rawAccentHex)
            ?? LedgerRGB(hex: defaultAccentHex)
            ?? LedgerRGB(red: 0.18, green: 0.44, blue: 0.93)
        let surfaceRGB = LedgerRGB(hex: ramp.surface) ?? LedgerRGB(red: 1, green: 1, blue: 1)

        let readable = LedgerAccent.readableText(
            for: accentRGB.hex,
            on: ramp.surface,
            isDark: isDark
        )
        let accentTextRGB = LedgerRGB(hex: readable.hex) ?? accentRGB
        let rawContrast = accentRGB.contrast(with: surfaceRGB)

        return Theme(
            scheme: scheme,
            isDark: isDark,
            background: Color(hex: ramp.background),
            surface: Color(hex: ramp.surface),
            surfaceElevated: Color(hex: ramp.surfaceElevated),
            surfaceSunken: Color(hex: ramp.surfaceSunken),
            primaryText: Color(hex: ramp.primaryText),
            secondaryText: Color(hex: ramp.secondaryText),
            tertiaryText: Color(hex: ramp.tertiaryText),
            separator: Color(hex: ramp.separator),
            borderStrong: Color(hex: ramp.borderStrong),
            accent: accentRGB.color,
            onAccent: LedgerAccent.onColor(for: accentRGB),
            accentText: accentTextRGB.color,
            accentSoft: accentRGB.color.opacity(0.12),
            accentHex: accentRGB.hex,
            accentTextHex: accentTextRGB.hex,
            accentContrast: rawContrast,
            accentTextContrast: accentTextRGB.contrast(with: surfaceRGB),
            accentInkOnAccent: LedgerAccent.usesInk(for: accentRGB.hex),
            accentIsLowContrast: rawContrast < LedgerAccent.minimumTextContrast,
            accentWasToned: readable.wasToned,
            income: Color(hex: ramp.income),
            expense: Color(hex: ramp.expense),
            warning: Color(hex: ramp.warning),
            incomeSoft: Color(hex: ramp.income).opacity(0.12),
            expenseSoft: Color(hex: ramp.expense).opacity(0.12),
            warningSoft: Color(hex: ramp.warning).opacity(0.12),
            cardRadius: 20,
            controlRadius: 11,
            segmentRadius: 15,
            pagePadding: 16,
            cardPadding: 20,
            spacing: 16,
            smallSpacing: 8,
            tinySpacing: 4,
            sectionSpacing: 24,
            cardSpacing: 12,
            minTapTarget: 44,
            rowMinHeight: 52,
            iconCircleSize: 36,
            hairline: 1
        )
    }

    // MARK: Type scale
    //
    // Text styles (not fixed point sizes) so Dynamic Type keeps working. Numeric
    // styles stay monospaced-digit and always render through `ledgerMoneyLine` so
    // they can shrink instead of clipping.

    var largeTitleFont: Font {
        .system(.title, design: .rounded, weight: .bold)
    }

    var screenTitleFont: Font {
        .system(.title, design: .rounded, weight: .bold)
    }

    var sectionTitleFont: Font {
        .system(.headline, design: .rounded, weight: .semibold)
    }

    var bodyFont: Font {
        .system(.subheadline, weight: .regular)
    }

    var captionFont: Font {
        .system(.caption, weight: .medium)
    }

    var overlineFont: Font {
        .system(.caption2, design: .rounded, weight: .semibold)
    }

    var badgeFont: Font {
        .system(.caption2, weight: .semibold)
    }

    var hexFont: Font {
        .system(.caption, design: .monospaced, weight: .medium)
    }

    var moneyFont: Font {
        .system(.title, design: .rounded, weight: .semibold).monospacedDigit()
    }

    var balanceFont: Font {
        .system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit()
    }

    var amountFont: Font {
        .system(.largeTitle, design: .rounded, weight: .semibold).monospacedDigit()
    }

    var statValueFont: Font {
        .system(.headline, design: .rounded, weight: .semibold).monospacedDigit()
    }

    var currencySymbolFont: Font {
        .system(.title, design: .rounded, weight: .medium)
    }

    var rowMoneyFont: Font {
        .system(.callout, design: .rounded, weight: .semibold).monospacedDigit()
    }

    var headerActionFont: Font {
        .system(.callout, weight: .bold)
    }

    var buttonLabelFont: Font {
        .system(.callout, design: .rounded, weight: .semibold)
    }

    var emptyStateIconFont: Font {
        .system(.title, weight: .medium)
    }

    var rowIconFont: Font {
        .system(.subheadline, weight: .semibold)
    }

    var controlIconFont: Font {
        .system(.footnote, weight: .semibold)
    }

    var chartLabelFont: Font {
        .system(.caption2, weight: .medium)
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

    /// Always a normalized 6-digit hex. Use `setAccent(hex:)` to change it so an
    /// unparseable value can never reach the palette.
    @Published private(set) var accentHex: String

    /// Non-nil when a stored accent had to be replaced during launch.
    @Published private(set) var accentFallbackNotice: String?

    private let defaults: UserDefaults

    private enum Keys {
        static let mode = "ledgerbox.theme.mode"
        static let accentHex = "ledgerbox.theme.accentHex"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedMode = defaults.string(forKey: Keys.mode) ?? ThemeMode.system.rawValue
        self.mode = ThemeMode(rawValue: storedMode) ?? .system

        let storedAccent = defaults.string(forKey: Keys.accentHex) ?? Theme.defaultAccentHex
        if let normalized = LedgerAccent.normalizedHex(storedAccent) {
            self.accentHex = normalized
            self.accentFallbackNotice = nil
        } else {
            self.accentHex = Theme.defaultAccentHex
            self.accentFallbackNotice = "已保存的强调色无法识别，已回退为默认蓝色。"
            defaults.set(Theme.defaultAccentHex, forKey: Keys.accentHex)
        }
    }

    var preferredColorScheme: ColorScheme? {
        mode.colorScheme
    }

    var accentColor: Color {
        Color(hex: accentHex)
    }

    /// Applies a custom accent. Returns false (and keeps the previous color) when
    /// the string is not a 6/8 digit hex value.
    @discardableResult
    func setAccent(hex: String) -> Bool {
        guard let normalized = LedgerAccent.normalizedHex(hex) else {
            return false
        }
        accentFallbackNotice = nil
        if normalized != accentHex {
            accentHex = normalized
        }
        defaults.set(accentHex, forKey: Keys.accentHex)
        return true
    }

    func resetAccent() {
        setAccent(hex: Theme.defaultAccentHex)
    }

    func dismissFallbackNotice() {
        accentFallbackNotice = nil
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

// MARK: - Shared chrome

enum LedgerCardSurface {
    case surface
    case elevated
    case sunken
}

struct LedgerCard<Content: View>: View {
    @Environment(\.ledgerTheme) private var theme

    private let surface: LedgerCardSurface
    private let padding: CGFloat?
    private let content: Content

    init(
        surface: LedgerCardSurface = .surface,
        padding: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.surface = surface
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding ?? theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
                    .strokeBorder(theme.separator, lineWidth: theme.hairline)
            )
    }

    private var fill: Color {
        switch surface {
        case .surface: return theme.surface
        case .elevated: return theme.surfaceElevated
        case .sunken: return theme.surfaceSunken
        }
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
                    .foregroundStyle(theme.accentText)
                    .frame(minHeight: theme.minTapTarget, alignment: .trailing)
                    .contentShape(Rectangle())
            }
        }
        .frame(minHeight: actionTitle == nil ? 0 : theme.minTapTarget)
    }
}

/// Flat capsule badge used for tags such as "本地" or "已启用".
struct LedgerTag: View {
    let text: String
    var tint: Color?

    @Environment(\.ledgerTheme) private var theme

    init(_ text: String, tint: Color? = nil) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(theme.badgeFont)
            .foregroundStyle(tint ?? theme.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background, in: Capsule())
            .accessibilityLabel(text)
    }

    private var background: Color {
        if let tint {
            return tint.opacity(0.12)
        }
        return theme.surfaceElevated
    }
}

/// Rounded-square icon container: no circles, no shadows, one tint at 12%.
struct LedgerIconBadge: View {
    let systemName: String
    var tint: Color?
    var size: CGFloat = 36

    @Environment(\.ledgerTheme) private var theme

    init(systemName: String, tint: Color? = nil, size: CGFloat = 36) {
        self.systemName = systemName
        self.tint = tint
        self.size = size
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(tintColor.opacity(0.12))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemName)
                    .font(theme.rowIconFont)
                    .foregroundStyle(tintColor)
            }
            .accessibilityHidden(true)
    }

    private var tintColor: Color {
        tint ?? theme.accentText
    }
}

/// Capsule segmented control. Replaces the default rectangular segmented picker
/// so selected state is an accent pill with contrast-checked label.
struct LedgerSegmentedControl<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> String
    var symbol: ((Item) -> String)?
    @Binding var selection: Item

    @Environment(\.ledgerTheme) private var theme

    init(
        items: [Item],
        title: @escaping (Item) -> String,
        symbol: ((Item) -> String)? = nil,
        selection: Binding<Item>
    ) {
        self.items = items
        self.title = title
        self.symbol = symbol
        self._selection = selection
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.self) { item in
                segment(for: item)
            }
        }
        .padding(4)
        .background(theme.surfaceElevated, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.separator, lineWidth: theme.hairline))
    }

    private func segment(for item: Item) -> some View {
        let isSelected = item == selection
        return Button {
            withAnimation(.snappy(duration: 0.18)) {
                selection = item
            }
        } label: {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol(item))
                        .font(theme.controlIconFont)
                }

                Text(title(item))
                    .font(theme.captionFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(isSelected ? theme.onAccent : theme.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 8)
            .background {
                if isSelected {
                    Capsule().fill(theme.accent)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }
}

// MARK: - Button styles

struct LedgerPrimaryButtonStyle: ButtonStyle {
    let theme: Theme
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.buttonLabelFont)
            .foregroundStyle(theme.onAccent)
            .padding(.horizontal, theme.cardPadding)
            .padding(.vertical, 13)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: theme.minTapTarget)
            .background(theme.accent, in: Capsule())
            .opacity(configuration.isPressed ? 0.86 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct LedgerSecondaryButtonStyle: ButtonStyle {
    let theme: Theme
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.buttonLabelFont)
            .foregroundStyle(theme.accentText)
            .padding(.horizontal, theme.cardPadding)
            .padding(.vertical, 13)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: theme.minTapTarget)
            .background(theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(theme.borderStrong, lineWidth: theme.hairline))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Reusable coach card

/// Shared local-coach card used by Home, Budget, Statistics and Advisor.
struct CoachTipCard: View {
    let tip: FinanceCoachTip
    var compact = false

    @Environment(\.ledgerTheme) private var theme

    var body: some View {
        LedgerCard {
            HStack(alignment: .top, spacing: theme.cardSpacing) {
                LedgerIconBadge(systemName: tip.symbol, tint: tint, size: 38)

                VStack(alignment: .leading, spacing: compact ? 4 : 8) {
                    HStack(alignment: .firstTextBaseline, spacing: theme.smallSpacing) {
                        Text(tip.title)
                            .font(theme.bodyFont.weight(.semibold))
                            .foregroundStyle(theme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: theme.tinySpacing)

                        LedgerTag(tip.tag, tint: tint)
                    }

                    Text(tip.body)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("本地大脑 · 不上传")
                        .font(theme.overlineFont)
                        .foregroundStyle(theme.tertiaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch tip.tone {
        case .positive:
            return theme.income
        case .warning:
            return theme.warning
        case .neutral:
            return theme.accentText
        }
    }
}

// MARK: - Layout helpers

extension View {
    /// One-line money text that shrinks instead of clipping when Dynamic Type grows
    /// or when the amount gets long.
    func ledgerMoneyLine(minScale: CGFloat = 0.6) -> some View {
        lineLimit(1)
            .minimumScaleFactor(minScale)
            .allowsTightening(true)
    }
}

// MARK: - Hex color parser

extension Color {
    init(hex: String, opacity: Double = 1) {
        if let parsed = LedgerRGB(hex: hex) {
            self.init(.sRGB, red: parsed.red, green: parsed.green, blue: parsed.blue, opacity: opacity)
            return
        }

        // Legacy #RRGGBBAA values keep their alpha channel.
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if cleaned.count == 8, let value = UInt64(cleaned, radix: 16) {
            let red = Double((value >> 24) & 0xFF) / 255
            let green = Double((value >> 16) & 0xFF) / 255
            let blue = Double((value >> 8) & 0xFF) / 255
            let alpha = Double(value & 0xFF) / 255
            self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity * alpha)
            return
        }

        self.init(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: opacity)
    }

    /// 6-digit sRGB hex for persistence. Nil for pattern or non-convertible colors.
    var ledgerHex: String? {
        let uiColor = UIColor(self)

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }

        return LedgerRGB(
            red: Double(red),
            green: Double(green),
            blue: Double(blue)
        ).hex
    }
}
