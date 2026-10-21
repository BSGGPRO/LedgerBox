import Foundation
import NaturalLanguage

/// Pure-Foundation parser for the "quick entry" sentence.
///
/// The parser deliberately knows nothing about SwiftUI or Core Data. Callers
/// map their current `Category` / `Account` objects into the lightweight
/// `CategoryOption` / `AccountOption` snapshots below. This keeps the parser
/// deterministic, testable, and reusable from both the in-app panel and an
/// App Intent.
struct QuickEntryParser {

    // MARK: - Input snapshots

    struct CategoryOption: Equatable {
        let id: UUID
        let name: String
        let kind: CategoryKind
    }

    struct AccountOption: Equatable {
        let id: UUID
        let name: String
    }

    // MARK: - Result

    enum Issue: String, CaseIterable, Equatable {
        case emptyInput
        case inputTooLong
        case missingAmount
        case invalidAmount
        case negativeAmount
        case multipleAmounts
        case missingType
        case ambiguousType
        case missingCategory
        case ambiguousCategory
        case missingAccount
        case ambiguousAccount

        var message: String {
            switch self {
            case .emptyInput:
                return "请输入一句话"
            case .inputTooLong:
                return "输入过长，已截断"
            case .missingAmount, .invalidAmount, .negativeAmount:
                return "无法识别金额"
            case .multipleAmounts:
                return "识别到多笔金额，请确认"
            case .missingType, .ambiguousType:
                return "请选择收入或支出"
            case .missingCategory, .ambiguousCategory:
                return "请选择分类"
            case .missingAccount, .ambiguousAccount:
                return "请选择账户"
            }
        }
    }

    enum TypeSource: String, Equatable {
        case keyword
        case category
        case none
    }

    struct ParsedEntry: Equatable {
        let originalText: String
        var amount: Decimal?
        var type: TransactionType?
        var typeSource: TypeSource
        var category: CategoryOption?
        var account: AccountOption?
        var remark: String
        var issues: [Issue]

        /// A strict gate for the UI. Any unmatched or ambiguous field keeps the
        /// result out of the one-tap save path until the user resolves it.
        var isReadyToSave: Bool {
            amount != nil
                && type != nil
                && category != nil
                && account != nil
                && issues.isEmpty
        }
    }

    // MARK: - Limits

    private static let maxInputLength = 512
    private static let maxRemarkLength = 60

    // MARK: - Public API

    func parse(
        _ rawText: String,
        categories: [CategoryOption] = [],
        accounts: [AccountOption] = []
    ) -> ParsedEntry {
        let sanitized = sanitize(rawText)
        var issues: [Issue] = []

        guard !sanitized.text.isEmpty else {
            issues.append(.emptyInput)
            return ParsedEntry(
                originalText: sanitized.text,
                amount: nil,
                type: nil,
                typeSource: .none,
                category: nil,
                account: nil,
                remark: "",
                issues: issues
            )
        }

        if sanitized.wasTruncated {
            issues.append(.inputTooLong)
        }

        let text = normalize(sanitized.text)
        let amountResult = extractAmounts(from: text)
        issues.append(contentsOf: amountResult.issues)

        let typeResult = detectType(in: text)
        if typeResult.ambiguous {
            issues.append(.ambiguousType)
        }

        let categoryResult = matchCategory(in: text, categories: categories, type: typeResult.type)
        if categoryResult.ambiguous {
            issues.append(.ambiguousCategory)
        }

        let accountResult = matchAccount(in: text, accounts: accounts)
        if accountResult.ambiguous {
            issues.append(.ambiguousAccount)
        }

        var resolvedType = typeResult.type
        var typeSource: TypeSource = resolvedType == nil ? .none : .keyword

        // A uniquely matched category is a safe fallback for "吃饭 30".
        // It is still not used when the sentence contains conflicting type
        // keywords, because that case must go back to the user.
        if resolvedType == nil,
           !typeResult.ambiguous,
           let category = categoryResult.match?.option {
            resolvedType = category.kind == .income ? .income : .expense
            typeSource = .category
        }

        if resolvedType == nil, !typeResult.ambiguous {
            issues.append(.missingType)
        }

        if categoryResult.match == nil, !categoryResult.ambiguous {
            issues.append(.missingCategory)
        }

        if accountResult.match == nil, !accountResult.ambiguous {
            issues.append(.missingAccount)
        }

        let remark = makeRemark(
            from: text,
            amountRanges: amountResult.ranges,
            categoryMatch: categoryResult.match,
            accountMatch: accountResult.match
        )

        return ParsedEntry(
            originalText: sanitized.text,
            amount: amountResult.amount,
            type: resolvedType,
            typeSource: typeSource,
            category: categoryResult.match?.option,
            account: accountResult.match?.option,
            remark: remark,
            issues: issues
        )
    }

    // MARK: - Sanitizing and normalization

    private func sanitize(_ rawText: String) -> (text: String, wasTruncated: Bool) {
        let filtered = rawText.unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }
            .map(String.init)
            .joined()

        let trimmed = filtered.trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = String(trimmed.prefix(Self.maxInputLength))
        return (limited, trimmed.count > Self.maxInputLength)
    }

    private func normalize(_ text: String) -> String {
        let mapped = text.map { Self.widthMap[$0] ?? $0 }
        return String(mapped).lowercased()
    }

    private static let widthMap: [Character: Character] = [
        "０": "0", "１": "1", "２": "2", "３": "3", "４": "4",
        "５": "5", "６": "6", "７": "7", "８": "8", "９": "9",
        "．": ".", "，": ",", "￥": "¥", "－": "-", "−": "-",
        "—": "-", "：": ":", "；": ";", "（": "(", "）": ")",
        "【": "[", "】": "]", "《": "<", "》": ">"
    ]

    // MARK: - Amount

    private struct AmountCandidate {
        let value: Decimal
        let range: Range<String.Index>
        let hasCurrencyOrUnit: Bool
        let isNegative: Bool
    }

    private struct AmountExtraction {
        let amount: Decimal?
        let ranges: [Range<String.Index>]
        let issues: [Issue]
    }

    private static let amountRegex: NSRegularExpression = {
        // Groups: 1 = sign, 2 = currency, 3 = number, 4 = unit.
        let pattern = "(?<![0-9.])([-−－])?\\s*([¥￥$€£])?\\s*(\\d+(?:[.,]\\d{1,3})?)\\s*(元|块|圆|人民币|CNY|RMB)?(?![0-9.])"
        return try! NSRegularExpression(pattern: pattern, options: [])
    }()

    private func extractAmounts(from text: String) -> AmountExtraction {
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = Self.amountRegex.matches(in: text, options: [], range: fullRange)
        var candidates: [AmountCandidate] = []
        var issues: [Issue] = []

        for match in matches {
            guard let numberRange = Range(match.range(at: 3), in: text),
                  let fullMatchRange = Range(match.range, in: text) else {
                continue
            }

            let rawNumber = String(text[numberRange])
            if isDateOrTimeComponent(
                text: text,
                numberRange: numberRange,
                rawNumber: rawNumber
            ) {
                continue
            }

            guard let value = decimal(from: rawNumber), value > 0 else {
                issues.append(.invalidAmount)
                continue
            }

            let currencyRange = match.range(at: 2)
            let unitRange = match.range(at: 4)
            let hasCurrencyOrUnit =
                (currencyRange.location != NSNotFound && currencyRange.length > 0)
                || (unitRange.location != NSNotFound && unitRange.length > 0)
            let isNegative = match.range(at: 1).location != NSNotFound
                && match.range(at: 1).length > 0

            candidates.append(
                AmountCandidate(
                    value: value,
                    range: fullMatchRange,
                    hasCurrencyOrUnit: hasCurrencyOrUnit,
                    isNegative: isNegative
                )
            )
        }

        guard !candidates.isEmpty else {
            if !issues.contains(.invalidAmount) {
                issues.append(.missingAmount)
            }
            return AmountExtraction(amount: nil, ranges: [], issues: issues)
        }

        if candidates.contains(where: { $0.isNegative }) {
            issues.append(.negativeAmount)
            return AmountExtraction(
                amount: nil,
                ranges: candidates.map(\.range),
                issues: issues
            )
        }

        if candidates.count > 1 {
            issues.append(.multipleAmounts)
        }

        let preferred = candidates.first(where: { $0.hasCurrencyOrUnit }) ?? candidates[0]
        return AmountExtraction(
            amount: preferred.value,
            ranges: candidates.map(\.range),
            issues: issues
        )
    }

    private func decimal(from rawNumber: String) -> Decimal? {
        var number = rawNumber
        if number.contains(",") {
            let parts = number.split(separator: ",", omittingEmptySubsequences: false)
            if parts.count == 2, parts[1].count == 3 {
                // 1,000 is a thousands separator.
                number = parts.joined()
            } else {
                // 15,5 is a decimal comma.
                number = number.replacingOccurrences(of: ",", with: ".")
            }
        }
        return Decimal(string: number, locale: Locale(identifier: "en_US_POSIX"))
    }

    private func isDateOrTimeComponent(
        text: String,
        numberRange: Range<String.Index>,
        rawNumber: String
    ) -> Bool {
        let before = text[..<numberRange.lowerBound].last.map(String.init) ?? ""
        let after = text[numberRange.upperBound...].prefix(2)

        if after.hasPrefix("年")
            || after.hasPrefix("月")
            || after.hasPrefix("日")
            || after.hasPrefix("号")
            || after.hasPrefix("点")
            || after.hasPrefix("分")
            || after.hasPrefix("秒")
            || after.hasPrefix("%")
            || after.hasPrefix("折")
            || after.hasPrefix("岁") {
            return true
        }

        if after.hasPrefix(":") || after.hasPrefix("：") {
            return true
        }

        if before == ":" || before == "：" {
            return true
        }

        if rawNumber.count == 4, after.hasPrefix("-") || after.hasPrefix("/") {
            return true
        }

        if (before == "-" || before == "/")
            && (after.hasPrefix("-") || after.hasPrefix("/") || after.isEmpty) {
            return true
        }

        return false
    }

    // MARK: - Type

    private struct TypeDetection {
        let type: TransactionType?
        let ambiguous: Bool
    }

    private static let expenseKeywords = [
        "支出", "花了", "花费", "消费", "付款", "支付", "买了", "付了",
        "扣款", "扣费", "发红包", "买", "付", "花"
    ]

    private static let incomeKeywords = [
        "收入", "入账", "到账", "发工资", "发薪", "发放", "工资", "薪水",
        "薪资", "奖金", "报销", "收款", "收到", "赚了", "赚", "收", "发"
    ]

    private func detectType(in text: String) -> TypeDetection {
        let expense = firstKeyword(in: text, keywords: Self.expenseKeywords)
        let income = firstKeyword(in: text, keywords: Self.incomeKeywords)

        if let expense, let income {
            // "发红包" is an expense, not an income because of the generic "发".
            if expense == "发红包", income == "发" {
                return TypeDetection(type: .expense, ambiguous: false)
            }
            return TypeDetection(type: nil, ambiguous: true)
        }

        if let expense {
            return TypeDetection(type: .expense, ambiguous: false)
        }

        if let income {
            return TypeDetection(type: .income, ambiguous: false)
        }

        return TypeDetection(type: nil, ambiguous: false)
    }

    private func firstKeyword(in text: String, keywords: [String]) -> String? {
        keywords.first(where: { text.contains($0) })
    }

    // MARK: - Category

    private struct CategoryMatch {
        let option: CategoryOption
        let surface: String
        let score: Int
        let matchedByName: Bool
    }

    private struct CategoryMatchResult {
        let match: CategoryMatch?
        let ambiguous: Bool
    }

    private static let categoryAliases: [String: [String]] = [
        "餐饮": [
            "吃饭", "早餐", "午餐", "晚餐", "外卖", "餐厅", "食堂",
            "火锅", "烧烤", "奶茶", "咖啡", "零食", "买菜", "菜市场"
        ],
        "交通": [
            "打车", "地铁", "公交", "出租车", "滴滴", "高铁", "火车",
            "机票", "加油", "停车", "过路费", "共享单车"
        ],
        "购物": [
            "淘宝", "京东", "拼多多", "衣服", "鞋子", "日用品",
            "超市", "网购", "商场"
        ],
        "住房": [
            "房租", "水费", "电费", "燃气", "物业", "宽带", "维修"
        ],
        "娱乐": [
            "电影", "游戏", "唱歌", "ktv", "会员", "视频会员", "演出"
        ],
        "医疗": [
            "医院", "看病", "挂号", "药", "体检", "牙医"
        ],
        "学习": [
            "书", "课程", "学费", "文具", "培训", "考试"
        ],
        "奶茶": [
            "奶茶", "喜茶", "蜜雪", "瑞幸", "茶饮"
        ],
        "工资": [
            "工资", "薪水", "薪资", "发薪", "月薪", "奖金"
        ],
        "副业": [
            "兼职", "副业", "稿费", "外包", "接单"
        ],
        "红包": [
            "红包", "压岁钱", "礼金"
        ],
        "生活费": [
            "生活费", "家用"
        ],
        "兼职": [
            "兼职", "副业", "外包"
        ],
        "奖学金": [
            "奖学金", "助学金"
        ]
    ]

    private func matchCategory(
        in text: String,
        categories: [CategoryOption],
        type: TransactionType?
    ) -> CategoryMatchResult {
        let allowedKind: CategoryKind?
        switch type {
        case .income:
            allowedKind = .income
        case .expense:
            allowedKind = .expense
        default:
            allowedKind = nil
        }

        let textTokens = tokens(in: text)
        var best: CategoryMatch?
        var ambiguous = false

        for category in categories {
            if let allowedKind, category.kind != allowedKind {
                continue
            }
            guard let candidate = categoryCandidate(
                category,
                text: text,
                textTokens: textTokens
            ) else {
                continue
            }

            if let currentBest = best {
                if candidate.score < currentBest.score {
                    continue
                }
                if candidate.score == currentBest.score {
                    ambiguous = true
                    continue
                }
            }

            best = candidate
            ambiguous = false
        }

        return CategoryMatchResult(match: ambiguous ? nil : best, ambiguous: ambiguous)
    }

    private func categoryCandidate(
        _ category: CategoryOption,
        text: String,
        textTokens: Set<String>
    ) -> CategoryMatch? {
        let name = normalize(category.name)
        guard !name.isEmpty else {
            return nil
        }

        var best: CategoryMatch?

        if text.contains(name) {
            best = CategoryMatch(
                option: category,
                surface: name,
                score: 200 + name.count,
                matchedByName: true
            )
        }

        for alias in Self.categoryAliases[name] ?? [] {
            let term = normalize(alias)
            guard !term.isEmpty, text.contains(term) else {
                continue
            }
            let candidate = CategoryMatch(
                option: category,
                surface: term,
                score: 120 + term.count,
                matchedByName: false
            )
            if best == nil || candidate.score > best!.score {
                best = candidate
            }
        }

        if best == nil {
            let nameTokens = tokens(in: name)
            let sharedTokens = nameTokens.intersection(textTokens).count
            if !nameTokens.isEmpty,
               Double(sharedTokens) / Double(nameTokens.count) >= 0.5 {
                best = CategoryMatch(
                    option: category,
                    surface: name,
                    score: 80,
                    matchedByName: true
                )
            } else {
                let nameCharacters = Set(name)
                let sharedCharacters = nameCharacters.intersection(Set(text)).count
                if nameCharacters.count >= 2,
                   Double(sharedCharacters) / Double(nameCharacters.count) >= 0.66 {
                    best = CategoryMatch(
                        option: category,
                        surface: name,
                        score: 60,
                        matchedByName: true
                    )
                }
            }
        }

        return best
    }

    // MARK: - Account

    private struct AccountMatch {
        let option: AccountOption
        let surface: String
        let score: Int
    }

    private struct AccountMatchResult {
        let match: AccountMatch?
        let ambiguous: Bool
    }

    private static let accountAliases: [String: [String]] = [
        "微信": ["微信", "微信支付", "wechat", "wx"],
        "支付宝": ["支付宝", "alipay", "zfb"],
        "现金": ["现金", "现钞", "钱包"],
        "银行卡": ["银行卡", "储蓄卡", "借记卡", "信用卡", "银行", "卡"],
        "花呗": ["花呗"],
        "云闪付": ["云闪付"],
        "招商银行": ["招行", "招商银行"],
        "工商银行": ["工行", "工商银行"],
        "建设银行": ["建行", "建设银行"],
        "农业银行": ["农行", "农业银行"],
        "中国银行": ["中行", "中国银行"]
    ]

    private func matchAccount(
        in text: String,
        accounts: [AccountOption]
    ) -> AccountMatchResult {
        var best: AccountMatch?
        var ambiguous = false

        for account in accounts {
            guard let candidate = accountCandidate(account, text: text) else {
                continue
            }

            if let currentBest = best {
                if candidate.score < currentBest.score {
                    continue
                }
                if candidate.score == currentBest.score {
                    ambiguous = true
                    continue
                }
            }

            best = candidate
            ambiguous = false
        }

        return AccountMatchResult(match: ambiguous ? nil : best, ambiguous: ambiguous)
    }

    private func accountCandidate(
        _ account: AccountOption,
        text: String
    ) -> AccountMatch? {
        let name = normalize(account.name)
        guard !name.isEmpty else {
            return nil
        }

        var best: AccountMatch?

        if text.contains(name) {
            best = AccountMatch(
                option: account,
                surface: name,
                score: 200 + name.count
            )
        }

        for alias in accountAliases(for: name) {
            let term = normalize(alias)
            guard !term.isEmpty, text.contains(term) else {
                continue
            }
            let candidate = AccountMatch(
                option: account,
                surface: term,
                score: 120 + term.count
            )
            if best == nil || candidate.score > best!.score {
                best = candidate
            }
        }

        return best
    }

    private func accountAliases(for name: String) -> [String] {
        var terms = Self.accountAliases[name] ?? []

        if name.contains("微信") {
            terms.append(contentsOf: ["微信", "微信支付", "wechat", "wx"])
        }
        if name.contains("支付宝") {
            terms.append(contentsOf: ["支付宝", "alipay", "zfb"])
        }
        if name.contains("现金") {
            terms.append(contentsOf: ["现金", "现钞", "钱包"])
        }
        if name.contains("银行") || name.contains("卡") {
            terms.append(contentsOf: ["银行卡", "储蓄卡", "借记卡", "信用卡", "银行", "卡"])
        }
        if name.contains("招商") {
            terms.append(contentsOf: ["招行", "招商银行"])
        }
        if name.contains("工商") {
            terms.append(contentsOf: ["工行", "工商银行"])
        }
        if name.contains("建设") {
            terms.append(contentsOf: ["建行", "建设银行"])
        }
        if name.contains("农业") {
            terms.append(contentsOf: ["农行", "农业银行"])
        }
        if name.contains("中国银行") {
            terms.append(contentsOf: ["中行", "中国银行"])
        }

        return Array(Set(terms)).sorted()
    }

    // MARK: - Tokenization

    private func tokens(in text: String) -> Set<String> {
        guard !text.isEmpty else {
            return []
        }

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var result: Set<String> = []

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = String(text[range])
            if token.count >= 2 {
                result.insert(token)
            }
            return true
        }

        // Keep a small lexical pass as a second opinion. NLTokenizer handles
        // Chinese word boundaries; NLTagger adds noun/verb tokens that are
        // useful for merchant and category names.
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitPunctuation, .omitWhitespace]
        ) { tag, range in
            if let tag, tag == .noun || tag == .verb {
                let token = String(text[range])
                if token.count >= 2 {
                    result.insert(token)
                }
            }
            return true
        }

        return result
    }

    // MARK: - Remark

    private func makeRemark(
        from text: String,
        amountRanges: [Range<String.Index>],
        categoryMatch: CategoryMatch?,
        accountMatch: AccountMatch?
    ) -> String {
        var result = text

        for range in amountRanges.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            guard range.lowerBound >= result.startIndex,
                  range.upperBound <= result.endIndex else {
                continue
            }
            result.removeSubrange(range)
        }

        if let accountMatch {
            result = result.replacingOccurrences(of: accountMatch.surface, with: " ")
        }

        if let categoryMatch, categoryMatch.matchedByName {
            // Alias matches stay in the remark: "买奶茶 15" -> "奶茶".
            result = result.replacingOccurrences(of: categoryMatch.surface, with: " ")
        }

        for keyword in Self.expenseKeywords + Self.incomeKeywords {
            result = result.replacingOccurrences(of: keyword, with: " ")
        }

        let cleaned = result.unicodeScalars
            .filter { scalar in
                !CharacterSet.punctuationCharacters.contains(scalar)
                    && !CharacterSet.whitespacesAndNewlines.contains(scalar)
                    && !CharacterSet.symbols.contains(scalar)
            }
            .map(String.init)
            .joined()

        if cleaned.isEmpty {
            return "极速记账"
        }

        return String(cleaned.prefix(Self.maxRemarkLength))
    }
}
