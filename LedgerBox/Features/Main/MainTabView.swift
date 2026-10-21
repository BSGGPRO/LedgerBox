import SwiftUI

enum MainTab: Hashable, CaseIterable {
    case home
    case transactions
    case statistics
    case budget
    case goals

    var title: String {
        switch self {
        case .home: return "首页"
        case .transactions: return "流水"
        case .statistics: return "统计"
        case .budget: return "预算"
        case .goals: return "目标"
        }
    }

    /// Outline glyphs keep the bar flat; the tint alone marks the active tab.
    var symbolName: String {
        switch self {
        case .home: return "house"
        case .transactions: return "list.bullet.rectangle"
        case .statistics: return "chart.pie"
        case .budget: return "gauge.with.dots.needle.50percent"
        case .goals: return "target"
        }
    }
}

struct MainTabView: View {
    @Environment(\.ledgerTheme) private var theme
    @State private var selection: MainTab = .home

    var body: some View {
        TabView(selection: $selection) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                tabContent(for: tab)
                    .tabItem {
                        Label(tab.title, systemImage: tab.symbolName)
                    }
                    .tag(tab)
            }
        }
        // `accentText` is contrast-corrected for the tab bar surface, so a pale
        // custom accent still produces a readable selected state.
        .tint(theme.accentText)
        .toolbarBackground(theme.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(theme.scheme, for: .tabBar)
    }

    @ViewBuilder
    private func tabContent(for tab: MainTab) -> some View {
        switch tab {
        case .home:
            HomeView()
        case .transactions:
            TransactionsView()
        case .statistics:
            StatisticsView()
        case .budget:
            BudgetView()
        case .goals:
            GoalsView()
        }
    }
}

#Preview("主界面 · 浅色") {
    MainTabView()
        .environment(
            \.managedObjectContext,
            PersistenceController.preview.container.viewContext
        )
        .environment(\.ledgerTheme, Theme.palette(for: .light))
        .environmentObject(ThemeManager())
}

#Preview("主界面 · 深色") {
    MainTabView()
        .environment(
            \.managedObjectContext,
            PersistenceController.preview.container.viewContext
        )
        .environment(\.ledgerTheme, Theme.palette(for: .dark))
        .environmentObject(ThemeManager())
}
