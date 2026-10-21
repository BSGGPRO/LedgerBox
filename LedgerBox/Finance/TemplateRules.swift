import Foundation

// Template rules are scenario configuration only. They never enter
// FinanceEngine, so the general ledger engine stays scenario-agnostic.
// [铁律1] [边界14]

struct TemplateCategorySeed: Equatable {
    let name: String
    let icon: String
    let colorHex: String
    let kind: CategoryKind
    let sortOrder: Int16
}

struct TemplateBudgetSeed: Equatable {
    /// nil means the total budget.
    let categoryName: String?
    let period: BudgetPeriod
    let limit: Decimal
}

struct TemplateGoalSeed: Equatable {
    let name: String
    let target: Decimal
    let current: Decimal
    let priority: Int16
    let templateTag: String
}

struct TemplateAccountSeed: Equatable {
    let name: String
    let type: AccountType
    let openingBalance: Decimal
}

struct TemplatePlan: Equatable {
    let categories: [TemplateCategorySeed]
    let budgets: [TemplateBudgetSeed]
    let goals: [TemplateGoalSeed]
    let accounts: [TemplateAccountSeed]
    let notes: [String]
}

protocol TemplateRuleProviding {
    var kind: TemplateKind { get }
    var title: String { get }
    var subtitle: String { get }
    var accentHex: String { get }
    var plan: TemplatePlan { get }
}

struct DailyTemplateRules: TemplateRuleProviding {
    let kind: TemplateKind = .daily
    let title = "日常记账"
    let subtitle = "总预算 + 分类预算 + 应急金，适合稳定收支。"
    let accentHex = ThemeAccent.blue.hex

    let plan = TemplatePlan(
        categories: [
            TemplateCategorySeed(name: "餐饮", icon: "fork.knife", colorHex: "D97706", kind: .expense, sortOrder: 0),
            TemplateCategorySeed(name: "交通", icon: "tram.fill", colorHex: "2563EB", kind: .expense, sortOrder: 1),
            TemplateCategorySeed(name: "购物", icon: "bag.fill", colorHex: "DB2777", kind: .expense, sortOrder: 2),
            TemplateCategorySeed(name: "住房", icon: "house.fill", colorHex: "7C3AED", kind: .expense, sortOrder: 3),
            TemplateCategorySeed(name: "娱乐", icon: "gamecontroller.fill", colorHex: "0891B2", kind: .expense, sortOrder: 4),
            TemplateCategorySeed(name: "医疗", icon: "cross.case.fill", colorHex: "DC2626", kind: .expense, sortOrder: 5),
            TemplateCategorySeed(name: "其他", icon: "ellipsis.circle.fill", colorHex: "8A919C", kind: .expense, sortOrder: 6),
            TemplateCategorySeed(name: "工资", icon: "banknote.fill", colorHex: "248A5B", kind: .income, sortOrder: 0),
            TemplateCategorySeed(name: "副业", icon: "briefcase.fill", colorHex: "2F6FED", kind: .income, sortOrder: 1),
            TemplateCategorySeed(name: "红包", icon: "gift.fill", colorHex: "D9485F", kind: .income, sortOrder: 2),
            TemplateCategorySeed(name: "其他", icon: "plus.circle.fill", colorHex: "6C7480", kind: .income, sortOrder: 3)
        ],
        budgets: [
            TemplateBudgetSeed(categoryName: nil, period: .monthly, limit: 2_000),
            TemplateBudgetSeed(categoryName: "餐饮", period: .monthly, limit: 800),
            TemplateBudgetSeed(categoryName: "交通", period: .monthly, limit: 300)
        ],
        goals: [
            TemplateGoalSeed(
                name: "应急金",
                target: 3_000,
                current: 0,
                priority: 1,
                templateTag: "daily.emergency"
            )
        ],
        accounts: [],
        notes: [
            "总预算 2,000 元/月",
            "餐饮 800 元/月，交通 300 元/月",
            "应急金目标 3,000 元"
        ]
    )
}

struct StudentTemplateRules: TemplateRuleProviding {
    let kind: TemplateKind = .student
    let title = "学生预算"
    let subtitle = "低总预算 + 学习支出 + 旅行目标，适合校园生活。"
    let accentHex = ThemeAccent.green.hex

    let plan = TemplatePlan(
        categories: [
            TemplateCategorySeed(name: "餐饮", icon: "fork.knife", colorHex: "D97706", kind: .expense, sortOrder: 0),
            TemplateCategorySeed(name: "交通", icon: "tram.fill", colorHex: "2563EB", kind: .expense, sortOrder: 1),
            TemplateCategorySeed(name: "学习", icon: "book.fill", colorHex: "7C3AED", kind: .expense, sortOrder: 2),
            TemplateCategorySeed(name: "娱乐", icon: "gamecontroller.fill", colorHex: "0891B2", kind: .expense, sortOrder: 3),
            TemplateCategorySeed(name: "其他", icon: "ellipsis.circle.fill", colorHex: "8A919C", kind: .expense, sortOrder: 4),
            TemplateCategorySeed(name: "生活费", icon: "creditcard.fill", colorHex: "248A5B", kind: .income, sortOrder: 0),
            TemplateCategorySeed(name: "兼职", icon: "briefcase.fill", colorHex: "2F6FED", kind: .income, sortOrder: 1),
            TemplateCategorySeed(name: "奖学金", icon: "rosette", colorHex: "B87400", kind: .income, sortOrder: 2),
            TemplateCategorySeed(name: "其他", icon: "plus.circle.fill", colorHex: "6C7480", kind: .income, sortOrder: 3)
        ],
        budgets: [
            TemplateBudgetSeed(categoryName: nil, period: .monthly, limit: 1_500),
            TemplateBudgetSeed(categoryName: "餐饮", period: .monthly, limit: 700),
            TemplateBudgetSeed(categoryName: "学习", period: .monthly, limit: 200),
            TemplateBudgetSeed(categoryName: "交通", period: .monthly, limit: 150)
        ],
        goals: [
            TemplateGoalSeed(
                name: "旅行基金",
                target: 2_000,
                current: 0,
                priority: 1,
                templateTag: "student.travel"
            )
        ],
        accounts: [],
        notes: [
            "总预算 1,500 元/月",
            "餐饮 700 元/月，学习 200 元/月",
            "旅行基金目标 2,000 元"
        ]
    )
}

struct BuyCarTemplateRules: TemplateRuleProviding {
    static let repairTarget = Decimal(4_400)
    static let carTarget = Decimal(25_000)
    static let minimumSplitRatio = Decimal(7) / Decimal(10)
    static let milkTeaMonthlyLimit = Decimal(150)

    let kind: TemplateKind = .car
    let title = "买车攒钱"
    let subtitle = "修机 4,400 优先，随后买车 25,000；副业收入按 70/30 分账。"
    let accentHex = ThemeAccent.orange.hex

    let plan = TemplatePlan(
        categories: [
            TemplateCategorySeed(name: "餐饮", icon: "fork.knife", colorHex: "D97706", kind: .expense, sortOrder: 0),
            TemplateCategorySeed(name: "交通", icon: "tram.fill", colorHex: "2563EB", kind: .expense, sortOrder: 1),
            TemplateCategorySeed(name: "住房", icon: "house.fill", colorHex: "7C3AED", kind: .expense, sortOrder: 2),
            TemplateCategorySeed(name: "日常", icon: "cart.fill", colorHex: "0891B2", kind: .expense, sortOrder: 3),
            TemplateCategorySeed(name: "奶茶", icon: "cup.and.saucer.fill", colorHex: "DB2777", kind: .expense, sortOrder: 4),
            TemplateCategorySeed(name: "其他", icon: "ellipsis.circle.fill", colorHex: "8A919C", kind: .expense, sortOrder: 5),
            TemplateCategorySeed(name: "工资", icon: "banknote.fill", colorHex: "248A5B", kind: .income, sortOrder: 0),
            TemplateCategorySeed(name: "副业", icon: "briefcase.fill", colorHex: "2F6FED", kind: .income, sortOrder: 1),
            TemplateCategorySeed(name: "其他", icon: "plus.circle.fill", colorHex: "6C7480", kind: .income, sortOrder: 2)
        ],
        budgets: [
            TemplateBudgetSeed(categoryName: nil, period: .monthly, limit: 2_500),
            TemplateBudgetSeed(categoryName: "餐饮", period: .monthly, limit: 800),
            TemplateBudgetSeed(categoryName: "交通", period: .monthly, limit: 300),
            TemplateBudgetSeed(categoryName: "奶茶", period: .monthly, limit: 150)
        ],
        goals: [
            TemplateGoalSeed(
                name: "修机专户",
                target: BuyCarTemplateRules.repairTarget,
                current: 0,
                priority: 1,
                templateTag: "car.repair"
            ),
            TemplateGoalSeed(
                name: "买车专户",
                target: BuyCarTemplateRules.carTarget,
                current: 0,
                priority: 2,
                templateTag: "car.car"
            ),
            TemplateGoalSeed(
                name: "备用金",
                target: 5_000,
                current: 0,
                priority: 3,
                templateTag: "car.reserve"
            )
        ],
        accounts: [
            TemplateAccountSeed(name: "修机专户", type: .goal, openingBalance: 0),
            TemplateAccountSeed(name: "买车专户", type: .goal, openingBalance: 0),
            TemplateAccountSeed(name: "备用金", type: .reserve, openingBalance: 0)
        ],
        notes: [
            "修机 4,400 元优先，达成后新增结余进买车 25,000 元",
            "副业收入至少 70% 进当前目标，最多 30% 进备用金",
            "奶茶 150 元/月，每周最多 2 杯",
            "固定工资 500 元/月；打卡上班每次 100 元"
        ]
    )

    /// 70/30 split. A request below 0.7 is clamped up to protect the goal.
    /// Only future income should call this. [边界16]
    func splitSideHustle(
        _ amount: Decimal,
        requestedRatio: Decimal = BuyCarTemplateRules.minimumSplitRatio
    ) -> (goal: Decimal, reserve: Decimal) {
        guard amount > 0 else {
            return (0, 0)
        }

        let ratio = Swift.min(
            Swift.max(requestedRatio, BuyCarTemplateRules.minimumSplitRatio),
            1
        )
        let goal = (amount * ratio).roundedToCents()
        return (goal, amount - goal)
    }

    /// Repair fund first, then car fund, then overflow to the next target.
    /// [边界15]
    func allocateSurplus(
        _ amount: Decimal,
        repairCurrent: Decimal,
        carCurrent: Decimal
    ) -> (repair: Decimal, car: Decimal, overflow: Decimal) {
        guard amount > 0 else {
            return (0, 0, 0)
        }

        let repairRoom = Swift.max(BuyCarTemplateRules.repairTarget - repairCurrent, 0)
        let repair = Swift.min(amount, repairRoom)
        let afterRepair = amount - repair

        let carRoom = Swift.max(BuyCarTemplateRules.carTarget - carCurrent, 0)
        let car = Swift.min(afterRepair, carRoom)
        let overflow = afterRepair - car

        return (repair, car, overflow)
    }

    func milkTeaWarnings(monthExpense: Decimal, weekCups: Int) -> [String] {
        var warnings: [String] = []

        if monthExpense > BuyCarTemplateRules.milkTeaMonthlyLimit {
            warnings.append("本月奶茶已超过 150 元上限。")
        }
        if weekCups >= 2 {
            warnings.append("本周奶茶已达 2 杯上限。")
        }

        return warnings
    }

    /// Direct spending from a goal account is a savings-discipline violation.
    /// Reserve spending is allowed. [边界15]
    func savingsDisciplineWarning(accountType: AccountType) -> String? {
        guard accountType == .goal else {
            return nil
        }
        return "这是目标专户，直接支出会破坏储蓄纪律；请从现金账户支出。"
    }

    func workShiftIncome() -> Decimal {
        100
    }

    func fixedMonthlyIncome() -> Decimal {
        500
    }

    func annualSubsidies() -> [Decimal] {
        [3_000, 3_500, 4_500]
    }
}

enum TemplateCatalog {
    static let allKinds: [TemplateKind] = [.daily, .student, .car]

    static let all: [any TemplateRuleProviding] = [
        DailyTemplateRules(),
        StudentTemplateRules(),
        BuyCarTemplateRules()
    ]

    static func rules(for kind: TemplateKind) -> (any TemplateRuleProviding)? {
        all.first { $0.kind == kind }
    }
}
