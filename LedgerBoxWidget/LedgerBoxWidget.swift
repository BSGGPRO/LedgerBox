import SwiftUI
import WidgetKit

struct LedgerBoxWidgetEntry: TimelineEntry {
    let date: Date
}

struct LedgerBoxWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> LedgerBoxWidgetEntry {
        LedgerBoxWidgetEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (LedgerBoxWidgetEntry) -> Void) {
        completion(LedgerBoxWidgetEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LedgerBoxWidgetEntry>) -> Void) {
        let entry = LedgerBoxWidgetEntry(date: Date())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct LedgerBoxWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumContent
            default:
                smallContent
            }
        }
        .containerBackground(for: .widget) {
            WidgetPalette.background(for: colorScheme)
        }
    }

    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Image(systemName: "banknote.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WidgetPalette.accent)

                Spacer(minLength: 4)

                Text("v\(widgetVersion)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetPalette.secondary(for: colorScheme))
            }

            Text("LedgerBox")
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetPalette.primary(for: colorScheme))
                .minimumScaleFactor(0.8)

            Text("本地优先 · 不上传账本")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(WidgetPalette.secondary(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 2)

            HStack(spacing: 5) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 12, weight: .semibold))

                Text("打开 App 记一笔")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(WidgetPalette.accent)
        }
        .padding(14)
    }

    private var mediumContent: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Image(systemName: "banknote.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(WidgetPalette.accent)

                    Text("LedgerBox")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(WidgetPalette.primary(for: colorScheme))
                }

                Text("把每一笔，记得清楚一点")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(WidgetPalette.secondary(for: colorScheme))

                Spacer(minLength: 4)

                HStack(spacing: 6) {
                    widgetChip("极速记账")
                    widgetChip("本地存储")
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 7) {
                Image(systemName: "square.and.pencil.circle.fill")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(WidgetPalette.accent)

                Text("打开 App")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetPalette.accent)
            }
        }
        .padding(16)
    }

    private func widgetChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(WidgetPalette.primary(for: colorScheme))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(WidgetPalette.chip(for: colorScheme), in: Capsule())
    }

    private var widgetVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
    }
}

enum WidgetPalette {
    static let accent = Color(red: 0.10, green: 0.55, blue: 0.47)

    static func background(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.07, green: 0.09, blue: 0.09)
            : Color(red: 0.96, green: 0.97, blue: 0.95)
    }

    static func primary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white : Color(red: 0.10, green: 0.13, blue: 0.13)
    }

    static func secondary(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.70)
            : Color(red: 0.36, green: 0.40, blue: 0.39)
    }

    static func chip(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.10)
            : Color(red: 0.10, green: 0.55, blue: 0.47).opacity(0.10)
    }
}

struct LedgerBoxWidget: Widget {
    let kind = "LedgerBoxWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LedgerBoxWidgetProvider()) { _ in
            LedgerBoxWidgetEntryView()
        }
        .configurationDisplayName("LedgerBox")
        .description("把 LedgerBox 放在主屏幕，随时打开记一笔。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview("小组件 · 小", as: .systemSmall) {
    LedgerBoxWidget()
} timeline: {
    LedgerBoxWidgetEntry(date: Date())
}

#Preview("小组件 · 中", as: .systemMedium) {
    LedgerBoxWidget()
} timeline: {
    LedgerBoxWidgetEntry(date: Date())
}
