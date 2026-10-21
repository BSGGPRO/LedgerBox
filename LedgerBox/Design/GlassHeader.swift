import SwiftUI
import UIKit

/// Shared coordinate-space name for the glass header's scroll measurement.
enum LedgerGlassScroll {
    static let coordinateSpace = "ledger.scroll"
}

/// UIKit material bridge. SwiftUI's material styles adapt to the current color
/// scheme, while this header intentionally stays on the ultra-thin dark material.
struct VisualEffectBlur: UIViewRepresentable {
    var blurStyle: UIBlurEffect.Style = .systemUltraThinMaterialDark

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: blurStyle)
    }
}

/// Dark glass capsule used behind the floating header. The fill sits above the
/// blur so the capsule stays legible over bright, scrolled content.
struct GlassCapsule: View {
    @Environment(\.ledgerTheme) private var theme

    var body: some View {
        Capsule(style: .continuous)
            .fill(theme.isDark ? darkFill : theme.surface.opacity(0.94))
            .background {
                VisualEffectBlur(
                    blurStyle: theme.isDark
                        ? .systemUltraThinMaterialDark
                        : .systemUltraThinMaterialLight
                )
                .clipShape(Capsule(style: .continuous))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        theme.isDark
                            ? Color.white.opacity(0.08)
                            : theme.borderStrong.opacity(0.55),
                        lineWidth: 1
                    )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var darkFill: Color {
        Color(
            .sRGB,
            red: 20.0 / 255.0,
            green: 20.0 / 255.0,
            blue: 22.0 / 255.0,
            opacity: 0.72
        )
    }
}

/// Header content that swaps between a 68pt expanded capsule and a 52pt
/// compact capsule. The nominal sizes are minimums so Dynamic Type can grow the
/// capsule instead of clipping large accessibility text.
struct CollapsibleGlassHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    let compact: Bool

    private let trailing: Trailing

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.ledgerTheme) private var theme

    private var titleColor: Color {
        theme.isDark ? .white : theme.primaryText
    }

    private var subtitleColor: Color {
        theme.isDark ? Color.white.opacity(0.68) : theme.secondaryText
    }

    init(
        title: String,
        subtitle: String = "",
        compact: Bool,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.compact = compact
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: compact ? 0 : 2) {
                Text(title)
                    .font(
                        .system(
                            compact ? .headline : .title2,
                            design: .rounded,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(titleColor)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)
                    .accessibilityAddTraits(.isHeader)

                if !compact, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(.callout, design: .rounded, weight: .bold))
                        .foregroundStyle(subtitleColor)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            trailing
        }
        .padding(.horizontal, 18)
        .frame(
            maxWidth: .infinity,
            minHeight: compact ? 52 : 68,
            alignment: .leading
        )
        .background {
            GlassCapsule()
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.2),
            value: compact
        )
        .accessibilityElement(children: .contain)
    }
}

/// Reports the scroll content's top edge in the host's named coordinate space.
struct ScrollOffsetReader: View {
    var coordinateSpaceName: String = LedgerGlassScroll.coordinateSpace

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ScrollOffsetPreferenceKey.self,
                value: proxy.frame(in: .named(coordinateSpaceName)).minY
            )
        }
        .frame(height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Scroll host for screens that use `CollapsibleGlassHeader` instead of the
/// system navigation bar. The header is installed as a top safe-area inset so
/// it floats above content without a navigation-bar background.
struct GlassHeaderHost<Content: View, Trailing: View>: View {
    let title: String
    let subtitle: String

    private let trailing: Trailing
    private let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ledgerTheme) private var theme

    @State private var isCompact = false

    init(
        title: String,
        subtitle: String = "",
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScrollOffsetReader()
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .coordinateSpace(name: LedgerGlassScroll.coordinateSpace)
        .background(theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            headerInset
        }
        .toolbar(.hidden, for: .navigationBar)
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
            let shouldCompact = offset < -8
            // Guarding the state change is the debounce: scrolling within the
            // same side of the threshold cannot restart the animation.
            guard shouldCompact != isCompact else {
                return
            }

            if reduceMotion {
                isCompact = shouldCompact
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCompact = shouldCompact
                }
            }
        }
    }

    private var headerInset: some View {
        CollapsibleGlassHeader(
            title: title,
            subtitle: subtitle,
            compact: isCompact
        ) {
            trailing
        }
        .padding(.horizontal, theme.pagePadding)
        .padding(.vertical, 4)
        .frame(minHeight: isCompact ? 60 : 76)
        // Deliberately no full-width background here. The capsule must float on
        // the page surface; a background on the safe-area inset is the exact
        // gray strip this header is meant to remove.
    }
}

extension GlassHeaderHost where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String = "",
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            trailing: { EmptyView() },
            content: content
        )
    }
}
