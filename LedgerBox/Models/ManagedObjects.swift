import CoreData
import Foundation

// The Core Data model uses manual/none code generation. Every NSManagedObject
// subclass is declared here so the Xcode project does not depend on generated
// source files. Entity names and attribute names must match
// Resources/LedgerBox.xcdatamodeld/LedgerBox.xcdatamodel/contents exactly.

@objc(Account)
final class Account: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var type: String
    @NSManaged var balance: NSDecimalNumber
    @NSManaged var currencyCode: String
    @NSManaged var locked: Bool
    @NSManaged var sortOrder: Int16
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date

    @nonobjc class func fetchRequest() -> NSFetchRequest<Account> {
        NSFetchRequest<Account>(entityName: "Account")
    }

    var accountType: AccountType {
        AccountType(rawValue: type) ?? .cash
    }

    /// Core Data stores Decimal attributes through NSDecimalNumber. All public
    /// calculations immediately convert back to Decimal. [铁律2] [边界3]
    var balanceValue: Decimal {
        balance.decimalValue
    }

    func setBalance(_ value: Decimal) {
        balance = NSDecimalNumber(decimal: value.roundedToCents())
        updatedAt = Date()
    }
}

@objc(LedgerTransaction)
final class LedgerTransaction: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var type: String
    @NSManaged var categoryId: UUID?
    @NSManaged var accountId: UUID
    @NSManaged var toAccountId: UUID?
    @NSManaged var amount: NSDecimalNumber
    @NSManaged var date: Date
    @NSManaged var note: String?
    @NSManaged var createdAt: Date
    @NSManaged var templateTag: String?

    @nonobjc class func fetchRequest() -> NSFetchRequest<LedgerTransaction> {
        NSFetchRequest<LedgerTransaction>(entityName: "Transaction")
    }

    var transactionType: TransactionType {
        TransactionType(rawValue: type) ?? .expense
    }

    /// See Account.balanceValue for the NSDecimalNumber boundary. [铁律2]
    var amountValue: Decimal {
        amount.decimalValue
    }
}

extension LedgerTransaction: TransactionProviding {
    var financeType: TransactionType { transactionType }
    var financeCategoryID: UUID? { categoryId }
    var financeAccountID: UUID { accountId }
    var financeAmount: Decimal { amountValue }
    var financeDate: Date { date }
}

@objc(Category)
final class Category: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var icon: String
    @NSManaged var kind: String
    @NSManaged var colorHex: String
    // NSManagedObject already declares isDeleted. The soft-delete flag therefore
    // uses a distinct persisted name. [边界6]
    @NSManaged var isSoftDeleted: Bool
    @NSManaged var sortOrder: Int16

    @nonobjc class func fetchRequest() -> NSFetchRequest<Category> {
        NSFetchRequest<Category>(entityName: "Category")
    }

    var categoryKind: CategoryKind {
        CategoryKind(rawValue: kind) ?? .expense
    }

    var isSelectable: Bool {
        !isSoftDeleted
    }
}

@objc(Budget)
final class Budget: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var categoryId: UUID?
    @NSManaged var period: String
    @NSManaged var limitAmount: NSDecimalNumber
    @NSManaged var startDate: Date
    @NSManaged var enabled: Bool

    @nonobjc class func fetchRequest() -> NSFetchRequest<Budget> {
        NSFetchRequest<Budget>(entityName: "Budget")
    }

    var budgetPeriod: BudgetPeriod {
        BudgetPeriod(rawValue: period) ?? .monthly
    }

    var limitValue: Decimal {
        limitAmount.decimalValue
    }
}

@objc(SavingsGoal)
final class SavingsGoal: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var targetAmount: NSDecimalNumber
    @NSManaged var currentAmount: NSDecimalNumber
    @NSManaged var priority: Int16
    @NSManaged var status: String
    @NSManaged var templateTag: String?
    @NSManaged var deadline: Date?
    @NSManaged var createdAt: Date

    @nonobjc class func fetchRequest() -> NSFetchRequest<SavingsGoal> {
        NSFetchRequest<SavingsGoal>(entityName: "SavingsGoal")
    }

    var goalStatus: SavingsGoalStatus {
        SavingsGoalStatus(rawValue: status) ?? .active
    }

    var targetValue: Decimal {
        targetAmount.decimalValue
    }

    var currentValue: Decimal {
        currentAmount.decimalValue
    }

    /// Double is used only for drawing the progress ring. [铁律2]
    var progressRatio: Double {
        guard targetValue > 0 else { return 0 }
        return Swift.min(Swift.max(currentValue.doubleValue / targetValue.doubleValue, 0), 1)
    }
}

@objc(TemplateRules)
final class TemplateRules: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var type: String
    @NSManaged var configJSON: String
    @NSManaged var active: Bool
    @NSManaged var createdAt: Date

    @nonobjc class func fetchRequest() -> NSFetchRequest<TemplateRules> {
        NSFetchRequest<TemplateRules>(entityName: "TemplateRules")
    }

    var templateKind: TemplateKind {
        TemplateKind(rawValue: type) ?? .custom
    }
}

/// The entity is called AppSettings because Settings is also a SwiftUI scene
/// name on Apple platforms. The persisted fields match the data dictionary.
@objc(AppSettings)
final class AppSettings: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var themeMode: String
    @NSManaged var accentColorHex: String
    @NSManaged var activeTemplateId: UUID?
    @NSManaged var sideHustleSplitRatio: NSDecimalNumber
    @NSManaged var updatedAt: Date

    @nonobjc class func fetchRequest() -> NSFetchRequest<AppSettings> {
        NSFetchRequest<AppSettings>(entityName: "AppSettings")
    }

    var splitRatioValue: Decimal {
        sideHustleSplitRatio.decimalValue
    }
}
