import CoreData
import Foundation
import OSLog

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

// MARK: - Diagnostics

struct LedgerLogEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let level: String
    let event: String
    let detail: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: String,
        event: String,
        detail: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.event = event
        self.detail = detail
    }
}

/// Small, privacy-conscious diagnostic log. Callers must never pass raw
/// screenshots, question text, merchant names, amounts, order IDs, or tokens.
final class LedgerLog {

    static let shared = LedgerLog()

    private let fileURL: URL
    private let lock = NSLock()
    private let logger = Logger(
        subsystem: "com.example.ledgerbox",
        category: "diagnostics"
    )
    private var entries: [LedgerLogEntry]
    private let maxEntries = 500

    init(fileURL: URL? = nil) {
        let resolved = fileURL ?? Self.defaultFileURL()
        self.fileURL = resolved
        try? FileManager.default.createDirectory(
            at: resolved.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        self.entries = Self.load(from: resolved)
    }

    func info(_ event: String, detail: String = "") {
        append(level: "info", event: event, detail: detail)
    }

    func warning(_ event: String, detail: String = "") {
        append(level: "warning", event: event, detail: detail)
    }

    func error(_ event: String, detail: String = "") {
        append(level: "error", event: event, detail: detail)
    }

    func exportText() -> String {
        lock.lock()
        defer { lock.unlock() }
        let formatter = ISO8601DateFormatter()
        return entries.map { entry in
            let time = formatter.string(from: entry.timestamp)
            let suffix = entry.detail.isEmpty ? "" : " | \(entry.detail)"
            return "[\(time)] \(entry.level.uppercased()) \(entry.event)\(suffix)"
        }.joined(separator: "\n")
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func append(level: String, event: String, detail: String) {
        let safeEvent = String(event.prefix(80))
        let safeDetail = String(detail.prefix(240))
        let entry = LedgerLogEntry(
            level: level,
            event: safeEvent,
            detail: safeDetail
        )

        switch level {
        case "error":
            logger.error("\(safeEvent, privacy: .public) \(safeDetail, privacy: .public)")
        case "warning":
            logger.warning("\(safeEvent, privacy: .public) \(safeDetail, privacy: .public)")
        default:
            logger.info("\(safeEvent, privacy: .public) \(safeDetail, privacy: .public)")
        }

        lock.lock()
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        let snapshot = entries
        lock.unlock()

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Diagnostics must never break the ledger write path.
            logger.error("log_persist_failed")
        }
    }

    private static func defaultFileURL() -> URL {
        let manager = FileManager.default
        let base = manager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? manager.temporaryDirectory
        let directory = base.appendingPathComponent("LedgerBox", isDirectory: true)
        try? manager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent("Diagnostics.json")
    }

    private static func load(from url: URL) -> [LedgerLogEntry] {
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([LedgerLogEntry].self, from: data)) ?? []
    }
}
