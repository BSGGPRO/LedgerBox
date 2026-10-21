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
    @State private var showingSettingsPage = false
    @State private var isEntryMenuExpanded = false
    @State private var entryMenuStep = 0
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            TabView(selection: $selection) {
                ForEach(MainTab.allCases, id: \.self) { tab in
                    tabContent(for: tab)
                        .toolbar(.hidden, for: .tabBar)
                        .tag(tab)
                }
            }
            // Keep exactly five TabView children. A sixth child makes UIKit
            // synthesize a "More" list and adds back buttons to 目标/设置.
            .toolbar(.hidden, for: .tabBar)
            .opacity(showingSettingsPage ? 0 : 1)
            .allowsHitTesting(!showingSettingsPage)
            .accessibilityHidden(showingSettingsPage)

            if showingSettingsPage {
                SettingsView(showsDoneButton: false)
                    .environment(\.managedObjectContext, viewContext)
                    .environmentObject(themeManager)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showingSettingsPage)
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
            tabButton(.home)
            tabButton(.transactions)
            tabButton(.statistics)

            Button {
                toggleEntryMenu()
            } label: {
                barItemContent(
                    systemImage: "plus",
                    title: "记账",
                    isSelected: false,
                    iconSize: 22,
                    isEmphasized: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("记账")
            .accessibilityHint("依次展开极速记账和手动记一笔")

            tabButton(.budget)
            tabButton(.goals)

            Button {
                collapseEntryMenu()
                withAnimation(.easeOut(duration: 0.18)) {
                    showingSettingsPage = true
                }
            } label: {
                barItemContent(
                    systemImage: "gearshape",
                    title: "设置",
                    isSelected: showingSettingsPage
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("设置")
            .accessibilityValue(showingSettingsPage ? "已选中" : "")
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
        .overlay(alignment: .bottom) {
            if isEntryMenuExpanded {
                entryIsland
                    .offset(y: -58)
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 0.5)
        }
    }

    // MARK: - Entry island

    private var entryIsland: some View {
        VStack(spacing: 8) {
            if entryMenuStep >= 2 {
                entryBubble(
                    title: "记一笔",
                    systemImage: "square.and.pencil"
                ) {
                    collapseEntryMenu()
                    router.open(.manual)
                }
                .transition(entryBubbleTransition)
            }

            if entryMenuStep >= 1 {
                entryBubble(
                    title: "极速记账",
                    systemImage: "bolt.fill"
                ) {
                    collapseEntryMenu()
                    router.open(.image)
                }
                .transition(entryBubbleTransition)
            }
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.82), value: entryMenuStep)
    }

    private func entryBubble(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)

                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .padding(.bottom, 7)
            .background {
                EntryBubbleShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(
                                    .sRGB,
                                    red: 34.0 / 255.0,
                                    green: 34.0 / 255.0,
                                    blue: 38.0 / 255.0,
                                    opacity: 0.98
                                ),
                                Color(
                                    .sRGB,
                                    red: 18.0 / 255.0,
                                    green: 18.0 / 255.0,
                                    blue: 21.0 / 255.0,
                                    opacity: 0.98
                                )
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .shadow(color: Color.black.opacity(0.30), radius: 7, x: 0, y: 4)
            .contentShape(EntryBubbleShape())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(
            Text(
                title == "极速记账"
                    ? "打开相机或相册识别记账"
                    : "手动填写金额与分类"
            )
        )
    }

    private var entryBubbleTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.72, anchor: .bottom)),
            removal: .opacity
                .combined(with: .scale(scale: 0.88, anchor: .bottom))
        )
    }

    private func toggleEntryMenu() {
        if isEntryMenuExpanded {
            collapseEntryMenu()
            return
        }

        entryMenuStep = 0
        isEntryMenuExpanded = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            guard isEntryMenuExpanded else { return }
            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                entryMenuStep = 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
            guard isEntryMenuExpanded else { return }
            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                entryMenuStep = 2
            }
        }
    }

    private func collapseEntryMenu() {
        withAnimation(.easeOut(duration: 0.14)) {
            entryMenuStep = 0
            isEntryMenuExpanded = false
        }
    }

    private func tabButton(_ tab: MainTab) -> some View {
        Button {
            collapseEntryMenu()
            showingSettingsPage = false
            withAnimation(.easeOut(duration: 0.18)) {
                selection = tab
            }
        } label: {
            barItemContent(
                systemImage: tab.symbolName,
                title: tab.title,
                isSelected: !showingSettingsPage && selection == tab
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityValue(
            !showingSettingsPage && selection == tab ? "已选中" : ""
        )
    }

    private func barItemContent(
        systemImage: String,
        title: String,
        isSelected: Bool,
        iconSize: CGFloat = 16,
        isEmphasized: Bool = false
    ) -> some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(
                    .system(
                        size: iconSize,
                        weight: isEmphasized || isSelected ? .semibold : .regular
                    )
                )
                .frame(height: 20)

            Text(title)
                .font(
                    .system(
                        size: isEmphasized ? 9.5 : 9,
                        weight: isEmphasized || isSelected ? .semibold : .medium
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(
            isSelected
                ? Color.white
                : Color.white.opacity(isEmphasized ? 0.84 : 0.56)
        )
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .contentShape(Rectangle())
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

private struct EntryBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let tailHeight: CGFloat = 7
        let tailWidth: CGFloat = 12
        let bodyHeight = max(rect.height - tailHeight, 0)
        let radius = min(15, bodyHeight / 2)

        var path = RoundedRectangle(cornerRadius: radius, style: .continuous)
            .path(
                in: CGRect(
                    x: rect.minX,
                    y: rect.minY,
                    width: rect.width,
                    height: bodyHeight
                )
            )

        let tailTop = bodyHeight - 1
        let centerX = rect.midX
        path.move(to: CGPoint(x: centerX - tailWidth / 2, y: tailTop))
        path.addLine(to: CGPoint(x: centerX, y: rect.maxY))
        path.addLine(to: CGPoint(x: centerX + tailWidth / 2, y: tailTop))
        path.closeSubpath()
        return path
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
