import Charts
import CoreData
import Foundation
import SwiftUI

struct StatisticsView: View {
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

    @State private var selectedMonth: Date = Calendar.current
        .dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var showingAddTransaction = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: theme.spacing) {
                    monthPicker

                    if monthTransactions.isEmpty {
                        emptyState
                    } else {
                        summaryCard
                        coachCard
                        monthlyBarSection
                        categoryDonutSection
                        cumulativeTrendSection
                    }
                }
                .padding(.horizontal, theme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("统计")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .sheet(isPresented: $showingAddTransaction) {
            AddTransactionView()
                .environment(\.managedObjectContext, viewContext)
                .environment(\.ledgerTheme, theme)
        }
    }

    private var monthPicker: some View {
        HStack(spacing: theme.smallSpacing) {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(theme.controlIconFont)
                    .foregroundStyle(theme.primaryText)
                    .frame(width: 44, height: 44)
                    .background(theme.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("上个月")

            Spacer(minLength: theme.smallSpacing)

            Text(selectedMonth.formatted(.dateTime.year().month(.wide)))
                .font(theme.sectionTitleFont)
                .foregroundStyle(theme.primaryText)

            Spacer(minLength: theme.smallSpacing)

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(theme.controlIconFont)
                    .foregroundStyle(canGoForward ? theme.primaryText : theme.secondaryText)
                    .frame(width: 44, height: 44)
                    .background(theme.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canGoForward)
            .accessibilityLabel("下个月")
        }
    }

    private var summaryCard: some View {
        LedgerCard {
            HStack(alignment: .top, spacing: theme.smallSpacing) {
                summaryColumn(title: "收入", value: summary.income, color: theme.income)

                Divider()
                    .frame(height: 34)
                    .overlay(theme.separator)

                summaryColumn(title: "支出", value: summary.expense, color: theme.expense)

                Divider()
                    .frame(height: 34)
                    .overlay(theme.separator)

                summaryColumn(
                    title: "结余",
                    value: summary.net,
                    color: summary.net >= 0 ? theme.income : theme.expense
                )
            }
        }
    }

    private var coachCard: some View {
        CoachTipCard(
            tip: FinanceCoach.dailyTip(
                context: FinanceCoachContext(
                    monthIncome: summary.income,
                    monthExpense: summary.expense,
                    topCategory: categorySlices.first?.name,
                    topCategoryAmount: categorySlices.first?.amount,
                    transactionCount: monthTransactions.count
                )
            ),
            compact: true
        )
        .animation(.snappy, value: selectedMonth)
    }

    private func summaryColumn(title: String, value: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(theme.captionFont)
                .foregroundStyle(theme.secondaryText)

            Text(MoneyFormat.currency(value))
                .font(theme.rowMoneyFont)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)
    }

    private var monthlyBarSection: some View {
        VStack(spacing: theme.smallSpacing) {
            LedgerSectionHeader(title: "近 6 个月收支")

            LedgerCard {
                VStack(alignment: .leading, spacing: theme.smallSpacing) {
                    legend

                    Chart {
                        ForEach(monthlySeries) { point in
                            BarMark(
                                x: .value("月份", point.monthStart, unit: .month),
                                y: .value("金额", point.summary.income.doubleValue)
                            )
                            .foregroundStyle(theme.income)
                            .cornerRadius(4)
                            .position(by: .value("类型", "收入"))

                            BarMark(
                                x: .value("月份", point.monthStart, unit: .month),
                                y: .value("金额", point.summary.expense.doubleValue)
                            )
                            .foregroundStyle(theme.expense)
                            .cornerRadius(4)
                            .position(by: .value("类型", "支出"))
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .month)) { value in
                            AxisGridLine().foregroundStyle(theme.separator)
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(date, format: .dateTime.month(.abbreviated))
                                        .font(theme.chartLabelFont)
                                        .foregroundStyle(theme.secondaryText)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(theme.separator)
                            AxisValueLabel {
                                if let amount = value.as(Double.self) {
                                    Text(amount, format: .number.precision(.fractionLength(0)))
                                        .font(theme.chartLabelFont)
                                        .foregroundStyle(theme.secondaryText)
                                }
                            }
                        }
                    }
                    .frame(height: 200)
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(color: theme.income, title: "收入")
            legendItem(color: theme.expense, title: "支出")
        }
    }

    private func legendItem(color: Color, title: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)

            Text(title)
                .font(theme.captionFont)
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var categoryDonutSection: some View {
        VStack(spacing: theme.smallSpacing) {
            LedgerSectionHeader(title: "分类占比")

            LedgerCard {
                if categorySlices.isEmpty {
                    compactEmpty(message: "本月没有可统计的支出。")
                } else {
                    VStack(spacing: theme.spacing) {
                        ZStack {
                            Chart(categorySlices) { slice in
                                SectorMark(
                                    angle: .value("金额", slice.amount.doubleValue),
                                    innerRadius: .ratio(0.62),
                                    angularInset: 1.5
                                )
                                .cornerRadius(4)
                                .foregroundStyle(slice.color)
                            }
                            .chartLegend(.hidden)

                            VStack(spacing: 2) {
                                Text("支出")
                                    .font(theme.captionFont)
                                    .foregroundStyle(theme.secondaryText)

                                Text(MoneyFormat.currency(categoryTotal))
                                    .font(theme.rowMoneyFont)
                                    .foregroundStyle(theme.primaryText)
                            }
                        }
                        .frame(height: 210)

                        VStack(spacing: 0) {
                            ForEach(Array(categorySlices.prefix(6))) { slice in
                                HStack(spacing: theme.smallSpacing) {
                                    Circle()
                                        .fill(slice.color)
                                        .frame(width: 8, height: 8)

                                    Text(slice.name)
                                        .font(theme.bodyFont)
                                        .foregroundStyle(theme.primaryText)
                                        .lineLimit(1)

                                    Spacer(minLength: theme.smallSpacing)

                                    Text(MoneyFormat.currency(slice.amount))
                                        .font(theme.rowMoneyFont)
                                        .foregroundStyle(theme.secondaryText)
                                        .lineLimit(1)
                                }
                                .padding(.vertical, 7)

                                if slice.id != categorySlices.prefix(6).last?.id {
                                    Divider()
                                        .overlay(theme.separator)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var cumulativeTrendSection: some View {
        VStack(spacing: theme.smallSpacing) {
            LedgerSectionHeader(title: "本月累计结余")

            LedgerCard {
                if dailyPoints.isEmpty {
                    compactEmpty(message: "本月还没有趋势数据。")
                } else {
                    Chart {
                        ForEach(dailyPoints) { point in
                            AreaMark(
                                x: .value("日期", point.date),
                                y: .value("累计结余", point.cumulativeNet.doubleValue)
                            )
                            .foregroundStyle(theme.accent.opacity(0.10))

                            LineMark(
                                x: .value("日期", point.date),
                                y: .value("累计结余", point.cumulativeNet.doubleValue)
                            )
                            .foregroundStyle(theme.accentText)
                            .lineStyle(
                                StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                            )
                            .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 7)) { value in
                            AxisGridLine().foregroundStyle(theme.separator)
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(date, format: .dateTime.month(.abbreviated).day())
                                        .font(theme.chartLabelFont)
                                        .foregroundStyle(theme.secondaryText)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(theme.separator)
                            AxisValueLabel {
                                if let amount = value.as(Double.self) {
                                    Text(amount, format: .number.precision(.fractionLength(0)))
                                        .font(theme.chartLabelFont)
                                        .foregroundStyle(theme.secondaryText)
                                }
                            }
                        }
                    }
                    .frame(height: 190)
                }
            }
        }
    }

    private var emptyState: some View {
        LedgerCard {
            VStack(spacing: theme.smallSpacing) {
                Image(systemName: "chart.pie")
                    .font(theme.emptyStateIconFont)
                    .foregroundStyle(theme.secondaryText)

                Text("这个月还没有数据")
                    .font(theme.sectionTitleFont)
                    .foregroundStyle(theme.primaryText)

                Text("记一笔后，这里会生成收支柱状图、分类占比和趋势线。")
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)

                Button("去记账") {
                    showingAddTransaction = true
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        }
    }

    private func compactEmpty(message: String) -> some View {
        HStack(spacing: theme.smallSpacing) {
            Image(systemName: "chart.bar.xaxis")
                .foregroundStyle(theme.secondaryText)

            Text(message)
                .font(theme.bodyFont)
                .foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var currentMonthStart: Date {
        Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    }

    private var canGoForward: Bool {
        selectedMonth < currentMonthStart
    }

    private var selectedInterval: DateInterval {
        FinanceEngine.interval(for: .monthly, containing: selectedMonth)
    }

    private var monthTransactions: [LedgerTransaction] {
        transactions.filter { selectedInterval.contains($0.date) }
    }

    private var summary: LedgerSummary {
        FinanceEngine.summary(
            transactions: Array(transactions),
            in: selectedInterval
        )
    }

    private var monthlySeries: [MonthlySummaryPoint] {
        FinanceEngine.monthlySeries(
            transactions: Array(transactions),
            endingAt: selectedMonth,
            count: 6
        )
    }

    private var dailyPoints: [DailyNetPoint] {
        FinanceEngine.dailyCumulativeNet(
            transactions: Array(transactions),
            in: selectedInterval
        )
    }

    private var categoriesByID: [UUID: Category] {
        Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    }

    private var categoryTotal: Decimal {
        categorySlices.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private var categorySlices: [CategorySlice] {
        var totals: [String: (name: String, amount: Decimal, colorHex: String?)] = [:]

        for transaction in monthTransactions {
            let delta: Decimal
            switch transaction.transactionType {
            case .expense:
                delta = transaction.amountValue
            case .refund:
                delta = -transaction.amountValue
            case .income, .transfer:
                continue
            }

            let category = transaction.categoryId.flatMap { categoriesByID[$0] }
            let isDeleted = category?.isSoftDeleted == true
            let key = isDeleted
                ? "deleted-category"
                : (category?.id.uuidString ?? "uncategorized")
            let name = isDeleted
                ? "其他"
                : (category?.name ?? "未分类")
            let colorHex = isDeleted ? nil : category?.colorHex
            let existing = totals[key]
            totals[key] = (
                name: name,
                amount: (existing?.amount ?? .zero) + delta,
                colorHex: colorHex
            )
        }

        return totals.compactMap { key, value in
            guard value.amount > 0 else { return nil }
            return CategorySlice(
                id: key,
                name: value.name,
                amount: value.amount,
                color: value.colorHex.map { Color(hex: $0) } ?? theme.secondaryText
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    private func shiftMonth(by offset: Int) {
        guard
            let next = Calendar.current.date(byAdding: .month, value: offset, to: selectedMonth),
            next <= currentMonthStart
        else {
            return
        }

        withAnimation(.snappy) {
            selectedMonth = next
        }
    }
}

private struct CategorySlice: Identifiable {
    let id: String
    let name: String
    let amount: Decimal
    let color: Color
}

#Preview("统计 · 浅色") {
    StatisticsView()
        .environment(
            \.managedObjectContext,
            PersistenceController.preview.container.viewContext
        )
        .environment(\.ledgerTheme, Theme.palette(for: .light))
}

#Preview("统计 · 深色") {
    StatisticsView()
        .environment(
            \.managedObjectContext,
            PersistenceController.preview.container.viewContext
        )
        .environment(\.ledgerTheme, Theme.palette(for: .dark))
}
