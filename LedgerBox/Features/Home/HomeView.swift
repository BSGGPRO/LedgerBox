import CoreData
import Foundation
import SwiftUI

private enum HomeSheet: String, Identifiable {
    case add
    case quickEntry
    case settings

    var id: String { rawValue }
}

struct HomeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.ledgerTheme) private var theme
    @EnvironmentObject private var themeManager: ThemeManager

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Account.sortOrder, ascending: true)],
        animation: .snappy
    )
    private var accounts: FetchedResults<Account>

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
        sortDescriptors: [NSSortDescriptor(keyPath: \Budget.startDate, ascending: false)],
        animation: .snappy
    )
    private var budgets: FetchedResults<Budget>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \SavingsGoal.createdAt, ascending: false)],
        animation: .snappy
    )
    private var goals: FetchedResults<SavingsGoal>

    @State private var activeSheet: HomeSheet?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: theme.spacing) {
                    header
                    balanceCard
                    coachCard
                    recentSection
                }
                .padding(.horizontal, theme.pagePadding)
                .padding(.top, 10)
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
            .background(theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                actionBar
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .add:
                AddTransactionView()
                    .environment(\.managedObjectContext, viewContext)
                    .environment(\.ledgerTheme, theme)
            case .quickEntry:
                QuickEntryView()
                    .environment(\.managedObjectContext, viewContext)
                    .environment(\.ledgerTheme, theme)
            case .settings:
                SettingsView()
                    .environment(\.managedObjectContext, viewContext)
                    .environmentObject(themeManager)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: theme.spacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LedgerBox")
                    .font(theme.largeTitleFont)
                    .tracking(-0.6)
                    .foregroundStyle(theme.primaryText)

                Text(Date.now.formatted(.dateTime.year().month(.wide)))
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
            }

            Spacer(minLength: theme.smallSpacing)

            Button {
                activeSheet = .settings
            } label: {
                ZStack {
                    Circle()
                        .fill(theme.surface)
                        .frame(width: 42, height: 42)

                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 27, weight: .regular))
                        .foregroundStyle(theme.accent)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("用户与设置")
        }
    }

    private var balanceCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: theme.spacing) {
                Text("总余额")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)

                Text(MoneyFormat.currency(totalBalance))
                    .font(theme.moneyFont)
                    .foregroundStyle(theme.primaryText)
                    .contentTransition(.numericText())

                HStack(spacing: theme.spacing) {
                    amountColumn(
                        title: "本月收入",
                        value: summary.income,
                        color: theme.income
                    )

                    Divider()
                        .frame(height: 30)
                        .overlay(theme.separator)

                    amountColumn(
                        title: "本月支出",
                        value: summary.expense,
                        color: theme.expense
                    )
                }

                HStack {
                    Text("本月结余")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondaryText)

                    Spacer(minLength: theme.smallSpacing)

                    Text(MoneyFormat.currency(summary.net))
                        .font(theme.rowMoneyFont)
                        .foregroundStyle(summary.net >= 0 ? theme.income : theme.expense)
                        .contentTransition(.numericText())
                }
            }
            .animation(.snappy, value: summary)
        }
    }

    private func amountColumn(title: String, value: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(theme.captionFont)
                .foregroundStyle(theme.secondaryText)

            Text(MoneyFormat.currency(value))
                .font(theme.rowMoneyFont)
                .foregroundStyle(color)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
    }

    private var coachCard: some View {
        CoachTipCard(tip: FinanceCoach.dailyTip(context: coachContext))
            .animation(.easeInOut(duration: 0.3), value: summary)
    }

    private var recentSection: some View {
        VStack(spacing: theme.smallSpacing) {
            LedgerSectionHeader(title: "最近流水")

            if recentTransactions.isEmpty {
                emptyTransactions
            } else {
                LedgerCard {
                    VStack(spacing: 0) {
                        ForEach(recentTransactions, id: \.objectID) { transaction in
                            TransactionRow(
                                transaction: transaction,
                                category: category(for: transaction),
                                theme: theme
                            )

                            if transaction.objectID != recentTransactions.last?.objectID {
                                Divider()
                                    .overlay(theme.separator)
                                    .padding(.leading, 48)
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyTransactions: some View {
        LedgerCard {
            VStack(spacing: theme.smallSpacing) {
                Image(systemName: "tray")
                    .font(theme.emptyStateIconFont)
                    .foregroundStyle(theme.secondaryText)

                Text("还没有流水")
                    .font(theme.sectionTitleFont)
                    .foregroundStyle(theme.primaryText)

                Text("记下第一笔收入，首页会自动汇总。")
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)

                Button("记一笔") {
                    activeSheet = .add
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                activeSheet = .quickEntry
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                    Text("极速")
                }
                .font(theme.buttonLabelFont)
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(theme.surface, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(theme.accent.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("极速记账")

            addButton
        }
        .padding(.bottom, 8)
    }

    private var addButton: some View {
        Button {
            activeSheet = .add
        } label: {
            HStack(spacing: theme.smallSpacing) {
                Image(systemName: "plus")
                Text("记一笔")
            }
            .font(theme.buttonLabelFont)
            .foregroundStyle(theme.onAccent)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(theme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var currentMonthInterval: DateInterval {
        Calendar.current.dateInterval(of: .month, for: Date())
            ?? DateInterval(start: Date(), duration: 0)
    }

    private var summary: LedgerSummary {
        FinanceEngine.summary(
            transactions: Array(transactions),
            in: currentMonthInterval
        )
    }

    private var coachContext: FinanceCoachContext {
        let names = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        var spending: [String: Decimal] = [:]

        for transaction in transactions where currentMonthInterval.contains(transaction.date) {
            guard let categoryID = transaction.categoryId,
                  let name = names[categoryID] else {
                continue
            }
            switch transaction.transactionType {
            case .expense:
                spending[name, default: 0] += transaction.amountValue
            case .refund:
                spending[name, default: 0] -= transaction.amountValue
            case .income, .transfer:
                break
            }
        }

        let top = spending
            .filter { $0.value > 0 }
            .max { $0.value < $1.value }

        let monthlyBudgets = budgets.filter { $0.enabled && $0.budgetPeriod == .monthly }
        let totalBudget = monthlyBudgets.first { $0.categoryId == nil }
        let budgetLimit: Decimal?
        let budgetSpent: Decimal?
        if let totalBudget {
            budgetLimit = totalBudget.limitValue
            budgetSpent = summary.expense
        } else if !monthlyBudgets.isEmpty {
            budgetLimit = monthlyBudgets.reduce(Decimal.zero) { $0 + $1.limitValue }
            budgetSpent = monthlyBudgets.reduce(Decimal.zero) { partial, budget in
                guard let categoryID = budget.categoryId,
                      let name = names[categoryID] else {
                    return partial
                }
                return partial + (spending[name] ?? 0)
            }
        } else {
            budgetLimit = nil
            budgetSpent = nil
        }

        let goal = goals.first { $0.goalStatus == .active }
        return FinanceCoachContext(
            monthIncome: summary.income,
            monthExpense: summary.expense,
            totalBalance: totalBalance,
            budgetLimit: budgetLimit,
            budgetSpent: budgetSpent,
            goalName: goal?.name,
            goalTarget: goal?.targetValue,
            goalCurrent: goal?.currentValue,
            topCategory: top?.key,
            topCategoryAmount: top?.value,
            transactionCount: transactions.filter { currentMonthInterval.contains($0.date) }.count
        )
    }

    private var totalBalance: Decimal {
        accounts.reduce(Decimal.zero) { partialResult, account in
            partialResult + account.balanceValue
        }
    }

    private var recentTransactions: [LedgerTransaction] {
        Array(transactions.prefix(5))
    }

    private func category(for transaction: LedgerTransaction) -> Category? {
        guard let categoryID = transaction.categoryId else {
            return nil
        }
        return categories.first { $0.id == categoryID }
    }
}

private struct TransactionRow: View {
    let transaction: LedgerTransaction
    let category: Category?
    let theme: Theme

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(theme.surfaceElevated)
                    .frame(width: theme.iconCircleSize, height: theme.iconCircleSize)

                Image(systemName: category?.icon ?? transaction.transactionType.symbolName)
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

            Text(
                MoneyFormat.signed(
                    transaction.amountValue,
                    type: transaction.transactionType
                )
            )
            .font(theme.rowMoneyFont)
            .foregroundStyle(amountColor)
            .contentTransition(.numericText())
        }
        .padding(.vertical, 10)
    }

    private var title: String {
        if let note = transaction.note, !note.isEmpty {
            return note
        }
        if let category {
            return category.name
        }
        return transaction.transactionType.displayName
    }

    private var subtitle: String {
        let dateText = transaction.date.formatted(date: .abbreviated, time: .shortened)
        if let category {
            return "\(category.name) · \(dateText)"
        }
        return "\(transaction.transactionType.displayName) · \(dateText)"
    }

    private var amountColor: Color {
        switch transaction.transactionType {
        case .income:
            return theme.income
        case .expense:
            return theme.expense
        case .refund:
            return theme.income
        case .transfer:
            return theme.accent
        }
    }
}

#Preview("首页 · 浅色") {
    HomeView()
        .environment(
            \.managedObjectContext,
            PersistenceController.preview.container.viewContext
        )
        .environment(\.ledgerTheme, Theme.palette(for: .light))
        .environmentObject(ThemeManager())
}

#Preview("首页 · 深色") {
    HomeView()
        .environment(
            \.managedObjectContext,
            PersistenceController.preview.container.viewContext
        )
        .environment(\.ledgerTheme, Theme.palette(for: .dark))
        .environmentObject(ThemeManager())
}
