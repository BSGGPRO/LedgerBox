import SwiftUI

enum MainTab: Hashable {
    case home
    case transactions
    case statistics
    case budget
    case goals
}

struct MainTabView: View {
    @Environment(\.ledgerTheme) private var theme
    @State private var selection: MainTab = .home

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem {
                    Label("首页", systemImage: "house.fill")
                }
                .tag(MainTab.home)

            TransactionsView()
                .tabItem {
                    Label("流水", systemImage: "list.bullet.rectangle")
                }
                .tag(MainTab.transactions)

            StatisticsView()
                .tabItem {
                    Label("统计", systemImage: "chart.pie.fill")
                }
                .tag(MainTab.statistics)

            BudgetView()
                .tabItem {
                    Label("预算", systemImage: "gauge.with.dots.needle.50percent")
                }
                .tag(MainTab.budget)

            GoalsView()
                .tabItem {
                    Label("目标", systemImage: "target")
                }
                .tag(MainTab.goals)
        }
        .tint(theme.accent)
        .toolbarBackground(theme.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
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
