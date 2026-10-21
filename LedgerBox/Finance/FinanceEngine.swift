import Foundation

// MARK: - Domain enums

enum AccountType: String, CaseIterable, Identifiable, Codable {
    case cash
    case savings
    case goal
    case reserve

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cash: return "现金"
        case .savings: return "储蓄"
        case .goal: return "目标专户"
        case .reserve: return "备用金"
        }
    }

    var symbolName: String {
        switch self {
        case .cash: return "banknote"
        case .savings: return "building.columns"
        case .goal: return "target"
        case .reserve: return "shield.lefthalf.filled"
        }
    }
}

enum TransactionType: String, CaseIterable, Identifiable, Codable {
    case income
    case expense
    case transfer
    case refund

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .income: return "收入"
        case .expense: return "支出"
        case .transfer: return "转账"
        case .refund: return "退款"
        }
    }

    var symbolName: String {
        switch self {
        case .income: return "arrow.down.left"
        case .expense: return "arrow.up.right"
        case .transfer: return "arrow.left.arrow.right"
        case .refund: return "arrow.uturn.backward"
        }
    }

    var isSpending: Bool {
        self == .expense || self == .refund
    }
}

enum CategoryKind: String, CaseIterable, Identifiable, Codable {
    case expense
    case income

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .expense: return "支出"
        case .income: return "收入"
        }
    }
}

enum BudgetPeriod: String, CaseIterable, Identifiable, Codable {
    case monthly
    case weekly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .monthly: return "每月"
        case .weekly: return "每周"
        }
    }
}

enum SavingsGoalStatus: String, CaseIterable, Identifiable, Codable {
    case active
    case achieved
    case frozen

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .active: return "进行中"
        case .achieved: return "已达成"
        case .frozen: return "已冻结"
        }
    }
}

enum TemplateKind: String, CaseIterable, Identifiable, Codable {
    case daily
    case student
    case car
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .daily: return "日常记账"
        case .student: return "学生预算"
        case .car: return "买车攒钱"
        case .custom: return "自定义"
        }
    }
}

// MARK: - Read-only finance projections

/// The engine deliberately depends on this small read-only protocol instead of
/// NSManagedObject. This keeps FinanceEngine free of Core Data and SwiftUI.
/// [铁律1] [铁律2]
protocol TransactionProviding {
    var financeType: TransactionType { get }
    var financeCategoryID: UUID? { get }
    var financeAccountID: UUID { get }
    var financeAmount: Decimal { get }
    var financeDate: Date { get }
}

struct LedgerSummary: Equatable {
    var income: Decimal = .zero
    var expense: Decimal = .zero

    var net: Decimal {
        income - expense
    }
}

struct BudgetProgress: Equatable {
    let limit: Decimal
    let spent: Decimal
    let remaining: Decimal
    let ratio: Double
    let isOverBudget: Bool
}

enum GoalCountdownStatus: Equatable {
    case accumulating(activeDays: Int)
    case insufficientRate(activeDays: Int, dailyRate: Decimal)
    case estimated(days: Int, dailyRate: Decimal, activeDays: Int)
    case achieved
}

struct GoalCountdown: Equatable {
    let status: GoalCountdownStatus
    let remainingAmount: Decimal
}

struct MonthlySummaryPoint: Identifiable, Equatable {
    let monthStart: Date
    let summary: LedgerSummary

    var id: Date { monthStart }
}

struct DailyNetPoint: Identifiable, Equatable {
    let date: Date
    let cumulativeNet: Decimal

    var id: Date { date }
}

// MARK: - Local finance coach

/// A snapshot for the local, deterministic coach. Every number here comes from
/// Core Data; the coach writes sentences, never transactions.
struct FinanceCoachContext {
    var monthIncome: Decimal
    var monthExpense: Decimal
    var totalBalance: Decimal?
    var budgetLimit: Decimal?
    var budgetSpent: Decimal?
    var goalName: String?
    var goalTarget: Decimal?
    var goalCurrent: Decimal?
    var topCategory: String?
    var topCategoryAmount: Decimal?
    var transactionCount: Int

    init(
        monthIncome: Decimal,
        monthExpense: Decimal,
        totalBalance: Decimal? = nil,
        budgetLimit: Decimal? = nil,
        budgetSpent: Decimal? = nil,
        goalName: String? = nil,
        goalTarget: Decimal? = nil,
        goalCurrent: Decimal? = nil,
        topCategory: String? = nil,
        topCategoryAmount: Decimal? = nil,
        transactionCount: Int = 0
    ) {
        self.monthIncome = monthIncome
        self.monthExpense = monthExpense
        self.totalBalance = totalBalance
        self.budgetLimit = budgetLimit
        self.budgetSpent = budgetSpent
        self.goalName = goalName
        self.goalTarget = goalTarget
        self.goalCurrent = goalCurrent
        self.topCategory = topCategory
        self.topCategoryAmount = topCategoryAmount
        self.transactionCount = transactionCount
    }
}

struct FinanceCoachTip {
    enum Tone {
        case positive
        case warning
        case neutral
    }

    let title: String
    let body: String
    let tag: String
    let symbol: String
    let tone: Tone
}

/// Rule-based daily guidance that shares the same local ledger snapshot as
/// FinanceAdvisor. It is intentionally deterministic for a given day.
enum FinanceCoach {
    static func dailyTip(
        context: FinanceCoachContext,
        date: Date = Date(),
        calendar: Calendar = .current
    ) -> FinanceCoachTip {
        if context.transactionCount == 0 {
            return FinanceCoachTip(
                title: "先记下第一笔",
                body: "不用等账本完美。先记一笔今天最常见的支出，明天再回来看分类和预算。",
                tag: "开始",
                symbol: "sparkles",
                tone: .neutral
            )
        }

        if let limit = context.budgetLimit,
           let spent = context.budgetSpent,
           limit > 0 {
            let ratio = (spent / limit).doubleValue
            let remaining = max(limit - spent, Decimal.zero)

            if ratio >= 1 {
                return FinanceCoachTip(
                    title: "预算已经超了",
                    body: "本月已超出 \(MoneyFormat.currency(spent - limit))。先暂停非必要支出，把接下来的每一笔记清楚。",
                    tag: "预算",
                    symbol: "exclamationmark.triangle.fill",
                    tone: .warning
                )
            }

            if ratio >= 0.85 {
                return FinanceCoachTip(
                    title: "预算进入最后一段",
                    body: "只剩 \(MoneyFormat.currency(remaining))，大约还能花 \(max(Int((1 - ratio) * 100), 1))%。今天先别急着下单。",
                    tag: "预算",
                    symbol: "gauge.with.dots.needle.67percent",
                    tone: .warning
                )
            }

            if spent == .zero {
                return FinanceCoachTip(
                    title: "预算还没开始动",
                    body: "本月预算 \(MoneyFormat.currency(limit)) 还没怎么花。先记下今天的支出，再看进度更准。",
                    tag: "预算",
                    symbol: "gauge.with.dots.needle.0percent",
                    tone: .neutral
                )
            }
        }

        if context.monthIncome > 0, context.monthExpense > context.monthIncome {
            return FinanceCoachTip(
                title: "支出超过了收入",
                body: "本月支出比收入多 \(MoneyFormat.currency(context.monthExpense - context.monthIncome))。先找一项可以暂缓的订阅或冲动消费。",
                tag: "现金流",
                symbol: "arrow.down.right.circle.fill",
                tone: .warning
            )
        }

        if let name = context.goalName,
           let target = context.goalTarget,
           let current = context.goalCurrent,
           target > current {
            let remaining = target - current
            let ratio = (current / target).doubleValue
            if ratio >= 0.8 {
                return FinanceCoachTip(
                    title: "目标只差最后一段",
                    body: "「\(name)」还差 \(MoneyFormat.currency(remaining))。先别挪用它，完成后再奖励自己。",
                    tag: "目标",
                    symbol: "flag.checkered",
                    tone: .positive
                )
            }
            return FinanceCoachTip(
                title: "给目标留一点",
                body: "「\(name)」已完成 \(Int((ratio * 100).rounded()))%。今天先存一笔小钱，也比月底一次硬省更容易。",
                tag: "目标",
                symbol: "target",
                tone: .neutral
            )
        }

        if let category = context.topCategory,
           let amount = context.topCategoryAmount,
           context.monthExpense > 0 {
            let share = (amount / context.monthExpense).doubleValue
            if share >= 0.35 {
                return FinanceCoachTip(
                    title: "支出集中在一类",
                    body: "\(category)占本月支出的 \(Int((share * 100).rounded()))%。不是不能花，先确认这笔钱花得值不值。",
                    tag: "分类",
                    symbol: "chart.pie.fill",
                    tone: .neutral
                )
            }
        }

        let prompts: [(String, String, String)] = [
            (
                "今天先别急着下单",
                "把想买的东西放 24 小时。明天还想要，再回来记一笔；很多冲动会自己消失。",
                "冷静期"
            ),
            (
                "先存一点，再花",
                "今天收到钱后，先把 10% 转到不容易随手花掉的账户，剩下的再安排。",
                "先存后花"
            ),
            (
                "检查一个自动续费",
                "打开订阅列表，找一个这周没用过的服务。关掉它，比硬省一杯咖啡更有效。",
                "订阅"
            ),
            (
                "只花预算内的钱",
                "今天每次付款前看一眼剩余额度。额度不够就换一个更便宜的方案，而不是先买了再说。",
                "预算"
            )
        ]
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        let pick = prompts[abs(day) % prompts.count]
        return FinanceCoachTip(
            title: pick.0,
            body: pick.1,
            tag: pick.2,
            symbol: "leaf.fill",
            tone: .positive
        )
    }
}

// MARK: - Pure finance engine

enum FinanceEngine {

    /// Sums income and net expense inside the supplied interval.
    /// Transfers never affect income or expense. Refunds reduce expense.
    /// [边界2] [边界7] [边界8]
    static func summary<T: TransactionProviding>(
        transactions: [T],
        in interval: DateInterval,
        accountID: UUID? = nil
    ) -> LedgerSummary {
        var income = Decimal.zero
        var expense = Decimal.zero

        for item in transactions where interval.contains(item.financeDate) {
            if let accountID, item.financeAccountID != accountID {
                continue
            }

            switch item.financeType {
            case .income:
                income += item.financeAmount
            case .expense:
                expense += item.financeAmount
            case .refund:
                expense -= item.financeAmount
            case .transfer:
                break
            }
        }

        return LedgerSummary(income: income, expense: expense)
    }

    /// Natural-month or Monday-to-Sunday interval. A week crossing a month
    /// boundary stays intact and is reported under its starting month.
    /// [边界5]
    static func interval(
        for period: BudgetPeriod,
        containing date: Date,
        calendar: Calendar = .current
    ) -> DateInterval {
        switch period {
        case .monthly:
            return calendar.dateInterval(of: .month, for: date)
                ?? DateInterval(start: calendar.startOfDay(for: date), duration: 0)
        case .weekly:
            var isoCalendar = Calendar(identifier: .iso8601)
            isoCalendar.timeZone = calendar.timeZone
            isoCalendar.locale = calendar.locale
            return isoCalendar.dateInterval(of: .weekOfYear, for: date)
                ?? DateInterval(start: calendar.startOfDay(for: date), duration: 0)
        }
    }

    /// Returns month starts in chronological order, ending with the month that
    /// contains `date`. Used by the statistics chart.
    static func monthStarts(
        endingAt date: Date,
        count: Int,
        calendar: Calendar = .current
    ) -> [Date] {
        guard count > 0 else { return [] }
        guard let currentMonth = calendar.dateInterval(of: .month, for: date)?.start else {
            return []
        }

        return (0..<count).reversed().compactMap { offset in
            calendar.date(byAdding: .month, value: -offset, to: currentMonth)
        }
    }

    /// Six-month income/expense series for the bar chart. All money remains
    /// Decimal; the view converts to Double only for Charts.
    static func monthlySeries<T: TransactionProviding>(
        transactions: [T],
        endingAt date: Date,
        count: Int,
        calendar: Calendar = .current
    ) -> [MonthlySummaryPoint] {
        monthStarts(endingAt: date, count: count, calendar: calendar).map { monthStart in
            let monthInterval = calendar.dateInterval(of: .month, for: monthStart)
                ?? DateInterval(start: monthStart, duration: 0)
            return MonthlySummaryPoint(
                monthStart: monthStart,
                summary: summary(transactions: transactions, in: monthInterval)
            )
        }
    }

    /// Daily cumulative net line for the selected month. Transfers are excluded
    /// by summary(); refunds reduce expense. [边界2] [边界8]
    static func dailyCumulativeNet<T: TransactionProviding>(
        transactions: [T],
        in interval: DateInterval,
        calendar: Calendar = .current
    ) -> [DailyNetPoint] {
        var points: [DailyNetPoint] = []
        var running = Decimal.zero
        var day = calendar.startOfDay(for: interval.start)

        while day < interval.end {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                break
            }
            let dayInterval = DateInterval(start: day, end: nextDay)
            running += summary(transactions: transactions, in: dayInterval).net
            points.append(DailyNetPoint(date: day, cumulativeNet: running))
            day = nextDay
        }

        return points
    }

    /// Returns net spending for one category, or for all categories when
    /// categoryID is nil. Refunds subtract from the category total.
    /// [边界7] [边界8]
    static func spending<T: TransactionProviding>(
        categoryID: UUID?,
        transactions: [T],
        in interval: DateInterval
    ) -> Decimal {
        var total = Decimal.zero

        for item in transactions where interval.contains(item.financeDate) {
            guard item.financeType == .expense || item.financeType == .refund else {
                continue
            }
            if let categoryID, item.financeCategoryID != categoryID {
                continue
            }
            if item.financeType == .expense {
                total += item.financeAmount
            } else {
                total -= item.financeAmount
            }
        }

        return total
    }

    /// Produces a display-ready budget result. Ratio uses Double only for the
    /// progress bar; every persisted and calculated money value stays Decimal.
    /// [铁律2]
    static func budgetProgress(limit: Decimal, spent: Decimal) -> BudgetProgress {
        let safeLimit = Swift.max(limit, Decimal.zero)
        let remaining = safeLimit - spent
        let rawRatio: Double

        if safeLimit > 0 {
            rawRatio = spent.doubleValue / safeLimit.doubleValue
        } else {
            rawRatio = spent > 0 ? 1 : 0
        }

        let clampedRatio = Swift.min(Swift.max(rawRatio, 0), 1)
        return BudgetProgress(
            limit: safeLimit,
            spent: spent,
            remaining: remaining,
            ratio: clampedRatio,
            isOverBudget: spent > safeLimit
        )
    }

    /// Countdown formula from the specification:
    /// ceil((target - current) / average daily net surplus over the last 30 days).
    /// "Effective days" means distinct calendar days containing at least one
    /// non-transfer transaction. Fewer than 7 effective days is treated as
    /// insufficient history. A rate <= 0 cannot produce an estimate.
    /// Money remains Decimal; Double is used only to round the day count.
    /// [边界10]
    static func savingsCountdown<T: TransactionProviding>(
        target: Decimal,
        current: Decimal,
        transactions: [T],
        asOf date: Date = Date(),
        calendar: Calendar = .current
    ) -> GoalCountdown {
        let remainingAmount = Swift.max(target - current, Decimal.zero)
        if remainingAmount == .zero {
            return GoalCountdown(status: .achieved, remainingAmount: .zero)
        }

        let dayStart = calendar.startOfDay(for: date)
        guard
            let windowStart = calendar.date(byAdding: .day, value: -29, to: dayStart),
            let windowEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
        else {
            return GoalCountdown(
                status: .accumulating(activeDays: 0),
                remainingAmount: remainingAmount
            )
        }

        let window = DateInterval(start: windowStart, end: windowEnd)
        let recent = transactions.filter {
            window.contains($0.financeDate) && $0.financeType != .transfer
        }
        let activeDays = Set(recent.map { calendar.startOfDay(for: $0.financeDate) }).count

        guard activeDays >= 7 else {
            return GoalCountdown(
                status: .accumulating(activeDays: activeDays),
                remainingAmount: remainingAmount
            )
        }

        let netSurplus = summary(transactions: recent, in: window).net
        let dailyRate = netSurplus / Decimal(activeDays)

        guard dailyRate > 0 else {
            return GoalCountdown(
                status: .insufficientRate(activeDays: activeDays, dailyRate: dailyRate),
                remainingAmount: remainingAmount
            )
        }

        let rawDays = (remainingAmount / dailyRate).doubleValue
        let days = Swift.max(Int(ceil(rawDays)), 1)
        return GoalCountdown(
            status: .estimated(days: days, dailyRate: dailyRate, activeDays: activeDays),
            remainingAmount: remainingAmount
        )
    }
}

// MARK: - Decimal and money helpers

extension Decimal {
    /// Rounds a monetary value to two fraction digits without using Double.
    /// The distinct name avoids colliding with `Decimal.rounded(_:_:)`, whose
    /// default scale is 0 and would silently drop cents. [铁律2]
    func roundedToCents() -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, 2, .plain)
        return result
    }

    /// Double is permitted only at UI / chart boundaries, never for storage.
    /// [铁律2]
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}

enum MoneyFormat {
    static func currency(_ amount: Decimal, code: String = "CNY") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "¥0.00"
    }

    static func signed(_ amount: Decimal, type: TransactionType, code: String = "CNY") -> String {
        let prefix: String
        switch type {
        case .income, .refund:
            prefix = "+"
        case .expense:
            prefix = "-"
        case .transfer:
            prefix = ""
        }
        return prefix + currency(amount, code: code)
    }

    /// Plain editable amount for TextField. No currency symbol or grouping
    /// separator, so Decimal(string:locale:) always receives a stable value.
    static func editable(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "0"
    }
}
