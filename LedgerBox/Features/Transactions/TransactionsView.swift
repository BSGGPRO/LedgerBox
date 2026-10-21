import CoreData
import Foundation
import SwiftUI

struct TransactionsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.ledgerTheme) private var theme

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \LedgerTransaction.date, ascending: false)],
        animation: .snappy
    )
    private var transactions: FetchedResults<LedgerTransaction>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Category.sortOrder, ascending: true)],
        animation: .snappy
    )
    private var categories: FetchedResults<Category>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Account.sortOrder, ascending: true)],
        animation: .snappy
    )
    private var accounts: FetchedResults<Account>

    @State private var filter: TransactionFilter = .all
    @State private var searchText = ""
    @State private var showingAddTransaction = false
    @State private var pendingDelete: LedgerTransaction?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar

                if filteredTransactions.isEmpty {
                    emptyState
                } else {
                    transactionList
                }
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("流水")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .searchable(text: $searchText, prompt: "搜索备注、分类或账户")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddTransaction = true
                    } label: {
                        Image(systemName: "plus")
                            .font(theme.controlIconFont)
                    }
                    .accessibilityLabel("新增交易")
                }
            }
        }
        .sheet(isPresented: $showingAddTransaction) {
            AddTransactionView()
                .environment(\.managedObjectContext, viewContext)
                .environment(\.ledgerTheme, theme)
        }
        .confirmationDialog(
            "删除这笔交易？",
            isPresented: deleteConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                confirmDelete()
            }
            Button("取消", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text("删除后账户余额会同步回滚，预算和统计会重新计算。")
        }
        .alert(
            "操作失败",
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

    private var filterBar: some View {
        Picker("筛选", selection: $filter) {
            ForEach(TransactionFilter.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, theme.pagePadding)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private var transactionList: some View {
        List {
            ForEach(daySections) { section in
                Section {
                    ForEach(section.transactions, id: \.objectID) { transaction in
                        TransactionRow(
                            transaction: transaction,
                            category: category(for: transaction),
                            account: account(for: transaction),
                            toAccount: toAccount(for: transaction),
                            theme: theme
                        )
                        .listRowInsets(
                            EdgeInsets(
                                top: 4,
                                leading: theme.pagePadding,
                                bottom: 4,
                                trailing: theme.pagePadding
                            )
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDelete = transaction
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text(dayTitle(section.day))
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)
                        .textCase(nil)
                        .padding(.vertical, 4)
                }
                .listSectionSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.background)
    }

    private var emptyState: some View {
        VStack(spacing: theme.smallSpacing) {
            Spacer()

            Image(systemName: "list.bullet.rectangle")
                .font(theme.emptyStateIconFont)
                .foregroundStyle(theme.secondaryText)

            Text(hasAnyTransaction ? "没有匹配的流水" : "还没有流水")
                .font(theme.sectionTitleFont)
                .foregroundStyle(theme.primaryText)

            Text(
                hasAnyTransaction
                    ? "换个筛选条件，或清空搜索关键词。"
                    : "记下第一笔收入或支出，账户余额会自动更新。"
            )
            .font(theme.bodyFont)
            .foregroundStyle(theme.secondaryText)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)

            Button(hasAnyTransaction ? "清除筛选" : "记一笔") {
                if hasAnyTransaction {
                    filter = .all
                    searchText = ""
                } else {
                    showingAddTransaction = true
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hasAnyTransaction: Bool {
        !transactions.isEmpty
    }

    private var filteredTransactions: [LedgerTransaction] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return transactions.filter { transaction in
            if let type = filter.type, transaction.transactionType != type {
                return false
            }

            guard !keyword.isEmpty else {
                return true
            }

            let categoryName = category(for: transaction)?.name ?? "未分类"
            let accountName = account(for: transaction)?.name ?? "未知账户"
            let note = transaction.note ?? ""
            let haystack = "\(note) \(categoryName) \(accountName) \(transaction.transactionType.displayName)"

            return haystack.localizedCaseInsensitiveContains(keyword)
        }
    }

    private var daySections: [TransactionDaySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredTransactions) { transaction in
            calendar.startOfDay(for: transaction.date)
        }

        return grouped.map { day, items in
            TransactionDaySection(
                day: day,
                transactions: items.sorted { $0.createdAt > $1.createdAt }
            )
        }
        .sorted { $0.day > $1.day }
    }

    private var categoriesByID: [UUID: Category] {
        Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    }

    private var accountsByID: [UUID: Account] {
        Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { newValue in
                if !newValue {
                    pendingDelete = nil
                }
            }
        )
    }

    private func category(for transaction: LedgerTransaction) -> Category? {
        guard let categoryID = transaction.categoryId else {
            return nil
        }
        return categoriesByID[categoryID]
    }

    private func account(for transaction: LedgerTransaction) -> Account? {
        accountsByID[transaction.accountId]
    }

    private func toAccount(for transaction: LedgerTransaction) -> Account? {
        guard let toAccountID = transaction.toAccountId else {
            return nil
        }
        return accountsByID[toAccountID]
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) {
            return "今天"
        }
        if calendar.isDateInYesterday(day) {
            return "昨天"
        }
        return day.formatted(
            .dateTime
                .year()
                .month(.abbreviated)
                .day()
                .weekday(.abbreviated)
        )
    }

    private func confirmDelete() {
        guard let transaction = pendingDelete else {
            return
        }

        do {
            try LedgerService.delete(transaction, in: viewContext)
            pendingDelete = nil
        } catch {
            pendingDelete = nil
            errorMessage = error.localizedDescription
        }
    }
}

private enum TransactionFilter: String, CaseIterable, Identifiable {
    case all
    case income
    case expense
    case transfer
    case refund

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .income: return "收入"
        case .expense: return "支出"
        case .transfer: return "转账"
        case .refund: return "退款"
        }
    }

    var type: TransactionType? {
        switch self {
        case .all: return nil
        case .income: return .income
        case .expense: return .expense
        case .transfer: return .transfer
        case .refund: return .refund
        }
    }
}

private struct TransactionDaySection: Identifiable {
    let day: Date
    let transactions: [LedgerTransaction]

    var id: Date { day }
}

private struct TransactionRow: View {
    let transaction: LedgerTransaction
    let category: Category?
    let account: Account?
    let toAccount: Account?
    let theme: Theme

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(theme.surfaceElevated)
                    .frame(width: theme.iconCircleSize, height: theme.iconCircleSize)

                Image(systemName: iconName)
                    .font(theme.rowIconFont)
                    .foregroundStyle(amountColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                Text(subtitle)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: theme.smallSpacing)

            VStack(alignment: .trailing, spacing: 3) {
                Text(MoneyFormat.signed(transaction.amountValue, type: transaction.transactionType))
                    .font(theme.rowMoneyFont)
                    .foregroundStyle(amountColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(transaction.date.formatted(.dateTime.hour().minute()))
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .padding(12)
        .background(
            theme.surface,
            in: RoundedRectangle(cornerRadius: theme.controlRadius, style: .continuous)
        )
    }

    private var title: String {
        if let note = transaction.note, !note.isEmpty {
            return note
        }
        return category?.name ?? transaction.transactionType.displayName
    }

    private var subtitle: String {
        switch transaction.transactionType {
        case .transfer:
            let from = account?.name ?? "未知账户"
            let to = toAccount?.name ?? "未知账户"
            return "转账 · \(from) → \(to)"
        case .income:
            return "收入 · \(account?.name ?? "未知账户")"
        case .expense:
            return "支出 · \(account?.name ?? "未知账户")"
        case .refund:
            return "退款 · \(account?.name ?? "未知账户")"
        }
    }

    private var iconName: String {
        switch transaction.transactionType {
        case .transfer:
            return "arrow.left.arrow.right"
        case .income:
            return "arrow.down.left"
        case .expense:
            return category?.icon ?? "arrow.up.right"
        case .refund:
            return "arrow.uturn.backward"
        }
    }

    private var amountColor: Color {
        switch transaction.transactionType {
        case .income, .refund:
            return theme.income
        case .expense:
            return theme.expense
        case .transfer:
            return theme.secondaryText
        }
    }
}

#Preview("流水 · 浅色") {
    TransactionsView()
        .environment(
            \.managedObjectContext,
            PersistenceController.preview.container.viewContext
        )
        .environment(\.ledgerTheme, Theme.palette(for: .light))
}

#Preview("流水 · 深色") {
    TransactionsView()
        .environment(
            \.managedObjectContext,
            PersistenceController.preview.container.viewContext
        )
        .environment(\.ledgerTheme, Theme.palette(for: .dark))
}
