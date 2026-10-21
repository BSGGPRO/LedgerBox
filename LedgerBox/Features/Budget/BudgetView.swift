import CoreData
import Foundation
import SwiftUI

struct BudgetView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.ledgerTheme) private var theme

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Budget.startDate, ascending: true)],
        animation: .snappy
    )
    private var budgets: FetchedResults<Budget>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Category.sortOrder, ascending: true)],
        animation: .snappy
    )
    private var categories: FetchedResults<Category>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \LedgerTransaction.date, ascending: false)],
        animation: .snappy
    )
    private var transactions: FetchedResults<LedgerTransaction>

    @State private var showingEditor = false
    @State private var editingBudget: Budget?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: theme.spacing) {
                    if activeBudgets.isEmpty {
                        emptyState
                    } else {
                        overviewCard
                        totalBudgetSection
                        categoryBudgetSection
                    }

                    if !disabledBudgets.isEmpty {
                        disabledSection
                    }
                }
                .padding(.horizontal, theme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("预算")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        presentEditor(for: nil)
                    } label: {
                        Image(systemName: "plus")
                            .font(theme.controlIconFont)
                    }
                    .accessibilityLabel("新增预算")
                }
            }
        }
        .sheet(isPresented: $showingEditor, onDismiss: {
            editingBudget = nil
        }) {
            BudgetEditorView(budget: editingBudget)
                .environment(\.managedObjectContext, viewContext)
                .environment(\.ledgerTheme, theme)
        }
    }

    private var overviewCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: theme.smallSpacing) {
                Text("预算总览")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)

                HStack(alignment: .firstTextBaseline, spacing: theme.smallSpacing) {
                    Text(MoneyFormat.currency(overviewProgress.spent))
                        .font(theme.moneyFont)
                        .foregroundStyle(theme.primaryText)
                        .contentTransition(.numericText())

                    Text("/ \(MoneyFormat.currency(overviewProgress.limit))")
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.secondaryText)
                }

                ProgressView(value: overviewProgress.ratio)
                    .tint(overviewProgress.isOverBudget ? theme.expense : theme.accent)

                Text(overviewMessage)
                    .font(theme.captionFont)
                    .foregroundStyle(overviewProgress.isOverBudget ? theme.expense : theme.secondaryText)
            }
            .animation(.snappy, value: overviewProgress)
        }
    }

    private var totalBudgetSection: some View {
        VStack(spacing: theme.smallSpacing) {
            LedgerSectionHeader(title: "总预算")

            if totalBudgets.isEmpty {
                LedgerCard {
                    Text("还没有设置总预算。总预算会约束全部支出。")
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.secondaryText)
                }
            } else {
                ForEach(totalBudgets, id: \.objectID) { budget in
                    budgetButton(for: budget)
                }
            }
        }
    }

    private var categoryBudgetSection: some View {
        VStack(spacing: theme.smallSpacing) {
            LedgerSectionHeader(title: "分类预算")

            if categoryBudgets.isEmpty {
                LedgerCard {
                    Text("还没有分类预算。可为餐饮、交通等分类单独设限。")
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.secondaryText)
                }
            } else {
                ForEach(categoryBudgets, id: \.objectID) { budget in
                    budgetButton(for: budget)
                }
            }
        }
    }

    private var disabledSection: some View {
        VStack(spacing: theme.smallSpacing) {
            LedgerSectionHeader(title: "已停用")

            ForEach(disabledBudgets, id: \.objectID) { budget in
                budgetButton(for: budget)
                    .opacity(0.65)
            }
        }
    }

    private func budgetButton(for budget: Budget) -> some View {
        Button {
            presentEditor(for: budget)
        } label: {
            BudgetRow(
                budget: budget,
                category: category(for: budget),
                progress: progress(for: budget),
                theme: theme
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        LedgerCard {
            VStack(spacing: theme.smallSpacing) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(theme.emptyStateIconFont)
                    .foregroundStyle(theme.secondaryText)

                Text("还没有预算")
                    .font(theme.sectionTitleFont)
                    .foregroundStyle(theme.primaryText)

                Text("先设一个总预算，再给餐饮、奶茶等分类单独设限。")
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)

                Button("新增预算") {
                    presentEditor(for: nil)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        }
    }

    private var activeBudgets: [Budget] {
        budgets.filter { $0.enabled }
    }

    private var disabledBudgets: [Budget] {
        budgets.filter { !$0.enabled }
    }

    private var totalBudgets: [Budget] {
        activeBudgets.filter { $0.categoryId == nil }
    }

    private var categoryBudgets: [Budget] {
        activeBudgets.filter { $0.categoryId != nil }
    }

    private var overviewProgress: BudgetProgress {
        let limit = totalBudgets.reduce(Decimal.zero) { $0 + $1.limitValue }
        let spent = totalBudgets.reduce(Decimal.zero) { partial, budget in
            partial + progress(for: budget).spent
        }
        return FinanceEngine.budgetProgress(limit: limit, spent: spent)
    }

    private var overviewMessage: String {
        if overviewProgress.limit == 0 {
            return "未设置总预算，分类预算仍会独立计算。"
        }
        if overviewProgress.isOverBudget {
            return "已超支 \(MoneyFormat.currency(-overviewProgress.remaining))"
        }
        return "本月还可使用 \(MoneyFormat.currency(overviewProgress.remaining))"
    }

    private func category(for budget: Budget) -> Category? {
        guard let categoryID = budget.categoryId else {
            return nil
        }
        return categories.first { $0.id == categoryID }
    }

    private func progress(for budget: Budget) -> BudgetProgress {
        let interval = FinanceEngine.interval(
            for: budget.budgetPeriod,
            containing: Date()
        )
        let spent = FinanceEngine.spending(
            categoryID: budget.categoryId,
            transactions: Array(transactions),
            in: interval
        )
        return FinanceEngine.budgetProgress(limit: budget.limitValue, spent: spent)
    }

    private func presentEditor(for budget: Budget?) {
        editingBudget = budget
        showingEditor = true
    }
}

private struct BudgetRow: View {
    let budget: Budget
    let category: Category?
    let progress: BudgetProgress
    let theme: Theme

    var body: some View {
        LedgerCard {
            VStack(spacing: theme.smallSpacing) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(theme.surfaceElevated)
                            .frame(width: theme.iconCircleSize, height: theme.iconCircleSize)

                        Image(systemName: category?.icon ?? "chart.pie.fill")
                            .font(theme.rowIconFont)
                            .foregroundStyle(progress.isOverBudget ? theme.expense : theme.accent)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(category?.name ?? (budget.categoryId == nil ? "总预算" : "已删除分类"))
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.primaryText)

                        Text(subtitle)
                            .font(theme.captionFont)
                            .foregroundStyle(progress.isOverBudget ? theme.expense : theme.secondaryText)
                    }

                    Spacer(minLength: theme.smallSpacing)

                    Text("\(MoneyFormat.currency(progress.spent)) / \(MoneyFormat.currency(progress.limit))")
                        .font(theme.rowMoneyFont)
                        .foregroundStyle(progress.isOverBudget ? theme.expense : theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                ProgressView(value: progress.ratio)
                    .tint(progress.isOverBudget ? theme.expense : theme.accent)
            }
            .animation(.snappy, value: progress)
        }
    }

    private var subtitle: String {
        if progress.isOverBudget {
            return "\(budget.budgetPeriod.displayName) · 已超支 \(MoneyFormat.currency(-progress.remaining))"
        }
        return "\(budget.budgetPeriod.displayName) · 剩余 \(MoneyFormat.currency(progress.remaining))"
    }
}

private struct BudgetEditorView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ledgerTheme) private var theme

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Category.sortOrder, ascending: true)],
        animation: .snappy
    )
    private var categories: FetchedResults<Category>

    let budget: Budget?

    @State private var limitText: String
    @State private var selectedCategoryID: UUID?
    @State private var period: BudgetPeriod
    @State private var enabled: Bool
    @State private var errorMessage: String?
    @State private var showingDeleteConfirmation = false

    init(budget: Budget?) {
        self.budget = budget
        _limitText = State(initialValue: budget.map { MoneyFormat.editable($0.limitValue) } ?? "")
        _selectedCategoryID = State(initialValue: budget?.categoryId)
        _period = State(initialValue: budget?.budgetPeriod ?? .monthly)
        _enabled = State(initialValue: budget?.enabled ?? true)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: theme.spacing) {
                    amountCard
                    configurationCard

                    if budget != nil {
                        deleteButton
                    }
                }
                .padding(.horizontal, theme.pagePadding)
                .padding(.vertical, theme.spacing)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle(budget == nil ? "新增预算" : "编辑预算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
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
        .confirmationDialog(
            "删除这个预算？",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除预算", role: .destructive) {
                deleteBudget()
            }
            Button("取消", role: .cancel) {
            }
        } message: {
            Text("删除后历史交易不会受影响。")
        }
    }

    private var amountCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: theme.smallSpacing) {
                Text("预算上限")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("¥")
                        .font(theme.currencySymbolFont)
                        .foregroundStyle(theme.secondaryText)

                    TextField("0.00", text: $limitText)
                        .keyboardType(.decimalPad)
                        .font(theme.amountFont)
                        .foregroundStyle(theme.primaryText)
                        .textFieldStyle(.plain)
                        .onChange(of: limitText) { _, newValue in
                            sanitizeAmount(newValue)
                        }
                }
            }
        }
    }

    private var configurationCard: some View {
        LedgerCard {
            VStack(spacing: 0) {
                HStack {
                    Text("适用范围")
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.primaryText)

                    Spacer(minLength: theme.smallSpacing)

                    Picker("适用范围", selection: $selectedCategoryID) {
                        Text("总预算").tag(Optional<UUID>.none)

                        ForEach(selectableCategories, id: \.objectID) { category in
                            Label(category.name, systemImage: category.icon)
                                .tag(Optional(category.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(theme.accent)
                }
                .padding(.vertical, 8)

                Divider()
                    .overlay(theme.separator)

                HStack {
                    Text("周期")
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.primaryText)

                    Spacer(minLength: theme.smallSpacing)

                    Picker("周期", selection: $period) {
                        ForEach(BudgetPeriod.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .tint(theme.accent)
                    .fixedSize()
                }
                .padding(.vertical, 8)

                Divider()
                    .overlay(theme.separator)

                Toggle(isOn: $enabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("启用")
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.primaryText)

                        Text("停用后不参与进度计算。")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                .tint(theme.accent)
                .padding(.vertical, 8)
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showingDeleteConfirmation = true
        } label: {
            Label("删除预算", systemImage: "trash")
                .font(theme.bodyFont)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    theme.surface,
                    in: RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.expense)
    }

    private var selectableCategories: [Category] {
        categories.filter { category in
            category.isSelectable || category.id == budget?.categoryId
        }
    }

    private var parsedLimit: Decimal? {
        let normalized = limitText.replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else {
            return nil
        }
        return Decimal(
            string: normalized,
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private var canSave: Bool {
        guard let parsedLimit else { return false }
        return parsedLimit > 0
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
            limitText = filtered
        }
    }

    private func save() {
        guard let limit = parsedLimit, limit > 0 else {
            errorMessage = "请输入大于 0 的预算上限。"
            return
        }

        if let duplicate = duplicateBudget(for: selectedCategoryID) {
            if let budget, duplicate.objectID == budget.objectID {
                // Editing the existing budget is allowed.
            } else {
                errorMessage = "这个范围已经有一个预算，请编辑原预算或先删除它。"
                return
            }
        }

        let target = budget ?? Budget(context: viewContext)
        if budget == nil {
            target.id = UUID()
            target.startDate = Date()
        }

        target.categoryId = selectedCategoryID
        target.period = period.rawValue
        target.limitAmount = NSDecimalNumber(decimal: limit.roundedToCents())
        target.enabled = enabled

        do {
            try viewContext.save()
            dismiss()
        } catch {
            viewContext.rollback()
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private func duplicateBudget(for categoryID: UUID?) -> Budget? {
        let request = Budget.fetchRequest()
        request.fetchLimit = 1

        if let categoryID {
            request.predicate = NSPredicate(format: "categoryId == %@", nsUUID(categoryID))
        } else {
            request.predicate = NSPredicate(format: "categoryId == nil")
        }

        return try? viewContext.fetch(request).first
    }

    private func deleteBudget() {
        guard let budget else { return }
        viewContext.delete(budget)

        do {
            try viewContext.save()
            dismiss()
        } catch {
            viewContext.rollback()
            errorMessage = "删除失败：\(error.localizedDescription)"
        }
    }

    private func nsUUID(_ id: UUID) -> NSUUID {
        NSUUID(uuidString: id.uuidString)!
    }
}

#Preview("预算 · 浅色") {
    BudgetView()
        .environment(
            \.managedObjectContext,
            PersistenceController.preview.container.viewContext
        )
        .environment(\.ledgerTheme, Theme.palette(for: .light))
}

#Preview("预算 · 深色") {
    BudgetView()
        .environment(
            \.managedObjectContext,
            PersistenceController.preview.container.viewContext
        )
        .environment(\.ledgerTheme, Theme.palette(for: .dark))
}
