import Foundation

// MARK: - Intents

enum FinanceIntent: String, CaseIterable {
    case recordExpense = "record_expense"
    case recordIncome = "record_income"
    case spendingQuery = "spending_query"
    case balanceQuery = "balance_query"
    case budgetStatus = "budget_status"
    case categoryQuestion = "category_question"
    case savingAdvice = "saving_advice"
    case debtAdvice = "debt_advice"
    case investmentRisk = "investment_risk"
    case emergencyFund = "emergency_fund"
    case financialGoal = "financial_goal"
    case billReminder = "bill_reminder"
    case subscription = "subscription"
    case impulseSpending = "impulse_spending"
    case refund = "refund"
    case transfer = "transfer"
    case splitBill = "split_bill"
    case insurance = "insurance"
    case tax = "tax"
    case other

    var displayName: String {
        switch self {
        case .recordExpense: return "记一笔支出"
        case .recordIncome: return "记一笔收入"
        case .spendingQuery: return "查支出"
        case .balanceQuery: return "查结余"
        case .budgetStatus: return "预算"
        case .categoryQuestion: return "分类"
        case .savingAdvice: return "储蓄"
        case .debtAdvice: return "负债"
        case .investmentRisk: return "投资风险"
        case .emergencyFund: return "应急金"
        case .financialGoal: return "目标"
        case .billReminder: return "账单"
        case .subscription: return "订阅"
        case .impulseSpending: return "冲动消费"
        case .refund: return "退款"
        case .transfer: return "转账"
        case .splitBill: return "分账"
        case .insurance: return "保险"
        case .tax: return "税务"
        case .other: return "其他"
        }
    }
}

struct FinanceIntentPrediction {
    let intent: FinanceIntent
    let confidence: Float

    var percent: Int {
        Int((confidence * 100).rounded())
    }
}

// MARK: - Model

/// A finance-only, hashed character n-gram intent classifier.
///
/// 20 intents x 768 buckets + 20 biases = 15,380 parameters. It routes text to
/// deterministic advice templates; it is not a compressed Qwen checkpoint and
/// it does not generate free-form answers.
final class FinanceMind {
    static let shared = FinanceMind()

    static let parameterCount =
        (FinanceMindWeights.bucketCount * FinanceMindWeights.classCount)
        + FinanceMindWeights.classCount

    private let weights: [Float]
    private let biases: [Float]

    private init() {
        let decoded = Self.decodeWeights()
        weights = decoded.weights
        biases = decoded.biases
    }

    func predict(_ text: String) -> FinanceIntentPrediction? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 2 else {
            return nil
        }

        let features = Self.featureBuckets(normalized)
        guard !features.isEmpty else {
            return nil
        }

        let classCount = FinanceMindWeights.classCount
        var scores = biases
        for (bucket, value) in features {
            for classIndex in 0..<classCount {
                scores[classIndex] += weights[classIndex * FinanceMindWeights.bucketCount + bucket] * value
            }
        }

        let maxScore = scores.max() ?? 0
        var sum: Float = 0
        for index in scores.indices {
            scores[index] = exp(scores[index] - maxScore)
            sum += scores[index]
        }
        guard sum > 0 else {
            return nil
        }

        var bestIndex = 0
        var bestScore = scores[0]
        for index in 1..<scores.count where scores[index] > bestScore {
            bestIndex = index
            bestScore = scores[index]
        }

        let confidence = bestScore / sum
        guard confidence >= 0.35 else {
            return nil
        }

        let label = FinanceMindWeights.labels[bestIndex]
        guard let intent = FinanceIntent(rawValue: label) else {
            return nil
        }
        return FinanceIntentPrediction(intent: intent, confidence: confidence)
    }

    private static func featureBuckets(_ text: String) -> [Int: Float] {
        let chars = text.lowercased().filter {
            !$0.isNumber && !$0.isWhitespace && !"，。！？、,.!?：:；;（）()【】[]".contains($0)
        }
        guard !chars.isEmpty else {
            return [:]
        }

        var buckets: [Int: Float] = [:]
        for char in chars {
            let index = Int(fnv1a("u:\(char)") % UInt32(FinanceMindWeights.bucketCount))
            buckets[index, default: 0] += 1
        }

        let array = Array(chars)
        for index in 0..<(array.count - 1) {
            let key = "b:\(array[index])\(array[index + 1])"
            let bucket = Int(fnv1a(key) % UInt32(FinanceMindWeights.bucketCount))
            buckets[bucket, default: 0] += 1
        }
        return buckets
    }

    private static func fnv1a(_ text: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in text.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return hash
    }

    private static func decodeWeights() -> (weights: [Float], biases: [Float]) {
        guard let data = Data(
            base64Encoded: FinanceMindWeights.encoded,
            options: .ignoreUnknownCharacters
        ) else {
            return (Array(repeating: 0, count: FinanceMindWeights.bucketCount * FinanceMindWeights.classCount),
                    Array(repeating: 0, count: FinanceMindWeights.classCount))
        }

        let count = data.count / MemoryLayout<Int16>.size
        var raw = [Int16](repeating: 0, count: count)
        _ = raw.withUnsafeMutableBytes { buffer in
            data.copyBytes(to: buffer)
        }

        let expected = FinanceMindWeights.bucketCount * FinanceMindWeights.classCount
        guard raw.count >= expected + FinanceMindWeights.classCount else {
            return (Array(repeating: 0, count: expected),
                    Array(repeating: 0, count: FinanceMindWeights.classCount))
        }

        let weights = raw.prefix(expected).map {
            Float(Int16(littleEndian: $0)) / FinanceMindWeights.scale
        }
        let biases = raw.suffix(FinanceMindWeights.classCount).map {
            Float(Int16(littleEndian: $0)) / FinanceMindWeights.scale
        }
        return (weights, biases)
    }
}

// MARK: - Snapshot

struct FinanceSnapshot {
    var monthIncome: Decimal = 0
    var monthExpense: Decimal = 0
    var totalBalance: Decimal = 0
    var categories: [(name: String, amount: Decimal)] = []
    var budgetLimit: Decimal?
    var budgetSpent: Decimal?
    var goalName: String?
    var goalTarget: Decimal?
    var goalCurrent: Decimal?

    var monthNet: Decimal {
        monthIncome - monthExpense
    }

    var topCategory: (name: String, amount: Decimal)? {
        categories.max { $0.amount < $1.amount }
    }
}

// MARK: - Advice

struct FinanceAdvice {
    let title: String
    let body: String
    let tag: String
}

enum FinanceAdvisor {
    static func answer(to text: String, snapshot: FinanceSnapshot) -> FinanceAdvice {
        let prediction = FinanceMind.shared.predict(text)
        let intent = prediction?.intent ?? .other
        let tag = prediction.map { "\($0.intent.displayName) · \($0.percent)%" } ?? "财务"

        switch intent {
        case .recordExpense:
            return FinanceAdvice(
                title: "这像一笔支出",
                body: "回到 AI 记账，补上金额、分类和账户再保存。财务大脑只给建议，不会直接写账。",
                tag: tag
            )

        case .recordIncome:
            return FinanceAdvice(
                title: "这像一笔收入",
                body: "收入也要选对分类；工资、奖金、理财收益不要混在一起，否则结余率会失真。",
                tag: tag
            )

        case .spendingQuery:
            return spendingAnswer(text: text, snapshot: snapshot, tag: tag)

        case .balanceQuery:
            return FinanceAdvice(
                title: "本月结余",
                body: """
                本月收入 \(money(snapshot.monthIncome))，支出 \(money(snapshot.monthExpense))，结余 \(money(snapshot.monthNet))。
                账户总余额约 \(money(snapshot.totalBalance))。
                """,
                tag: tag
            )

        case .budgetStatus:
            return budgetAnswer(snapshot: snapshot, tag: tag)

        case .categoryQuestion:
            return categoryAnswer(text: text, tag: tag)

        case .savingAdvice:
            return savingAnswer(snapshot: snapshot, tag: tag)

        case .debtAdvice:
            return FinanceAdvice(
                title: "先处理高息负债",
                body: "把所有负债按年化利率从高到低列出来，优先还高息；分期要看总手续费，不只是每期金额。不要用新贷款还旧贷款。",
                tag: tag
            )

        case .investmentRisk:
            return FinanceAdvice(
                title: "只做风险提示",
                body: "我不能预测涨跌。先留 3–6 个月必要开支的应急金，再考虑投资；高收益一定伴随高风险，别把短期要用的钱拿去买波动大的资产。",
                tag: tag
            )

        case .emergencyFund:
            let low = snapshot.monthExpense * 3
            let high = snapshot.monthExpense * 6
            return FinanceAdvice(
                title: "应急金",
                body: "常见目标是 3–6 个月必要开支。按你本月支出估算，约 \(money(low))–\(money(high))；先放在随取、低风险的地方。",
                tag: tag
            )

        case .financialGoal:
            return goalAnswer(snapshot: snapshot, tag: tag)

        case .billReminder:
            return FinanceAdvice(
                title: "把固定账单拆出来",
                body: "房租、房贷、水电、会员这些固定支出，建议单独列一张账单清单，设置还款日提醒；预算里先扣掉固定项，再看可花多少。",
                tag: tag
            )

        case .subscription:
            return FinanceAdvice(
                title: "订阅要定期清理",
                body: "把连续包月、年卡和自动续费列出来，问自己过去 30 天有没有真的用过；不用的立刻取消，别让小额订阅吃掉结余。",
                tag: tag
            )

        case .impulseSpending:
            return FinanceAdvice(
                title: "先放 24 小时",
                body: "想买但不确定时，先加购物车放 24 小时；第二天还想要，再检查预算和同类物品是否已有。冲动消费最贵的不是单价，是重复购买。",
                tag: tag
            )

        case .refund:
            return FinanceAdvice(
                title: "退款要冲减支出",
                body: "退款不是新收入。记成退款类型，让它冲减原分类支出和预算；否则本月支出和结余都会虚高。",
                tag: tag
            )

        case .transfer:
            return FinanceAdvice(
                title: "账户互转不算收支",
                body: "银行卡、支付宝、微信之间的互转只是账户搬家，不计收入也不计支出；还信用卡按转账处理，避免重复计算。",
                tag: tag
            )

        case .splitBill:
            return FinanceAdvice(
                title: "分账要留下凭证",
                body: "先确认总金额、参与人数和谁垫付，再按人头或实际消费拆分；用模板生成分账记录，别只靠聊天记录。",
                tag: tag
            )

        case .insurance:
            return FinanceAdvice(
                title: "先保障，后理财",
                body: "先确认社保/医保，再考虑医疗险、意外险、重疾险；重点看免赔额、等待期、续保条件和免责条款，不要只看保费。",
                tag: tag
            )

        case .tax:
            return FinanceAdvice(
                title: "税务问题要谨慎",
                body: "这里只做记账提醒，不提供申报结论。个税、专项扣除和年终奖计税请以税务部门或专业顾问的口径为准。",
                tag: tag
            )

        case .other:
            return FinanceAdvice(
                title: "我只懂财务这一块",
                body: "可以问我支出、预算、储蓄、负债、退款、转账、保险和税务记账；太泛的问题我会承认不知道，不编答案。",
                tag: tag
            )
        }
    }

    private static func spendingAnswer(text: String, snapshot: FinanceSnapshot, tag: String) -> FinanceAdvice {
        if let domain = MoneyBrain.shared.predict(text)?.domain,
           domain != .other,
           let matched = snapshot.categories.first(where: { item in
               domain.categoryAliases.contains { alias in
                   item.name.contains(alias) || alias.contains(item.name)
               }
           }) {
            let share = percent(matched.amount, snapshot.monthExpense)
            return FinanceAdvice(
                title: "\(matched.name)支出",
                body: "本月 \(matched.name) 约 \(money(matched.amount))，占本月支出的 \(share)%。数据来自本机账本，不联网。",
                tag: tag
            )
        }

        if let top = snapshot.topCategory {
            return FinanceAdvice(
                title: "本月支出",
                body: "本月支出 \(money(snapshot.monthExpense))；最大类是 \(top.name)，约 \(money(top.amount))。完整明细在统计页。",
                tag: tag
            )
        }

        return FinanceAdvice(
            title: "还没有本月支出",
            body: "先记几笔，或者检查当前月份筛选；没有数据时我不会编一个数字。",
            tag: tag
        )
    }

    private static func budgetAnswer(snapshot: FinanceSnapshot, tag: String) -> FinanceAdvice {
        guard let limit = snapshot.budgetLimit, limit > 0 else {
            return FinanceAdvice(
                title: "还没有本月预算",
                body: "到预算页设置总预算或分类预算；设置后我可以按本机账本算剩余额度。",
                tag: tag
            )
        }

        let spent = snapshot.budgetSpent ?? snapshot.monthExpense
        let remaining = limit - spent
        let used = percent(spent, limit)
        return FinanceAdvice(
            title: remaining >= 0 ? "预算还剩 \(money(remaining))" : "已超预算 \(money(-remaining))",
            body: "本月预算 \(money(limit))，已用 \(money(spent))（\(used)%）。\(remaining >= 0 ? "后面每笔支出都会继续扣减。" : "先暂停非必要支出，或调整预算。")",
            tag: tag
        )
    }

    private static func categoryAnswer(text: String, tag: String) -> FinanceAdvice {
        if let domain = MoneyBrain.shared.predict(text)?.domain, domain != .other {
            return FinanceAdvice(
                title: "更像「\(domain.displayName)」",
                body: "本地分类器判断更像 \(domain.displayName)；保存前仍以你选的分类为准。分类器只给建议，不会覆盖明确规则。",
                tag: tag
            )
        }

        return FinanceAdvice(
            title: "分类拿不准",
            body: "先看这笔钱花在什么场景：吃、行、住、娱乐、医疗，还是工资/理财/转账/退款。拿不准就选“其他”，别为了好看硬塞。",
            tag: tag
        )
    }

    private static func savingAnswer(snapshot: FinanceSnapshot, tag: String) -> FinanceAdvice {
        guard snapshot.monthIncome > 0 else {
            return FinanceAdvice(
                title: "先记收入",
                body: "没有本月收入数据时，结余率算不出来。先记工资/兼职/理财收入，再看能存多少。",
                tag: tag
            )
        }

        let rate = percent(snapshot.monthNet, snapshot.monthIncome)
        return FinanceAdvice(
            title: "本月结余率 \(rate)%",
            body: "收入 \(money(snapshot.monthIncome))，支出 \(money(snapshot.monthExpense))，结余 \(money(snapshot.monthNet))。先设一个自动转存比例，再优化最大支出类；不要靠月底“剩下多少存多少”。",
            tag: tag
        )
    }

    private static func goalAnswer(snapshot: FinanceSnapshot, tag: String) -> FinanceAdvice {
        guard let name = snapshot.goalName, let target = snapshot.goalTarget, target > 0 else {
            return FinanceAdvice(
                title: "还没有目标",
                body: "到目标页建一个储蓄目标，填目标金额和截止日期；有目标后才能算每月要存多少。",
                tag: tag
            )
        }

        let current = snapshot.goalCurrent ?? 0
        let progress = percent(current, target)
        return FinanceAdvice(
            title: "\(name) · \(progress)%",
            body: "已存 \(money(current)) / \(money(target))，还差 \(money(target - current))。按剩余月份拆成每月固定转存，比月底临时补更稳。",
            tag: tag
        )
    }

    private static func money(_ value: Decimal) -> String {
        MoneyFormat.currency(value)
    }

    private static func percent(_ part: Decimal, _ total: Decimal) -> Int {
        guard total > 0 else {
            return 0
        }
        let value = NSDecimalNumber(decimal: part).doubleValue
            / NSDecimalNumber(decimal: total).doubleValue
        return Int((value * 100).rounded())
    }
}
