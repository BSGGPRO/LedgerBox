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
                    .toolbar(.hidden, for: .tabBar)
                    .tag(tab)
            }
        }
        // The custom bar contains the five destinations, the local avatar,
        // Settings and the centered entry button in one row. The native bar is
        // hidden so the "+" sits inside that row rather than in a second row.
        .toolbar(.hidden, for: .tabBar)
        .tint(theme.accentText)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .overlay(alignment: .bottom) {
            if let toast = toastCenter.toast {
                ImportToastView(toast: toast) {
                    undo(toast)
                }
                .frame(maxWidth: 310)
                .padding(.horizontal, theme.pagePadding)
                .padding(.bottom, 94)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.2), value: toastCenter.toast)
            }
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

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 0) {
            // Bottom-left identity: local avatar only, no third-party login.
            ProfileBadge()
                .frame(width: 38)

            tabButton(.home)
            tabButton(.transactions)

            // The centered entry button overlays this gap, so no tab sits
            // underneath its 62pt touch target.
            Spacer(minLength: 58)

            tabButton(.statistics)
            tabButton(.budget)
            tabButton(.goals)

            Button {
                isActionMenuExpanded = false
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .frame(width: 32, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("设置")
            .accessibilityHint("打开主题、分类、导出与关于")
        }
        .padding(.horizontal, 6)
        .padding(.top, 5)
        .padding(.bottom, 3)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)

                Rectangle()
                    .fill(
                        Color(
                            .sRGB,
                            red: 20.0 / 255.0,
                            green: 20.0 / 255.0,
                            blue: 22.0 / 255.0,
                            opacity: 0.88
                        )
                    )
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 0.5)
        }
        .overlay {
            FloatingActionMenu(
                isExpanded: $isActionMenuExpanded,
                onQuickEntry: { router.open(.image) },
                onManualEntry: { router.open(.manual) }
            )
            .offset(y: -2)
        }
    }

    private func tabButton(_ tab: MainTab) -> some View {
        let isSelected = selection == tab

        return Button {
            isActionMenuExpanded = false
            withAnimation(.easeOut(duration: 0.18)) {
                selection = tab
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .frame(height: 20)

                Text(tab.title)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(
                isSelected ? Color.white : Color.white.opacity(0.56)
            )
            .frame(width: tab == .budget || tab == .goals ? 38 : 42, height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityValue(isSelected ? "已选中" : "")
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
