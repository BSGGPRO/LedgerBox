import CoreData
import Foundation
import SwiftUI

// MARK: - Quick entry panel

struct QuickEntryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ledgerTheme) private var theme

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

    @State private var text = ""
    @State private var parsed: QuickEntryParser.ParsedEntry?
    @State private var selectedType: TransactionType?
    @State private var selectedCategoryID: UUID?
    @State private var selectedAccountID: UUID?
    @State private var autoType: TransactionType?
    @State private var autoCategoryID: UUID?
    @State private var autoAccountID: UUID?

    // These flags distinguish "not touched yet" from "the user explicitly
    // cleared this field". A nil selection alone cannot tell them apart.
    @State private var typeManuallyEdited = false
    @State private var categoryManuallyEdited = false
    @State private var accountManuallyEdited = false
    @State private var date = Date()
    @State private var amountText = ""
    @State private var lastAutoAmount = ""
    @State private var note = ""
    @State private var lastAutoRemark = ""
    @State private var alert: QuickEntryAlert?
    @FocusState private var inputFocused: Bool

    private let parser = QuickEntryParser()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: theme.spacing) {
                    inputCard
                    aiCard
                    previewCard
                    detailsCard
                    saveButton
                }
                .padding(.horizontal, theme.pagePadding)
                .padding(.vertical, theme.spacing)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("AI 记账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                    .foregroundStyle(theme.secondaryText)
                }
            }
        }
        .tint(theme.accent)
        .presentationDragIndicator(.visible)
        .onAppear {
            reparse()
        }
        .onChange(of: text) { _, _ in
            reparse()
        }
        .onChange(of: amountText) { _, newValue in
            sanitizeAmount(newValue)
        }
        .onChange(of: categorySignature) { _, _ in
            normalizeSelection()
            reparse()
        }
        .onChange(of: accounts.count) { _, _ in
            reparse()
        }
        .alert(item: $alert) { item in
            Alert(
                title: Text("小 AI 记账"),
                message: Text(item.message),
                dismissButton: .default(Text("好"))
            )
        }
    }

    // MARK: - Cards

    private var inputCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: theme.smallSpacing) {
                HStack(spacing: 8) {
                    Text("告诉小 AI 一笔账")
                        .font(theme.sectionTitleFont)
                        .foregroundStyle(theme.primaryText)

                    Spacer(minLength: 4)

                    Label("本地", systemImage: "sparkles")
                        .font(theme.badgeFont)
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(theme.accent.opacity(0.10), in: Capsule())
                }

                HStack(alignment: .bottom, spacing: theme.smallSpacing) {
                    TextField("例如：微信买奶茶 15 元", text: $text, axis: .vertical)
                        .focused($inputFocused)
                        .font(theme.bodyFont)
                        .lineLimit(3...6)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(
                            theme.surfaceElevated,
                            in: RoundedRectangle(
                                cornerRadius: theme.controlRadius,
                                style: .continuous
                            )
                        )

                    Button {
                        inputFocused = false
                        reparse()
                    } label: {
                        Image(systemName: "sparkles")
                            .font(theme.headerActionFont)
                            .foregroundStyle(theme.onAccent)
                            .frame(width: 48, height: 48)
                            .background(theme.accent, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("让小 AI 重新理解这段文字")
                }

                Text("小 AI 只在本机拆文本：金额、收支、分类、账户；不会上传，也不会假装成云端大模型。")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(QuickEntryAI.examples, id: \.self) { example in
                            Button {
                                text = example
                                inputFocused = false
                            } label: {
                                Text(example)
                                    .font(theme.captionFont)
                                    .foregroundStyle(theme.secondaryText)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(theme.surfaceElevated, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var aiCard: some View {
        let insight = aiInsight

        return LedgerCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(theme.rowIconFont)
                        .foregroundStyle(aiColor(insight.state))

                    Text(insight.title)
                        .font(theme.bodyFont.weight(.semibold))
                        .foregroundStyle(theme.primaryText)

                    Spacer(minLength: 4)

                    Text("\(insight.recognizedFields)/\(insight.totalFields)")
                        .font(theme.badgeFont)
                        .foregroundStyle(theme.secondaryText)
                }

                Text(insight.detail)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                ProgressView(value: Double(insight.confidence), total: 100)
                    .tint(aiColor(insight.state))

                HStack {
                    Text("字段完整度")
                    Spacer()
                    Text("\(insight.confidence)%")
                }
                .font(theme.badgeFont)
                .foregroundStyle(theme.secondaryText)
            }
        }
    }

    private var previewCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("识别结果")
                        .font(theme.sectionTitleFont)
                        .foregroundStyle(theme.primaryText)

                    Spacer()

                    Text(canSave ? "可保存" : "待补全")
                        .font(theme.badgeFont)
                        .foregroundStyle(canSave ? theme.income : theme.warning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            (canSave ? theme.income : theme.warning).opacity(0.12),
                            in: Capsule()
                        )
                }

                if parsed == nil {
                    Text("输入一句话，例如“微信买奶茶 15 元”。")
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.secondaryText)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(effectiveType?.displayName ?? "待选择")
                            .font(theme.captionFont)
                            .foregroundStyle(typeColor)

                        Text(amountValue.map { MoneyFormat.currency($0) } ?? "未识别金额")
                            .font(theme.moneyFont)
                            .foregroundStyle(theme.primaryText)
                    }

                    HStack(spacing: 8) {
                        summaryChip(title: "分类", value: effectiveCategory?.name ?? "待选择")
                        summaryChip(title: "账户", value: effectiveAccount?.name ?? "待选择")
                    }

                    if effectiveCategory == nil, !filteredCategories.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("小 AI 建议")
                                .font(theme.badgeFont)
                                .foregroundStyle(theme.secondaryText)

                            ScrollView(.horizontal) {
                                HStack(spacing: 8) {
                                    ForEach(Array(filteredCategories.prefix(5)), id: \.id) { category in
                                        Button {
                                            if effectiveType == nil {
                                                selectedType = category.categoryKind == .income ? .income : .expense
                                            }
                                            categorySelection.wrappedValue = category.id
                                        } label: {
                                            Text(category.name)
                                                .font(theme.captionFont)
                                                .foregroundStyle(theme.accent)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(theme.accent.opacity(0.10), in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .scrollIndicators(.hidden)
                        }
                    }

                    if effectiveAccount == nil, !accounts.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("小 AI 常用账户")
                                .font(theme.badgeFont)
                                .foregroundStyle(theme.secondaryText)

                            ScrollView(.horizontal) {
                                HStack(spacing: 8) {
                                    ForEach(Array(accounts.prefix(4)), id: \.id) { account in
                                        Button {
                                            accountSelection.wrappedValue = account.id
                                        } label: {
                                            Text(account.name)
                                                .font(theme.captionFont)
                                                .foregroundStyle(theme.accent)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(theme.accent.opacity(0.10), in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .scrollIndicators(.hidden)
                        }
                    }

                    if !visibleIssues.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(visibleIssues.prefix(3)), id: \.rawValue) { issue in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text(issue.message)
                                        .font(theme.captionFont)
                                }
                                .foregroundStyle(theme.warning)
                            }
                        }
                    } else if !canSave {
                        Text("补全金额、分类和账户后即可保存。")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
            }
        }
    }

    private var detailsCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("补全信息")
                    .font(theme.sectionTitleFont)
                    .foregroundStyle(theme.primaryText)

                typeSelector
                amountRow
                categoryPicker
                accountPicker
                datePicker
                noteField
            }
        }
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            HStack(spacing: theme.smallSpacing) {
                Image(systemName: "checkmark.circle.fill")
                Text("保存并回首页")
            }
            .font(theme.buttonLabelFont)
            .foregroundStyle(canSave ? theme.onAccent : theme.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                canSave ? theme.accent : theme.surfaceElevated,
                in: RoundedRectangle(
                    cornerRadius: theme.controlRadius,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .accessibilityHint("保存后首页流水和余额会自动刷新")
    }

    // MARK: - Form pieces

    private var categorySelection: Binding<UUID?> {
        Binding(
            get: { selectedCategoryID },
            set: { newValue in
                selectedCategoryID = newValue
                autoCategoryID = nil
                categoryManuallyEdited = true
            }
        )
    }

    private var accountSelection: Binding<UUID?> {
        Binding(
            get: { selectedAccountID },
            set: { newValue in
                selectedAccountID = newValue
                autoAccountID = nil
                accountManuallyEdited = true
            }
        )
    }

    private func selectType(_ type: TransactionType) {
        // Tapping the already-selected type pins it against later parser
        // changes; it must still be treated as a manual choice.
        typeManuallyEdited = true
        autoType = nil

        guard selectedType != type else {
            normalizeSelection()
            reparseIfTextPresent()
            return
        }

        selectedType = type

        // Categories are kind-specific. A manual type switch invalidates the
        // old category and lets the parser suggest one for the new kind.
        selectedCategoryID = nil
        autoCategoryID = nil
        categoryManuallyEdited = false

        normalizeSelection()
        reparseIfTextPresent()
    }

    private func reparseIfTextPresent() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        reparse()
    }

    private var typeSelector: some View {
        HStack(spacing: 8) {
            ForEach([TransactionType.expense, TransactionType.income]) { type in
                Button {
                    selectType(type)
                } label: {
                    Text(type.displayName)
                        .font(theme.buttonLabelFont)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(
                            effectiveType == type ? theme.onAccent : theme.secondaryText
                        )
                        .background(
                            effectiveType == type ? theme.accent : theme.surfaceElevated,
                            in: RoundedRectangle(
                                cornerRadius: theme.controlRadius,
                                style: .continuous
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var amountRow: some View {
        HStack(spacing: 12) {
            Text("金额")
                .font(theme.captionFont)
                .foregroundStyle(theme.secondaryText)

            Spacer(minLength: 8)

            TextField("0.00", text: $amountText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(theme.rowMoneyFont)
                .foregroundStyle(theme.primaryText)
                .frame(maxWidth: 160)
        }
        .padding(.vertical, 2)
    }

    private var categoryPicker: some View {
        Picker("分类", selection: categorySelection) {
            Text("请选择").tag(Optional<UUID>.none)
            ForEach(filteredCategories, id: \.id) { category in
                Text(category.name).tag(Optional(category.id))
            }
        }
        .pickerStyle(.menu)
        .tint(theme.accent)
    }

    private var accountPicker: some View {
        Picker("账户", selection: accountSelection) {
            Text("请选择").tag(Optional<UUID>.none)
            ForEach(accounts, id: \.id) { account in
                Text(account.name).tag(Optional(account.id))
            }
        }
        .pickerStyle(.menu)
        .tint(theme.accent)
    }

    private var datePicker: some View {
        DatePicker(
            "日期",
            selection: $date,
            in: ...Date(),
            displayedComponents: .date
        )
        .font(theme.captionFont)
        .foregroundStyle(theme.secondaryText)
    }

    private var noteField: some View {
        TextField("备注", text: $note)
            .font(theme.bodyFont)
            .foregroundStyle(theme.primaryText)
            .padding(12)
            .background(
                theme.surfaceElevated,
                in: RoundedRectangle(
                    cornerRadius: theme.controlRadius,
                    style: .continuous
                )
            )
    }

    private func summaryChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(theme.badgeFont)
                .foregroundStyle(theme.secondaryText)
            Text(value)
                .font(theme.captionFont)
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            theme.surfaceElevated,
            in: RoundedRectangle(
                cornerRadius: theme.controlRadius,
                style: .continuous
            )
        )
    }

    // MARK: - State

    private var categoryOptions: [QuickEntryParser.CategoryOption] {
        categories
            .filter { $0.isSelectable }
            .map {
                QuickEntryParser.CategoryOption(
                    id: $0.id,
                    name: $0.name,
                    kind: $0.categoryKind
                )
            }
    }

    private var accountOptions: [QuickEntryParser.AccountOption] {
        accounts.map {
            QuickEntryParser.AccountOption(id: $0.id, name: $0.name)
        }
    }

    private var effectiveType: TransactionType? {
        selectedType ?? parsed?.type
    }

    private var categoryKindForSelection: CategoryKind {
        effectiveType == .income ? .income : .expense
    }

    // Count alone misses soft-deletes, which keep the row count unchanged.
    private var categorySignature: [String] {
        categories.map {
            [
                $0.id.uuidString,
                String($0.isSoftDeleted),
                $0.kind,
                $0.name
            ].joined(separator: "|")
        }
    }

    private var filteredCategories: [Category] {
        categories.filter {
            $0.isSelectable && $0.categoryKind == categoryKindForSelection
        }
    }

    private var effectiveCategory: Category? {
        guard
            let selectedCategoryID,
            let effectiveType
        else {
            return nil
        }

        let kind: CategoryKind = effectiveType == .income ? .income : .expense
        return categories.first {
            $0.id == selectedCategoryID
                && $0.isSelectable
                && $0.categoryKind == kind
        }
    }

    private var effectiveAccount: Account? {
        guard let selectedAccountID else {
            return nil
        }
        return accounts.first { $0.id == selectedAccountID }
    }

    private var amountValue: Decimal? {
        let normalized = amountText.replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else {
            return nil
        }
        return Decimal(
            string: normalized,
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private var typeColor: Color {
        if effectiveType == .income {
            return theme.income
        }
        if effectiveType == .expense {
            return theme.expense
        }
        return theme.secondaryText
    }

    private var hasBlockingIssue: Bool {
        guard let parsed else {
            return false
        }
        return parsed.issues.contains {
            $0 == .multipleAmounts || $0 == .inputTooLong
        }
    }

    private var visibleIssues: [QuickEntryParser.Issue] {
        guard let parsed else {
            return []
        }

        return parsed.issues.filter { issue in
            switch issue {
            case .missingAmount:
                return amountValue == nil
            case .invalidAmount, .negativeAmount:
                return amountValue == nil || (amountValue ?? 0) <= 0
            case .missingType, .ambiguousType:
                return effectiveType == nil
            case .missingCategory, .ambiguousCategory:
                return effectiveCategory == nil
            case .missingAccount, .ambiguousAccount:
                return effectiveAccount == nil
            case .multipleAmounts, .inputTooLong:
                return true
            case .emptyInput:
                return false
            }
        }
    }

    private var canSave: Bool {
        guard
            let amountValue,
            amountValue > 0,
            effectiveType != nil,
            effectiveCategory != nil,
            effectiveAccount != nil,
            date <= Date(),
            !hasBlockingIssue
        else {
            return false
        }
        return true
    }

    private var aiInsight: QuickEntryAI.Insight {
        QuickEntryAI.insight(
            text: text,
            parsed: parsed,
            canSave: canSave,
            visibleIssueCount: visibleIssues.count,
            type: effectiveType,
            amount: amountValue,
            categoryName: effectiveCategory?.name,
            accountName: effectiveAccount?.name
        )
    }

    private func aiColor(_ state: QuickEntryAI.State) -> Color {
        switch state {
        case .idle:
            return theme.accent
        case .ready:
            return theme.income
        case .needsInfo:
            return theme.warning
        case .blocked:
            return theme.expense
        }
    }

    // MARK: - Actions

    private func reparse() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            parsed = nil
            selectedType = nil
            selectedCategoryID = nil
            selectedAccountID = nil
            autoType = nil
            autoCategoryID = nil
            autoAccountID = nil
            typeManuallyEdited = false
            categoryManuallyEdited = false
            accountManuallyEdited = false
            if amountText == lastAutoAmount {
                amountText = ""
                lastAutoAmount = ""
            }
            if note == lastAutoRemark {
                note = ""
                lastAutoRemark = ""
            }
            return
        }

        let result = parser.parse(
            trimmed,
            categories: categoryOptions,
            accounts: accountOptions
        )
        parsed = result

        // Only follow the parser while the field is untouched or still holds the
        // parser's previous suggestion. Once the user overrides a field, keep it.
        if let type = result.type {
            if !typeManuallyEdited,
               (selectedType == nil || selectedType == autoType) {
                autoType = type
                selectedType = type
            }
        } else if !typeManuallyEdited, selectedType == autoType {
            selectedType = nil
            autoType = nil
        }

        if let category = result.category {
            if !categoryManuallyEdited,
               selectedCategoryID == nil || selectedCategoryID == autoCategoryID {
                autoCategoryID = category.id
                selectedCategoryID = category.id
            }
        } else if !categoryManuallyEdited, selectedCategoryID == autoCategoryID {
            selectedCategoryID = nil
            autoCategoryID = nil
        }

        if let account = result.account {
            if !accountManuallyEdited,
               selectedAccountID == nil || selectedAccountID == autoAccountID {
                autoAccountID = account.id
                selectedAccountID = account.id
            }
        } else if !accountManuallyEdited, selectedAccountID == autoAccountID {
            selectedAccountID = nil
            autoAccountID = nil
        }

        if let amount = result.amount {
            let formatted = MoneyFormat.editable(amount)
            if amountText.isEmpty || amountText == lastAutoAmount {
                amountText = formatted
                lastAutoAmount = formatted
            }
        } else if amountText == lastAutoAmount {
            amountText = ""
            lastAutoAmount = ""
        }

        if note.isEmpty || note == lastAutoRemark {
            note = result.remark
            lastAutoRemark = result.remark
        }

        normalizeSelection()
    }

    private func normalizeSelection() {
        let validCategoryIDs = Set(filteredCategories.map(\.id))
        if let selectedCategoryID, !validCategoryIDs.contains(selectedCategoryID) {
            self.selectedCategoryID = nil
            autoCategoryID = nil
            // The row disappeared or the type changed; this was not an
            // intentional clear, so allow the parser to suggest again.
            categoryManuallyEdited = false
        }

        if let selectedAccountID,
           !accounts.contains(where: { $0.id == selectedAccountID }) {
            self.selectedAccountID = nil
            autoAccountID = nil
            accountManuallyEdited = false
        }
    }

    private func sanitizeAmount(_ rawValue: String) {
        var filtered = rawValue.replacingOccurrences(of: ",", with: ".")
        filtered = String(filtered.filter { "0123456789.".contains($0) })

        let parts = filtered.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count > 2 {
            filtered = String(parts[0]) + "." + String(parts[1])
        }

        if let dotIndex = filtered.firstIndex(of: ".") {
            let decimals = filtered.distance(
                from: filtered.index(after: dotIndex),
                to: filtered.endIndex
            )
            if decimals > 2 {
                let cutoff = filtered.index(dotIndex, offsetBy: 3)
                filtered = String(filtered[..<cutoff])
            }
        }

        if filtered != rawValue {
            amountText = filtered
        }
    }

    private func save() {
        guard
            let amountValue,
            amountValue > 0,
            let type = effectiveType,
            let category = effectiveCategory,
            let account = effectiveAccount
        else {
            alert = QuickEntryAlert(message: "请补全金额、收支、分类和账户。")
            return
        }

        guard date <= Date() else {
            alert = QuickEntryAlert(message: "记账日期不能晚于当前时间。")
            return
        }

        guard !hasBlockingIssue else {
            alert = QuickEntryAlert(message: "当前输入存在多笔金额或超长内容，请缩短后再保存。")
            return
        }

        do {
            try LedgerService.record(
                type: type,
                amount: amountValue,
                date: date,
                note: note,
                account: account,
                category: category,
                in: viewContext
            )
            dismiss()
        } catch {
            alert = QuickEntryAlert(message: error.localizedDescription)
        }
    }
}

private struct QuickEntryAlert: Identifiable {
    let id = UUID()
    let message: String
}

#Preview("极速记账 · 浅色") {
    QuickEntryView()
        .environment(
            \.managedObjectContext,
            PersistenceController.preview.container.viewContext
        )
        .environment(\.ledgerTheme, Theme.palette(for: .light))
}

#Preview("极速记账 · 深色") {
    QuickEntryView()
        .environment(
            \.managedObjectContext,
            PersistenceController.preview.container.viewContext
        )
        .environment(\.ledgerTheme, Theme.palette(for: .dark))
}
