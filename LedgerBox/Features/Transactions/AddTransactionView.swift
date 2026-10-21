import CoreData
import Foundation
import SwiftUI

struct AddTransactionView: View {
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

    @State private var type: TransactionType = .expense
    @State private var amountText = ""
    @State private var selectedAccountID: UUID?
    @State private var selectedToAccountID: UUID?
    @State private var selectedCategoryID: UUID?
    @State private var date = Date()
    @State private var note = ""
    @State private var errorMessage: String?

    // One focus binding drives every dismissal path (keyboard "完成", blank
    // tap, save, cancel). Focus never feeds `canSave`, so validation is
    // unchanged.
    @FocusState private var focusedField: InputField?

    private enum InputField: Hashable {
        case amount
        case note
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: theme.spacing) {
                    typePicker
                    amountCard
                    detailsCard
                }
                .padding(.horizontal, theme.pagePadding)
                .padding(.vertical, theme.spacing)
                .keyboardDismissOnBlankTap { focusedField = nil }
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneBar { focusedField = nil }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("记一笔")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        focusedField = nil
                        dismiss()
                    }
                    .foregroundStyle(theme.secondaryText)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(canSave ? theme.accent : theme.secondaryText)
                    .disabled(!canSave)
                }
            }
        }
        .tint(theme.accent)
        .presentationDragIndicator(.visible)
        .onAppear {
            seedSelections()
        }
        .onChange(of: type) { _, _ in
            normalizeSelection()
        }
        .alert(
            "无法保存",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { newValue in
                    if !newValue {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var typePicker: some View {
        HStack(spacing: 4) {
            ForEach(TransactionType.allCases) { item in
                Button {
                    withAnimation(.snappy) {
                        type = item
                    }
                } label: {
                    Text(item.displayName)
                        .font(theme.captionFont)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(type == item ? theme.onAccent : theme.secondaryText)
                        .background(
                            type == item ? theme.accent : Color.clear,
                            in: RoundedRectangle(
                                cornerRadius: theme.controlRadius,
                                style: .continuous
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            theme.surface,
            in: RoundedRectangle(
                cornerRadius: theme.segmentRadius,
                style: .continuous
            )
        )
    }

    private var amountCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: theme.smallSpacing) {
                Text("金额")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("¥")
                        .font(theme.currencySymbolFont)
                        .foregroundStyle(theme.secondaryText)

                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .amount)
                        .font(theme.amountFont)
                        .foregroundStyle(theme.primaryText)
                        .textFieldStyle(.plain)
                        .onChange(of: amountText) { _, newValue in
                            sanitizeAmount(newValue)
                        }
                }

                Text("金额会立即计入账户余额与本月统计。")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
            }
            .keyboardDismissOnBlankTap { focusedField = nil }
        }
    }

    private var detailsCard: some View {
        LedgerCard {
            VStack(spacing: 0) {
                detailRow(title: "账户") {
                    Picker("账户", selection: $selectedAccountID) {
                        Text("请选择").tag(Optional<UUID>.none)
                        ForEach(accounts, id: \.objectID) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(theme.accent)
                }

                if (type == .expense || type == .transfer),
                   selectedAccount?.accountType == .goal {
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(theme.captionFont)

                        Text("这是目标专户，只建议转入、不建议直接支出或转出；否则会破坏储蓄纪律。")
                            .font(theme.captionFont)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(theme.warning)
                    .padding(.vertical, 8)
                }

                if type == .transfer {
                    divider

                    detailRow(title: "转入账户") {
                        Picker("转入账户", selection: $selectedToAccountID) {
                            Text("请选择").tag(Optional<UUID>.none)
                            ForEach(destinationAccounts, id: \.objectID) { account in
                                Text(account.name).tag(Optional(account.id))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(theme.accent)
                    }
                } else {
                    divider

                    detailRow(title: "分类") {
                        Picker("分类", selection: $selectedCategoryID) {
                            Text("未分类").tag(Optional<UUID>.none)
                            ForEach(filteredCategories, id: \.objectID) { category in
                                Label(category.name, systemImage: category.icon)
                                    .tag(Optional(category.id))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(theme.accent)
                    }
                }

                divider

                HStack {
                    Text("日期")
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.primaryText)

                    Spacer(minLength: theme.smallSpacing)

                    DatePicker(
                        "日期",
                        selection: $date,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .tint(theme.accent)
                }
                .padding(.vertical, 11)

                divider

                HStack(alignment: .top) {
                    Text("备注")
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.primaryText)
                        .padding(.top, 2)

                    Spacer(minLength: theme.smallSpacing)

                    TextField("可选", text: $note, axis: .vertical)
                        .focused($focusedField, equals: .note)
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.primaryText)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1...3)
                        .textFieldStyle(.plain)
                }
                .padding(.vertical, 11)
            }
            .keyboardDismissOnBlankTap { focusedField = nil }
        }
    }

    private func detailRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Text(title)
                .font(theme.bodyFont)
                .foregroundStyle(theme.primaryText)

            Spacer(minLength: theme.smallSpacing)

            content()
        }
        .padding(.vertical, 7)
    }

    private var divider: some View {
        Divider()
            .overlay(theme.separator)
    }

    private var destinationAccounts: [Account] {
        accounts.filter { account in
            account.id != selectedAccountID
        }
    }

    private var selectedAccount: Account? {
        accounts.first { $0.id == selectedAccountID }
    }

    private var filteredCategories: [Category] {
        let targetKind: CategoryKind = type == .income ? .income : .expense
        return categories.filter { category in
            category.categoryKind == targetKind && category.isSelectable
        }
    }

    private var parsedAmount: Decimal? {
        let normalized = amountText.replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else {
            return nil
        }
        return Decimal(
            string: normalized,
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private var canSave: Bool {
        guard let parsedAmount, parsedAmount > 0, selectedAccountID != nil else {
            return false
        }
        if type == .transfer {
            guard let selectedAccountID, let selectedToAccountID else {
                return false
            }
            return selectedAccountID != selectedToAccountID
        }
        return true
    }

    private func seedSelections() {
        if selectedAccountID == nil {
            selectedAccountID = accounts.first?.id
        }
        if selectedToAccountID == nil {
            selectedToAccountID = destinationAccounts.first?.id
        }
        if selectedCategoryID == nil {
            selectedCategoryID = filteredCategories.first?.id
        }
        normalizeSelection()
    }

    private func normalizeSelection() {
        if !accounts.contains(where: { $0.id == selectedAccountID }) {
            selectedAccountID = accounts.first?.id
        }

        if type == .transfer {
            if selectedToAccountID == selectedAccountID ||
                !accounts.contains(where: { $0.id == selectedToAccountID }) {
                selectedToAccountID = destinationAccounts.first?.id
            }
        } else {
            selectedToAccountID = nil
        }

        if !filteredCategories.contains(where: { $0.id == selectedCategoryID }) {
            selectedCategoryID = filteredCategories.first?.id
        }
    }

    private func sanitizeAmount(_ rawValue: String) {
        var filtered = rawValue.replacingOccurrences(of: ",", with: ".")
        filtered = String(filtered.filter { $0.isNumber || $0 == "." })

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
        focusedField = nil

        guard let amount = parsedAmount, amount > 0 else {
            errorMessage = "请输入大于 0 的有效金额。"
            return
        }

        guard
            let selectedAccountID,
            let account = accounts.first(where: { $0.id == selectedAccountID })
        else {
            errorMessage = "请选择账户。"
            return
        }

        var toAccount: Account?
        if type == .transfer {
            guard
                let selectedToAccountID,
                let destination = accounts.first(where: { $0.id == selectedToAccountID }),
                destination.id != account.id
            else {
                errorMessage = "请选择不同的转入账户。"
                return
            }
            toAccount = destination
        }

        let selectedCategory = type == .transfer
            ? nil
            : filteredCategories.first(where: { $0.id == selectedCategoryID })

        do {
            try LedgerService.record(
                type: type,
                amount: amount,
                date: date,
                note: note,
                account: account,
                toAccount: toAccount,
                category: selectedCategory,
                in: viewContext
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview("记账 · 浅色") {
    AddTransactionView()
        .environment(
            \.managedObjectContext,
            PersistenceController.preview.container.viewContext
        )
        .environment(\.ledgerTheme, Theme.palette(for: .light))
}

#Preview("记账 · 深色") {
    AddTransactionView()
        .environment(
            \.managedObjectContext,
            PersistenceController.preview.container.viewContext
        )
        .environment(\.ledgerTheme, Theme.palette(for: .dark))
}
