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
