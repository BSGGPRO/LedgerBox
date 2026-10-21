import AppIntents
import CoreData
import Foundation

// MARK: - Intent vocabulary

enum LedgerIntentType: String, AppEnum {
    case expense
    case income

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "收支类型")

    static var caseDisplayRepresentations: [LedgerIntentType: DisplayRepresentation] = [
        .expense: DisplayRepresentation(title: "支出"),
        .income: DisplayRepresentation(title: "收入")
    ]

    var transactionType: TransactionType {
        switch self {
        case .expense:
            return .expense
        case .income:
            return .income
        }
    }
}

enum LedgerIntentError: LocalizedError {
    case invalidAmount
    case futureDate
    case categoryNotFound(String)
    case accountNotFound(String)
    case needsReview(String)

    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return "金额必须大于 0。"
        case .futureDate:
            return "记账日期不能晚于当前时间。"
        case .categoryNotFound(let name):
            return "找不到分类「\(name)」。请先在 LedgerBox 中创建它。"
        case .accountNotFound(let name):
            return "找不到账户「\(name)」。请先在 LedgerBox 中创建它。"
        case .needsReview(let reason):
            return "这句话还需要确认：\(reason)"
        }
    }
}

// MARK: - Add transaction

/// The Shortcuts/Siri write path. It deliberately accepts only income and
/// expense, so a voice command can never create a half-valid transfer.
struct AddTransactionIntent: AppIntent {
    static var title: LocalizedStringResource = "记一笔"
    static var description = IntentDescription("把一笔收入或支出写入 LedgerBox 本地账本。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "金额")
    var amount: Double

    @Parameter(title: "类型")
    var type: LedgerIntentType

    @Parameter(title: "分类")
    var categoryName: String

    @Parameter(title: "账户")
    var accountName: String

    @Parameter(title: "备注")
    var note: String?

    @Parameter(title: "日期")
    var date: Date?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let decimalAmount = try validatedAmount()
        let entryDate = date ?? Date()

        guard entryDate <= Date() else {
            throw LedgerIntentError.futureDate
        }

        let entryType = type.transactionType
        let categoryKind: CategoryKind = entryType == .income ? .income : .expense
        let requestedCategory = categoryName
        let requestedAccount = accountName
        let rawNote = note

        let dialog = try await MainActor.run {
            let context = PersistenceController.shared.container.viewContext
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            context.undoManager = nil

            return try context.performAndWait {
                let category = try Self.resolveCategory(
                    named: requestedCategory,
                    kind: categoryKind,
                    in: context
                )
                let account = try Self.resolveAccount(
                    named: requestedAccount,
                    in: context
                )

                let trimmedNote = rawNote?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let savedNote: String?
                if let trimmedNote, !trimmedNote.isEmpty {
                    savedNote = String(trimmedNote.prefix(120))
                } else {
                    savedNote = nil
                }

                try LedgerService.record(
                    type: entryType,
                    amount: decimalAmount,
                    date: entryDate,
                    note: savedNote,
                    account: account,
                    category: category,
                    in: context
                )

                return "已记录\(entryType.displayName) "
                    + "\(MoneyFormat.currency(decimalAmount))，分类：\(category.name)，"
                    + "账户：\(account.name)。"
            }
        }

        return .result(dialog: "\(dialog)")
    }

    private func validatedAmount() throws -> Decimal {
        guard amount.isFinite, amount > 0 else {
            throw LedgerIntentError.invalidAmount
        }

        let text = String(format: "%.2f", amount)
            .replacingOccurrences(of: ",", with: ".")
        guard
            let decimal = Decimal(
                string: text,
                locale: Locale(identifier: "en_US_POSIX")
            ),
            decimal > 0
        else {
            throw LedgerIntentError.invalidAmount
        }
        return decimal
    }

    private static func resolveCategory(
        named rawName: String,
        kind: CategoryKind,
        in context: NSManagedObjectContext
    ) throws -> Category {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw LedgerIntentError.categoryNotFound(rawName)
        }

        let request = Category.fetchRequest()
        request.predicate = NSPredicate(
            format: "isSoftDeleted == NO AND kind == %@",
            kind.rawValue
        )
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Category.sortOrder, ascending: true)
        ]

        let categories = try context.fetch(request)
        if let exact = categories.first(where: { $0.name == name }) {
            return exact
        }
        if let partial = categories.first(where: {
            $0.name.localizedCaseInsensitiveContains(name)
        }) {
            return partial
        }
        throw LedgerIntentError.categoryNotFound(name)
    }

    private static func resolveAccount(
        named rawName: String,
        in context: NSManagedObjectContext
    ) throws -> Account {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw LedgerIntentError.accountNotFound(rawName)
        }

        let accounts = try context.fetch(Account.fetchRequest())
        if let exact = accounts.first(where: { $0.name == name }) {
            return exact
        }
        if let partial = accounts.first(where: {
            $0.name.localizedCaseInsensitiveContains(name)
        }) {
            return partial
        }
        throw LedgerIntentError.accountNotFound(name)
    }
}

// MARK: - Text-based automation

/// Shortcuts can pass a message, share-sheet string, or personal automation
/// text here. iOS does not allow reading other apps' notifications.
/// The parser only saves when every field is unambiguous; otherwise the user
/// gets a review message instead of a guessed category or account.
struct QuickAddIntent: AppIntent {
    static var title: LocalizedStringResource = "从一句话记账"
    static var description = IntentDescription("把一段短信、分享文本或个人自动化文本解析成一笔收支。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "一句话")
    var text: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let inputText = text

        let dialog = try await MainActor.run {
            let context = PersistenceController.shared.container.viewContext
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            context.undoManager = nil

            return try context.performAndWait {
                let categoryObjects = try context.fetch(Category.fetchRequest())
                let accountObjects = try context.fetch(Account.fetchRequest())

                let categoryOptions = categoryObjects
                    .filter { $0.isSelectable }
                    .map {
                        QuickEntryParser.CategoryOption(
                            id: $0.id,
                            name: $0.name,
                            kind: $0.categoryKind
                        )
                    }
                let accountOptions = accountObjects.map {
                    QuickEntryParser.AccountOption(id: $0.id, name: $0.name)
                }

                let parsed = QuickEntryParser().parse(
                    inputText,
                    categories: categoryOptions,
                    accounts: accountOptions
                )

                guard
                    parsed.isReadyToSave,
                    let amount = parsed.amount,
                    let type = parsed.type,
                    let categoryID = parsed.category?.id,
                    let accountID = parsed.account?.id,
                    type == .income || type == .expense
                else {
                    let reason = parsed.issues.isEmpty
                        ? "请打开 LedgerBox 补全分类或账户。"
                        : parsed.issues.map(\.message).joined(separator: "；")
                    throw LedgerIntentError.needsReview(reason)
                }

                guard let category = categoryObjects.first(where: {
                    $0.id == categoryID && $0.isSelectable
                }) else {
                    throw LedgerIntentError.categoryNotFound(parsed.category?.name ?? "")
                }
                guard let account = accountObjects.first(where: {
                    $0.id == accountID
                }) else {
                    throw LedgerIntentError.accountNotFound(parsed.account?.name ?? "")
                }

                try LedgerService.record(
                    type: type,
                    amount: amount,
                    date: Date(),
                    note: parsed.remark,
                    account: account,
                    category: category,
                    in: context
                )

                return "已记录\(type.displayName) "
                    + "\(MoneyFormat.currency(amount))，分类：\(category.name)，"
                    + "账户：\(account.name)。"
            }
        }

        return .result(dialog: "\(dialog)")
    }
}

// MARK: - Shortcuts surface

struct LedgerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTransactionIntent(),
            phrases: [
                "用 \(.applicationName) 记一笔",
                "在 \(.applicationName) 里记一笔"
            ],
            shortTitle: "记一笔",
            systemImageName: "plus.circle.fill"
        )

        AppShortcut(
            intent: QuickAddIntent(),
            phrases: [
                "用 \(.applicationName) 快速记一笔",
                "用 \(.applicationName) 从一句话记账"
            ],
            shortTitle: "一句话记账",
            systemImageName: "text.bubble.fill"
        )
    }
}
