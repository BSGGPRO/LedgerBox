import XCTest
@testable import LedgerBox

final class FinanceMindTests: XCTestCase {
    func testModelLoadsAtFullCapacity() {
        XCTAssertTrue(FinanceMind.shared.isReady)
        XCTAssertEqual(FinanceMind.parameterCount, 20_971_560)
        XCTAssertEqual(FinanceMind.modelByteCount, 20_971_680)
        XCTAssertEqual(FinanceMindWeights.labels.count, 40)
        XCTAssertEqual(FinanceMindWeights.bucketCount, 524_288)
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
}
