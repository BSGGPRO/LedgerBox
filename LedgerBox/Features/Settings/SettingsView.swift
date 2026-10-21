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
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.accentText)
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
                        prepareExport()
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

                    Rectangle()
                        .fill(theme.separator)
                        .frame(height: theme.hairline)
                        .padding(.leading, theme.cardPadding)

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
                FinanceAdvisorView()
            } label: {
                LedgerCard {
                    SettingsRow(
                        theme: theme,
                        icon: "brain.head.profile",
                        tint: theme.accentText,
                        title: "财务大脑",
                        subtitle: "40 个记账意图 · 20,971,560 参数 · 离线",
                        trailingText: "本地",
                        trailingTint: theme.income
                    )
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("打开离线的财务专用小模型")
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
