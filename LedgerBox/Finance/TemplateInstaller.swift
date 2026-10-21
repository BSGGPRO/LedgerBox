import CoreData
import Foundation

struct TemplateApplyResult {
    let title: String
    let categoryCount: Int
    let budgetCount: Int
    let goalCount: Int
    let accountCount: Int

    var summary: String {
        "已应用\(title)：\(categoryCount) 个分类、\(budgetCount) 个预算、\(goalCount) 个目标、\(accountCount) 个专户。"
    }
}

enum TemplateInstallError: LocalizedError {
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let message):
            return "应用模板失败：\(message)"
        }
    }
}

/// Applies a template plan to Core Data. This is the only place that writes
/// template seed data. Existing transactions, balances, budgets and goal
/// progress are preserved wherever possible. [边界14]
enum TemplateInstaller {

    @discardableResult
    static func apply(
        _ rules: any TemplateRuleProviding,
        in context: NSManagedObjectContext
    ) throws -> TemplateApplyResult {
        do {
            let categories = try upsertCategories(rules.plan.categories, in: context)
            var expenseByName: [String: Category] = [:]
            for category in categories where category.categoryKind == .expense {
                if expenseByName[category.name] == nil {
                    expenseByName[category.name] = category
                }
            }

            try upsertBudgets(rules.plan.budgets, expenseByName: expenseByName, in: context)
            try upsertGoals(rules.plan.goals, in: context)
            try upsertAccounts(rules.plan.accounts, in: context)

            let template = try activate(rules, in: context)
            try attachSettings(to: template, accentHex: rules.accentHex, in: context)
            try context.save()

            return TemplateApplyResult(
                title: rules.title,
                categoryCount: rules.plan.categories.count,
                budgetCount: rules.plan.budgets.count,
                goalCount: rules.plan.goals.count,
                accountCount: rules.plan.accounts.count
            )
        } catch {
            context.rollback()
            throw TemplateInstallError.saveFailed(error.localizedDescription)
        }
    }

    private static func upsertCategories(
        _ seeds: [TemplateCategorySeed],
        in context: NSManagedObjectContext
    ) throws -> [Category] {
        let existing = try context.fetch(Category.fetchRequest())
        var byKey: [String: Category] = [:]

        for category in existing {
            byKey[key(kind: category.categoryKind, name: category.name)] = category
        }

        var result: [Category] = []
        for seed in seeds {
            let categoryKey = key(kind: seed.kind, name: seed.name)
            let category = byKey[categoryKey] ?? Category(context: context)

            if byKey[categoryKey] == nil {
                category.id = UUID()
            }

            category.name = seed.name
            category.icon = seed.icon
            category.kind = seed.kind.rawValue
            category.colorHex = seed.colorHex
            category.isSoftDeleted = false
            category.sortOrder = seed.sortOrder

            byKey[categoryKey] = category
            result.append(category)
        }

        return result
    }

    private static func upsertBudgets(
        _ seeds: [TemplateBudgetSeed],
        expenseByName: [String: Category],
        in context: NSManagedObjectContext
    ) throws {
        let existing = try context.fetch(Budget.fetchRequest())
        var byKey: [String: Budget] = [:]

        for budget in existing {
            let budgetKey = budget.categoryId?.uuidString ?? "total"
            if byKey[budgetKey] == nil {
                byKey[budgetKey] = budget
            }
        }

        for seed in seeds {
            let categoryID: UUID?
            if let categoryName = seed.categoryName {
                guard let category = expenseByName[categoryName] else {
                    continue
                }
                categoryID = category.id
            } else {
                categoryID = nil
            }

            let budgetKey = categoryID?.uuidString ?? "total"
            let budget = byKey[budgetKey] ?? Budget(context: context)

            if byKey[budgetKey] == nil {
                budget.id = UUID()
                budget.startDate = Date()
            }

            budget.categoryId = categoryID
            budget.period = seed.period.rawValue
            budget.limitAmount = NSDecimalNumber(decimal: seed.limit.roundedToCents())
            budget.enabled = true

            byKey[budgetKey] = budget
        }
    }

    private static func upsertGoals(
        _ seeds: [TemplateGoalSeed],
        in context: NSManagedObjectContext
    ) throws {
        let existing = try context.fetch(SavingsGoal.fetchRequest())
        var byTag: [String: SavingsGoal] = [:]

        for goal in existing {
            if let tag = goal.templateTag {
                byTag[tag] = goal
            }
        }

        for seed in seeds {
            let isNew = byTag[seed.templateTag] == nil
            let goal = byTag[seed.templateTag] ?? SavingsGoal(context: context)

            if isNew {
                goal.id = UUID()
                goal.createdAt = Date()
                goal.currentAmount = NSDecimalNumber(decimal: seed.current.roundedToCents())
                goal.deadline = nil
                goal.status = SavingsGoalStatus.active.rawValue
            }

            goal.name = seed.name
            goal.targetAmount = NSDecimalNumber(decimal: seed.target.roundedToCents())
            goal.priority = seed.priority
            goal.templateTag = seed.templateTag

            let current = goal.currentValue
            if current >= seed.target {
                goal.status = SavingsGoalStatus.achieved.rawValue
            } else if !isNew, goal.goalStatus == .achieved {
                goal.status = SavingsGoalStatus.active.rawValue
            }

            byTag[seed.templateTag] = goal
        }
    }

    private static func upsertAccounts(
        _ seeds: [TemplateAccountSeed],
        in context: NSManagedObjectContext
    ) throws {
        let existing = try context.fetch(Account.fetchRequest())
        var byName: [String: Account] = [:]
        for account in existing where byName[account.name] == nil {
            byName[account.name] = account
        }

        for (index, seed) in seeds.enumerated() {
            let account = byName[seed.name] ?? Account(context: context)

            if byName[seed.name] == nil {
                account.id = UUID()
                account.balance = NSDecimalNumber(decimal: seed.openingBalance.roundedToCents())
                account.locked = false
                account.createdAt = Date()
            }

            account.name = seed.name
            account.type = seed.type.rawValue
            account.currencyCode = "CNY"
            account.sortOrder = Int16(index)
            account.updatedAt = Date()

            byName[seed.name] = account
        }
    }

    private static func activate(
        _ rules: any TemplateRuleProviding,
        in context: NSManagedObjectContext
    ) throws -> TemplateRules {
        let all = try context.fetch(TemplateRules.fetchRequest())
        for template in all {
            template.active = false
        }

        let existing = all.first { $0.type == rules.kind.rawValue }
        let template = existing ?? TemplateRules(context: context)

        if existing == nil {
            template.id = UUID()
            template.createdAt = Date()
        }

        template.name = rules.title
        template.type = rules.kind.rawValue
        template.configJSON = configJSON(for: rules)
        template.active = true

        return template
    }

    private static func attachSettings(
        to template: TemplateRules,
        accentHex: String,
        in context: NSManagedObjectContext
    ) throws {
        let existing = try context.fetch(AppSettings.fetchRequest()).first
        let settings = existing ?? AppSettings(context: context)

        if existing == nil {
            settings.id = UUID()
            settings.themeMode = ThemeMode.system.rawValue
            settings.accentColorHex = accentHex
            settings.sideHustleSplitRatio = NSDecimalNumber(
                decimal: Decimal(7) / Decimal(10)
            )
        }

        settings.activeTemplateId = template.id
        settings.updatedAt = Date()
    }

    private static func configJSON(for rules: any TemplateRuleProviding) -> String {
        let payload: [String: Any] = [
            "version": 1,
            "kind": rules.kind.rawValue,
            "title": rules.title,
            "notes": rules.plan.notes
        ]

        guard
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }

        return string
    }

    private static func key(kind: CategoryKind, name: String) -> String {
        "\(kind.rawValue)|\(name)"
    }
}
