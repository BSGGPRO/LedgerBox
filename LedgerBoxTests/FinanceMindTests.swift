import XCTest
@testable import LedgerBox

final class FinanceMindTests: XCTestCase {
    func testModelLoadsAtFullCapacity() {
        XCTAssertTrue(FinanceMind.shared.isReady)
        XCTAssertEqual(FinanceMind.parameterCount, 41_943_080)
        XCTAssertEqual(FinanceMind.modelByteCount, 41_943_200)
        XCTAssertEqual(FinanceMindWeights.labels.count, 40)
        XCTAssertEqual(FinanceMindWeights.bucketCount, 1_048_576)
    }

    func testCashflowProbe() {
        let probe = FinanceMind.shared.probe("这个月现金流怎么样？")
        XCTAssertEqual(probe?.predictions.first?.intent, .cashflow)
        XCTAssertEqual(probe?.predictions.count, 8)
        XCTAssertGreaterThan(probe?.featureCount ?? 0, 0)
        XCTAssertGreaterThanOrEqual(probe?.predictions.first?.confidence ?? 0, 0.5)
    }

    func testReimbursementDoesNotCollapseIntoMedical() {
        let probe = FinanceMind.shared.probe("报销怎么记")
        XCTAssertEqual(probe?.predictions.first?.intent, .reimbursement)
    }

    func testAccountingIntentsAreReachable() {
        let cases: [(String, FinanceIntent)] = [
            ("固定资产折旧怎么算", .depreciation),
            ("权责发生制和收付实现制区别", .accrual),
            ("客户欠款怎么催", .accountsReceivable),
            ("增值税进项税", .vat),
            ("房贷月供怎么记", .mortgage),
            ("发票怎么开", .invoice)
        ]

        for (text, intent) in cases {
            XCTAssertEqual(
                FinanceMind.shared.probe(text)?.predictions.first?.intent,
                intent,
                "failed to route: \(text)"
            )
        }
    }

    func testNonFinanceTextStaysOther() {
        XCTAssertEqual(FinanceMind.shared.predict("今天天气怎么样")?.intent, .other)
    }

    func testEmptyInputDoesNotCrash() {
        XCTAssertNil(FinanceMind.shared.probe(""))
        XCTAssertNil(FinanceMind.shared.probe("   "))
    }

    private var computeSnapshot: FinanceSnapshot {
        FinanceSnapshot(
            monthIncome: 8_000,
            monthExpense: 3_200,
            totalBalance: 12_000,
            categories: [
                (name: "餐饮", amount: 1_000),
                (name: "交通", amount: 500)
            ],
            budgetLimit: 5_000,
            budgetSpent: 3_200,
            goalName: "旅行",
            goalTarget: 10_000,
            goalCurrent: 2_500
        )
    }

    func testAIModelRoutesSpendingToDecimalEngine() {
        let calculation = FinanceComputeRouter.route(
            "这个月花了多少",
            snapshot: computeSnapshot
        )
        XCTAssertEqual(calculation?.kind, .spendingTotal)
        XCTAssertEqual(calculation?.value, Decimal(string: "3200"))
        XCTAssertTrue(calculation?.routedByModel ?? false)
        XCTAssertTrue(calculation?.formula.contains("3,200.00") ?? false)
    }

    func testAIModelRoutesBalanceSeparatelyFromMonthlyNet() {
        let calculation = FinanceComputeRouter.route(
            "账户余额还有多少",
            snapshot: computeSnapshot
        )
        XCTAssertEqual(calculation?.kind, .accountBalance)
        XCTAssertEqual(calculation?.value, Decimal(string: "12000"))
        XCTAssertEqual(calculation?.secondaryValue, Decimal(string: "4800"))
    }

    func testAIModelRoutesBudgetAndKeepsExactRemainder() {
        let calculation = FinanceComputeRouter.route(
            "预算还剩多少",
            snapshot: computeSnapshot
        )
        XCTAssertEqual(calculation?.kind, .budgetRemaining)
        XCTAssertEqual(calculation?.value, Decimal(string: "1800"))
        XCTAssertEqual(calculation?.secondaryValue, Decimal(string: "64"))
    }

    func testCategoryShareIsComputedWithDecimal() {
        let calculation = FinanceComputeRouter.route(
            "餐饮花了多少",
            snapshot: computeSnapshot
        )
        XCTAssertEqual(calculation?.kind, .categoryShare)
        XCTAssertEqual(calculation?.value, Decimal(string: "1000"))
        XCTAssertEqual(calculation?.secondaryValue, Decimal(string: "31.3"))
        XCTAssertTrue(calculation?.formula.contains("31.3%") ?? false)
    }

    func testNonCalculationTextDoesNotInventANumber() {
        let calculation = FinanceComputeRouter.route(
            "今天天气怎么样",
            snapshot: computeSnapshot
        )
        XCTAssertNil(calculation)
    }
}
