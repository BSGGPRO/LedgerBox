import Foundation

/// The small, stable category set exposed by image import. Raw values are the
/// Chinese names used by the seeded `Category` rows.
enum LedgerCategory: String, Codable, CaseIterable, Identifiable, Equatable, Hashable {
    case food = "餐饮"
    case transport = "交通"
    case shopping = "购物"
    case housing = "房租"
    case entertainment = "娱乐"
    case medical = "医疗"
    case education = "教育"
    case salary = "工资"
    case transfer = "转账"
    case other = "其他"

    var id: String { rawValue }

    var displayName: String { rawValue }
}

struct CategoryResult: Equatable {
    let category: LedgerCategory
    let confidence: Double
    let needsReview: Bool
    let usedLexicon: Bool
    let modelIntent: String?
}

/// Fuses the local FinanceMind intent probe with the deterministic merchant
/// lexicon. The model only nudges the category; amount/date/order fields are
/// never taken from it. If the model weights are missing, the lexicon alone is
/// enough and no error is raised.
final class LedgerCategoryClassifier {

    static let shared = LedgerCategoryClassifier()

    private let lexicon: MerchantLexicon
    private let probe: (String, Int) -> FinanceBrainProbe?

    init(
        lexicon: MerchantLexicon = .shared,
        probe: @escaping (String, Int) -> FinanceBrainProbe? = { text, limit in
            FinanceMind.shared.probe(text, limit: limit)
        }
    ) {
        self.lexicon = lexicon
        self.probe = probe
    }

    func classify(_ text: String, fields: ReceiptFields) -> CategoryResult {
        let probeResult = probe(text, 40)
        let top = probeResult?.predictions.first
        let second = probeResult?.predictions.dropFirst().first

        let modelIntent = top?.intent
        let modelCategory = modelIntent.map { Self.category(for: $0) } ?? .other
        let modelConfidence = top.map { Double($0.confidence) } ?? 0
        let modelMargin: Double
        if let top, let second {
            modelMargin = Double(top.confidence - second.confidence)
        } else {
            modelMargin = Double(top?.confidence ?? 0)
        }
        let modelIsUsable = modelCategory != .other && modelConfidence >= 0.35

        let haystack = [
            text,
            fields.merchantText ?? "",
            fields.normalizedText
        ].joined(separator: " ")
        let lexiconMatch = lexicon.match(haystack)

        var category: LedgerCategory
        var confidence: Double
        var needsReview = false

        if let lexiconMatch {
            if modelIsUsable && modelCategory == lexiconMatch.category {
                category = lexiconMatch.category
                confidence = Swift.min(
                    1.0,
                    Swift.max(lexiconMatch.score, modelConfidence) + 0.06
                )
                needsReview = confidence < 0.75
            } else if modelIsUsable && modelCategory != lexiconMatch.category {
                if lexiconMatch.score >= 0.85 {
                    // A very specific merchant name outranks a generic intent.
                    category = lexiconMatch.category
                    confidence = lexiconMatch.score * 0.92
                    needsReview = true
                } else if modelMargin >= 0.12 && modelConfidence >= 0.55 {
                    category = modelCategory
                    confidence = modelConfidence
                    needsReview = true
                } else {
                    category = .other
                    confidence = Swift.min(
                        0.49,
                        Swift.max(lexiconMatch.score, modelConfidence)
                    )
                    needsReview = true
                }
            } else {
                category = lexiconMatch.category
                confidence = lexiconMatch.score
                needsReview = lexiconMatch.score < 0.72
            }
        } else if modelIsUsable && modelMargin >= 0.12 && modelConfidence >= 0.55 {
            category = modelCategory
            confidence = modelConfidence
        } else {
            // No merchant signal and a weak/ambiguous model margin: "其他"
            // is safer than a confident-looking wrong category.
            category = .other
            confidence = modelIsUsable ? Swift.min(modelConfidence, 0.49) : 0
            needsReview = true
        }

        if confidence < 0.55 {
            category = .other
            needsReview = true
        }

        let usedLexicon = lexiconMatch.map { $0.category == category } ?? false

        return CategoryResult(
            category: category,
            confidence: confidence,
            needsReview: needsReview,
            usedLexicon: usedLexicon,
            modelIntent: modelIntent?.rawValue
        )
    }

    /// Requirement mapping. Every intent not listed here deliberately falls
    /// back to `.other` rather than inventing a category.
    private static func category(for intent: FinanceIntent) -> LedgerCategory {
        switch intent {
        case .rent, .mortgage, .utilities:
            return .housing
        case .medical:
            return .medical
        case .education:
            return .education
        case .payroll:
            return .salary
        case .transfer, .splitBill:
            return .transfer
        case .subscription, .impulseSpending:
            return .shopping
        default:
            return .other
        }
    }
}
