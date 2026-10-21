import CoreData
import Foundation

enum LedgerError: LocalizedError {
    case invalidAmount
    case futureDate
    case missingAccount
    case invalidTransfer
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return "金额必须大于 0，且最多保留两位小数。"
        case .futureDate:
            return "记账日期不能晚于当前时间。"
        case .missingAccount:
            return "找不到对应账户，请重新选择。"
        case .invalidTransfer:
            return "转账需要选择两个不同的账户。"
        case .saveFailed(let message):
            return "保存失败：\(message)"
        }
    }
}

/// A validated-in-advance transaction draft. Batching exists so scenario
/// actions such as a 70/30 side-hustle split can save atomically.
struct LedgerDraft {
    let type: TransactionType
    let amount: Decimal
    let date: Date
    let note: String?
    let account: Account
    let toAccount: Account?
    let category: Category?
    let templateTag: String?

    init(
        type: TransactionType,
        amount: Decimal,
        date: Date,
        note: String? = nil,
        account: Account,
        toAccount: Account? = nil,
        category: Category? = nil,
        templateTag: String? = nil
    ) {
        self.type = type
        self.amount = amount
        self.date = date
        self.note = note
        self.account = account
        self.toAccount = toAccount
        self.category = category
        self.templateTag = templateTag
    }
}

/// Core Data write boundary. FinanceEngine stays pure; this service is the only
/// place that mutates account balances for transactions.
/// [铁律1] [铁律2] [边界1] [边界2] [边界8] [边界9]
enum LedgerService {

    @discardableResult
    static func record(
        type: TransactionType,
        amount: Decimal,
        date: Date,
        note: String?,
        account: Account,
        toAccount: Account? = nil,
        category: Category? = nil,
        templateTag: String? = nil,
        in context: NSManagedObjectContext
    ) throws -> LedgerTransaction {
        let draft = LedgerDraft(
            type: type,
            amount: amount,
            date: date,
            note: note,
            account: account,
            toAccount: toAccount,
            category: category,
            templateTag: templateTag
        )
        let saved = try recordBatch([draft], in: context)
        guard let transaction = saved.first else {
            throw LedgerError.saveFailed("未生成交易记录。")
        }
        return transaction
    }

    /// Validates every draft before creating anything, then saves once. If the
    /// save fails the whole context rolls back, so a split cannot be half-written.
    @discardableResult
    static func recordBatch(
        _ drafts: [LedgerDraft],
        in context: NSManagedObjectContext
    ) throws -> [LedgerTransaction] {
        guard !drafts.isEmpty else {
            return []
        }

        for draft in drafts {
            try validate(draft, in: context)
        }

        var saved: [LedgerTransaction] = []

        for draft in drafts {
            let normalizedAmount = draft.amount.roundedToCents()
            let trimmedNote = draft.note?.trimmingCharacters(in: .whitespacesAndNewlines)
            let savedNote = (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote

            let transaction = LedgerTransaction(context: context)
            transaction.id = UUID()
            transaction.type = draft.type.rawValue
            transaction.categoryId = draft.type == .transfer ? nil : draft.category?.id
            transaction.accountId = draft.account.id
            transaction.toAccountId = draft.type == .transfer ? draft.toAccount?.id : nil
            transaction.amount = NSDecimalNumber(decimal: normalizedAmount)
            transaction.date = draft.date
            transaction.note = savedNote
            transaction.createdAt = Date()
            transaction.templateTag = draft.templateTag

            applyBalanceImpact(
                type: draft.type,
                amount: normalizedAmount,
                account: draft.account,
                toAccount: draft.toAccount
            )

            saved.append(transaction)
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw LedgerError.saveFailed(error.localizedDescription)
        }

        return saved
    }

    /// Deleting a transaction must reverse its account impact before deleting
    /// the row. A transfer reverses both sides. [边界1] [边界2]
    static func delete(_ transaction: LedgerTransaction, in context: NSManagedObjectContext) throws {
        guard transaction.managedObjectContext === context else {
            throw LedgerError.saveFailed("交易不属于当前数据上下文。")
        }

        let type = transaction.transactionType
        let amount = transaction.amountValue

        if let account = try account(id: transaction.accountId, in: context) {
            switch type {
            case .income, .refund:
                account.setBalance(account.balanceValue - amount)
            case .expense:
                account.setBalance(account.balanceValue + amount)
            case .transfer:
                account.setBalance(account.balanceValue + amount)
            }
        }

        if type == .transfer, let toAccountID = transaction.toAccountId,
           let toAccount = try account(id: toAccountID, in: context) {
            toAccount.setBalance(toAccount.balanceValue - amount)
        }

        context.delete(transaction)

        do {
            try context.save()
        } catch {
            context.rollback()
            throw LedgerError.saveFailed(error.localizedDescription)
        }
    }

    static func account(id: UUID, in context: NSManagedObjectContext) throws -> Account? {
        let request = Account.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", nsUUID(id))
        return try context.fetch(request).first
    }

    private static func validate(
        _ draft: LedgerDraft,
        in context: NSManagedObjectContext
    ) throws {
        guard draft.amount.roundedToCents() > 0 else {
            throw LedgerError.invalidAmount
        }
        guard draft.date <= Date() else {
            throw LedgerError.futureDate
        }
        guard draft.account.managedObjectContext === context else {
            throw LedgerError.missingAccount
        }

        if let category = draft.category,
           category.managedObjectContext !== context {
            throw LedgerError.saveFailed("分类不属于当前数据上下文。")
        }

        if draft.type == .transfer {
            guard
                let toAccount = draft.toAccount,
                toAccount.managedObjectContext === context,
                toAccount.id != draft.account.id
            else {
                throw LedgerError.invalidTransfer
            }
        }
    }

    private static func applyBalanceImpact(
        type: TransactionType,
        amount: Decimal,
        account: Account,
        toAccount: Account?
    ) {
        switch type {
        case .income, .refund:
            account.setBalance(account.balanceValue + amount)
        case .expense:
            account.setBalance(account.balanceValue - amount)
        case .transfer:
            guard let toAccount else { return }
            account.setBalance(account.balanceValue - amount)
            toAccount.setBalance(toAccount.balanceValue + amount)
        }
    }

    private static func nsUUID(_ id: UUID) -> NSUUID {
        // uuidString always produces a valid UUID string.
        NSUUID(uuidString: id.uuidString)!
    }
}
