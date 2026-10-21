import Foundation

/// A tiny local classifier for money-ish Chinese text.
///
/// It is a hashed character n-gram multinomial logistic-regression model with
/// `5,643` weights. It is not an LLM and does not generate text. The parser
/// remains the source of truth; this model only ranks suggestions and adds a
/// low-confidence hint when the rules cannot decide.
enum MoneyDomain: String, CaseIterable {
    case food
    case transport
    case shopping
    case housing
    case entertainment
    case health
    case salary
    case investment
    case transfer
    case refund
    case other

    var displayName: String {
        switch self {
        case .food: return "餐饮"
        case .transport: return "交通"
        case .shopping: return "购物"
        case .housing: return "住房"
        case .entertainment: return "娱乐"
        case .health: return "医疗"
        case .salary: return "工资"
        case .investment: return "理财"
        case .transfer: return "转账"
        case .refund: return "退款"
        case .other: return "其他"
        }
    }

    var transactionType: TransactionType? {
        switch self {
        case .food, .transport, .shopping, .housing, .entertainment, .health:
            return .expense
        case .salary, .investment:
            return .income
        case .transfer:
            return .transfer
        case .refund:
            return .refund
        case .other:
            return nil
        }
    }

    var categoryAliases: [String] {
        switch self {
        case .food:
            return ["餐饮", "吃饭", "食品", "零食", "咖啡", "奶茶"]
        case .transport:
            return ["交通", "出行", "打车", "地铁", "加油"]
        case .shopping:
            return ["购物", "日用", "服饰", "数码"]
        case .housing:
            return ["住房", "房租", "水电", "物业"]
        case .entertainment:
            return ["娱乐", "电影", "游戏", "会员"]
        case .health:
            return ["医疗", "健康", "药"]
        case .salary:
            return ["工资", "薪水", "奖金"]
        case .investment:
            return ["理财", "投资", "基金", "股票", "利息"]
        case .transfer:
            return ["转账", "还款", "信用卡"]
        case .refund:
            return ["退款", "退货"]
        case .other:
            return []
        }
    }
}

struct MoneyBrainPrediction {
    let domain: MoneyDomain
    let confidence: Float

    var type: TransactionType? {
        domain.transactionType
    }

    var percent: Int {
        Int((confidence * 100).rounded())
    }
}

enum MoneyBrain {
    static let shared = MoneyBrain()
    static let parameterCount = MoneyBrainWeights.bucketCount
        * MoneyBrainWeights.classCount
        + MoneyBrainWeights.classCount

    private let weights: [Float]
    private let biases: [Float]

    private init() {
        let decoded = Self.decodeWeights()
        weights = decoded.weights
        biases = decoded.biases
    }

    /// Returns nil when the model is not confident enough; callers must never
    /// treat this as an authoritative parse.
    func predict(_ text: String) -> MoneyBrainPrediction? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 2 else {
            return nil
        }

        let features = Self.featureBuckets(normalized)
        guard !features.isEmpty else {
            return nil
        }

        var scores = [Float](repeating: 0, count: MoneyBrainWeights.classCount)
        for classIndex in 0..<MoneyBrainWeights.classCount {
            var score = biases[classIndex]
            let base = classIndex * MoneyBrainWeights.bucketCount
            for (bucket, value) in features {
                score += weights[base + bucket] * value
            }
            scores[classIndex] = score
        }

        guard let maxScore = scores.max() else {
            return nil
        }

        var exponentials = scores.map { exp($0 - maxScore) }
        let total = exponentials.reduce(0, +)
        guard total > 0 else {
            return nil
        }
        for index in exponentials.indices {
            exponentials[index] /= total
        }

        guard
            let best = exponentials.indices.max(by: { exponentials[$0] < exponentials[$1] }),
            best < MoneyBrainWeights.labels.count,
            let domain = MoneyDomain(rawValue: MoneyBrainWeights.labels[best])
        else {
            return nil
        }

        let confidence = exponentials[best]
        guard confidence >= 0.42 else {
            return nil
        }

        return MoneyBrainPrediction(domain: domain, confidence: confidence)
    }

    // MARK: - Features

    private static func featureBuckets(_ text: String) -> [Int: Float] {
        let characters = text.lowercased().filter { character in
            !character.isNumber
                && !character.isWhitespace
                && !character.isPunctuation
        }
        let chars = Array(characters)
        guard !chars.isEmpty else {
            return [:]
        }

        var features: [Int: Float] = [:]
        for character in chars {
            add(String(character), to: &features)
        }

        guard chars.count >= 2 else {
            return features
        }

        for index in 0..<(chars.count - 1) {
            add("\(chars[index])\(chars[index + 1])", to: &features)
        }
        return features
    }

    private static func add(_ token: String, to features: inout [Int: Float]) {
        let bucket = Int(fnv1a(token) % UInt32(MoneyBrainWeights.bucketCount))
        features[bucket, default: 0] += 1
    }

    private static func fnv1a(_ text: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in text.utf8 {
            hash ^= UInt32(byte)
            hash &*= 16_777_619
        }
        return hash
    }

    // MARK: - Weights

    private static func decodeWeights() -> (weights: [Float], biases: [Float]) {
        let encoded = MoneyBrainWeights.encoded.replacingOccurrences(of: "\n", with: "")
        guard let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters) else {
            assertionFailure("MoneyBrain weights are not valid base64")
            return (
                [Float](repeating: 0, count: parameterCount),
                [Float](repeating: 0, count: MoneyBrainWeights.classCount)
            )
        }

        let weightCount = MoneyBrainWeights.bucketCount * MoneyBrainWeights.classCount
        let totalCount = weightCount + MoneyBrainWeights.classCount
        var quantized = [Int16](repeating: 0, count: totalCount)

        data.withUnsafeBytes { raw in
            for index in 0..<totalCount {
                let low = UInt16(raw[index * 2])
                let high = UInt16(raw[index * 2 + 1]) << 8
                quantized[index] = Int16(bitPattern: low | high)
            }
        }

        let scale = MoneyBrainWeights.scale
        let weights = quantized[0..<weightCount].map { Float($0) / scale }
        let biases = quantized[weightCount..<totalCount].map { Float($0) / scale }
        return (weights, biases)
    }
}
