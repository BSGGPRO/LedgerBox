import CryptoKit
import Foundation

// MARK: - Receipt model

enum ReceiptSource: String, Codable, CaseIterable, Equatable, Hashable {
    case wechat
    case alipay
    case bank
    case unknown
}

enum ReceiptWarning: String, Codable, CaseIterable, Equatable, Hashable {
    case lowOCRConfidence
    case ambiguousAmount
    case missingAmount
    case missingDate
    case feeSplitAmbiguous
    case modelFallback
    case duplicateOrder
}

/// How a withdrawal fee is charged. The parser only supplies a default; the UI
/// must let the user switch because a single OCR line often cannot prove which
/// side paid the fee.
enum FeeMode: String, Codable, CaseIterable, Equatable, Hashable {
    case feeDeductedFromPrincipal
    case feePaidSeparately
}

struct TransferSplit: Equatable {
    /// The amount requested from the wallet before any fee adjustment.
    let principal: Decimal
    /// The service fee, normally zero when the receipt has no fee line.
    let fee: Decimal
    /// The amount that reaches the destination account.
    let credited: Decimal
    /// The total amount that leaves the source account.
    let cashOut: Decimal
    let mode: FeeMode

    /// Returns a consistent split for the requested interpretation. The
    /// principal and fee stay fixed; only credited/cashOut change.
    func switching(to mode: FeeMode) -> TransferSplit {
        switch mode {
        case .feeDeductedFromPrincipal:
            return TransferSplit(
                principal: principal,
                fee: fee,
                credited: Swift.max(principal - fee, Decimal.zero),
                cashOut: principal,
                mode: mode
            )
        case .feePaidSeparately:
            return TransferSplit(
                principal: principal,
                fee: fee,
                credited: principal,
                cashOut: principal + fee,
                mode: mode
            )
        }
    }
}

/// Pure parser output. Nothing here is persisted directly; the import service
/// turns it into an `ImportDraft` only after the user confirms the fields.
struct ReceiptFields: Equatable {
    let rawText: String
    let normalizedText: String
    let merchantText: String?
    let amount: Decimal?
    let fee: Decimal?
    let occurredAt: Date?
    let orderIDHash: String?
    let source: ReceiptSource
    let warnings: [ReceiptWarning]

    /// Order hash when available, otherwise a stable hash of source, merchant,
    /// amount and the minute-level date.
    var dedupeKey: String {
        ReceiptParser.dedupeKey(for: self)
    }
}

// MARK: - Parser

/// Deterministic receipt parser for WeChat/Alipay/bank screenshots.
///
/// The parser never guesses a final fee mode and never stores a raw order ID.
/// OCR text is the only input; no network or model call is made here.
enum ReceiptParser {

    // MARK: Limits

    private static let maxAmount: Decimal = 10_000_000
    private static let currencySymbol: Character = "¥"

    // MARK: Keywords

    private static let positiveAmountKeywords = [
        "实付", "支付", "付款", "合计", "总计", "金额", "消费", "应付",
        "交易金额", "提现金额", "到账金额", "转账金额"
    ]

    private static let negativeAmountKeywords = [
        "余额", "优惠", "红包", "积分", "订单号", "单号", "流水号",
        "服务费", "手续费", "折扣", "抵扣", "优惠券"
    ]

    private static let merchantStopLabels = [
        "支付时间", "交易时间", "付款时间", "收款时间", "转账时间",
        "订单号", "订单编号", "交易单号", "商户单号", "流水号",
        "金额", "实付", "合计", "付款方式", "支付方式", "备注"
    ]

    private static let merchantHeaderKeywords = [
        "微信支付", "支付宝", "支付成功", "交易成功", "付款成功", "收款成功",
        "账单详情", "账单", "详情", "收款方", "付款方", "交易时间",
        "支付时间", "订单号", "商户单号", "交易单号", "流水号", "金额",
        "实付", "合计", "备注", "银行卡", "信用卡", "储蓄卡", "银行",
        "电子回单", "回单", "交易流水"
    ]

    private static let transferPrincipalKeywords = [
        "提现金额", "提现", "取现金额", "取现", "转出金额", "转出", "本金"
    ]

    private static let transferFeeKeywords = ["服务费", "手续费", "提现费"]

    private static let transferCreditedKeywords = [
        "实际到账", "到账金额", "到账", "入账金额", "入账"
    ]

    // MARK: Regexes

    private static let amountRegex = try! NSRegularExpression(
        pattern: #"(?<![0-9A-Za-z])(?:¥\s*)?(\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)(?:\s*元)?"#,
        options: []
    )

    private static let fullDateRegex = try! NSRegularExpression(
        pattern: #"(\d{4})\s*[-/.年]\s*(\d{1,2})\s*[-/.月]\s*(\d{1,2})\s*日?(?:\s*[T ]?\s*(\d{1,2}):(\d{2})(?::\d{2})?)?"#,
        options: []
    )

    private static let monthDayRegex = try! NSRegularExpression(
        pattern: #"(\d{1,2})\s*月\s*(\d{1,2})\s*日?(?:\s*(\d{1,2}):(\d{2})(?::\d{2})?)?"#,
        options: []
    )

    private static let relativeDateRegex = try! NSRegularExpression(
        pattern: #"(今天|今日|昨天|昨日|前天)(?:\s*(\d{1,2}):(\d{2})(?::\d{2})?)?"#,
        options: []
    )

    private static let orderRegex = try! NSRegularExpression(
        pattern: #"(?:订单号|订单编号|交易单号|商户单号|流水号|交易号|单号)\s*[:#]?\s*([A-Za-z0-9][A-Za-z0-9_-]{3,63})"#,
        options: []
    )

    private static let merchantRegex = try! NSRegularExpression(
        pattern: #"(?:商户(?:名称|全称)?|商家|收款方|收款人|店铺(?:名称)?|门店)\s*[:：]?\s*([^\n]{2,60})"#,
        options: []
    )

    // MARK: Public API

    static func parse(
        _ text: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ReceiptFields {
        let normalized = normalize(text)
        let source = detectSource(normalized)
        let transfer = transferSplit(in: normalized)
        let amountResult = extractAmount(in: normalized)
        let dateResult = extractDate(in: normalized, now: now, calendar: calendar)
        let merchant = extractMerchant(in: normalized, source: source)
        let orderHash = extractOrderIDHash(in: normalized)

        var warnings: [ReceiptWarning] = []
        var amount: Decimal?
        var fee: Decimal?

        if let transfer {
            // A withdrawal line is the authoritative amount; generic scoring
            // frequently prefers the "到账" number instead of the principal.
            amount = transfer.principal
            fee = transfer.fee > 0 ? transfer.fee : nil
            if transfer.fee > 0 {
                warnings.append(.feeSplitAmbiguous)
            }
        } else {
            amount = amountResult.value
            if amountResult.ambiguous {
                warnings.append(.ambiguousAmount)
            }
        }

        if amount == nil {
            warnings.append(.missingAmount)
        }

        let occurredAt: Date
        if let parsedDate = dateResult.date {
            occurredAt = parsedDate
        } else {
            occurredAt = calendar.startOfDay(for: now)
            warnings.append(.missingDate)
        }

        return ReceiptFields(
            rawText: text,
            normalizedText: normalized,
            merchantText: merchant,
            amount: amount,
            fee: fee,
            occurredAt: occurredAt,
            orderIDHash: orderHash,
            source: source,
            warnings: warnings
        )
    }

    /// Width-folds full-width ASCII, normalizes the yen sign, trims each line
    /// and collapses repeated horizontal whitespace. Case is preserved so the
    /// merchant name remains readable in the UI.
    static func normalize(_ text: String) -> String {
        var folded = ""
        for scalar in text.unicodeScalars {
            var value = scalar
            if scalar.value == 0x3000 {
                value = " "
            } else if scalar.value == 0xFFE5 {
                value = "¥"
            } else if (0xFF01...0xFF5E).contains(scalar.value),
                      let converted = UnicodeScalar(scalar.value - 0xFEE0) {
                value = converted
            }

            if value.value == 0x0D {
                continue
            }
            folded.append(String(value))
        }

        let lines = folded.components(separatedBy: .newlines)
            .map { line -> String in
                var cleaned = line.replacingOccurrences(of: "\t", with: " ")
                cleaned = cleaned.replacingOccurrences(of: "\u{00A0}", with: " ")
                cleaned = cleaned.replacingOccurrences(
                    of: " {2,}",
                    with: " ",
                    options: .regularExpression
                )
                return cleaned.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }

        return lines.joined(separator: "\n")
    }

    /// Extracts a WeChat-style withdrawal split. Returns `nil` when the text is
    /// not a withdrawal. The default mode is fee-deducted, but callers must let
    /// the user switch to `feePaidSeparately`.
    static func transferSplit(in text: String) -> TransferSplit? {
        let normalized = normalize(text)
        guard normalized.contains("提现") || normalized.contains("取现") else {
            return nil
        }

        let candidates = rawAmounts(in: normalized)
        guard !candidates.isEmpty else {
            return nil
        }

        let feeCandidate = amountNear(
            keywords: transferFeeKeywords,
            in: normalized,
            candidates: candidates
        )
        let creditedCandidate = amountNear(
            keywords: transferCreditedKeywords,
            in: normalized,
            candidates: candidates
        )
        var principal = amountNear(
            keywords: transferPrincipalKeywords,
            in: normalized,
            candidates: candidates
        )

        var fee = feeCandidate ?? Decimal.zero

        if let creditedCandidate, let currentPrincipal = principal {
            if creditedCandidate < currentPrincipal, fee == 0 {
                // "提现 1000，到账 999.9" without an explicit fee label.
                fee = currentPrincipal - creditedCandidate
            }
        } else if principal == nil, let creditedCandidate {
            principal = creditedCandidate + fee
        }

        guard let principal, principal > 0 else {
            return nil
        }

        if fee < 0 {
            fee = Decimal.zero
        }

        var mode: FeeMode = .feeDeductedFromPrincipal
        if let creditedCandidate {
            if sameMoney(creditedCandidate, principal - fee) {
                mode = .feeDeductedFromPrincipal
            } else if fee > 0, sameMoney(creditedCandidate, principal) {
                mode = .feePaidSeparately
            }
        }

        let split = TransferSplit(
            principal: principal,
            fee: fee,
            credited: principal,
            cashOut: principal,
            mode: mode
        )
        return split.switching(to: mode)
    }

    // MARK: Dedupe

    static func dedupeKey(
        for fields: ReceiptFields,
        calendar: Calendar = .current
    ) -> String {
        dedupeKey(
            source: fields.source,
            merchant: fields.merchantText,
            amount: fields.amount,
            date: fields.occurredAt,
            orderIDHash: fields.orderIDHash,
            calendar: calendar
        )
    }

    static func dedupeKey(
        source: ReceiptSource,
        merchant: String?,
        amount: Decimal?,
        date: Date?,
        orderIDHash: String?,
        calendar: Calendar = .current
    ) -> String {
        if let orderIDHash, !orderIDHash.isEmpty {
            return orderIDHash
        }

        let merchantKey = merchant.map { normalize($0).lowercased() } ?? ""
        let amountKey = amount.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
        let dateKey = date.map { minuteStamp($0, calendar: calendar) } ?? ""
        let payload = [
            source.rawValue,
            merchantKey,
            amountKey,
            dateKey
        ].joined(separator: "|")
        return sha256Hex(payload)
    }

    static func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", Int($0)) }.joined()
    }

    // MARK: Amounts

    private struct RawAmount {
        let value: Decimal
        let range: Range<String.Index>
        let hasCurrency: Bool
        let hasUnit: Bool
        let isGrouped: Bool
        let hasDecimal: Bool
    }

    private struct ScoredAmount {
        let value: Decimal
        let range: Range<String.Index>
        let score: Double
        let tieBreak: Double
    }

    private static func extractAmount(in text: String) -> (value: Decimal?, ambiguous: Bool) {
        let candidates = scoredAmounts(in: text)
        guard !candidates.isEmpty else {
            return (nil, false)
        }

        let sorted = candidates.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            if lhs.tieBreak != rhs.tieBreak {
                return lhs.tieBreak > rhs.tieBreak
            }
            return lhs.range.lowerBound < rhs.range.lowerBound
        }

        guard let best = sorted.first else {
            return (nil, false)
        }

        var ambiguous = false
        if sorted.count > 1 {
            let second = sorted[1]
            ambiguous = abs(best.score - second.score) <= 0.5
                && best.value != second.value
        }
        return (best.value, ambiguous)
    }

    private static func scoredAmounts(in text: String) -> [ScoredAmount] {
        rawAmounts(in: text).compactMap { candidate in
            let context = lineContext(in: text, range: candidate.range)
            var score = 0.0

            for keyword in positiveAmountKeywords where context.contains(keyword) {
                score += 2
            }
            for keyword in negativeAmountKeywords where context.contains(keyword) {
                score -= 3
            }

            if candidate.hasCurrency { score += 2 }
            if candidate.hasUnit { score += 1 }
            if candidate.hasDecimal { score += 1 }
            if candidate.isGrouped { score += 1 }

            // Only a fallback for ties; it does not change the documented
            // +2 / -3 keyword weights.
            var tieBreak = 0.0
            if context.contains("实付") { tieBreak = 1 }
            else if context.contains("付款") { tieBreak = 0.5 }

            guard score >= 0 else {
                return nil
            }
            return ScoredAmount(
                value: candidate.value,
                range: candidate.range,
                score: score,
                tieBreak: tieBreak
            )
        }
    }

    private static func rawAmounts(in text: String) -> [RawAmount] {
        let nsText = text as NSString
        let matches = amountRegex.matches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        )

        var results: [RawAmount] = []
        for match in matches {
            guard match.numberOfRanges > 1,
                  let numberRange = Range(match.range(at: 1), in: text),
                  let fullRange = Range(match.range, in: text) else {
                continue
            }

            let numberSource = String(text[numberRange])
            let numberText = numberSource.replacingOccurrences(of: ",", with: "")
            guard let value = Decimal(
                string: numberText,
                locale: Locale(identifier: "en_US_POSIX")
            ), value > 0, value <= maxAmount else {
                continue
            }

            guard !isTokenEmbedded(numberRange, in: text),
                  !isTokenEmbedded(fullRange, in: text) else {
                continue
            }

            let prefix = text[fullRange.lowerBound..<numberRange.lowerBound]
            let suffix = text[numberRange.upperBound..<fullRange.upperBound]
            let hasCurrency = prefix.contains(currencySymbol)
            let hasUnit = suffix.contains("元")
            let hasDecimal = numberSource.contains(".")
            let isGrouped = numberSource.contains(",")

            if !hasCurrency && !hasUnit && !hasDecimal && !isGrouped {
                let nearby = shortContext(
                    in: text,
                    range: fullRange,
                    before: 8,
                    after: 4
                )
                let hasNearbyKeyword = positiveAmountKeywords.contains {
                    nearby.contains($0)
                }
                guard hasNearbyKeyword else {
                    continue
                }
            }

            results.append(
                RawAmount(
                    value: value,
                    range: fullRange,
                    hasCurrency: hasCurrency,
                    hasUnit: hasUnit,
                    isGrouped: isGrouped,
                    hasDecimal: hasDecimal
                )
            )
        }
        return results
    }

    /// Rejects numbers that are really dates, times, order IDs or model codes.
    private static func isTokenEmbedded(
        _ range: Range<String.Index>,
        in text: String
    ) -> Bool {
        if let before = character(before: range.lowerBound, in: text),
           isASCIIWord(before) {
            return true
        }
        if let after = character(after: range.upperBound, in: text),
           isASCIIWord(after) {
            return true
        }

        let separators: Set<Character> = ["-", "/", ":", ".", "_"]
        if let before = character(before: range.lowerBound, in: text),
           separators.contains(before) {
            let separatorIndex = text.index(before: range.lowerBound)
            if let earlier = character(before: separatorIndex, in: text),
               earlier.isNumber {
                return true
            }
        }
        if let after = character(after: range.upperBound, in: text),
           separators.contains(after) {
            let separatorIndex = text.index(after: range.upperBound)
            if let later = character(after: separatorIndex, in: text),
               later.isNumber {
                return true
            }
        }

        if let before = character(before: range.lowerBound, in: text),
           before == "第" {
            return true
        }

        let dateUnits: Set<Character> = ["年", "月", "日", "号", "折"]
        if let after = character(after: range.upperBound, in: text),
           dateUnits.contains(after) {
            return true
        }

        return false
    }

    private static func isASCIIWord(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || character == "_")
    }

    private static func character(
        before index: String.Index,
        in text: String
    ) -> Character? {
        guard index > text.startIndex else {
            return nil
        }
        return text[text.index(before: index)]
    }

    private static func character(
        after index: String.Index,
        in text: String
    ) -> Character? {
        guard index < text.endIndex else {
            return nil
        }
        return text[index]
    }

    // MARK: Context

    private static func lineContext(
        in text: String,
        range: Range<String.Index>
    ) -> String {
        let lineStart = text[..<range.lowerBound]
            .lastIndex(of: "\n")
            .map { text.index(after: $0) } ?? text.startIndex
        let lineEnd = text[range.upperBound...]
            .firstIndex(of: "\n") ?? text.endIndex
        let line = String(text[lineStart..<lineEnd])

        let hasKeyword = positiveAmountKeywords.contains { line.contains($0) }
            || negativeAmountKeywords.contains { line.contains($0) }
        if hasKeyword || lineStart == text.startIndex {
            return line
        }

        // Labels sometimes sit on the line above the amount. Only borrow that
        // line when the amount line itself has no keyword, so a nearby
        // "余额" line cannot poison a real "实付" line.
        let previousEnd = text.index(before: lineStart)
        let previousStart = text[..<previousEnd]
            .lastIndex(of: "\n")
            .map { text.index(after: $0) } ?? text.startIndex
        let previous = String(text[previousStart..<previousEnd])
            .trimmingCharacters(in: .whitespaces)
        guard !previous.isEmpty else {
            return line
        }
        return previous + " " + line
    }

    private static func shortContext(
        in text: String,
        range: Range<String.Index>,
        before: Int,
        after: Int
    ) -> String {
        let start = text.index(
            range.lowerBound,
            offsetBy: -before,
            limitedBy: text.startIndex
        ) ?? text.startIndex
        let end = text.index(
            range.upperBound,
            offsetBy: after,
            limitedBy: text.endIndex
        ) ?? text.endIndex
        return String(text[start..<end])
    }

    // MARK: Dates

    private struct DateCandidate {
        let date: Date
        let position: Int
        let score: Int
        let hasTime: Bool
    }

    private static func extractDate(
        in text: String,
        now: Date,
        calendar: Calendar
    ) -> (date: Date?, hasDate: Bool) {
        var candidates: [DateCandidate] = []
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        let fullDateMatches = fullDateRegex.matches(in: text, range: fullRange)
        var fullDateRanges: [NSRange] = []
        for match in fullDateMatches {
            fullDateRanges.append(match.range)
            guard let year = integer(in: text, match: match, group: 1),
                  let month = integer(in: text, match: match, group: 2),
                  let day = integer(in: text, match: match, group: 3) else {
                continue
            }
            let time = timeParts(in: text, match: match, hourGroup: 4, minuteGroup: 5)
            guard let date = makeDate(
                year: year,
                month: month,
                day: day,
                hour: time.hour,
                minute: time.minute,
                hasTime: time.hasTime,
                hasExplicitYear: true,
                now: now,
                calendar: calendar
            ) else {
                continue
            }
            candidates.append(
                DateCandidate(
                    date: date,
                    position: match.range.location,
                    score: dateContextScore(in: text, match: match),
                    hasTime: time.hasTime
                )
            )
        }

        for match in monthDayRegex.matches(in: text, range: fullRange) {
            // "2026年10月20日" also contains "10月20日". Do not let the
            // year-less shadow candidate replace the explicit year.
            if fullDateRanges.contains(where: {
                NSIntersectionRange($0, match.range).length > 0
            }) {
                continue
            }
            guard let month = integer(in: text, match: match, group: 1),
                  let day = integer(in: text, match: match, group: 2) else {
                continue
            }
            let time = timeParts(in: text, match: match, hourGroup: 3, minuteGroup: 4)
            guard let date = makeDate(
                year: calendar.component(.year, from: now),
                month: month,
                day: day,
                hour: time.hour,
                minute: time.minute,
                hasTime: time.hasTime,
                hasExplicitYear: false,
                now: now,
                calendar: calendar
            ) else {
                continue
            }
            candidates.append(
                DateCandidate(
                    date: date,
                    position: match.range.location,
                    score: dateContextScore(in: text, match: match),
                    hasTime: time.hasTime
                )
            )
        }

        for match in relativeDateRegex.matches(in: text, range: fullRange) {
            guard let relativeRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            let relative = String(text[relativeRange])
            let offset: Int
            switch relative {
            case "今天", "今日":
                offset = 0
            case "昨天", "昨日":
                offset = 1
            case "前天":
                offset = 2
            default:
                continue
            }

            let time = timeParts(in: text, match: match, hourGroup: 2, minuteGroup: 3)
            let base = calendar.startOfDay(for: now)
            guard let day = calendar.date(byAdding: .day, value: -offset, to: base) else {
                continue
            }
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = time.hasTime ? time.hour : 0
            components.minute = time.hasTime ? time.minute : 0
            components.second = 0
            guard let date = calendar.date(from: components) else {
                continue
            }
            candidates.append(
                DateCandidate(
                    date: date,
                    position: match.range.location,
                    score: dateContextScore(in: text, match: match),
                    hasTime: time.hasTime
                )
            )
        }

        guard let best = candidates.sorted(by: { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            if lhs.hasTime != rhs.hasTime {
                return lhs.hasTime && !rhs.hasTime
            }
            return lhs.position > rhs.position
        }).first else {
            return (nil, false)
        }
        return (best.date, true)
    }

    private static func integer(
        in text: String,
        match: NSTextCheckingResult,
        group: Int
    ) -> Int? {
        guard group < match.numberOfRanges,
              match.range(at: group).location != NSNotFound,
              let range = Range(match.range(at: group), in: text) else {
            return nil
        }
        return Int(text[range])
    }

    private static func timeParts(
        in text: String,
        match: NSTextCheckingResult,
        hourGroup: Int,
        minuteGroup: Int
    ) -> (hour: Int, minute: Int, hasTime: Bool) {
        guard let hour = integer(in: text, match: match, group: hourGroup),
              let minute = integer(in: text, match: match, group: minuteGroup),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return (0, 0, false)
        }
        return (hour, minute, true)
    }

    private static func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        hasTime: Bool,
        hasExplicitYear: Bool,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        guard (1...12).contains(month),
              (1...31).contains(day),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hasTime ? hour : 0
        components.minute = hasTime ? minute : 0
        components.second = 0

        guard let date = calendar.date(from: components) else {
            return nil
        }

        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == year,
              roundTrip.month == month,
              roundTrip.day == day else {
            return nil
        }

        if !hasExplicitYear {
            let threshold = calendar.date(byAdding: .day, value: 1, to: now)
                ?? now.addingTimeInterval(86_400)
            if date > threshold,
               let previousYear = calendar.date(byAdding: .year, value: -1, to: date) {
                return previousYear
            }
        }

        return date
    }

    private static func dateContextScore(
        in text: String,
        match: NSTextCheckingResult
    ) -> Int {
        guard let range = Range(match.range, in: text) else {
            return 0
        }
        let context = lineContext(in: text, range: range)
        var score = 0
        if context.contains("支付时间")
            || context.contains("交易时间")
            || context.contains("付款时间")
            || context.contains("转账时间") {
            score += 3
        } else if context.contains("时间") || context.contains("日期") {
            score += 1
        }
        if context.contains("订单日期") || context.contains("下单时间") {
            score -= 1
        }
        return score
    }

    // MARK: Transfer helpers

    private static func amountNear(
        keywords: [String],
        in text: String,
        candidates: [RawAmount]
    ) -> Decimal? {
        for keyword in keywords {
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let keywordRange = text.range(
                    of: keyword,
                    range: searchStart..<text.endIndex
                  ) {
                let after = candidates.compactMap { candidate -> (RawAmount, Int)? in
                    guard candidate.range.lowerBound >= keywordRange.upperBound else {
                        return nil
                    }
                    let distance = text.distance(
                        from: keywordRange.upperBound,
                        to: candidate.range.lowerBound
                    )
                    guard distance <= 24 else {
                        return nil
                    }
                    return (candidate, distance)
                }
                if let nearest = after.min(by: { $0.1 < $1.1 }) {
                    return nearest.0.value
                }

                let before = candidates.compactMap { candidate -> (RawAmount, Int)? in
                    guard candidate.range.upperBound <= keywordRange.lowerBound else {
                        return nil
                    }
                    let distance = text.distance(
                        from: candidate.range.upperBound,
                        to: keywordRange.lowerBound
                    )
                    guard distance <= 12 else {
                        return nil
                    }
                    return (candidate, distance)
                }
                if let nearest = before.min(by: { $0.1 < $1.1 }) {
                    return nearest.0.value
                }

                guard let next = text.index(
                    keywordRange.upperBound,
                    offsetBy: 1,
                    limitedBy: text.endIndex
                ), next > searchStart else {
                    break
                }
                searchStart = next
            }
        }
        return nil
    }

    private static func sameMoney(_ lhs: Decimal, _ rhs: Decimal) -> Bool {
        lhs.roundedToCents() == rhs.roundedToCents()
    }

    // MARK: Source and merchant

    private static func detectSource(_ text: String) -> ReceiptSource {
        let lower = text.lowercased()
        if containsAny(lower, ["微信", "wechat", "财付通", "零钱"]) {
            return .wechat
        }
        if containsAny(lower, ["支付宝", "alipay", "余额宝", "花呗"]) {
            return .alipay
        }
        if containsAny(lower, [
            "银行", "bank", "信用卡", "储蓄卡", "借记卡",
            "招商银行", "工商银行", "建设银行", "农业银行", "中国银行",
            "交通银行", "浦发", "中信", "民生", "兴业", "光大"
        ]) {
            return .bank
        }
        return .unknown
    }

    private static func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }

    private static func extractMerchant(
        in text: String,
        source: ReceiptSource
    ) -> String? {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        if let match = merchantRegex.firstMatch(in: text, range: range),
           let valueRange = Range(match.range(at: 1), in: text) {
            let value = cleanedMerchant(String(text[valueRange]))
            if !value.isEmpty {
                return value
            }
        }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 2, trimmed.count <= 40 else {
                continue
            }
            if merchantHeaderKeywords.contains(where: { trimmed.contains($0) }) {
                continue
            }
            if trimmed.contains("¥") || trimmed.contains("元") || trimmed.contains(":") {
                continue
            }
            if trimmed.contains(where: { $0.isNumber }) {
                continue
            }
            if trimmed.contains(where: { $0.isLetter }) {
                return trimmed
            }
        }

        // `source` is intentionally unused for the fallback; keeping it in the
        // signature makes future bank-specific headers easy to add.
        _ = source
        return nil
    }

    private static func cleanedMerchant(_ value: String) -> String {
        var cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for label in merchantStopLabels {
            if let range = cleaned.range(of: label) {
                cleaned = String(cleaned[..<range.lowerBound])
            }
        }

        let trailing: Set<Character> = [",", "，", ".", "。", ";", "；", "、", ":", "："]
        while let last = cleaned.last, trailing.contains(last) {
            cleaned.removeLast()
        }
        let leading: Set<Character> = [":", "：", ",", "，", "-", "—"]
        while let first = cleaned.first, leading.contains(first) {
            cleaned.removeFirst()
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(40))
    }

    // MARK: Order ID

    private static func extractOrderIDHash(in text: String) -> String? {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = orderRegex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let value = String(text[valueRange])
        guard value.count >= 4 else {
            return nil
        }
        return sha256Hex(value)
    }

    // MARK: Minute stamp

    private static func minuteStamp(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        return String(
            format: "%04d-%02d-%02dT%02d:%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0
        )
    }
}
