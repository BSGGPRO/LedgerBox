import CoreData
import Foundation

// MARK: - Draft and session

struct ImportDraft: Identifiable {
    let id: UUID
    let source: ReceiptSource
    let rawText: String
    let cleanText: String
    let merchant: String
    let amount: Decimal
    let fee: Decimal?
    let date: Date
    let category: LedgerCategory
    let type: TransactionType
    let accountID: UUID?
    let note: String?
    let orderIDHash: String?
    let dedupeKey: String
    let warnings: [ReceiptWarning]
    let modelConfidence: Double
    let needsReview: Bool
    let transferSplit: TransferSplit?

    init(
        id: UUID = UUID(),
        source: ReceiptSource,
        rawText: String,
        cleanText: String,
        merchant: String,
        amount: Decimal,
        fee: Decimal? = nil,
        date: Date,
        category: LedgerCategory,
        type: TransactionType,
        accountID: UUID? = nil,
        note: String? = nil,
        orderIDHash: String? = nil,
        dedupeKey: String,
        warnings: [ReceiptWarning] = [],
        modelConfidence: Double = 0,
        needsReview: Bool = false,
        transferSplit: TransferSplit? = nil
    ) {
        self.id = id
        self.source = source
        self.rawText = rawText
        self.cleanText = cleanText
        self.merchant = merchant
        self.amount = amount
        self.fee = fee
        self.date = date
        self.category = category
        self.type = type
        self.accountID = accountID
        self.note = note
        self.orderIDHash = orderIDHash
        self.dedupeKey = dedupeKey
        self.warnings = warnings
        self.modelConfidence = modelConfidence
        self.needsReview = needsReview
        self.transferSplit = transferSplit
    }
}

struct ImportSession: Codable, Identifiable, Equatable {
    enum Status: String, Codable, Equatable {
        case committed
        case undone
    }

    let id: UUID
    let createdAt: Date
    let dedupeKey: String
    let transactionIDs: [UUID]
    var status: Status

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        dedupeKey: String,
        transactionIDs: [UUID],
        status: Status = .committed
    ) {
        self.id = id
        self.createdAt = createdAt
        self.dedupeKey = dedupeKey
        self.transactionIDs = transactionIDs
        self.status = status
    }
}

enum ImportError: LocalizedError, Equatable {
    case duplicate(existingID: UUID)
    case duplicateInBatch
    case invalidAmount
    case accountUnavailable
    case transferRequiresDestinationAccount
    case sessionNotFound
    case historyWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .duplicate:
            return "这笔账单已经导入过，请勿重复记账。"
        case .duplicateInBatch:
            return "这张图里有两笔账单的识别结果完全相同，请先修改或删除其中一笔。"
        case .invalidAmount:
            return "导入金额无效。"
        case .accountUnavailable:
            return "找不到可写入的账户。"
        case .transferRequiresDestinationAccount:
            return "转账/提现需要选择转入账户。"
        case .sessionNotFound:
            return "找不到这次导入记录。"
        case .historyWriteFailed(let message):
            return "导入记录保存失败：\(message)"
        }
    }
}

// MARK: - History

/// Small JSON-backed ledger of import sessions. It lives in Application
/// Support and is intentionally independent of Core Data so a duplicate can be
/// detected before any transaction is written.
final class ImportHistoryStore {

    static let shared = ImportHistoryStore()

    private let fileURL: URL
    private let lock = NSLock()
    private var sessions: [ImportSession] = []

    /// Tests can pass a unique temporary URL. Production uses Application
    /// Support/LedgerBox/ImportHistory.json.
    init(fileURL: URL? = nil) {
        let resolved = fileURL ?? Self.defaultFileURL()
        self.fileURL = resolved

        try? FileManager.default.createDirectory(
            at: resolved.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        self.sessions = Self.load(from: resolved)
    }

    /// Newest committed session for a dedupe key, if any. Undone sessions do
    /// not block a later re-import.
    func duplicate(for dedupeKey: String) -> ImportSession? {
        lock.lock()
        defer { lock.unlock() }
        return sessions.last(where: {
            $0.dedupeKey == dedupeKey && $0.status == .committed
        })
    }

    func add(_ session: ImportSession) throws {
        lock.lock()
        defer { lock.unlock() }

        var updated = sessions
        if let index = updated.firstIndex(where: { $0.id == session.id }) {
            updated[index] = session
        } else {
            updated.append(session)
        }
        try persist(updated)
        sessions = updated
    }

    func markUndone(id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }

        guard let index = sessions.firstIndex(where: { $0.id == id }) else {
            throw ImportError.sessionNotFound
        }
        guard sessions[index].status != .undone else {
            return
        }

        var updated = sessions
        updated[index].status = .undone
        try persist(updated)
        sessions = updated
    }

    func session(id: UUID) -> ImportSession? {
        lock.lock()
        defer { lock.unlock() }
        return sessions.first(where: { $0.id == id })
    }

    // MARK: Private

    private static func defaultFileURL() -> URL {
        let manager = FileManager.default
        let base = manager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? manager.temporaryDirectory
        let directory = base.appendingPathComponent("LedgerBox", isDirectory: true)
        try? manager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return directory.appendingPathComponent("ImportHistory.json")
    }

    private static func load(from url: URL) -> [ImportSession] {
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([ImportSession].self, from: data)
        } catch {
            // Never let the next successful commit overwrite a corrupt history:
            // that would silently drop every prior session ID and disable both
            // duplicate protection and undo. Keep a forensic copy instead.
            let stamp = ISO8601DateFormatter()
                .string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("ImportHistory.corrupt-\(stamp).json")
            do {
                try FileManager.default.moveItem(at: url, to: backup)
            } catch {
                // If move fails, keep the original until the forensic copy is
                // safely written; never delete the only copy.
                do {
                    try data.write(to: backup, options: [.atomic])
                    try? FileManager.default.removeItem(at: url)
                } catch {
                    // Leave the unreadable file in place. The next launch will
                    // try again rather than silently overwrite it.
                }
            }
            return []
        }
    }

    private func persist(_ value: [ImportSession]) throws {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(value)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            throw ImportError.historyWriteFailed(error.localizedDescription)
        }
    }
}

// MARK: - Commit service

/// Turns OCR output into a reviewable draft, then writes through
/// `LedgerService` only. No other Core Data mutation path is used here.
enum ImportCommitService {

    /// Segments one screenshot into independent bills, then builds one draft per
    /// bill. A single-bill screenshot follows the same parser as before.
    static func makeDrafts(
        from ocr: OCRResult,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ImportDraft] {
        let segments = ReceiptSegmenter.segments(from: ocr)
        var candidates: [ImportDraft] = []

        if segments.count > 1 {
            for segment in segments {
                let segmentOCR = OCRResult(
                    lines: segment.lines,
                    imageSize: ocr.imageSize
                )
                if let draft = makeDraft(
                    from: segmentOCR,
                    now: now,
                    calendar: calendar
                ) {
                    candidates.append(draft)
                }
            }
        }

        if candidates.isEmpty,
           let whole = makeDraft(from: ocr, now: now, calendar: calendar) {
            candidates = [whole]
        }

        // Only a shared order hash is strong proof that two blocks are the same
        // bill. Two identical purchases without an order ID must remain two
        // separate cards; the user can still delete one before committing.
        var seenOrderHashes = Set<String>()
        return candidates.filter { draft in
            guard let orderHash = draft.orderIDHash else {
                return true
            }
            return seenOrderHashes.insert(orderHash).inserted
        }
    }

    static func makeDraft(
        from ocr: OCRResult,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ImportDraft? {
        let fields = ReceiptParser.parse(ocr.text, now: now, calendar: calendar)
        guard let amount = fields.amount, amount > 0 else {
            return nil
        }

        let categoryResult = LedgerCategoryClassifier.shared.classify(
            ocr.text,
            fields: fields
        )
        let transferSplit = ReceiptParser.transferSplit(in: fields.normalizedText)

        var warnings = fields.warnings
        if ocr.isLowConfidence, !warnings.contains(.lowOCRConfidence) {
            warnings.append(.lowOCRConfidence)
        }
        if categoryResult.modelIntent == nil, !warnings.contains(.modelFallback) {
            warnings.append(.modelFallback)
        }

        let merchant = resolvedMerchant(for: fields)
        let needsReview = categoryResult.needsReview
            || ocr.isLowConfidence
            || warnings.contains(.ambiguousAmount)
            || warnings.contains(.missingDate)
            || warnings.contains(.feeSplitAmbiguous)

        return ImportDraft(
            source: fields.source,
            rawText: fields.rawText,
            cleanText: fields.normalizedText,
            merchant: merchant,
            amount: amount,
            fee: fields.fee,
            date: fields.occurredAt ?? now,
            category: categoryResult.category,
            type: transactionType(for: fields),
            accountID: nil,
            note: merchant,
            orderIDHash: fields.orderIDHash,
            dedupeKey: ReceiptParser.dedupeKey(for: fields, calendar: calendar),
            warnings: warnings,
            modelConfidence: categoryResult.confidence,
            needsReview: needsReview,
            transferSplit: transferSplit
        )
    }

    @discardableResult
    static func commit(
        _ draft: ImportDraft,
        account: Account,
        toAccount: Account? = nil,
        category: Category?,
        context: NSManagedObjectContext,
        history: ImportHistoryStore = .shared
    ) throws -> ImportSession {
        // Duplicate detection MUST happen before any balance mutation.
        if let existing = history.duplicate(for: draft.dedupeKey) {
            throw ImportError.duplicate(existingID: existing.id)
        }

        guard draft.amount.roundedToCents() > 0 else {
            throw ImportError.invalidAmount
        }
        guard account.managedObjectContext === context else {
            throw ImportError.accountUnavailable
        }
        if draft.type == .transfer {
            guard let toAccount,
                  toAccount.managedObjectContext === context,
                  toAccount.objectID != account.objectID else {
                throw ImportError.transferRequiresDestinationAccount
            }
        }

        var recorded: [LedgerTransaction] = []
        do {
            let split: TransferSplit?
            if draft.type == .transfer, let fee = draft.fee, fee > 0 {
                let mode = draft.transferSplit?.mode ?? .feeDeductedFromPrincipal
                switch mode {
                case .feeDeductedFromPrincipal:
                    split = TransferSplit(
                        principal: draft.amount,
                        fee: fee,
                        credited: Swift.max(draft.amount - fee, Decimal.zero),
                        cashOut: draft.amount,
                        mode: mode
                    )
                case .feePaidSeparately:
                    split = TransferSplit(
                        principal: draft.amount,
                        fee: fee,
                        credited: draft.amount,
                        cashOut: draft.amount + fee,
                        mode: mode
                    )
                }
            } else {
                split = nil
            }
            let transferAmount = split?.credited ?? draft.amount
            let fee = split?.fee ?? 0

            let transfer = try LedgerService.record(
                type: draft.type,
                amount: transferAmount,
                date: draft.date,
                note: draft.note,
                account: account,
                toAccount: draft.type == .transfer ? toAccount : nil,
                category: category,
                in: context
            )
            recorded.append(transfer)

            // A transfer fee is an asymmetric cash-out: the source pays the
            // fee but the destination receives only the credited amount. Record
            // it separately so undo removes both entries and balances restore.
            if fee > 0 {
                let feeTransaction = try LedgerService.record(
                    type: .expense,
                    amount: fee,
                    date: draft.date,
                    note: "转账手续费",
                    account: account,
                    category: nil,
                    in: context
                )
                recorded.append(feeTransaction)
            }
        } catch {
            for transaction in recorded {
                try? LedgerService.delete(transaction, in: context)
            }
            throw error
        }

        let session = ImportSession(
            dedupeKey: draft.dedupeKey,
            transactionIDs: recorded.map(\.id),
            status: .committed
        )

        do {
            try history.add(session)
        } catch {
            // Best-effort rollback so a failed history write does not leave a
            // transaction that the duplicate guard cannot see.
            for transaction in recorded {
                try? LedgerService.delete(transaction, in: context)
            }
            throw error
        }

        return session
    }

    /// Commits several reviewed bills as one user action. Any failure rolls back
    /// the sessions that were already committed, so the toast can offer one
    /// all-or-nothing undo.
    @discardableResult
    static func commitBatch(
        _ drafts: [ImportDraft],
        account: Account,
        toAccount: Account? = nil,
        categoryFor: (ImportDraft) -> Category?,
        context: NSManagedObjectContext,
        history: ImportHistoryStore = .shared
    ) throws -> [ImportSession] {
        guard !drafts.isEmpty else {
            return []
        }

        var seenOrderHashes = Set<String>()
        var usedKeys = Set<String>()
        var normalized: [ImportDraft] = []
        for draft in drafts {
            if let orderHash = draft.orderIDHash {
                guard seenOrderHashes.insert(orderHash).inserted else {
                    throw ImportError.duplicateInBatch
                }
            }

            var key = draft.dedupeKey
            // Identical merchant/amount/minute is common in a list of two real
            // purchases. Only salt the fallback key; an order hash remains the
            // hard identity and is never bypassed.
            if draft.orderIDHash == nil {
                while usedKeys.contains(key) {
                    key += "#batch-" + UUID().uuidString
                }
            }
            usedKeys.insert(key)
            normalized.append(key == draft.dedupeKey ? draft : copying(draft, key: key))
        }

        var sessions: [ImportSession] = []
        do {
            for draft in normalized {
                let session = try commit(
                    draft,
                    account: account,
                    toAccount: draft.type == .transfer ? toAccount : nil,
                    category: categoryFor(draft),
                    context: context,
                    history: history
                )
                sessions.append(session)
            }
        } catch {
            for session in sessions.reversed() {
                try? undo(
                    sessionID: session.id,
                    context: context,
                    history: history
                )
            }
            throw error
        }
        return sessions
    }

    private static func copying(_ draft: ImportDraft, key: String) -> ImportDraft {
        ImportDraft(
            id: draft.id,
            source: draft.source,
            rawText: draft.rawText,
            cleanText: draft.cleanText,
            merchant: draft.merchant,
            amount: draft.amount,
            fee: draft.fee,
            date: draft.date,
            category: draft.category,
            type: draft.type,
            accountID: draft.accountID,
            note: draft.note,
            orderIDHash: draft.orderIDHash,
            dedupeKey: key,
            warnings: draft.warnings,
            modelConfidence: draft.modelConfidence,
            needsReview: draft.needsReview,
            transferSplit: draft.transferSplit
        )
    }

    static func undo(
        sessionID: UUID,
        context: NSManagedObjectContext,
        history: ImportHistoryStore = .shared
    ) throws {
        guard let session = history.session(id: sessionID) else {
            throw ImportError.sessionNotFound
        }
        guard session.status == .committed else {
            return
        }

        for transactionID in session.transactionIDs {
            if let transaction = try transaction(id: transactionID, in: context) {
                try LedgerService.delete(transaction, in: context)
            }
        }

        try history.markUndone(id: sessionID)
    }

    // MARK: Helpers

    private static func transactionType(for fields: ReceiptFields) -> TransactionType {
        let text = fields.normalizedText
        if ReceiptParser.transferSplit(in: text) != nil
            || containsAny(text, ["转账", "转出", "还款", "提现", "取现"]) {
            return .transfer
        }
        if containsAny(text, ["退款", "退货", "已退款"]) {
            return .refund
        }
        if containsAny(text, ["工资", "薪资", "奖金", "收入", "报销"]) {
            return .income
        }
        return .expense
    }

    private static func resolvedMerchant(for fields: ReceiptFields) -> String {
        if let merchantText = fields.merchantText {
            let merchant = merchantText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if !merchant.isEmpty {
                if let match = MerchantLexicon.shared.match(merchant),
                   match.score >= 0.72 {
                    return match.canonical
                }
                return merchant
            }
        }

        switch fields.source {
        case .wechat:
            return "微信账单"
        case .alipay:
            return "支付宝账单"
        case .bank:
            return "银行流水"
        case .unknown:
            return "图片记账"
        }
    }

    private static func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }

    private static func transaction(
        id: UUID,
        in context: NSManagedObjectContext
    ) throws -> LedgerTransaction? {
        let request = LedgerTransaction.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(
            format: "id == %@",
            NSUUID(uuidString: id.uuidString)!
        )
        return try context.fetch(request).first
    }
}
