import CoreData
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeManager: ThemeManager

    private let showsDoneButton: Bool

    init(showsDoneButton: Bool = true) {
        self.showsDoneButton = showsDoneButton
    }

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
    @State private var showingCSVExporter = false
    @State private var csvText = ""
    @State private var csvFilename = "LedgerBox"
    @State private var showingJSONExporter = false
    @State private var backupData = Data()
    @State private var backupFilename = "LedgerBox-backup"
    @State private var showingRestoreConfirmation = false
    @State private var showingJSONImporter = false
    @State private var lastRestoreSummary: String?
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showingAlert = false

    // Accent editing state. The source of truth is always `themeManager.accentHex`.
    @State private var customColor = Color(hex: Theme.defaultAccentHex)
    @State private var hexDraft = Theme.defaultAccentHex
    @State private var hexError: String?
    @FocusState private var hexFieldFocused: Bool

    private var theme: Theme {
        themeManager.theme(for: colorScheme)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.sectionSpacing) {
                    appearanceSection
                    templateSection
                    dataSection
                    aiSection
                    aboutSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, theme.pagePadding)
                .padding(.top, theme.smallSpacing)
                .padding(.bottom, theme.sectionSpacing + theme.smallSpacing)
                .keyboardDismissOnBlankTap {
                    hexFieldFocused = false
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                if showsDoneButton {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            dismiss()
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.accentText)
                    }
                }
            }
        }
        .environment(\.ledgerTheme, theme)
        .tint(theme.accentText)
        .onAppear {
            syncAccentFields()
        }
        .onChange(of: themeManager.accentHex) { _, newValue in
            if hexDraft.caseInsensitiveCompare(newValue) != .orderedSame {
                hexDraft = newValue
            }
            customColor = Color(hex: newValue)
        }
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
            isPresented: $showingCSVExporter,
            document: CSVDocument(text: csvText),
            contentType: .commaSeparatedText,
            defaultFilename: csvFilename
        ) { result in
            switch result {
            case .success:
                showAlert(title: "导出完成", message: "CSV 已保存到你选择的位置。")
            case .failure(let error):
                showAlert(title: "导出失败", message: error.localizedDescription)
            }
        }
        // JSON uses its own isPresented/document pair so it can never collide
        // with the CSV exporter above.
        .fileExporter(
            isPresented: $showingJSONExporter,
            document: JSONBackupDocument(data: backupData),
            contentType: .json,
            defaultFilename: backupFilename
        ) { result in
            switch result {
            case .success:
                showAlert(title: "备份已导出", message: "JSON 全量备份已保存到你选择的位置。")
            case .failure(let error):
                showAlert(title: "备份失败", message: error.localizedDescription)
            }
        }
        .confirmationDialog(
            "导入 JSON 备份？",
            isPresented: $showingRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("替换并导入", role: .destructive) {
                // Defer one run loop so the picker does not try to present while
                // the confirmation dialog is still dismissing.
                DispatchQueue.main.async {
                    showingJSONImporter = true
                }
            }
            Button("取消", role: .cancel) {
            }
        } message: {
            Text("会替换本机全部账本数据：账户、分类、流水、预算、目标与设置都以备份为准，且无法撤销。")
        }
        .fileImporter(
            isPresented: $showingJSONImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    return
                }
                // The view context is main-queue confined; restore on main even if
                // the picker hands the URL back on another queue.
                DispatchQueue.main.async {
                    restoreBackup(from: url)
                }
            case .failure(let error):
                showAlert(title: "导入失败", message: error.localizedDescription)
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        section("外观") {
            LedgerCard {
                VStack(alignment: .leading, spacing: theme.spacing) {
                    Text("主题")
                        .font(theme.overlineFont)
                        .tracking(0.8)
                        .foregroundStyle(theme.secondaryText)

                    LedgerSegmentedControl(
                        items: ThemeMode.allCases,
                        title: { $0.displayName },
                        symbol: { $0.symbolName },
                        selection: Binding(
                            get: { themeManager.mode },
                            set: { themeManager.mode = $0 }
                        )
                    )

                    hairline

                    accentEditor
                }
            }
        }
    }

    private var accentEditor: some View {
        VStack(alignment: .leading, spacing: theme.spacing) {
            HStack(alignment: .firstTextBaseline, spacing: theme.smallSpacing) {
                Text("强调色")
                    .font(theme.overlineFont)
                    .tracking(0.8)
                    .foregroundStyle(theme.secondaryText)

                Spacer(minLength: theme.smallSpacing)

                Text("#\(theme.accentHex)")
                    .font(theme.hexFont)
                    .foregroundStyle(theme.tertiaryText)
            }

            presetRow

            customColorRow

            hexRow

            if let hexError {
                Text(hexError)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.expense)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let notice = themeManager.accentFallbackNotice {
                fallbackNotice(notice)
            }

            accentPreview

            if showsAccentCorrection {
                lowContrastHint
            }
        }
    }

    private var presetRow: some View {
        HStack(spacing: theme.tinySpacing) {
            ForEach(ThemeAccent.allCases) { accent in
                Button {
                    applyHex(accent.hex)
                } label: {
                    swatch(hex: accent.hex, selected: isSelected(accent))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accent.displayName)
                .accessibilityAddTraits(isSelected(accent) ? AccessibilityTraits.isSelected : AccessibilityTraits())
            }

            Spacer(minLength: 0)
        }
    }

    private func swatch(hex: String, selected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 32, height: 32)

            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(LedgerAccent.onColor(for: hex))
            }
        }
        .frame(width: theme.minTapTarget, height: theme.minTapTarget)
        .overlay {
            Circle()
                .strokeBorder(theme.primaryText.opacity(selected ? 0.9 : 0), lineWidth: 1.5)
                .frame(width: 38, height: 38)
        }
        .contentShape(Circle())
    }

    private var customColorRow: some View {
        HStack(spacing: theme.cardSpacing) {
            ColorPicker(selection: customColorBinding, supportsOpacity: false) {
                HStack(spacing: 6) {
                    Image(systemName: "eyedropper")
                        .font(theme.controlIconFont)

                    Text("自定义颜色")
                        .font(theme.captionFont)
                }
                .foregroundStyle(theme.secondaryText)
            }
            .tint(theme.accentText)

            Spacer(minLength: theme.smallSpacing)
        }
        .frame(minHeight: theme.minTapTarget)
    }

    private var hexRow: some View {
        HStack(spacing: theme.smallSpacing) {
            Text("HEX")
                .font(theme.overlineFont)
                .tracking(0.6)
                .foregroundStyle(theme.tertiaryText)

            TextField("2F6FED", text: $hexDraft)
                .font(theme.hexFont)
                .foregroundStyle(theme.primaryText)
                .focused($hexFieldFocused)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .submitLabel(.done)
                .onSubmit { applyHexDraft() }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: 132)
                .background(
                    RoundedRectangle(cornerRadius: theme.controlRadius, style: .continuous)
                        .fill(theme.surfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: theme.controlRadius, style: .continuous)
                        .strokeBorder(hexError == nil ? theme.separator : theme.expense, lineWidth: theme.hairline)
                )
                .accessibilityLabel("强调色 HEX 值")

            Spacer(minLength: theme.smallSpacing)

            Button("应用") {
                applyHexDraft()
            }
            .buttonStyle(LedgerSecondaryButtonStyle(theme: theme))
            .accessibilityLabel("应用自定义 HEX 颜色")
        }
    }

    private func fallbackNotice(_ notice: String) -> some View {
        HStack(alignment: .top, spacing: theme.smallSpacing) {
            Image(systemName: "arrow.uturn.backward.circle")
                .font(theme.controlIconFont)
                .foregroundStyle(theme.warning)

            Text(notice)
                .font(theme.captionFont)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: theme.tinySpacing)

            Button {
                themeManager.dismissFallbackNotice()
            } label: {
                Image(systemName: "xmark")
                    .font(theme.controlIconFont)
                    .foregroundStyle(theme.tertiaryText)
                    .frame(width: theme.minTapTarget, height: theme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("收起提示")
        }
        .padding(.leading, theme.cardSpacing)
        .padding(.vertical, theme.tinySpacing)
        .background(
            theme.warningSoft,
            in: RoundedRectangle(cornerRadius: theme.controlRadius + 3, style: .continuous)
        )
    }

    private var accentPreview: some View {
        VStack(alignment: .leading, spacing: theme.smallSpacing) {
            HStack(spacing: theme.cardSpacing) {
                Text("记一笔")
                    .font(theme.buttonLabelFont)
                    .foregroundStyle(theme.onAccent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(theme.accent, in: Capsule())

                Text("强调文字 / 图标")
                    .font(theme.bodyFont.weight(.semibold))
                    .foregroundStyle(theme.accentText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: theme.tinySpacing)
            }

            Text("按钮文字 \(contrastText(buttonTextContrast)) · 文字 \(contrastText(theme.accentTextContrast))")
                .font(theme.captionFont)
                .foregroundStyle(theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            theme.surfaceElevated,
            in: RoundedRectangle(cornerRadius: theme.controlRadius + 3, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private var lowContrastHint: some View {
        HStack(alignment: .top, spacing: theme.smallSpacing) {
            Image(systemName: "exclamationmark.circle")
                .font(theme.controlIconFont)
                .foregroundStyle(theme.warning)

            VStack(alignment: .leading, spacing: 6) {
                Text("自定义颜色在卡片上作为文字只有 \(contrastText(theme.accentContrast))")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("按钮文字已自动使用\(theme.accentInkOnAccent ? "深色" : "白色")；文字与图标自动改用加深后的 #\(theme.accentTextHex)，保证可读。")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Button("改用加深版") {
                    applyHex(theme.accentTextHex)
                }
                .font(theme.captionFont.weight(.semibold))
                .foregroundStyle(theme.accentText)
                .frame(minHeight: theme.minTapTarget, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityLabel("改用加深后的强调色")
            }

            Spacer(minLength: 0)
        }
        .padding(theme.cardSpacing)
        .background(
            theme.warningSoft,
            in: RoundedRectangle(cornerRadius: theme.controlRadius + 3, style: .continuous)
        )
    }

    // MARK: - Templates

    private var templateSection: some View {
        section("模板") {
            if let activeTemplate {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal")
                        .font(theme.controlIconFont)
                        .foregroundStyle(theme.accentText)

                    Text("当前：\(activeTemplate.name)")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
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
                .foregroundStyle(theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, theme.tinySpacing)
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        section("数据") {
            LedgerCard(padding: 0) {
                VStack(spacing: 0) {
                    Button {
                        prepareCSVExport()
                    } label: {
                        SettingsRow(
                            theme: theme,
                            icon: "square.and.arrow.up",
                            tint: theme.accentText,
                            title: "导出 CSV",
                            subtitle: "日期、类型、金额、分类、账户、备注"
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, theme.cardPadding)
                    .padding(.vertical, theme.tinySpacing)

                    dataSeparator

                    Button {
                        prepareJSONExport()
                    } label: {
                        SettingsRow(
                            theme: theme,
                            icon: "archivebox",
                            tint: theme.accentText,
                            title: "导出 JSON 备份",
                            subtitle: "账户、分类、流水、预算、目标、模板与设置"
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, theme.cardPadding)
                    .padding(.vertical, theme.tinySpacing)

                    dataSeparator

                    Button {
                        showingRestoreConfirmation = true
                    } label: {
                        SettingsRow(
                            theme: theme,
                            icon: "square.and.arrow.down",
                            tint: theme.warning,
                            title: "导入 JSON 备份",
                            subtitle: "全量恢复 · 会替换本机全部数据"
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, theme.cardPadding)
                    .padding(.vertical, theme.tinySpacing)

                    dataSeparator

                    if let lastRestoreSummary {
                        HStack(alignment: .top, spacing: theme.smallSpacing) {
                            Image(systemName: "checkmark.seal")
                                .font(theme.controlIconFont)
                                .foregroundStyle(theme.income)

                            Text(lastRestoreSummary)
                                .font(theme.captionFont)
                                .foregroundStyle(theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, theme.cardPadding)
                        .padding(.vertical, theme.cardSpacing)

                        dataSeparator
                    }

                    HStack(alignment: .top, spacing: theme.smallSpacing) {
                        Image(systemName: "lock.shield")
                            .font(theme.controlIconFont)
                            .foregroundStyle(theme.tertiaryText)

                        Text("账本默认只保存在本机 Core Data。App 不含联网 AI，也不会发起任何网络请求；无登录、无广告、无内购。")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, theme.cardPadding)
                    .padding(.top, theme.cardSpacing)
                    .padding(.bottom, theme.cardPadding)
                }
            }
        }
    }

    // MARK: - AI

    private var aiSection: some View {
        section("AI") {
            NavigationLink {
                FinanceBrainSettingsView()
            } label: {
                LedgerCard {
                    SettingsRow(
                        theme: theme,
                        icon: "brain.head.profile",
                        tint: theme.accentText,
                        title: "财务大脑",
                        subtitle: "核心路由 · 本地解释引擎 · Qwen2.5-0.5B",
                        trailingText: "本地",
                        trailingTint: theme.income
                    )
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("查看核心路由和本地 Qwen 解释引擎")

            NavigationLink {
                AIFinanceLogDiagnosisView()
            } label: {
                LedgerCard {
                    SettingsRow(
                        theme: theme,
                        icon: "doc.text.magnifyingglass",
                        tint: theme.accentText,
                        title: "AI 财务日志诊断",
                        subtitle: "最近 30 天流水 · 拿铁因子与异常消费 · 本机 Qwen",
                        trailingText: "30 天",
                        trailingTint: theme.income
                    )
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("用本地模型分析最近 30 天的账单")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        section("关于") {
            LedgerCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LedgerBox \(appVersion)")
                        .font(theme.sectionTitleFont)
                        .foregroundStyle(theme.primaryText)

                    Text("iOS 17+ · SwiftUI · Core Data · 本地优先")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("通用记账引擎与场景模板分离；模板只影响之后的新规则。")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Link(destination: authorURL) {
                LedgerCard {
                    SettingsRow(
                        theme: theme,
                        icon: "play.rectangle",
                        tint: theme.accentText,
                        title: "Beausoleil",
                        subtitle: "作者 · Bilibili 个人空间",
                        showsChevron: false,
                        trailingSystemImage: "arrow.up.right"
                    )
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("在浏览器打开 Beausoleil 的 Bilibili 个人空间")

            Link(destination: repositoryURL) {
                LedgerCard {
                    SettingsRow(
                        theme: theme,
                        icon: "chevron.left.forwardslash.chevron.right",
                        tint: theme.accentText,
                        title: "GitHub 开源地址",
                        subtitle: "BSGGPRO / LedgerBox · MIT",
                        showsChevron: false,
                        trailingSystemImage: "arrow.up.right"
                    )
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("在浏览器打开 LedgerBox 的 GitHub 仓库")

            NavigationLink {
                ChangelogView()
            } label: {
                LedgerCard {
                    SettingsRow(
                        theme: theme,
                        icon: "clock.arrow.circlepath",
                        tint: theme.accentText,
                        title: "更新日志",
                        subtitle: "查看每个版本新增与修复了什么",
                        trailingText: "v\(appVersion)"
                    )
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("打开版本更新记录")
        }
    }

    // MARK: - Building blocks

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: theme.cardSpacing) {
            LedgerSectionHeader(title: title)
            content()
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(theme.separator)
            .frame(height: theme.hairline)
    }

    private var dataSeparator: some View {
        Rectangle()
            .fill(theme.separator)
            .frame(height: theme.hairline)
            .padding(.leading, theme.cardPadding)
    }

    // MARK: - Accent editing

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { customColor },
            set: { newValue in
                customColor = newValue
                applyCustomColor(newValue)
            }
        )
    }

    /// Contrast of the button label (white or ink) against the accent fill.
    private var buttonTextContrast: Double {
        guard let fill = LedgerRGB(hex: theme.accentHex),
              let label = LedgerRGB(hex: theme.accentInkOnAccent ? LedgerAccent.inkHex : "FFFFFF") else {
            return 0
        }
        return fill.contrast(with: label)
    }

    private func contrastText(_ value: Double) -> String {
        String(format: "%.1f:1", value)
    }

    private func applyCustomColor(_ color: Color) {
        guard let hex = color.ledgerHex else {
            syncAccentFields()
            showAlert(title: "无法读取这个颜色", message: "请换一个 sRGB 颜色。当前强调色保持不变。")
            return
        }

        _ = themeManager.setAccent(hex: hex)
        hexError = nil
        hexDraft = themeManager.accentHex
    }

    private func applyHex(_ hex: String) {
        hexFieldFocused = false
        guard themeManager.setAccent(hex: hex) else {
            hexError = "HEX 需要 6 位十六进制，例如 2F6FED。当前强调色未改变。"
            return
        }
        hexError = nil
        syncAccentFields()
    }

    private func applyHexDraft() {
        applyHex(hexDraft)
    }

    private func syncAccentFields() {
        hexDraft = themeManager.accentHex
        customColor = Color(hex: themeManager.accentHex)
    }

    private func isSelected(_ accent: ThemeAccent) -> Bool {
        themeManager.accentHex.caseInsensitiveCompare(accent.hex) == .orderedSame
    }

    /// The five curated presets are vetted by design; only user-picked colors get
    /// the auto-correction banner. The numeric contrast readout is always visible.
    private var isPresetAccent: Bool {
        ThemeAccent.allCases.contains { accent in
            themeManager.accentHex.caseInsensitiveCompare(accent.hex) == .orderedSame
        }
    }

    private var showsAccentCorrection: Bool {
        theme.accentIsLowContrast && !isPresetAccent
    }

    // MARK: - Templates & export

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

    private func prepareCSVExport() {
        csvText = CSVExporter.makeCSV(
            transactions: Array(transactions),
            accounts: Array(accounts),
            categories: Array(categories)
        )

        csvFilename = "LedgerBox-\(exportTimestamp)"
        showingCSVExporter = true
    }

    private func prepareJSONExport() {
        do {
            backupData = try LedgerBackupService.makeBackup(context: viewContext)
            backupFilename = "LedgerBox-backup-\(exportTimestamp)"
            showingJSONExporter = true
        } catch {
            showAlert(title: "备份失败", message: error.localizedDescription)
        }
    }

    private func restoreBackup(from url: URL) {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        lastRestoreSummary = nil

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            showAlert(
                title: "导入失败",
                message: "无法读取所选文件：\(error.localizedDescription)"
            )
            return
        }

        do {
            let summary = try LedgerBackupService.restore(data: data, context: viewContext)
            lastRestoreSummary = summary.summaryText
            showAlert(title: "导入完成", message: summary.summaryText)
        } catch {
            showAlert(title: "导入失败", message: error.localizedDescription)
        }
    }

    private var exportTimestamp: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: Date())
    }

    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }
}

// MARK: - Rows

private struct TemplateRuleRow: View {
    let rules: any TemplateRuleProviding
    let isActive: Bool
    let theme: Theme
    let onApply: () -> Void

    var body: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: theme.cardSpacing) {
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
                        LedgerTag("已启用", tint: theme.income)
                    }
                }

                if let note = rules.plan.notes.first {
                    Text(note)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.tertiaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: theme.smallSpacing) {
                    Text("\(rules.plan.budgets.count) 个预算 · \(rules.plan.goals.count) 个目标")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.tertiaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: theme.smallSpacing)

                    if isActive {
                        Text("已启用")
                            .font(theme.buttonLabelFont)
                            .foregroundStyle(theme.secondaryText)
                            .padding(.horizontal, theme.cardPadding)
                            .frame(minHeight: theme.minTapTarget)
                    } else {
                        Button("应用") {
                            onApply()
                        }
                        .buttonStyle(LedgerSecondaryButtonStyle(theme: theme))
                    }
                }
            }
        }
    }
}

private struct SettingsRow: View {
    let theme: Theme
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    var trailingText: String? = nil
    var trailingTint: Color? = nil
    var showsChevron = true
    var trailingSystemImage: String? = nil

    var body: some View {
        HStack(spacing: theme.cardSpacing) {
            LedgerIconBadge(systemName: icon, tint: tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(theme.bodyFont.weight(.medium))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                Text(subtitle)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(0)

            Spacer(minLength: theme.smallSpacing)

            if let trailingText {
                Text(trailingText)
                    .font(theme.captionFont)
                    .foregroundStyle(trailingTint ?? theme.tertiaryText)
                    .lineLimit(1)
                    .layoutPriority(1)
            }

            if let trailingSystemImage {
                Image(systemName: trailingSystemImage)
                    .font(theme.controlIconFont)
                    .foregroundStyle(theme.tertiaryText)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(theme.controlIconFont)
                    .foregroundStyle(theme.tertiaryText)
            }
        }
        .frame(minHeight: theme.minTapTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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


// MARK: - Merged finance brain settings

struct FinanceBrainSettingsView: View {
    @Environment(\.ledgerTheme) private var theme
    @StateObject private var localModel = QwenLocalModel.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.sectionSpacing) {
                summaryCard

                sectionHeader("核心路由")
                NavigationLink {
                    FinanceAdvisorView()
                } label: {
                    LedgerCard {
                        SettingsRow(
                            theme: theme,
                            icon: "point.3.connected.trianglepath.dotted",
                            tint: theme.accentText,
                            title: "40 个财务/会计意图",
                            subtitle: "41,943,080 参数 · 哈希分类器 · Decimal 精算；只选公式，不生成数字",
                            trailingText: "对话",
                            trailingTint: theme.accentText
                        )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("打开财务大脑对话与精算回答")

                sectionHeader("本地解释引擎")
                NavigationLink {
                    FinanceAdvisorView(startsInBrain: true)
                } label: {
                    LedgerCard {
                        SettingsRow(
                            theme: theme,
                            icon: "cpu",
                            tint: localModel.status.isReady ? theme.income : theme.warning,
                            title: "Qwen2.5-0.5B-Instruct",
                            subtitle: "\(localModel.status.summary) · \(localModel.completedGenerations) 次真实生成 · \(localModel.rejectedGenerations) 次拒绝",
                            trailingText: localModel.status.isReady ? "已加载" : "未就绪",
                            trailingTint: localModel.status.isReady ? theme.income : theme.warning
                        )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("打开大脑视图，运行一次真实 0.5B 解释自检")

                LedgerCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("解释层边界")
                            .font(theme.bodyFont.weight(.semibold))
                            .foregroundStyle(theme.primaryText)

                        Text("0.5B 只改写已经用 Decimal 算好的结果，不参与金额、比例、日期计算，也不写账。加载失败时，核心路由和所有记账功能继续可用。")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, theme.pagePadding)
            .padding(.vertical, theme.spacing)
        }
        .scrollIndicators(.hidden)
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("财务大脑")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            localModel.prepare()
        }
    }

    private var summaryCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(theme.rowIconFont)
                        .foregroundStyle(theme.accentText)

                    Text("本地 AI 总览")
                        .font(theme.sectionTitleFont)
                        .foregroundStyle(theme.primaryText)
                }

                Text("核心路由负责把问题送到确定性公式；Qwen 0.5B 只负责把结果改写成人话。两条链路都在本机运行，不联网。")
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Label("41.9M 参数", systemImage: "function")
                    Label("491 MB 模型", systemImage: "internaldrive")
                }
                .font(theme.badgeFont)
                .foregroundStyle(theme.income)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(theme.overlineFont)
            .tracking(0.8)
            .foregroundStyle(theme.secondaryText)
            .padding(.horizontal, 2)
    }
}

// MARK: - AI finance log diagnosis

/// Prompt constants for the local financial-log diagnosis.
///
/// The model is read-only: it receives a compact digest of the last 30 days and
/// returns Markdown advice. It never receives a Core Data context and cannot
/// write a transaction, account, budget, or goal.
enum AIFinanceLogPrompt {
    static let ledgerPlaceholder = "{{LEDGER_DATA}}"

    static let systemPrompt = """
    你是一位资深个人财务规划师。你的工作是帮助用户理解自己的消费习惯，而不是批评用户。

    任务：
    1. 阅读用户最近 30 天的记账流水，找出“拿铁因子”：高频、小额、容易被忽视的重复支出。
    2. 找出异常消费：明显偏离用户日常水平的大额支出、疑似重复扣款，或与分类不一致的消费。
    3. 只基于用户流水中的信息分析，不编造未出现的商户、金额、日期、分类或账户。

    输出要求：
    - 只输出 Markdown，不要输出代码块，不要输出前言或结尾寒暄。
    - 必须包含以下三个 Markdown 二级标题，标题文字保留方括号，顺序不能变：
      ## 【财务健康度体检】
      ## 【消费漏洞诊断】
      ## 【财务教练的 3 个建议】
    - “财务健康度体检”用 2 到 4 句话概括收支、结余和消费结构；可以引用流水中的金额或比例，没有数据时就明确说没有数据。
    - “消费漏洞诊断”分别说明支出大头、拿铁因子和异常消费；每条尽量给出金额、频次、分类或日期作为依据。没有发现时也要明确说没有发现。
    - “财务教练的 3 个建议”必须恰好给出 3 条可执行建议，按优先级排序；建议要温和、具体、可执行。
    - 语气专业、温和、不评判。不要使用“败家”“浪费”“不自律”等羞辱性表达。
    - 不承诺收益，不构成投资、税务或法律建议。
    - 只分析数据，不写账、不修改账本、不替用户做自动扣款或转账决定。
    """

    static let userPromptTemplate = """
    请分析下面的【用户流水数据】。数据来自用户本机最近 30 天的账本，已经整理成结构化纯文本。

    【用户流水数据】
    \(ledgerPlaceholder)

    【分析任务】
    请按照系统提示中的三个 Markdown 标题输出。优先关注高频小额支出中的重复模式，以及明显偏离日常水平的大额或异常消费。引用金额时只使用上面出现过的数字；数据不足时直接说明，不要猜测。
    """

    /// Inserts the user's structured ledger digest into the prompt template.
    static func makeUserPrompt(ledgerText: String) -> String {
        userPromptTemplate.replacingOccurrences(
            of: ledgerPlaceholder,
            with: ledgerText
        )
    }

    /// Complete Qwen ChatML prompt, including the read-only system instruction.
    static func makePrompt(ledgerText: String) -> String {
        """
        <|im_start|>system
        \(systemPrompt)
        <|im_end|>
        <|im_start|>user
        \(makeUserPrompt(ledgerText: ledgerText))
        <|im_end|>
        <|im_start|>assistant
        """
    }
}

struct AIFinanceLogDigest {
    let text: String
    let transactionCount: Int
    let listedCount: Int
    let startDate: Date
    let endDate: Date
    let totalExpense: Decimal
    let totalIncome: Decimal
    let totalRefund: Decimal
    let truncated: Bool

    var net: Decimal {
        totalIncome + totalRefund - totalExpense
    }
}

/// Builds a compact, deterministic text digest from Core Data.
///
/// All totals are calculated with `Decimal`. Only display percentages use
/// `Double`, and the per-transaction section is intentionally sampled so the
/// final prompt stays inside the local model's 2048-token context.
enum AIFinanceLogDigestBuilder {
    static let defaultDays = 30
    static let recentLineLimit = 10
    static let maxDigestCharacters = 1_000

    private struct CategoryAggregate {
        let name: String
        var amount: Decimal
        var count: Int
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func build(
        context: NSManagedObjectContext,
        now: Date = Date(),
        days: Int = AIFinanceLogDigestBuilder.defaultDays
    ) throws -> AIFinanceLogDigest {
        let startDate = Calendar.current.date(
            byAdding: .day,
            value: -max(1, days),
            to: now
        ) ?? now.addingTimeInterval(-30 * 86_400)

        let request = LedgerTransaction.fetchRequest()
        request.predicate = NSPredicate(
            format: "date >= %@ AND date <= %@",
            startDate as NSDate,
            now as NSDate
        )
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \LedgerTransaction.date, ascending: false)
        ]

        let transactions = try context.fetch(request)
        let accounts = try context.fetch(Account.fetchRequest())
        let categories = try context.fetch(Category.fetchRequest())
        let accountNames = Dictionary(
            uniqueKeysWithValues: accounts.map { ($0.id, $0.name) }
        )
        let categoryNames = Dictionary(
            uniqueKeysWithValues: categories.map { ($0.id, $0.name) }
        )

        guard !transactions.isEmpty else {
            let emptyText = """
            【分析窗口】\(dayFormatter.string(from: startDate)) 至 \(dayFormatter.string(from: now))
            【汇总】0 笔；最近 \(days) 天没有可用于分析的流水。
            """
            return AIFinanceLogDigest(
                text: emptyText,
                transactionCount: 0,
                listedCount: 0,
                startDate: startDate,
                endDate: now,
                totalExpense: 0,
                totalIncome: 0,
                totalRefund: 0,
                truncated: false
            )
        }

        var totalExpense: Decimal = 0
        var totalIncome: Decimal = 0
        var totalRefund: Decimal = 0
        var categoryTotals: [String: CategoryAggregate] = [:]
        var smallTotals: [String: (count: Int, amount: Decimal)] = [:]
        var expenseCount = 0

        for transaction in transactions {
            let amount = transaction.amount.decimalValue
            guard let type = TransactionType(rawValue: transaction.type) else {
                continue
            }
            let category = transaction.categoryId
                .flatMap { categoryNames[$0] } ?? "未分类"
            let note = normalizedNote(transaction.note) ?? category

            switch type {
            case .expense:
                totalExpense += amount
                expenseCount += 1
                var aggregate = categoryTotals[category]
                    ?? CategoryAggregate(name: category, amount: 0, count: 0)
                aggregate.amount += amount
                aggregate.count += 1
                categoryTotals[category] = aggregate

                if amount > 0, amount <= 50 {
                    var small = smallTotals[note] ?? (count: 0, amount: 0)
                    small.count += 1
                    small.amount += amount
                    smallTotals[note] = small
                }
            case .income:
                totalIncome += amount
            case .refund:
                totalRefund += amount
            case .transfer:
                break
            }
        }

        let topCategories = categoryTotals.values
            .sorted { $0.amount > $1.amount }
            .prefix(5)
            .map { item -> String in
                let share = totalExpense > 0
                    ? NSDecimalNumber(decimal: item.amount)
                        .doubleValue / NSDecimalNumber(decimal: totalExpense).doubleValue * 100
                    : 0
                return "\(item.name) \(money(item.amount))（\(item.count) 笔，\(String(format: "%.1f", share))%）"
            }

        let smallLines = smallTotals
            .filter { $0.value.count >= 2 }
            .sorted {
                if $0.value.count == $1.value.count {
                    return $0.value.amount > $1.value.amount
                }
                return $0.value.count > $1.value.count
            }
            .prefix(5)
            .map { item in
                let key = item.key
                let value = item.value
                return "\(key) \(money(value.amount)) × \(value.count) 次"
            }

        let averageExpense = expenseCount > 0
            ? totalExpense / Decimal(expenseCount)
            : 0
        let largeThreshold = max(
            averageExpense * (Decimal(string: "2.5") ?? 2),
            Decimal(200)
        )
        let largeLines = transactions
            .filter {
                $0.type == TransactionType.expense.rawValue
                    && $0.amount.decimalValue >= largeThreshold
            }
            .sorted { $0.amount.decimalValue > $1.amount.decimalValue }
            .prefix(3)
            .map { transaction in
                let category = transaction.categoryId
                    .flatMap { categoryNames[$0] } ?? "未分类"
                return "\(dayFormatter.string(from: transaction.date)) \(category) \(money(transaction.amount.decimalValue))"
            }

        let listed = Array(transactions.prefix(recentLineLimit))
        var lines: [String] = []
        lines.append(
            "【分析窗口】\(dayFormatter.string(from: startDate)) 至 \(dayFormatter.string(from: now))"
        )
        lines.append(
            "【汇总】共 \(transactions.count) 笔；支出 \(money(totalExpense))；收入 \(money(totalIncome))；退款 \(money(totalRefund))；净结余 \(money(totalIncome + totalRefund - totalExpense))"
        )

        if !topCategories.isEmpty {
            lines.append("【分类支出】" + topCategories.joined(separator: "；"))
        }
        if !smallLines.isEmpty {
            lines.append("【高频小额候选】" + smallLines.joined(separator: "；"))
        }
        if !largeLines.isEmpty {
            lines.append("【大额/异常候选】" + largeLines.joined(separator: "；"))
        }

        lines.append(
            "【逐笔明细·最近 \(listed.count) 条，汇总覆盖全部 \(transactions.count) 笔】"
        )
        for transaction in listed {
            let category = transaction.categoryId
                .flatMap { categoryNames[$0] } ?? "未分类"
            let account = accountNames[transaction.accountId] ?? "未知账户"
            let type = TransactionType(rawValue: transaction.type)?.displayName
                ?? transaction.type
            let note = normalizedNote(transaction.note) ?? "-"
            lines.append(
                "\(dayFormatter.string(from: transaction.date)) \(timeFormatter.string(from: transaction.date)) | \(type) | \(category) | \(money(transaction.amount.decimalValue)) | \(account) | \(note)"
            )
        }

        var text = lines.joined(separator: "\n")
        var truncated = transactions.count > listed.count
        if text.count > maxDigestCharacters {
            text = String(text.prefix(maxDigestCharacters))
                + "\n（数据已按长度截断；汇总和分类仍覆盖全部流水）"
            truncated = true
        }

        return AIFinanceLogDigest(
            text: text,
            transactionCount: transactions.count,
            listedCount: listed.count,
            startDate: startDate,
            endDate: now,
            totalExpense: totalExpense,
            totalIncome: totalIncome,
            totalRefund: totalRefund,
            truncated: truncated
        )
    }

    private static func normalizedNote(_ note: String?) -> String? {
        let value = (note ?? "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return String(value.prefix(14))
    }

    private static func money(_ value: Decimal) -> String {
        "¥" + NSDecimalNumber(decimal: value).stringValue
    }
}

// MARK: - AI finance log diagnosis page

struct AIFinanceLogDiagnosisView: View {
    private enum Phase: Equatable {
        case idle
        case building
        case generating
        case finished
        case failed
    }

    @Environment(\.ledgerTheme) private var theme
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var localModel = QwenLocalModel.shared

    @State private var phase: Phase = .idle
    @State private var digest: AIFinanceLogDigest?
    @State private var prompt = ""
    @State private var report: String?
    @State private var errorMessage: String?

    private var isBusy: Bool {
        phase == .building || phase == .generating
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.sectionSpacing) {
                introCard
                statusCard
                analyzeButton

                if let errorMessage {
                    errorCard(errorMessage)
                }

                if let report {
                    reportCard(report)
                }

                if let digest {
                    disclosureCard(
                        title: "查看用于分析的结构化流水",
                        text: digest.text
                    )
                }

                if !prompt.isEmpty {
                    promptCard
                }

                disclaimerCard
            }
            .padding(.horizontal, theme.pagePadding)
            .padding(.vertical, theme.spacing)
        }
        .scrollIndicators(.hidden)
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("AI 财务日志诊断")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            localModel.prepare()
        }
    }

    private var introCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(theme.rowIconFont)
                        .foregroundStyle(theme.accentText)

                    Text("最近 30 天 · 本地只读分析")
                        .font(theme.sectionTitleFont)
                        .foregroundStyle(theme.primaryText)
                }

                Text("从本机提取最近 30 天的分类、金额、时间和账户，拼成结构化纯文本，再交给内置 Qwen2.5-0.5B。分析结果只用于参考，不会写账或修改任何流水。")
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Label("不上传", systemImage: "lock.fill")
                    Label("不写账", systemImage: "pencil.slash")
                }
                .font(theme.badgeFont)
                .foregroundStyle(theme.income)
            }
        }
    }

    private var statusCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("分析状态")
                        .font(theme.sectionTitleFont)
                        .foregroundStyle(theme.primaryText)

                    Spacer()

                    Text(localModel.status.summary)
                        .font(theme.badgeFont)
                        .foregroundStyle(
                            localModel.status.isReady ? theme.income : theme.warning
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                if let digest {
                    HStack(spacing: 10) {
                        statusMetric("流水", value: "\(digest.transactionCount) 笔")
                        statusMetric("明细", value: "\(digest.listedCount) 条")
                        statusMetric("净结余", value: MoneyFormat.currency(digest.net))
                    }
                } else {
                    Text("点击下方按钮后才会读取本机流水。模拟器不会加载 0.5B，真机才会尝试加载。")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func statusMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(theme.badgeFont)
                .foregroundStyle(theme.secondaryText)
            Text(value)
                .font(theme.badgeFont.weight(.semibold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(theme.surfaceElevated, in: RoundedRectangle(
            cornerRadius: theme.controlRadius,
            style: .continuous
        ))
    }

    private var analyzeButton: some View {
        Button {
            Task { @MainActor in
                await analyze()
            }
        } label: {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(theme.onAccent)
                } else {
                    Image(systemName: "sparkles")
                }

                Text(buttonTitle)
                    .font(theme.buttonLabelFont)
            }
            .foregroundStyle(theme.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(theme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.72 : 1)
        .accessibilityHint("提取最近 30 天流水并调用本地模型")
    }

    private var buttonTitle: String {
        switch phase {
        case .building:
            return "正在提取最近 30 天流水…"
        case .generating:
            return "0.5B 正在分析…"
        default:
            return "开始分析近期账单"
        }
    }

    private func errorCard(_ message: String) -> some View {
        LedgerCard {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(theme.warning)

                VStack(alignment: .leading, spacing: 4) {
                    Text("这次没有生成分析")
                        .font(theme.bodyFont.weight(.semibold))
                        .foregroundStyle(theme.primaryText)

                    Text(message)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("流水摘要和完整 Prompt 已保留在下方，方便排查或复制到其它模型。")
                        .font(theme.badgeFont)
                        .foregroundStyle(theme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func reportCard(_ report: String) -> some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("分析报告")
                        .font(theme.sectionTitleFont)
                        .foregroundStyle(theme.primaryText)

                    Spacer()

                    ShareLink(item: report) {
                        Image(systemName: "square.and.arrow.up")
                            .font(theme.controlIconFont)
                            .foregroundStyle(theme.accentText)
                    }
                    .accessibilityLabel("分享分析报告")
                }

                AIFinanceLogMarkdownView(markdown: report)
            }
        }
    }

    private func disclosureCard(title: String, text: String) -> some View {
        LedgerCard {
            DisclosureGroup {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(theme.secondaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            } label: {
                Text(title)
                    .font(theme.bodyFont.weight(.medium))
                    .foregroundStyle(theme.primaryText)
            }
            .tint(theme.accentText)
        }
    }

    private var promptCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("发送给模型的 Prompt")
                        .font(theme.sectionTitleFont)
                        .foregroundStyle(theme.primaryText)

                    Spacer()

                    ShareLink(item: prompt) {
                        Label("复制", systemImage: "square.on.square")
                            .font(theme.badgeFont)
                            .foregroundStyle(theme.accentText)
                    }
                    .accessibilityLabel("复制或分享完整 Prompt")
                }

                DisclosureGroup("查看完整 Prompt") {
                    Text(prompt)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(theme.secondaryText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
                .tint(theme.accentText)
            }
        }
    }

    private var disclaimerCard: some View {
        Text("AI 分析只作参考，不构成投资、税务或法律建议；不会自动写账、转账或修改预算。")
            .font(theme.badgeFont)
            .foregroundStyle(theme.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    @MainActor
    private func analyze() async {
        guard !isBusy else { return }

        phase = .building
        report = nil
        errorMessage = nil

        do {
            let snapshot = try AIFinanceLogDigestBuilder.build(
                context: viewContext,
                days: AIFinanceLogDigestBuilder.defaultDays
            )
            digest = snapshot

            guard snapshot.transactionCount > 0 else {
                errorMessage = "最近 30 天没有流水，先记几笔再分析。"
                phase = .failed
                return
            }

            prompt = AIFinanceLogPrompt.makePrompt(ledgerText: snapshot.text)
            phase = .generating

            guard await waitForModel() else {
                errorMessage = "本地 0.5B 不可用：\(localModel.status.summary)。真机安装并重签 Frameworks/llama.framework 后再试。"
                phase = .failed
                return
            }

            guard let output = await localModel.diagnose(prompt: prompt) else {
                errorMessage = "本地 0.5B 没有返回内容：\(localModel.lastFailure ?? localModel.status.summary)"
                phase = .failed
                return
            }

            report = output
            phase = .finished
        } catch {
            errorMessage = "读取本地流水失败：\(error.localizedDescription)"
            phase = .failed
        }
    }

    @MainActor
    private func waitForModel() async -> Bool {
        localModel.prepare()

        if localModel.status.isReady {
            return true
        }
        if case .unavailable = localModel.status {
            return false
        }
        if case .failed = localModel.status {
            return false
        }

        // A 491 MB GGUF can take a while on first load. Leave the button in the
        // generating state instead of declaring failure after one runloop tick.
        for _ in 0..<150 {
            try? await Task<Never, Never>.sleep(nanoseconds: 200_000_000)
            if localModel.status.isReady {
                return true
            }
            if case .unavailable = localModel.status {
                return false
            }
            if case .failed = localModel.status {
                return false
            }
        }
        return localModel.status.isReady
    }
}

private struct AIFinanceLogMarkdownView: View {
    let markdown: String
    @Environment(\.ledgerTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(
                Array(markdown.components(separatedBy: "\n").enumerated()),
                id: \.offset
            ) { _, rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.isEmpty {
                    Color.clear.frame(height: 2)
                } else if line.hasPrefix("### ") {
                    Text(verbatim: String(line.dropFirst(4)))
                        .font(theme.bodyFont.weight(.semibold))
                        .foregroundStyle(theme.accentText)
                        .padding(.top, 2)
                } else if line.hasPrefix("## ") {
                    Text(verbatim: String(line.dropFirst(3)))
                        .font(theme.sectionTitleFont)
                        .foregroundStyle(theme.primaryText)
                        .padding(.top, 4)
                } else if line.hasPrefix("# ") {
                    Text(verbatim: String(line.dropFirst(2)))
                        .font(theme.screenTitleFont)
                        .foregroundStyle(theme.primaryText)
                        .padding(.top, 4)
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    HStack(alignment: .top, spacing: 6) {
                        Text(verbatim: "•")
                            .foregroundStyle(theme.accentText)
                        Text(verbatim: String(line.dropFirst(2)))
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if let dot = line.firstIndex(of: "."),
                          line[line.startIndex..<dot].allSatisfy({ $0.isNumber }) {
                    HStack(alignment: .top, spacing: 6) {
                        Text(verbatim: String(line[line.startIndex...dot]))
                            .foregroundStyle(theme.accentText)
                        Text(verbatim: String(line[line.index(after: dot)...]))
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(verbatim: line)
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
