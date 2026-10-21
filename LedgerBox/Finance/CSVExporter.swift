import CoreData
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    static var writableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = String(decoding: data, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Local-only CSV export. No credentials, no network, no cloud. [边界11]
enum CSVExporter {
    static func makeCSV(
        transactions: [LedgerTransaction],
        accounts: [Account],
        categories: [Category]
    ) -> String {
        let accountsByID = Dictionary(
            uniqueKeysWithValues: accounts.map { ($0.id, $0) }
        )
        let categoriesByID = Dictionary(
            uniqueKeysWithValues: categories.map { ($0.id, $0) }
        )

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let amountFormatter = NumberFormatter()
        amountFormatter.locale = Locale(identifier: "en_US_POSIX")
        amountFormatter.numberStyle = .decimal
        amountFormatter.usesGroupingSeparator = false
        amountFormatter.minimumFractionDigits = 2
        amountFormatter.maximumFractionDigits = 2

        var rows: [String] = [
            [
                "日期", "类型", "金额", "分类", "账户", "转入账户", "备注", "模板标签"
            ]
            .map { escape($0) }
            .joined(separator: ",")
        ]

        let sorted = transactions.sorted { $0.date < $1.date }
        for transaction in sorted {
            let categoryName = transaction.categoryId
                .flatMap { categoriesByID[$0]?.name } ?? "未分类"
            let accountName = accountsByID[transaction.accountId]?.name ?? "未知账户"
            let toAccountName = transaction.toAccountId
                .flatMap { accountsByID[$0]?.name } ?? ""
            let amount = amountFormatter.string(
                from: NSDecimalNumber(decimal: transaction.amountValue)
            ) ?? "0.00"

            rows.append(
                [
                    dateFormatter.string(from: transaction.date),
                    transaction.transactionType.displayName,
                    amount,
                    categoryName,
                    accountName,
                    toAccountName,
                    transaction.note ?? "",
                    transaction.templateTag ?? ""
                ]
                .map { escape($0) }
                .joined(separator: ",")
            )
        }

        // UTF-8 BOM keeps Chinese headers readable in Excel on Windows.
        return "\u{FEFF}" + rows.joined(separator: "\r\n")
    }

    private static func escape(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

// MARK: - JSON full backup

/// Every failure of the JSON backup pipeline. Messages are shown directly in the
/// settings alert, so they are written in user-facing Chinese.
enum BackupError: LocalizedError, Equatable {
    case unreadableFile
    case malformedJSON(String)
    case unsupportedSchemaVersion(Int)
    case invalidField(String)
    case saveFailed(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "无法读取备份文件：文件为空或不可访问。"
        case .malformedJSON(let detail):
            return "备份文件不是有效的 LedgerBox JSON：\(detail)"
        case .unsupportedSchemaVersion(let version):
            return "不支持的备份版本 \(version)。当前只支持 schemaVersion 1。"
        case .invalidField(let detail):
            return "备份数据校验失败：\(detail)"
        case .saveFailed(let detail):
            return "写入本机数据失败，已回滚到导入前的状态：\(detail)"
        case .exportFailed(let detail):
            return "生成备份失败：\(detail)"
        }
    }
}

/// The on-disk format. Decimal amounts are transported as strings so that the
/// value survives the JSON round-trip without binary floating point error.
/// Dates use ISO8601 through the encoder/decoder strategies. Entity UUIDs are
/// strings, and `settings` is an array because the model has no uniqueness
/// constraint on the AppSettings entity.
struct LedgerBackup: Codable {
    var schemaVersion: Int
    var appVersion: String
    var exportedAt: Date
    var accounts: [BackupAccount]
    var categories: [BackupCategory]
    var transactions: [BackupTransaction]
    var budgets: [BackupBudget]
    var goals: [BackupGoal]
    var templates: [BackupTemplate]
    var settings: [BackupSettings]
}

struct BackupAccount: Codable {
    var id: String
    var name: String
    var type: String
    var balance: String
    var currencyCode: String
    var locked: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
}

struct BackupCategory: Codable {
    var id: String
    var name: String
    var icon: String
    var kind: String
    var colorHex: String
    var isSoftDeleted: Bool
    var sortOrder: Int
}

struct BackupTransaction: Codable {
    var id: String
    var type: String
    var categoryId: String?
    var accountId: String
    var toAccountId: String?
    var amount: String
    var date: Date
    var note: String?
    var createdAt: Date
    var templateTag: String?
}

struct BackupBudget: Codable {
    var id: String
    var categoryId: String?
    var period: String
    var limit: String
    var startDate: Date
    var enabled: Bool
}

struct BackupGoal: Codable {
    var id: String
    var name: String
    var target: String
    var current: String
    var priority: Int
    var status: String
    var templateTag: String?
    var deadline: Date?
    var createdAt: Date
}

struct BackupTemplate: Codable {
    var id: String
    var name: String
    var type: String
    var configJSON: String
    var active: Bool
    var createdAt: Date
}

struct BackupSettings: Codable {
    var id: String
    var themeMode: String
    var accentColorHex: String
    var activeTemplateId: String?
    var sideHustleSplitRatio: String
    var updatedAt: Date
}

/// Decoded before the full payload so an unsupported file gets a version error
/// instead of a confusing missing-field error.
private struct BackupHeader: Decodable {
    let schemaVersion: Int
}

struct BackupRestoreSummary: Equatable {
    let accountCount: Int
    let transactionCount: Int
    let budgetCount: Int
    let goalCount: Int
    let categoryCount: Int
    let templateCount: Int
    let settingsCount: Int
    let appVersion: String
    let exportedAt: Date

    var summaryText: String {
        var text = "已替换本机数据：\(accountCount) 个账户、"
        text += "\(transactionCount) 笔流水、\(budgetCount) 个预算、\(goalCount) 个目标；"
        text += "另有 \(categoryCount) 个分类、\(templateCount) 个模板、\(settingsCount) 条设置。"
        text += "\n备份来自 LedgerBox \(appVersion)，导出于 \(Self.displayDate(exportedAt))。"
        return text
    }

    private static func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

/// FileDocument wrapper used by the SwiftUI fileExporter.
struct JSONBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Encodes and restores the complete local ledger. The restore path deliberately
/// does not call LedgerService.record: account balances come straight from the
/// backup, so replaying transactions would apply every amount twice.
enum LedgerBackupService {
    static let currentSchemaVersion = 1
    /// Upper bound for any persisted money value (10 million).
    static let maxMoneyAmount = Decimal(10_000_000)

    private static let posixLocale = Locale(identifier: "en_US_POSIX")
    /// Import accepts ISO8601 with or without fractional seconds; export uses the
    /// plain internet-date-time form.
    private static let iso8601Formatters: [ISO8601DateFormatter] = {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return [plain, fractional]
    }()
    private static let earliestAllowedDate: Date = utcDate(year: 1900, month: 1, day: 1)
    /// Exclusive upper bound: 2100-12-31 is the last accepted calendar day.
    private static let latestAllowedDate: Date = utcDate(year: 2101, month: 1, day: 1)

    // MARK: Export

    static func makeBackup(context: NSManagedObjectContext) throws -> Data {
        let backup: LedgerBackup
        do {
            backup = try snapshot(from: context)
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.exportFailed(error.localizedDescription)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            return try encoder.encode(backup)
        } catch {
            throw BackupError.exportFailed(error.localizedDescription)
        }
    }

    private static func snapshot(from context: NSManagedObjectContext) throws -> LedgerBackup {
        let accounts = try context.fetch(Account.fetchRequest()).sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        let categories = try context.fetch(Category.fetchRequest()).sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind < rhs.kind
            }
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        let transactions = try context.fetch(LedgerTransaction.fetchRequest()).sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date < rhs.date
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        let budgets = try context.fetch(Budget.fetchRequest()).sorted { lhs, rhs in
            if lhs.startDate != rhs.startDate {
                return lhs.startDate < rhs.startDate
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        let goals = try context.fetch(SavingsGoal.fetchRequest()).sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        let templates = try context.fetch(TemplateRules.fetchRequest()).sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        let settings = try context.fetch(AppSettings.fetchRequest()).sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt < rhs.updatedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        let accountRows: [BackupAccount] = accounts.map { account in
            BackupAccount(
                id: account.id.uuidString,
                name: account.name,
                type: account.type,
                balance: amountString(account.balanceValue),
                currencyCode: account.currencyCode,
                locked: account.locked,
                sortOrder: Int(account.sortOrder),
                createdAt: account.createdAt,
                updatedAt: account.updatedAt
            )
        }

        let categoryRows: [BackupCategory] = categories.map { category in
            BackupCategory(
                id: category.id.uuidString,
                name: category.name,
                icon: category.icon,
                kind: category.kind,
                colorHex: category.colorHex,
                isSoftDeleted: category.isSoftDeleted,
                sortOrder: Int(category.sortOrder)
            )
        }

        let transactionRows: [BackupTransaction] = transactions.map { transaction in
            BackupTransaction(
                id: transaction.id.uuidString,
                type: transaction.type,
                categoryId: transaction.categoryId?.uuidString,
                accountId: transaction.accountId.uuidString,
                toAccountId: transaction.toAccountId?.uuidString,
                amount: amountString(transaction.amountValue),
                date: transaction.date,
                note: transaction.note,
                createdAt: transaction.createdAt,
                templateTag: transaction.templateTag
            )
        }

        let budgetRows: [BackupBudget] = budgets.map { budget in
            BackupBudget(
                id: budget.id.uuidString,
                categoryId: budget.categoryId?.uuidString,
                period: budget.period,
                limit: amountString(budget.limitValue),
                startDate: budget.startDate,
                enabled: budget.enabled
            )
        }

        let goalRows: [BackupGoal] = goals.map { goal in
            BackupGoal(
                id: goal.id.uuidString,
                name: goal.name,
                target: amountString(goal.targetValue),
                current: amountString(goal.currentValue),
                priority: Int(goal.priority),
                status: goal.status,
                templateTag: goal.templateTag,
                deadline: goal.deadline,
                createdAt: goal.createdAt
            )
        }

        let templateRows: [BackupTemplate] = templates.map { template in
            BackupTemplate(
                id: template.id.uuidString,
                name: template.name,
                type: template.type,
                configJSON: template.configJSON,
                active: template.active,
                createdAt: template.createdAt
            )
        }

        let settingsRows: [BackupSettings] = settings.map { item in
            BackupSettings(
                id: item.id.uuidString,
                themeMode: item.themeMode,
                accentColorHex: item.accentColorHex,
                activeTemplateId: item.activeTemplateId?.uuidString,
                sideHustleSplitRatio: amountString(item.splitRatioValue),
                updatedAt: item.updatedAt
            )
        }

        return LedgerBackup(
            schemaVersion: currentSchemaVersion,
            appVersion: appVersion,
            exportedAt: Date(),
            accounts: accountRows,
            categories: categoryRows,
            transactions: transactionRows,
            budgets: budgetRows,
            goals: goalRows,
            templates: templateRows,
            settings: settingsRows
        )
    }

    // MARK: Import

    /// Decodes and validates the whole file before touching the context. The old
    /// rows are deleted and the new rows inserted inside a single unsaved
    /// transaction; any failure rolls the context back so a half-restored ledger
    /// can never be saved. Existing unsaved changes in `context` are discarded by
    /// that rollback as well, so callers should pass a clean context.
    static func restore(
        data: Data,
        context: NSManagedObjectContext
    ) throws -> BackupRestoreSummary {
        let backup = try decode(data)
        try validate(backup)

        do {
            try deleteAll(in: context)
            try insertAll(from: backup, in: context)
            try context.save()
        } catch let error as BackupError {
            context.rollback()
            throw error
        } catch {
            context.rollback()
            throw BackupError.saveFailed(error.localizedDescription)
        }

        return BackupRestoreSummary(
            accountCount: backup.accounts.count,
            transactionCount: backup.transactions.count,
            budgetCount: backup.budgets.count,
            goalCount: backup.goals.count,
            categoryCount: backup.categories.count,
            templateCount: backup.templates.count,
            settingsCount: backup.settings.count,
            appVersion: backup.appVersion,
            exportedAt: backup.exportedAt
        )
    }

    private static func decode(_ data: Data) throws -> LedgerBackup {
        guard !data.isEmpty else {
            throw BackupError.unreadableFile
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            for formatter in iso8601Formatters {
                if let date = formatter.date(from: text) {
                    return date
                }
            }
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "日期不是 ISO8601 格式：\(text)"
                )
            )
        }

        do {
            let header = try JSONDecoder().decode(BackupHeader.self, from: data)
            guard header.schemaVersion == currentSchemaVersion else {
                throw BackupError.unsupportedSchemaVersion(header.schemaVersion)
            }
            return try decoder.decode(LedgerBackup.self, from: data)
        } catch let error as BackupError {
            throw error
        } catch let error as DecodingError {
            throw BackupError.malformedJSON(decodingMessage(error))
        } catch {
            throw BackupError.malformedJSON(error.localizedDescription)
        }
    }

    private static func decodingMessage(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            var path = context.codingPath.map { $0.stringValue }
            path.append(key.stringValue)
            return "缺少字段「\(path.joined(separator: "."))」。"
        case .typeMismatch(_, let context):
            return "字段「\(pathDescription(context.codingPath))」的类型不正确。"
        case .valueNotFound(_, let context):
            return "字段「\(pathDescription(context.codingPath))」缺少值。"
        case .dataCorrupted(let context):
            if context.codingPath.isEmpty {
                return "JSON 语法错误，或日期不是 ISO8601 格式。"
            }
            return "字段「\(pathDescription(context.codingPath))」无法解析（日期需要 ISO8601 格式）。"
        @unknown default:
            return "JSON 数据无法解析。"
        }
    }

    private static func pathDescription(_ path: [CodingKey]) -> String {
        guard !path.isEmpty else {
            return "根对象"
        }
        return path.map { $0.stringValue }.joined(separator: ".")
    }

    // MARK: Validation

    private static func validate(_ backup: LedgerBackup) throws {
        guard backup.schemaVersion == currentSchemaVersion else {
            throw BackupError.unsupportedSchemaVersion(backup.schemaVersion)
        }

        try date(backup.exportedAt, field: "备份导出时间")

        var accountIDs = Set<UUID>()
        var categoryIDs = Set<UUID>()
        var transactionIDs = Set<UUID>()
        var budgetIDs = Set<UUID>()
        var goalIDs = Set<UUID>()
        var templateIDs = Set<UUID>()
        var settingsIDs = Set<UUID>()

        for account in backup.accounts {
            let id = try uuid(account.id, field: "账户 ID")
            try requireUnique(id, in: &accountIDs, kind: "账户")
            guard !account.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BackupError.invalidField("账户 \(id.uuidString) 的名称不能为空。")
            }
            _ = try requireEnum(
                account.type,
                as: AccountType.self,
                field: "账户「\(account.name)」的类型"
            )
            // Balances are restored verbatim and may legitimately be negative,
            // so they are only parsed for exactness, not range-checked.
            _ = try parseDecimal(
                account.balance,
                field: "账户「\(account.name)」的余额"
            )
            _ = try int16Value(account.sortOrder, field: "账户「\(account.name)」的排序")
            try date(account.createdAt, field: "账户「\(account.name)」的创建时间")
            try date(account.updatedAt, field: "账户「\(account.name)」的更新时间")
        }

        for category in backup.categories {
            let id = try uuid(category.id, field: "分类 ID")
            try requireUnique(id, in: &categoryIDs, kind: "分类")
            guard !category.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BackupError.invalidField("分类 \(id.uuidString) 的名称不能为空。")
            }
            _ = try requireEnum(
                category.kind,
                as: CategoryKind.self,
                field: "分类「\(category.name)」的类型"
            )
            _ = try int16Value(category.sortOrder, field: "分类「\(category.name)」的排序")
        }

        for template in backup.templates {
            let id = try uuid(template.id, field: "模板 ID")
            try requireUnique(id, in: &templateIDs, kind: "模板")
            _ = try requireEnum(
                template.type,
                as: TemplateKind.self,
                field: "模板「\(template.name)」的类型"
            )
            try date(template.createdAt, field: "模板「\(template.name)」的创建时间")
        }

        for budget in backup.budgets {
            let id = try uuid(budget.id, field: "预算 ID")
            try requireUnique(id, in: &budgetIDs, kind: "预算")
            _ = try requireEnum(
                budget.period,
                as: BudgetPeriod.self,
                field: "预算 \(id.uuidString) 的周期"
            )
            _ = try money(budget.limit, field: "预算 \(id.uuidString) 的限额")
            try date(budget.startDate, field: "预算 \(id.uuidString) 的开始日期")

            if let categoryId = budget.categoryId {
                let reference = try uuid(
                    categoryId,
                    field: "预算 \(id.uuidString) 的分类 ID"
                )
                guard categoryIDs.contains(reference) else {
                    throw BackupError.invalidField(
                        "预算 \(id.uuidString) 引用了不存在的分类 \(reference.uuidString)。"
                    )
                }
            }
        }

        for goal in backup.goals {
            let id = try uuid(goal.id, field: "目标 ID")
            try requireUnique(id, in: &goalIDs, kind: "目标")
            guard !goal.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BackupError.invalidField("目标 \(id.uuidString) 的名称不能为空。")
            }
            _ = try money(goal.target, field: "目标「\(goal.name)」的目标金额")
            _ = try money(goal.current, field: "目标「\(goal.name)」的当前金额")
            _ = try int16Value(goal.priority, field: "目标「\(goal.name)」的优先级")
            _ = try requireEnum(
                goal.status,
                as: SavingsGoalStatus.self,
                field: "目标「\(goal.name)」的状态"
            )
            try date(goal.createdAt, field: "目标「\(goal.name)」的创建时间")
            if let deadline = goal.deadline {
                try date(deadline, field: "目标「\(goal.name)」的截止日期")
            }
        }

        for transaction in backup.transactions {
            let id = try uuid(transaction.id, field: "流水 ID")
            try requireUnique(id, in: &transactionIDs, kind: "流水")
            _ = try requireEnum(
                transaction.type,
                as: TransactionType.self,
                field: "流水 \(id.uuidString) 的类型"
            )
            _ = try money(transaction.amount, field: "流水 \(id.uuidString) 的金额")
            try date(transaction.date, field: "流水 \(id.uuidString) 的日期")
            try date(transaction.createdAt, field: "流水 \(id.uuidString) 的创建时间")

            let accountID = try uuid(
                transaction.accountId,
                field: "流水 \(id.uuidString) 的账户 ID"
            )
            guard accountIDs.contains(accountID) else {
                throw BackupError.invalidField(
                    "流水 \(id.uuidString) 引用了不存在的账户 \(accountID.uuidString)。"
                )
            }

            if let categoryId = transaction.categoryId {
                let reference = try uuid(
                    categoryId,
                    field: "流水 \(id.uuidString) 的分类 ID"
                )
                guard categoryIDs.contains(reference) else {
                    throw BackupError.invalidField(
                        "流水 \(id.uuidString) 引用了不存在的分类 \(reference.uuidString)。"
                    )
                }
            }

            if let toAccountId = transaction.toAccountId {
                let reference = try uuid(
                    toAccountId,
                    field: "流水 \(id.uuidString) 的转入账户 ID"
                )
                guard accountIDs.contains(reference) else {
                    throw BackupError.invalidField(
                        "流水 \(id.uuidString) 引用了不存在的转入账户 \(reference.uuidString)。"
                    )
                }
            }
        }

        for settings in backup.settings {
            let id = try uuid(settings.id, field: "设置 ID")
            try requireUnique(id, in: &settingsIDs, kind: "设置")
            _ = try requireEnum(
                settings.themeMode,
                as: ThemeMode.self,
                field: "设置的主题模式"
            )

            let ratio = try parseDecimal(
                settings.sideHustleSplitRatio,
                field: "设置的副业分成比例"
            )
            guard ratio >= 0, ratio <= 1 else {
                throw BackupError.invalidField("设置的副业分成比例必须在 0 到 1 之间。")
            }

            try date(settings.updatedAt, field: "设置的更新时间")
            if let activeTemplateId = settings.activeTemplateId {
                // A dangling template reference is tolerated (it can exist in the
                // live store too), but the value still has to be a UUID.
                _ = try uuid(activeTemplateId, field: "设置的活动模板 ID")
            }
        }
    }

    // MARK: Store replacement

    private static func deleteAll(in context: NSManagedObjectContext) throws {
        // Batch deletes bypass the context and cannot be rolled back, so every
        // old row is deleted through `context.delete` instead.
        let entityNames = [
            "Transaction",
            "Account",
            "Category",
            "Budget",
            "SavingsGoal",
            "TemplateRules",
            "AppSettings"
        ]

        for entityName in entityNames {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.includesPropertyValues = false
            request.includesSubentities = false
            for object in try context.fetch(request) {
                context.delete(object)
            }
        }
    }

    private static func insertAll(
        from backup: LedgerBackup,
        in context: NSManagedObjectContext
    ) throws {
        for item in backup.accounts {
            try insert(item, in: context)
        }
        for item in backup.categories {
            try insert(item, in: context)
        }
        for item in backup.templates {
            try insert(item, in: context)
        }
        for item in backup.budgets {
            try insert(item, in: context)
        }
        for item in backup.goals {
            try insert(item, in: context)
        }
        for item in backup.transactions {
            try insert(item, in: context)
        }
        for item in backup.settings {
            try insert(item, in: context)
        }
    }

    private static func insert(
        _ item: BackupAccount,
        in context: NSManagedObjectContext
    ) throws {
        let account = Account(context: context)
        account.id = try uuid(item.id, field: "账户 ID")
        account.name = item.name
        account.type = item.type
        account.balance = NSDecimalNumber(
            decimal: try parseDecimal(item.balance, field: "账户余额")
        )
        account.currencyCode = item.currencyCode
        account.locked = item.locked
        account.sortOrder = try int16Value(item.sortOrder, field: "账户排序")
        account.createdAt = item.createdAt
        account.updatedAt = item.updatedAt
    }

    private static func insert(
        _ item: BackupCategory,
        in context: NSManagedObjectContext
    ) throws {
        let category = Category(context: context)
        category.id = try uuid(item.id, field: "分类 ID")
        category.name = item.name
        category.icon = item.icon
        category.kind = item.kind
        category.colorHex = item.colorHex
        category.isSoftDeleted = item.isSoftDeleted
        category.sortOrder = try int16Value(item.sortOrder, field: "分类排序")
    }

    private static func insert(
        _ item: BackupTransaction,
        in context: NSManagedObjectContext
    ) throws {
        let transaction = LedgerTransaction(context: context)
        transaction.id = try uuid(item.id, field: "流水 ID")
        transaction.type = item.type
        transaction.categoryId = try item.categoryId.map {
            try uuid($0, field: "流水分类 ID")
        }
        transaction.accountId = try uuid(item.accountId, field: "流水账户 ID")
        transaction.toAccountId = try item.toAccountId.map {
            try uuid($0, field: "流水转入账户 ID")
        }
        transaction.amount = NSDecimalNumber(
            decimal: try money(item.amount, field: "流水金额")
        )
        transaction.date = item.date
        transaction.note = item.note
        transaction.createdAt = item.createdAt
        transaction.templateTag = item.templateTag
    }

    private static func insert(
        _ item: BackupBudget,
        in context: NSManagedObjectContext
    ) throws {
        let budget = Budget(context: context)
        budget.id = try uuid(item.id, field: "预算 ID")
        budget.categoryId = try item.categoryId.map {
            try uuid($0, field: "预算分类 ID")
        }
        budget.period = item.period
        budget.limitAmount = NSDecimalNumber(
            decimal: try money(item.limit, field: "预算限额")
        )
        budget.startDate = item.startDate
        budget.enabled = item.enabled
    }

    private static func insert(
        _ item: BackupGoal,
        in context: NSManagedObjectContext
    ) throws {
        let goal = SavingsGoal(context: context)
        goal.id = try uuid(item.id, field: "目标 ID")
        goal.name = item.name
        goal.targetAmount = NSDecimalNumber(
            decimal: try money(item.target, field: "目标金额")
        )
        goal.currentAmount = NSDecimalNumber(
            decimal: try money(item.current, field: "目标当前金额")
        )
        goal.priority = try int16Value(item.priority, field: "目标优先级")
        goal.status = item.status
        goal.templateTag = item.templateTag
        goal.deadline = item.deadline
        goal.createdAt = item.createdAt
    }

    private static func insert(
        _ item: BackupTemplate,
        in context: NSManagedObjectContext
    ) throws {
        let template = TemplateRules(context: context)
        template.id = try uuid(item.id, field: "模板 ID")
        template.name = item.name
        template.type = item.type
        template.configJSON = item.configJSON
        template.active = item.active
        template.createdAt = item.createdAt
    }

    private static func insert(
        _ item: BackupSettings,
        in context: NSManagedObjectContext
    ) throws {
        let settings = AppSettings(context: context)
        settings.id = try uuid(item.id, field: "设置 ID")
        settings.themeMode = item.themeMode
        settings.accentColorHex = item.accentColorHex
        settings.activeTemplateId = try item.activeTemplateId.map {
            try uuid($0, field: "设置活动模板 ID")
        }
        settings.sideHustleSplitRatio = NSDecimalNumber(
            decimal: try parseDecimal(
                item.sideHustleSplitRatio,
                field: "副业分成比例"
            )
        )
        settings.updatedAt = item.updatedAt
    }

    // MARK: Helpers

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private static func amountString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private static func utcDate(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")
            ?? TimeZone(secondsFromGMT: 0)
            ?? .current
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    private static func uuid(_ text: String, field: String) throws -> UUID {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = UUID(uuidString: trimmed) else {
            throw BackupError.invalidField("「\(field)」不是有效的 UUID：\(text)。")
        }
        return value
    }

    private static func requireUnique(
        _ id: UUID,
        in ids: inout Set<UUID>,
        kind: String
    ) throws {
        guard ids.insert(id).inserted else {
            throw BackupError.invalidField("\(kind) ID 重复：\(id.uuidString)。")
        }
    }

    private static func requireEnum<T: RawRepresentable>(
        _ raw: String,
        as type: T.Type,
        field: String
    ) throws -> T where T.RawValue == String {
        guard let value = T(rawValue: raw) else {
            throw BackupError.invalidField("「\(field)」不是支持的值：\(raw)。")
        }
        return value
    }

    private static func parseDecimal(_ text: String, field: String) throws -> Decimal {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let value = Decimal(string: trimmed, locale: posixLocale),
              !value.isNaN else {
            throw BackupError.invalidField("「\(field)」不是有效的十进制数字：\(text)。")
        }
        return value
    }

    /// Range checks also reject non-finite values, because comparisons with NaN
    /// are always false.
    private static func money(_ text: String, field: String) throws -> Decimal {
        let value = try parseDecimal(text, field: field)

        guard value >= 0 else {
            throw BackupError.invalidField("「\(field)」不能为负数：\(text)。")
        }
        guard value <= maxMoneyAmount else {
            throw BackupError.invalidField(
                "「\(field)」必须是有限数字且不超过 10,000,000：\(text)。"
            )
        }
        return value
    }

    private static func int16Value(_ value: Int, field: String) throws -> Int16 {
        guard value >= Int(Int16.min), value <= Int(Int16.max) else {
            throw BackupError.invalidField("「\(field)」超出 16 位整数范围：\(value)。")
        }
        return Int16(value)
    }

    private static func date(_ value: Date, field: String) throws {
        guard value >= earliestAllowedDate, value < latestAllowedDate else {
            throw BackupError.invalidField(
                "「\(field)」超出允许范围（1900-01-01 至 2100-12-31，UTC）。"
            )
        }
    }
}
