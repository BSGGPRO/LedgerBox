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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.top, theme.smallSpacing)

                    VStack(alignment: .leading, spacing: theme.sectionSpacing) {
                        balanceCard
                        monthStatsSection
                        coachCard
                        recentSection
                    }
                    .padding(.top, theme.sectionSpacing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, theme.pagePadding)
                .padding(.bottom, theme.sectionSpacing)
            }
            .scrollIndicators(.hidden)
            .background(theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
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

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: theme.spacing) {
            VStack(alignment: .leading, spacing: theme.tinySpacing) {
                Text("LedgerBox")
                    .font(theme.screenTitleFont)
                    .tracking(-0.6)
                    .foregroundStyle(theme.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Text(Date.now.formatted(.dateTime.year().month(.wide)))
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
            }

            Spacer(minLength: theme.smallSpacing)

            Button {
                activeSheet = .settings
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(theme.accentText)
                    .frame(width: theme.minTapTarget, height: theme.minTapTarget)
                    .background(theme.surface, in: Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(theme.separator, lineWidth: theme.hairline)
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("用户与设置")
        }
    }

    // MARK: - Balance

    private var balanceCard: some View {
        LedgerCard {
            VStack(alignment: .leading, spacing: theme.spacing) {
                HStack(alignment: .center, spacing: theme.smallSpacing) {
                    Text("总余额")
                        .font(theme.overlineFont)
                        .tracking(0.8)
                        .foregroundStyle(theme.secondaryText)

                    Spacer(minLength: theme.smallSpacing)

                    LedgerTag("CNY")
                }

                Text(MoneyFormat.currency(totalBalance))
                    .font(theme.balanceFont)
                    .foregroundStyle(theme.primaryText)
                    .ledgerMoneyLine(minScale: 0.45)
                    .contentTransition(.numericText())

                Rectangle()
                    .fill(theme.separator)
                    .frame(height: theme.hairline)

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(theme.controlIconFont)
                        .foregroundStyle(theme.tertiaryText)

                    Text("\(monthTransactionCount) 笔本月记录 · \(accounts.count) 个账户")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.tertiaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .animation(.snappy, value: summary)
        }
    }

    // MARK: - This month, three columns

    private var monthStatsSection: some View {
        VStack(alignment: .leading, spacing: theme.cardSpacing) {
            LedgerSectionHeader(title: "本月")

            LedgerCard {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: theme.cardSpacing) {
                        statLine(title: "收入", value: summary.income, color: theme.income)
                        horizontalDivider
                        statLine(title: "支出", value: summary.expense, color: theme.expense)
                        horizontalDivider
                        statLine(title: "结余", value: summary.net, color: netColor)
                    }
                } else {
                    HStack(alignment: .top, spacing: theme.cardSpacing) {
                        statColumn(title: "收入", value: summary.income, color: theme.income)
                        verticalDivider
                        statColumn(title: "支出", value: summary.expense, color: theme.expense)
                        verticalDivider
                        statColumn(title: "结余", value: summary.net, color: netColor)
                    }
                }
            }
            .animation(.snappy, value: summary)
        }
    }

    private func statColumn(title: String, value: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(theme.captionFont)
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)

            Text(MoneyFormat.currency(value))
                .font(theme.statValueFont)
                .foregroundStyle(color)
                .ledgerMoneyLine(minScale: 0.55)
                .contentTransition(.numericText())
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: 44, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private func statLine(title: String, value: Decimal, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.smallSpacing) {
            Text(title)
                .font(theme.captionFont)
                .foregroundStyle(theme.secondaryText)

            Spacer(minLength: theme.smallSpacing)

            Text(MoneyFormat.currency(value))
                .font(theme.statValueFont)
                .foregroundStyle(color)
                .ledgerMoneyLine(minScale: 0.6)
                .contentTransition(.numericText())
                .layoutPriority(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(theme.separator)
            .frame(width: theme.hairline, height: 34)
            .padding(.top, 2)
    }

    private var horizontalDivider: some View {
        Rectangle()
            .fill(theme.separator)
            .frame(height: theme.hairline)
    }

    // MARK: - Coach

    private var coachCard: some View {
        VStack(alignment: .leading, spacing: theme.cardSpacing) {
            LedgerSectionHeader(title: "财务教练")

            CoachTipCard(tip: FinanceCoach.dailyTip(context: coachContext))
                .animation(.easeInOut(duration: 0.3), value: summary)
        }
    }

    // MARK: - Recent transactions

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: theme.cardSpacing) {
            LedgerSectionHeader(title: "最近流水")

            if recentTransactions.isEmpty {
                emptyTransactions
            } else {
                LedgerCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(recentTransactions, id: \.objectID) { transaction in
                            TransactionRow(
                                transaction: transaction,
                                category: category(for: transaction),
                                theme: theme
                            )
                            .padding(.horizontal, theme.cardPadding)

                            if transaction.objectID != recentTransactions.last?.objectID {
                                Rectangle()
                                    .fill(theme.separator)
                                    .frame(height: theme.hairline)
                                    .padding(.leading, theme.cardPadding + theme.iconCircleSize + theme.cardSpacing)
                                    .padding(.trailing, theme.cardPadding)
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyTransactions: some View {
        LedgerCard {
            VStack(spacing: theme.cardSpacing) {
                LedgerIconBadge(systemName: "tray", tint: theme.secondaryText, size: 44)

                Text("还没有流水")
                    .font(theme.sectionTitleFont)
                    .foregroundStyle(theme.primaryText)

                Text("记下第一笔收入，首页会自动汇总。")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button("记一笔") {
                    activeSheet = .add
                }
                .buttonStyle(LedgerPrimaryButtonStyle(theme: theme))
                .padding(.top, theme.tinySpacing)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, theme.cardSpacing)
        }
    }

    // MARK: - Bottom actions

    private var actionBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(theme.separator)
                .frame(height: theme.hairline)

            HStack(spacing: theme.smallSpacing + 2) {
                Button {
                    activeSheet = .quickEntry
                } label: {
                    Label("极速", systemImage: "bolt.fill")
                }
                .buttonStyle(LedgerSecondaryButtonStyle(theme: theme))
                .accessibilityLabel("极速记账")

                Button {
                    activeSheet = .add
                } label: {
                    Label("记一笔", systemImage: "plus")
                }
                .buttonStyle(LedgerPrimaryButtonStyle(theme: theme, fullWidth: true))
                .accessibilityLabel("记一笔")
            }
            .padding(.horizontal, theme.pagePadding)
            .padding(.top, theme.cardSpacing)
            .padding(.bottom, theme.smallSpacing)
        }
        .background(theme.background)
    }

    // MARK: - Derived data

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

    private var netColor: Color {
        summary.net >= 0 ? theme.income : theme.expense
    }

    private var monthTransactionCount: Int {
        transactions.filter { currentMonthInterval.contains($0.date) }.count
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
        HStack(spacing: theme.cardSpacing) {
            LedgerIconBadge(systemName: iconName, tint: amountColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(theme.bodyFont.weight(.medium))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                Text(subtitle)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }
            .layoutPriority(0)

            Spacer(minLength: theme.smallSpacing)

            Text(
                MoneyFormat.signed(
                    transaction.amountValue,
                    type: transaction.transactionType
                )
            )
            .font(theme.rowMoneyFont)
            .foregroundStyle(amountColor)
            .ledgerMoneyLine(minScale: 0.7)
            .contentTransition(.numericText())
            .layoutPriority(1)
        }
        .frame(minHeight: theme.rowMinHeight)
        .accessibilityElement(children: .combine)
    }

    private var iconName: String {
        category?.icon ?? transaction.transactionType.symbolName
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
            return theme.accentText
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
