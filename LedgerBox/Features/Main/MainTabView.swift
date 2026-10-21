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

@MainActor
struct MainTabView: View {
    @Environment(\.ledgerTheme) private var theme
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var themeManager: ThemeManager

    @StateObject private var router = LedgerRouter()
    @StateObject private var toastCenter = ImportToastCenter()
    @State private var selection: MainTab = .home
    @State private var isActionMenuExpanded = false
    @State private var showingSettings = false
    @State private var errorMessage: String?

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
        .overlay(alignment: .bottom) {
            VStack(spacing: 10) {
                if let toast = toastCenter.toast {
                    ImportToastView(toast: toast) {
                        undo(toast)
                    }
                    .frame(maxWidth: 310)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                bottomDock
            }
            .padding(.horizontal, theme.pagePadding)
            // Keep the dock clear of the system tab bar; this is a floating
            // row, not a replacement for the five-tab navigation.
            .padding(.bottom, 70)
            .animation(.easeInOut(duration: 0.2), value: toastCenter.toast)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environment(\.managedObjectContext, viewContext)
                .environmentObject(themeManager)
        }
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .manual:
                AddTransactionView()
                    .environment(\.managedObjectContext, viewContext)
                    .environment(\.ledgerTheme, theme)
            case .image:
                ImageLedgerFlowView { session in
                    toastCenter.show(
                        sessionID: session.id,
                        count: session.transactionIDs.count
                    )
                }
                .environment(\.managedObjectContext, viewContext)
                .environment(\.ledgerTheme, theme)
            case .profile:
                ProfileMenuView()
                    .environment(\.managedObjectContext, viewContext)
                    .environment(\.ledgerTheme, theme)
            }
        }
        .alert(
            "操作未完成",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var bottomDock: some View {
        HStack(spacing: 0) {
            // Bottom-left identity: local avatar only, no third-party login.
            ProfileBadge()

            Spacer(minLength: 0)

            FloatingActionMenu(
                isExpanded: $isActionMenuExpanded,
                onQuickEntry: { router.open(.image) },
                onManualEntry: { router.open(.manual) }
            )

            Spacer(minLength: 0)

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.10), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("设置")
            .accessibilityHint("打开主题、分类、导出与关于")
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: 340, minHeight: 74)
        .background {
            Capsule(style: .continuous)
                .fill(
                    Color(
                        .sRGB,
                        red: 20.0 / 255.0,
                        green: 20.0 / 255.0,
                        blue: 22.0 / 255.0,
                        opacity: 0.72
                    )
                )
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.28), radius: 12, x: 0, y: 6)
    }

    private func undo(_ toast: ImportToast) {
        do {
            try ImportCommitService.undo(
                sessionID: toast.sessionID,
                context: viewContext
            )
            toastCenter.dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
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
