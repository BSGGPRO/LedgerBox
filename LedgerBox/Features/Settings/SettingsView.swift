import CoreData
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeManager: ThemeManager

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \TemplateRules.createdAt, ascending: true)],
        animation: .snappy
    )
    private var templates: FetchedResults<TemplateRules>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \LedgerTransaction.date, ascending: true)],
        animation: .snappy
    )
    private var transactions: FetchedResults<LedgerTransaction>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Account.sortOrder, ascending: true)],
        animation: .snappy
    )
    private var accounts: FetchedResults<Account>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Category.sortOrder, ascending: true)],
        animation: .snappy
    )
    private var categories: FetchedResults<Category>

    @State private var pendingTemplateKind: TemplateKind?
    @State private var showingTemplateConfirmation = false
    @State private var showingExporter = false
    @State private var csvText = ""
    @State private var exportFilename = "LedgerBox"
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showingAlert = false

    private var theme: Theme {
        themeManager.theme(for: colorScheme)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: theme.spacing) {
                    appearanceSection
                    templateSection
                    dataSection
                    aiSection
                    aboutSection
                }
                .padding(.horizontal, theme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.accent)
                }
            }
        }
        .environment(\.ledgerTheme, theme)
        .tint(theme.accent)
        .confirmationDialog(
            "切换模板？",
            isPresented: $showingTemplateConfirmation,
            titleVisibility: .visible
        ) {
            Button("应用模板", role: .destructive) {
                applyPendingTemplate()
            }
            Button("取消", role: .cancel) {
                pendingTemplateKind = nil
            }
        } message: {
            Text("只影响之后的新规则，不回溯历史。已有分类、预算和目标会更新；不会删除交易，也不会重置已存金额。")
        }
        .alert(
            alertTitle,
            isPresented: $showingAlert
        ) {
            Button("好", role: .cancel) {
            }
        } message: {
            Text(alertMessage)
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: CSVDocument(text: csvText),
            contentType: .commaSeparatedText,
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success:
                showAlert(title: "导出完成", message: "CSV 已保存到你选择的位置。")
            case .failure(let error):
                showAlert(title: "导出失败", message: error.localizedDescription)
            }
        }
    }

    private var appearanceSection: some View {
        VStack(spacing: theme.smallSpacing) {
            LedgerSectionHeader(title: "外观")

            LedgerCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("主题")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)

                    Picker(
                        "主题",
                        selection: Binding(
                            get: { themeManager.mode },
                            set: { themeManager.mode = $0 }
                        )
                    ) {
                        ForEach(ThemeMode.allCases) { mode in
                            Label(mode.displayName, systemImage: mode.symbolName)
                                .tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    Divider()
                        .overlay(theme.separator)

                    Text("强调色")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)

                    HStack(spacing: 14) {
                        ForEach(ThemeAccent.allCases) { accent in
                            Button {
                                themeManager.accentHex = accent.hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: accent.hex))
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        if isSelected(accent) {
                                            Image(systemName: "checkmark")
                                                .font(theme.badgeFont)
                                                .foregroundStyle(theme.onAccent)
                                        }
                                    }
                                    .overlay {
                                        Circle()
                                            .stroke(
                                                theme.primaryText.opacity(isSelected(accent) ? 0.25 : 0),
                                                lineWidth: 2
                                            )
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(accent.displayName)
                        }

                        Spacer()
                    }
                }
            }
        }
    }

    private var templateSection: some View {
        VStack(spacing: theme.smallSpacing) {
            LedgerSectionHeader(title: "模板")

            if let activeTemplate {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(theme.accent)

                    Text("当前：\(activeTemplate.name)")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ForEach(TemplateCatalog.allKinds, id: \.self) { kind in
                if let rules = TemplateCatalog.rules(for: kind) {
                    TemplateRuleRow(
                        rules: rules,
                        isActive: activeTemplate?.type == kind.rawValue,
                        theme: theme
                    ) {
                        requestApply(kind)
                    }
                }
            }

            Text("切换模板只影响之后的新规则，不回溯历史。已存金额与交易记录不会被重置。")
                .font(theme.captionFont)
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
        }
    }

    private var dataSection: some View {
        VStack(spacing: theme.smallSpacing) {
            LedgerSectionHeader(title: "数据")

            LedgerCard {
                VStack(spacing: 0) {
                    Button {
                        prepareExport()
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(theme.surfaceElevated)
                                    .frame(width: theme.iconCircleSize, height: theme.iconCircleSize)

                                Image(systemName: "square.and.arrow.up")
                                    .font(theme.rowIconFont)
                                    .foregroundStyle(theme.accent)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text("导出 CSV")
                                    .font(theme.bodyFont)
                                    .foregroundStyle(theme.primaryText)

                                Text("日期、类型、金额、分类、账户、备注")
                                    .font(theme.captionFont)
                                    .foregroundStyle(theme.secondaryText)
                            }

                            Spacer(minLength: theme.smallSpacing)

                            Image(systemName: "chevron.right")
                                .font(theme.controlIconFont)
                                .foregroundStyle(theme.secondaryText)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .overlay(theme.separator)
                        .padding(.vertical, 12)

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.shield")
                            .font(theme.rowIconFont)
                            .foregroundStyle(theme.secondaryText)

                        Text("账本默认只保存在本机 Core Data。App 不含联网 AI，也不会发起任何网络请求；无登录、无广告、无内购。")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var aiSection: some View {
        VStack(spacing: theme.smallSpacing) {
            LedgerSectionHeader(title: "AI")

            NavigationLink {
                FinanceAdvisorView()
            } label: {
                LedgerCard {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(theme.accent.opacity(0.12))
                                .frame(width: theme.iconCircleSize, height: theme.iconCircleSize)

                            Image(systemName: "brain.head.profile")
                                .font(theme.rowIconFont)
                                .foregroundStyle(theme.accent)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text("财务大脑")
                                .font(theme.bodyFont)
                                .foregroundStyle(theme.primaryText)

                            Text("40 个记账意图 · 20,971,560 参数 · 离线")
                                .font(theme.captionFont)
                                .foregroundStyle(theme.secondaryText)
                        }

                        Spacer(minLength: theme.smallSpacing)

                        Text("本地")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.income)

                        Image(systemName: "chevron.right")
                            .font(theme.controlIconFont)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("打开离线的财务专用小模型")

        }
    }

    private var aboutSection: some View {
        VStack(spacing: theme.smallSpacing) {
            LedgerCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LedgerBox \(appVersion)")
                        .font(theme.sectionTitleFont)
                        .foregroundStyle(theme.primaryText)

                    Text("iOS 17+ · SwiftUI · Core Data · 本地优先")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)

                    Text("通用记账引擎与场景模板分离；模板只影响之后的新规则。")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                }
            }

            Link(destination: authorURL) {
                LedgerCard {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(theme.surfaceElevated)
                                .frame(width: theme.iconCircleSize, height: theme.iconCircleSize)

                            Image(systemName: "play.rectangle.fill")
                                .font(theme.rowIconFont)
                                .foregroundStyle(theme.accent)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Beausoleil")
                                .font(theme.bodyFont)
                                .foregroundStyle(theme.primaryText)

                            Text("作者 · Bilibili 个人空间")
                                .font(theme.captionFont)
                                .foregroundStyle(theme.secondaryText)
                        }

                        Spacer(minLength: theme.smallSpacing)

                        Image(systemName: "arrow.up.right")
                            .font(theme.controlIconFont)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("在浏览器打开 Beausoleil 的 Bilibili 个人空间")

            Link(destination: repositoryURL) {
                LedgerCard {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(theme.accent.opacity(0.12))
                                .frame(width: theme.iconCircleSize, height: theme.iconCircleSize)

                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .font(theme.rowIconFont)
                                .foregroundStyle(theme.accent)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text("GitHub 开源地址")
                                .font(theme.bodyFont)
                                .foregroundStyle(theme.primaryText)

                            Text("BSGGPRO / LedgerBox · MIT")
                                .font(theme.captionFont)
                                .foregroundStyle(theme.secondaryText)
                        }

                        Spacer(minLength: theme.smallSpacing)

                        Image(systemName: "arrow.up.right")
                            .font(theme.controlIconFont)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("在浏览器打开 LedgerBox 的 GitHub 仓库")

            NavigationLink {
                ChangelogView()
            } label: {
                LedgerCard {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(theme.surfaceElevated)
                                .frame(width: theme.iconCircleSize, height: theme.iconCircleSize)

                            Image(systemName: "clock.arrow.circlepath")
                                .font(theme.rowIconFont)
                                .foregroundStyle(theme.accent)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text("更新日志")
                                .font(theme.bodyFont)
                                .foregroundStyle(theme.primaryText)

                            Text("查看每个版本新增与修复了什么")
                                .font(theme.captionFont)
                                .foregroundStyle(theme.secondaryText)
                        }

                        Spacer(minLength: theme.smallSpacing)

                        Text("v\(appVersion)")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)

                        Image(systemName: "chevron.right")
                            .font(theme.controlIconFont)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("打开版本更新记录")
        }
    }

    private var activeTemplate: TemplateRules? {
        templates.first { $0.active }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var authorURL: URL {
        URL(string: "https://space.bilibili.com/1477283849")!
    }

    private var repositoryURL: URL {
        URL(string: "https://github.com/BSGGPRO/LedgerBox")!
    }

    private func isSelected(_ accent: ThemeAccent) -> Bool {
        themeManager.accentHex.caseInsensitiveCompare(accent.hex) == .orderedSame
    }

    private func requestApply(_ kind: TemplateKind) {
        pendingTemplateKind = kind
        showingTemplateConfirmation = true
    }

    private func applyPendingTemplate() {
        guard
            let kind = pendingTemplateKind,
            let rules = TemplateCatalog.rules(for: kind)
        else {
            pendingTemplateKind = nil
            return
        }

        do {
            let result = try TemplateInstaller.apply(rules, in: viewContext)
            pendingTemplateKind = nil
            showAlert(title: "模板已应用", message: result.summary)
        } catch {
            pendingTemplateKind = nil
            showAlert(title: "模板应用失败", message: error.localizedDescription)
        }
    }

    private func prepareExport() {
        csvText = CSVExporter.makeCSV(
            transactions: Array(transactions),
            accounts: Array(accounts),
            categories: Array(categories)
        )

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        exportFilename = "LedgerBox-\(formatter.string(from: Date()))"
        showingExporter = true
    }

    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }
}

private struct TemplateRuleRow: View {
    let rules: any TemplateRuleProviding
    let isActive: Bool
    let theme: Theme
    let onApply: () -> Void

    var body: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: theme.smallSpacing) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(rules.title)
                            .font(theme.sectionTitleFont)
                            .foregroundStyle(theme.primaryText)

                        Text(rules.subtitle)
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: theme.smallSpacing)

                    if isActive {
                        Text("已启用")
                            .font(theme.badgeFont)
                            .foregroundStyle(theme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(theme.accent.opacity(0.12), in: Capsule())
                    }
                }

                if let note = rules.plan.notes.first {
                    Text(note)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(2)
                }

                HStack(spacing: theme.smallSpacing) {
                    Text("\(rules.plan.budgets.count) 个预算 · \(rules.plan.goals.count) 个目标")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)

                    Spacer(minLength: theme.smallSpacing)

                    Button(isActive ? "已启用" : "应用") {
                        onApply()
                    }
                    .font(theme.captionFont)
                    .buttonStyle(.bordered)
                    .tint(theme.accent)
                    .disabled(isActive)
                }
            }
        }
    }
}

private func previewThemeManager(name: String, mode: ThemeMode) -> ThemeManager {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    let manager = ThemeManager(defaults: defaults)
    manager.mode = mode
    return manager
}

#Preview("设置 · 浅色") {
    SettingsView()
        .environment(
            \.managedObjectContext,
            PersistenceController.preview.container.viewContext
        )
        .environmentObject(previewThemeManager(name: "LedgerBoxSettingsPreviewLight", mode: .light))
        .environment(\.colorScheme, .light)
}

#Preview("设置 · 深色") {
    SettingsView()
        .environment(
            \.managedObjectContext,
            PersistenceController.preview.container.viewContext
        )
        .environmentObject(previewThemeManager(name: "LedgerBoxSettingsPreviewDark", mode: .dark))
        .environment(\.colorScheme, .dark)
}
