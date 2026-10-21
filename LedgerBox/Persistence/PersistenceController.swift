import CoreData
import Foundation

final class PersistenceController {
    static let shared = PersistenceController()

    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        controller.seedPreviewData()
        return controller
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "LedgerBox")

        if inMemory {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            description.shouldAddStoreAsynchronously = false
            container.persistentStoreDescriptions = [description]
        } else {
            container.persistentStoreDescriptions.forEach { description in
                description.shouldAddStoreAsynchronously = false
            }
        }

        container.loadPersistentStores { _, error in
            if let error {
                assertionFailure("Core Data load failed: \(error.localizedDescription)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.undoManager = nil

        // A failed store load is reported by assertionFailure in Debug. Do not
        // attempt to seed a container that has no persistent store attached.
        guard !container.persistentStoreCoordinator.persistentStores.isEmpty else {
            return
        }
        seedIfNeeded()
    }

    /// Creates the minimum local data needed by the first-round flow: one cash
    /// account and an editable starter category list. No network, login, cloud
    /// sync or third-party SDK is involved. [铁律2]
    private func seedIfNeeded() {
        let context = container.viewContext
        context.performAndWait {
            do {
                if try context.count(for: Account.fetchRequest()) == 0 {
                    let now = Date()
                    let account = Account(context: context)
                    account.id = UUID()
                    account.name = "现金账户"
                    account.type = AccountType.cash.rawValue
                    account.balance = NSDecimalNumber(value: 0)
                    account.currencyCode = "CNY"
                    account.locked = false
                    account.sortOrder = 0
                    account.createdAt = now
                    account.updatedAt = now
                }

                if try context.count(for: Category.fetchRequest()) == 0 {
                    insertDefaultCategories(in: context)
                }

                if context.hasChanges {
                    try context.save()
                }
            } catch {
                context.rollback()
                assertionFailure("Core Data seed failed: \(error.localizedDescription)")
            }
        }
    }

    private func insertDefaultCategories(in context: NSManagedObjectContext) {
        let expense: [(String, String, String)] = [
            ("餐饮", "fork.knife", "E8734A"),
            ("交通", "tram.fill", "3F8FD8"),
            ("购物", "bag.fill", "C26BD4"),
            ("房租", "house.fill", "7A8391"),
            ("娱乐", "gamecontroller.fill", "D89B3C"),
            ("医疗", "cross.case.fill", "D95B6A"),
            ("其他", "ellipsis.circle.fill", "8A919C")
        ]

        let income: [(String, String, String)] = [
            ("工资", "banknote.fill", "248A5B"),
            ("副业", "briefcase.fill", "2F6FED"),
            ("红包", "gift.fill", "D9485F"),
            ("其他", "plus.circle.fill", "6C7480")
        ]

        for (index, item) in expense.enumerated() {
            let category = Category(context: context)
            category.id = UUID()
            category.name = item.0
            category.icon = item.1
            category.kind = CategoryKind.expense.rawValue
            category.colorHex = item.2
            category.isSoftDeleted = false
            category.sortOrder = Int16(index)
        }

        for (index, item) in income.enumerated() {
            let category = Category(context: context)
            category.id = UUID()
            category.name = item.0
            category.icon = item.1
            category.kind = CategoryKind.income.rawValue
            category.colorHex = item.2
            category.isSoftDeleted = false
            category.sortOrder = Int16(index)
        }
    }

    /// Preview data is in-memory only. It never touches the user's store.
    private func seedPreviewData() {
        let context = container.viewContext
        context.performAndWait {
            do {
                guard let account = try context.fetch(Account.fetchRequest()).first else {
                    return
                }
                let categories = try context.fetch(Category.fetchRequest())
                let salary = categories.first { $0.name == "工资" }
                let food = categories.first { $0.name == "餐饮" }
                let transport = categories.first { $0.name == "交通" }

                try LedgerService.record(
                    type: .income,
                    amount: 500,
                    date: Date().addingTimeInterval(-3 * 86_400),
                    note: "零花钱",
                    account: account,
                    category: salary,
                    in: context
                )

                try LedgerService.record(
                    type: .expense,
                    amount: 32.50,
                    date: Date().addingTimeInterval(-2 * 86_400),
                    note: "午饭",
                    account: account,
                    category: food,
                    in: context
                )

                try LedgerService.record(
                    type: .expense,
                    amount: 18,
                    date: Date().addingTimeInterval(-86_400),
                    note: "地铁",
                    account: account,
                    category: transport,
                    in: context
                )

                try LedgerService.record(
                    type: .income,
                    amount: 120,
                    date: Date().addingTimeInterval(-12 * 3_600),
                    note: "周末打工",
                    account: account,
                    category: salary,
                    in: context
                )

                let totalBudget = Budget(context: context)
                totalBudget.id = UUID()
                totalBudget.categoryId = nil
                totalBudget.period = BudgetPeriod.monthly.rawValue
                totalBudget.limitAmount = NSDecimalNumber(value: 2_000)
                totalBudget.startDate = Date()
                totalBudget.enabled = true

                if let food {
                    let foodBudget = Budget(context: context)
                    foodBudget.id = UUID()
                    foodBudget.categoryId = food.id
                    foodBudget.period = BudgetPeriod.monthly.rawValue
                    foodBudget.limitAmount = NSDecimalNumber(value: 600)
                    foodBudget.startDate = Date()
                    foodBudget.enabled = true
                }

                let phoneGoal = SavingsGoal(context: context)
                phoneGoal.id = UUID()
                phoneGoal.name = "换手机"
                phoneGoal.targetAmount = NSDecimalNumber(value: 5_000)
                phoneGoal.currentAmount = NSDecimalNumber(value: 1_200)
                phoneGoal.priority = 1
                phoneGoal.status = SavingsGoalStatus.active.rawValue
                phoneGoal.templateTag = nil
                phoneGoal.deadline = Calendar.current.date(byAdding: .month, value: 6, to: Date())
                phoneGoal.createdAt = Date()

                let tripGoal = SavingsGoal(context: context)
                tripGoal.id = UUID()
                tripGoal.name = "周末旅行"
                tripGoal.targetAmount = NSDecimalNumber(value: 1_500)
                tripGoal.currentAmount = NSDecimalNumber(value: 1_500)
                tripGoal.priority = 2
                tripGoal.status = SavingsGoalStatus.achieved.rawValue
                tripGoal.templateTag = nil
                tripGoal.deadline = nil
                tripGoal.createdAt = Date()

                try context.save()
            } catch {
                context.rollback()
                assertionFailure("Preview seed failed: \(error.localizedDescription)")
            }
        }
    }
}
