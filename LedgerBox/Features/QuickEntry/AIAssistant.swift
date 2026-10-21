import Foundation

/// A deliberately small, local text assistant.
///
/// It does not call a model, a server, or a network API. It turns the parser's
/// structured result into a short explanation, a completeness score, and a few
/// examples. The actual extraction still lives in `QuickEntryParser`.
enum QuickEntryAI {
    enum State {
        case idle
        case ready
        case needsInfo
        case blocked
    }

    struct Insight {
        let state: State
        let title: String
        let detail: String
        let confidence: Int
        let recognizedFields: Int
        let totalFields: Int
    }

    static let examples = [
        "微信买奶茶 15 元",
        "工资到账 8000",
        "支付宝打车 32.5",
        "现金买菜 20"
    ]

    static let totalFields = 4

    static func insight(
        text: String,
        parsed: QuickEntryParser.ParsedEntry?,
        canSave: Bool,
        visibleIssueCount: Int,
        type: TransactionType?,
        amount: Decimal?,
        categoryName: String?,
        accountName: String?
    ) -> Insight {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return Insight(
                state: .idle,
                title: "小 AI 在线",
                detail: "输入一句话，我在本机拆出金额、收支、分类和账户。",
                confidence: 0,
                recognizedFields: 0,
                totalFields: totalFields
            )
        }

        let recognized = [
            amount != nil,
            type != nil,
            categoryName != nil,
            accountName != nil
        ].filter { $0 }.count

        if canSave {
            return Insight(
                state: .ready,
                title: "小 AI 已理解",
                detail: summary(
                    type: type,
                    amount: amount,
                    categoryName: categoryName,
                    accountName: accountName
                ),
                confidence: 100,
                recognizedFields: recognized,
                totalFields: totalFields
            )
        }

        if visibleIssueCount > 0, parsed?.issues.contains(where: {
            $0 == .multipleAmounts || $0 == .inputTooLong
        }) == true {
            return Insight(
                state: .blocked,
                title: "这笔需要先确认",
                detail: "检测到多个金额或文本过长。先删掉多余数字，再让我重新理解。",
                confidence: 20,
                recognizedFields: recognized,
                totalFields: totalFields
            )
        }

        let missing = missingFields(
            amount: amount,
            type: type,
            categoryName: categoryName,
            accountName: accountName
        )

        return Insight(
            state: .needsInfo,
            title: missing.isEmpty ? "还差一点信息" : "还差\(missing.count)项",
            detail: "已识别 \(recognized)/\(totalFields) 个字段。\(missing.isEmpty ? "补全后即可保存。" : "补全" + missing.joined(separator: "、") + "即可保存。")",
            confidence: max(10, recognized * 25),
            recognizedFields: recognized,
            totalFields: totalFields
        )
    }

    private static func summary(
        type: TransactionType?,
        amount: Decimal?,
        categoryName: String?,
        accountName: String?
    ) -> String {
        [
            type?.displayName,
            categoryName,
            accountName,
            amount.map { MoneyFormat.currency($0) }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private static func missingFields(
        amount: Decimal?,
        type: TransactionType?,
        categoryName: String?,
        accountName: String?
    ) -> [String] {
        var missing: [String] = []
        if amount == nil { missing.append("金额") }
        if type == nil { missing.append("收支") }
        if categoryName == nil { missing.append("分类") }
        if accountName == nil { missing.append("账户") }
        return missing
    }
}

// MARK: - Action intents

/// The advisor can either answer a question or prepare one controlled action.
///
/// Routing is deterministic: keyword rules only, no model. Amount extraction is
/// intentionally absent — for `.record` the router just hands the original
/// sentence to `QuickEntryParser`, which stays the single source of truth for
/// money.
enum AIActionIntent: String, CaseIterable, Equatable {
    case record
    case query
    case exportCSV
    case backupJSON
    case imageImport
    case unknown

    var displayName: String {
        switch self {
        case .record:
            return "记一笔"
        case .query:
            return "查账"
        case .exportCSV:
            return "导出 CSV"
        case .backupJSON:
            return "备份 JSON"
        case .imageImport:
            return "图片记账"
        case .unknown:
            return "普通问答"
        }
    }

    /// Anything that reads or writes user data needs an explicit tap first.
    /// `query` and `unknown` keep the existing answer path.
    var requiresConfirmation: Bool {
        switch self {
        case .record, .exportCSV, .backupJSON, .imageImport:
            return true
        case .query, .unknown:
            return false
        }
    }
}

/// The result of routing one sentence. `recordText` is only the text the parser
/// should read; it is not a parsed amount.
struct AIRoutedAction: Equatable {
    let intent: AIActionIntent
    let confidence: Double
    let reason: String
    let recordText: String?

    var requiresConfirmation: Bool {
        intent.requiresConfirmation
    }
}

// MARK: - Router

enum AIActionRouter {

    // Imperative commands, longest first so stripping never leaves leftovers
    // such as "录一下". A bare "记账" is not a command: "记账有什么技巧" is a
    // question, so it must reach the query branch instead.
    private static let recordCommands = [
        "帮我记录一下", "帮我记一笔", "帮我记一下", "帮我记录",
        "记一笔账", "新增一笔", "新增一条", "添加一笔", "添加一条",
        "记录一下", "记一笔", "记一下", "记个账", "帮我记"
    ]

    private static let recordKeywords = [
        "记一笔", "记账", "花了", "花费", "消费", "付款", "支付",
        "买了", "买", "收入", "工资", "报销", "退款", "入账", "到账",
        "奖金", "赚了", "收到"
    ]

    private static let formatKeywords = ["json", "csv", "excel", "表格"]
    private static let backupKeywords = ["备份", "存档"]
    private static let exportKeywords = ["导出"]
    private static let imageKeywords = ["图片", "截图", "拍照", "相册", "小票", "照片"]

    private static let strongQueryKeywords = [
        "多少", "还剩", "剩多少", "剩下", "结余", "余额", "统计",
        "查一下", "查查", "查询", "查", "几笔", "什么", "怎么", "怎样",
        "如何", "哪", "吗", "呢", "？", "?"
    ]

    private static let weakQueryKeywords = [
        "这个月", "本月", "上个月", "去年", "预算", "账单", "报表", "分析", "建议"
    ]

    /// Routes a free-form sentence. An explicit record command wins unless the
    /// sentence names a file/image action; then data actions, then questions,
    /// then softer record hints.
    static func route(_ text: String) -> AIRoutedAction {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return AIRoutedAction(
                intent: .unknown,
                confidence: 0,
                reason: "没有输入内容",
                recordText: nil
            )
        }

        let normalized = trimmed.lowercased()

        // "截图记一笔" and "把账导出" contain a record command but clearly ask
        // for another surface, so a file/image keyword wins over the command.
        let hasFileAction = firstMatch(
            in: normalized,
            keywords: formatKeywords + backupKeywords + exportKeywords + imageKeywords
        ) != nil

        if !hasFileAction, let command = recordCommand(in: normalized) {
            return AIRoutedAction(
                intent: .record,
                confidence: 0.96,
                reason: "以“\(command)”开头或结尾，按记一笔处理",
                recordText: recordText(from: trimmed)
            )
        }

        if let export = exportIntent(in: normalized) {
            return AIRoutedAction(
                intent: export.intent,
                confidence: 0.9,
                reason: "提到“\(export.keyword)”，按\(export.intent.displayName)处理",
                recordText: nil
            )
        }

        if let keyword = firstMatch(in: normalized, keywords: imageKeywords) {
            return AIRoutedAction(
                intent: .imageImport,
                confidence: 0.9,
                reason: "提到“\(keyword)”，按图片记账处理",
                recordText: nil
            )
        }

        if let keyword = firstMatch(in: normalized, keywords: strongQueryKeywords) {
            return AIRoutedAction(
                intent: .query,
                confidence: 0.84,
                reason: "像在问“\(keyword)”，按查账处理",
                recordText: nil
            )
        }

        if let keyword = firstMatch(in: normalized, keywords: recordKeywords) {
            return AIRoutedAction(
                intent: .record,
                confidence: 0.8,
                reason: "提到“\(keyword)”，按记一笔处理",
                recordText: recordText(from: trimmed)
            )
        }

        if let keyword = firstMatch(in: normalized, keywords: weakQueryKeywords) {
            return AIRoutedAction(
                intent: .query,
                confidence: 0.62,
                reason: "提到“\(keyword)”，按查账处理",
                recordText: nil
            )
        }

        return AIRoutedAction(
            intent: .unknown,
            confidence: 0.2,
            reason: "没有命中动作关键词，按普通问答处理",
            recordText: nil
        )
    }

    // MARK: Helpers

    private static func firstMatch(in text: String, keywords: [String]) -> String? {
        keywords.first { text.contains($0) }
    }

    /// A concrete format wins over a vague "备份": "备份成 CSV" exports,
    /// while "导出 JSON" routes to the (not yet implemented) JSON backup.
    private static func exportIntent(
        in text: String
    ) -> (intent: AIActionIntent, keyword: String)? {
        if let keyword = firstMatch(in: text, keywords: formatKeywords) {
            let intent: AIActionIntent = keyword == "json" ? .backupJSON : .exportCSV
            return (intent, keyword)
        }
        if let keyword = firstMatch(in: text, keywords: backupKeywords) {
            return (.backupJSON, keyword)
        }
        if let keyword = firstMatch(in: text, keywords: exportKeywords) {
            return (.exportCSV, keyword)
        }
        return nil
    }

    private static func recordCommand(in text: String) -> String? {
        recordCommands.first { text.hasPrefix($0) || text.hasSuffix($0) }
    }

    /// Removes the command wrapper only. Every other character — including the
    /// amount — is passed through untouched for `QuickEntryParser`.
    private static func recordText(from text: String) -> String? {
        var result = text
        let ordered = recordCommands.sorted { $0.count > $1.count }

        if let command = ordered.first(where: { result.hasPrefix($0) }) {
            result.removeFirst(command.count)
        }
        if let command = ordered.first(where: { result.hasSuffix($0) }) {
            result.removeLast(command.count)
        }

        result = result.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        )
        return result.isEmpty ? nil : result
    }
}

// MARK: - Confirmation

/// Holds one action's parameters plus its confirmation/undo state, so a view can
/// render a confirm card without re-routing the sentence. A confirmation only
/// becomes actionable after the user taps a button; `markCompleted` records the
/// transaction so the same card can undo it.
struct AIActionConfirmation: Identifiable, Equatable {

    enum Payload: Equatable {
        case record(text: String)
        case exportCSV
        case backupJSON
        case imageImport
    }

    let id: UUID
    let intent: AIActionIntent
    let payload: Payload?
    let reason: String
    let confidence: Double
    private(set) var isConfirmed: Bool
    private(set) var completedTransactionID: UUID?

    init(id: UUID = UUID(), action: AIRoutedAction, isConfirmed: Bool = false) {
        let resolvedPayload = Self.makePayload(for: action)
        self.id = id
        self.intent = action.intent
        self.payload = resolvedPayload
        self.reason = action.reason
        self.confidence = action.confidence
        self.isConfirmed = resolvedPayload == nil ? false : isConfirmed
        self.completedTransactionID = nil
    }

    var requiresConfirmation: Bool {
        payload != nil
    }

    var isUndoable: Bool {
        completedTransactionID != nil
    }

    var recordText: String? {
        guard let stored = payload else {
            return nil
        }
        if case .record(let text) = stored {
            return text
        }
        return nil
    }

    mutating func confirm() {
        guard payload != nil else { return }
        isConfirmed = true
    }

    mutating func markCompleted(transactionID: UUID) {
        isConfirmed = true
        completedTransactionID = transactionID
    }

    mutating func revokeCompletion() {
        isConfirmed = false
        completedTransactionID = nil
    }

    private static func makePayload(for action: AIRoutedAction) -> Payload? {
        switch action.intent {
        case .record:
            return .record(text: action.recordText ?? "")
        case .exportCSV:
            return .exportCSV
        case .backupJSON:
            return .backupJSON
        case .imageImport:
            return .imageImport
        case .query, .unknown:
            return nil
        }
    }
}
