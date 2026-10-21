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
    case cashflow = "cashflow"
    case reconciliation = "reconciliation"
    case invoice = "invoice"
    case reimbursement = "reimbursement"
    case payroll = "payroll"
    case inventory = "inventory"
    case depreciation = "depreciation"
    case amortization = "amortization"
    case vat = "vat"
    case accrual = "accrual"
    case pettyCash = "petty_cash"
    case accountsReceivable = "accounts_receivable"
    case accountsPayable = "accounts_payable"
    case loan = "loan"
    case mortgage = "mortgage"
    case rent = "rent"
    case utilities = "utilities"
    case medical = "medical"
    case education = "education"
    case charity = "charity"
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
        case .cashflow: return "现金流"
        case .reconciliation: return "对账"
        case .invoice: return "发票"
        case .reimbursement: return "报销"
        case .payroll: return "工资核算"
        case .inventory: return "存货"
        case .depreciation: return "折旧"
        case .amortization: return "摊销"
        case .vat: return "增值税"
        case .accrual: return "权责发生"
        case .pettyCash: return "备用金"
        case .accountsReceivable: return "应收账款"
        case .accountsPayable: return "应付账款"
        case .loan: return "借款"
        case .mortgage: return "房贷"
        case .rent: return "房租"
        case .utilities: return "水电"
        case .medical: return "医疗"
        case .education: return "教育"
        case .charity: return "公益"
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
/// 40 intents x 262,144 buckets + 40 biases = 10,485,800 parameters. The
/// weights are Int8 in FinanceMindWeights.bin (about 10 MB), loaded locally.
/// It routes text to deterministic advice templates; it is not a compressed
/// Qwen checkpoint and it does not generate free-form answers.
final class FinanceMind {
    static let shared = FinanceMind()

    static let parameterCount = FinanceMindWeights.parameterCount
    static let weightByteCount = FinanceMindWeights.weightByteCount
    static let modelByteCount =
        FinanceMindWeights.weightByteCount + FinanceMindWeights.biasByteCount

    private let weightData: Data
    private let biases: [Float]
    private(set) var isReady: Bool

    private init() {
        var loadedData: Data?
        for bundle in [Bundle.main, Bundle(for: FinanceMind.self)] {
            guard let url = bundle.url(
                forResource: "FinanceMindWeights",
                withExtension: "bin"
            ) else {
                continue
            }
            loadedData = try? Data(contentsOf: url, options: .mappedIfSafe)
            if loadedData != nil {
                break
            }
        }

        var decodedBiases = [Float](
            repeating: 0,
            count: FinanceMindWeights.classCount
        )
        var ready = false

        if let data = loadedData,
           data.count == Self.modelByteCount {
            _ = decodedBiases.withUnsafeMutableBytes { buffer in
                data.copyBytes(
                    to: buffer,
                    from: 0..<FinanceMindWeights.biasByteCount
                )
            }
            ready = true
            weightData = data
        } else {
            weightData = Data()
        }

        biases = decodedBiases
        isReady = ready
    }

    /// Full ranked probe for the visual brain page.
    func probe(_ text: String, limit: Int = 8) -> FinanceBrainProbe? {
        guard isReady else {
            return nil
        }

        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 2 else {
            return nil
        }

        let features = Self.featureBuckets(normalized)
        guard !features.isEmpty else {
            return nil
        }

        let classCount = FinanceMindWeights.classCount
        let bucketCount = FinanceMindWeights.bucketCount
        var scores = biases
        let started = CFAbsoluteTimeGetCurrent()

        weightData.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: Int8.self).baseAddress else {
                return
            }
            let weights = base.advanced(by: FinanceMindWeights.biasByteCount)
            for (bucket, value) in features {
                for classIndex in 0..<classCount {
                    let raw = weights[classIndex * bucketCount + bucket]
                    scores[classIndex] += Float(raw) / FinanceMindWeights.scale * value
                }
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

        let ranked = scores.enumerated()
            .sorted { $0.element > $1.element }
            .prefix(limit)
            .compactMap { index, value -> FinanceIntentPrediction? in
                let label = FinanceMindWeights.labels[index]
                guard let intent = FinanceIntent(rawValue: label) else {
                    return nil
                }
                return FinanceIntentPrediction(
                    intent: intent,
                    confidence: value / sum
                )
            }

        guard !ranked.isEmpty else {
            return nil
        }

        return FinanceBrainProbe(
            predictions: Array(ranked),
            latencyMilliseconds: (CFAbsoluteTimeGetCurrent() - started) * 1000,
            featureCount: features.count,
            bucketCount: bucketCount,
            parameterCount: Self.parameterCount
        )
    }

    func predict(_ text: String) -> FinanceIntentPrediction? {
        guard let first = probe(text, limit: 1)?.predictions.first,
              first.confidence >= 0.30 else {
            return nil
        }
        return first
    }

    private static func featureBuckets(_ text: String) -> [Int: Float] {
        let blocked = Set("，。！？、,.!?：:；;（）()【】[]《》“”\"'")
        let chars = text.lowercased().filter {
            !$0.isNumber && !$0.isWhitespace && !blocked.contains($0)
        }
        guard !chars.isEmpty else {
            return [:]
        }

        var buckets: [Int: Float] = [:]
        let array = Array(chars)
        for char in array {
            let index = Int(fnv1a("u:\(char)") % UInt32(FinanceMindWeights.bucketCount))
            buckets[index, default: 0] += 1
        }

        for index in 0..<(array.count - 1) {
            let key = "b:\(array[index])\(array[index + 1])"
            let bucket = Int(fnv1a(key) % UInt32(FinanceMindWeights.bucketCount))
            buckets[bucket, default: 0] += 1
        }

        if array.count >= 3 {
            for index in 0..<(array.count - 2) {
                let key = "t:\(array[index])\(array[index + 1])\(array[index + 2])"
                let bucket = Int(fnv1a(key) % UInt32(FinanceMindWeights.bucketCount))
                buckets[bucket, default: 0] += 1
            }
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
}

struct FinanceBrainProbe {
    let predictions: [FinanceIntentPrediction]
    let latencyMilliseconds: Double
    let featureCount: Int
    let bucketCount: Int
    let parameterCount: Int
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

        case .cashflow:
            return FinanceAdvice(
                title: "现金流看进出节奏",
                body: "把经营、投资、筹资现金流分开看：利润为正但现金流为负，可能是应收账款或存货占款。先保证下月必要支出有现金覆盖。",
                tag: tag
            )

        case .reconciliation:
            return FinanceAdvice(
                title: "对账先找差异",
                body: "用银行/支付平台流水和账本逐笔核对，先标出未达账项，再做余额调节表；不要直接用“调平”分录把差异藏掉。",
                tag: tag
            )

        case .invoice:
            return FinanceAdvice(
                title: "发票要三流一致",
                body: "合同、发票、资金流水尽量对应；普票和专票的抵扣规则不同，进项票要及时认证，退票/红冲要留痕。",
                tag: tag
            )

        case .reimbursement:
            return FinanceAdvice(
                title: "报销不是收入",
                body: "员工垫付后报销，本质是归垫：报销到账冲减原费用或挂其他应收，不要记成工资/收入，否则会虚增收入。",
                tag: tag
            )

        case .payroll:
            return FinanceAdvice(
                title: "工资要拆应发与实发",
                body: "应发工资包含基本工资、绩效、补贴；代扣个税、社保、公积金后才是实发。计提和发放分两个步骤，别只记银行付款。",
                tag: tag
            )

        case .inventory:
            return FinanceAdvice(
                title: "存货要管数量和成本",
                body: "入库、出库、结转成本要同步；先进先出/加权平均是核算方法，不是随便估价。期末盘点差异要查明原因再调整。",
                tag: tag
            )

        case .depreciation:
            return FinanceAdvice(
                title: "折旧是分摊不是付现",
                body: "固定资产按预计使用年限系统分摊，残值和折旧方法要一致；折旧不产生现金流出，但会影响利润和税。",
                tag: tag
            )

        case .amortization:
            return FinanceAdvice(
                title: "摊销看受益期",
                body: "长期待摊费用、无形资产按受益期限分摊；摊销年限要有依据，不能为了调利润随意拉长或缩短。",
                tag: tag
            )

        case .vat:
            return FinanceAdvice(
                title: "增值税要价税分离",
                body: "含税价先拆成不含税金额和税额；进项税能否抵扣取决于用途和凭证。小规模/一般纳税人规则不同，申报以税务口径为准。",
                tag: tag
            )

        case .accrual:
            return FinanceAdvice(
                title: "权责发生制看归属期",
                body: "费用/收入按实际发生期间确认，不看钱哪天到账；跨期部分用应付、预提、待摊处理，避免某个月利润大起大落。",
                tag: tag
            )

        case .pettyCash:
            return FinanceAdvice(
                title: "备用金要定额管理",
                body: "定额备用金先借出、报销后补足；现金盘点差异要查明原因，不能长期挂账。小额支出也要留凭证。",
                tag: tag
            )

        case .accountsReceivable:
            return FinanceAdvice(
                title: "应收账款要盯回款",
                body: "赊销确认收入同时挂应收；按账龄催收，评估坏账风险。收到钱时冲应收，不要重复记收入。",
                tag: tag
            )

        case .accountsPayable:
            return FinanceAdvice(
                title: "应付账款要排付款计划",
                body: "采购入库/收票后挂应付，付款时冲应付；先按到期日排优先级，别用短期借款硬撑长期欠款。",
                tag: tag
            )

        case .loan:
            return FinanceAdvice(
                title: "借款要拆本金和利息",
                body: "收到借款记负债，不是收入；还款时本金冲负债、利息记费用。等额本息前期利息高，提前还款要先看违约金。",
                tag: tag
            )

        case .mortgage:
            return FinanceAdvice(
                title: "房贷看总成本",
                body: "月供之外还要算首付、税费、保险和维修；提前还款是否划算，要比较剩余利息和手里的应急金，别把现金全压进去。",
                tag: tag
            )

        case .rent:
            return FinanceAdvice(
                title: "房租要区分押金和租金",
                body: "押金是资产，不是当月费用；租金按租期分摊。合租/转租要留合同和分摊规则，押金退还要冲回。",
                tag: tag
            )

        case .utilities:
            return FinanceAdvice(
                title: "水电燃气按实际用量",
                body: "自用记生活支出，公司/出租房要区分成本或代收代付；合租按账单或约定分摊，预存费用先挂预付。",
                tag: tag
            )

        case .medical:
            return FinanceAdvice(
                title: "医疗支出留好票据",
                body: "挂号、药费、住院分别归类；医保报销和商保理赔到账后冲减原支出，不要重复记收入。大额支出先看应急金。",
                tag: tag
            )

        case .education:
            return FinanceAdvice(
                title: "教育支出看受益期",
                body: "短期课程记当期费用，长期培训/学历教育按受益期分摊；书本、住宿、交通可以单列，方便做教育金预算。",
                tag: tag
            )

        case .charity:
            return FinanceAdvice(
                title: "捐赠要留合规凭证",
                body: "公益捐赠记支出并保留捐赠票据；税前扣除有比例和资格限制，具体以税务规定为准。捐物按公允价值留证。",
                tag: tag
            )

        case .other:
            return FinanceAdvice(
                title: "我只懂财务这一块",
                body: "可以问我支出、预算、储蓄、负债、退款、转账、保险、税务、发票、报销、存货、折旧、现金流等记账问题；太泛的问题我会承认不知道，不编答案。",
                tag: tag
            )
        }
    }

    private static func spendingAnswer(text: String, snapshot: FinanceSnapshot, tag: String) -> FinanceAdvice {
        if let domain = MoneyBrain.shared.predict(text)?.domain,
           domain != .other,
           domain.categoryAliases.contains(where: { text.contains($0) }),
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
