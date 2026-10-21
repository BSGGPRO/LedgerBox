import CoreData
import Foundation
import XCTest
@testable import LedgerBox

final class FinanceEngineTests: XCTestCase {
    private let accountID = UUID()
    private let otherAccountID = UUID()
    private let categoryID = UUID()
    private let otherCategoryID = UUID()
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    private var interval: DateInterval {
        DateInterval(start: baseDate.addingTimeInterval(-3_600), duration: 7_200)
    }

    private func transaction(
        _ type: TransactionType,
        amount: Decimal,
        categoryID: UUID? = nil,
        accountID: UUID? = nil,
        date: Date? = nil
    ) -> MockTransaction {
        MockTransaction(
            financeType: type,
            financeCategoryID: categoryID,
            financeAccountID: accountID ?? self.accountID,
            financeAmount: amount,
            financeDate: date ?? baseDate
        )
    }

    func testMoneyRoundingKeepsTwoFractionDigits() {
        XCTAssertEqual(
            Decimal(string: "15.5")!.roundedToCents(),
            Decimal(string: "15.5")!
        )
        XCTAssertEqual(
            Decimal(string: "15.555")!.roundedToCents(),
            Decimal(string: "15.56")!
        )
        XCTAssertEqual(
            Decimal(string: "15.554")!.roundedToCents(),
            Decimal(string: "15.55")!
        )
    }

    func testLedgerServicePreservesCentsOnRecordAndDelete() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let account = try XCTUnwrap(
            try context.fetch(Account.fetchRequest()).first
        )
        let category = try XCTUnwrap(
            try context.fetch(Category.fetchRequest()).first {
                $0.isSelectable && $0.categoryKind == .expense
            }
        )
        let amount = Decimal(string: "1234.56")!

        let transaction = try LedgerService.record(
            type: .expense,
            amount: amount,
            date: Date(),
            note: nil,
            account: account,
            category: category,
            in: context
        )

        XCTAssertEqual(transaction.amountValue, amount)
        XCTAssertEqual(account.balanceValue, Decimal(string: "-1234.56")!)

        try LedgerService.delete(transaction, in: context)
        XCTAssertEqual(account.balanceValue, 0)
    }

    func testSummaryExcludesTransfersAndOffsetsRefunds() {
        let items = [
            transaction(.income, amount: Decimal(500)),
            transaction(.expense, amount: Decimal(100), categoryID: categoryID),
            transaction(.refund, amount: Decimal(20), categoryID: categoryID),
            transaction(.transfer, amount: Decimal(50), accountID: otherAccountID)
        ]

        let summary = FinanceEngine.summary(transactions: items, in: interval)

        XCTAssertEqual(summary.income, Decimal(500))
        XCTAssertEqual(summary.expense, Decimal(80))
        XCTAssertEqual(summary.net, Decimal(420))
    }

    func testSummaryCanFilterByAccount() {
        let items = [
            transaction(.income, amount: Decimal(500)),
            transaction(.income, amount: Decimal(300), accountID: otherAccountID),
            transaction(.expense, amount: Decimal(100), accountID: otherAccountID)
        ]

        let summary = FinanceEngine.summary(
            transactions: items,
            in: interval,
            accountID: accountID
        )

        XCTAssertEqual(summary.income, Decimal(500))
        XCTAssertEqual(summary.expense, Decimal.zero)
        XCTAssertEqual(summary.net, Decimal(500))
    }

    func testSpendingOffsetsRefundsAndFiltersCategory() {
        let items = [
            transaction(.expense, amount: Decimal(100), categoryID: categoryID),
            transaction(.refund, amount: Decimal(20), categoryID: categoryID),
            transaction(.expense, amount: Decimal(30), categoryID: otherCategoryID),
            transaction(.income, amount: Decimal(999), categoryID: categoryID)
        ]

        let categorySpend = FinanceEngine.spending(
            categoryID: categoryID,
            transactions: items,
            in: interval
        )
        let allSpend = FinanceEngine.spending(
            categoryID: nil,
            transactions: items,
            in: interval
        )

        XCTAssertEqual(categorySpend, Decimal(80))
        XCTAssertEqual(allSpend, Decimal(110))
    }

    func testBudgetProgressClampsRatioAndDetectsOverBudget() {
        let normal = FinanceEngine.budgetProgress(
            limit: Decimal(2_000),
            spent: Decimal(500)
        )
        XCTAssertEqual(normal.remaining, Decimal(1_500))
        XCTAssertEqual(normal.ratio, 0.25, accuracy: 0.0001)
        XCTAssertFalse(normal.isOverBudget)

        let over = FinanceEngine.budgetProgress(
            limit: Decimal(2_000),
            spent: Decimal(2_100)
        )
        XCTAssertEqual(over.remaining, Decimal(-100))
        XCTAssertEqual(over.ratio, 1.0, accuracy: 0.0001)
        XCTAssertTrue(over.isOverBudget)

        let zero = FinanceEngine.budgetProgress(
            limit: Decimal.zero,
            spent: Decimal(10)
        )
        XCTAssertEqual(zero.ratio, 1.0, accuracy: 0.0001)
        XCTAssertTrue(zero.isOverBudget)
    }

    func testSideHustleSplitClampsBelowSeventyPercent() {
        let rules = BuyCarTemplateRules()
        let split = rules.splitSideHustle(
            Decimal(1_000),
            requestedRatio: Decimal(5) / Decimal(10)
        )

        XCTAssertEqual(split.goal, Decimal(700))
        XCTAssertEqual(split.reserve, Decimal(300))
    }

    func testSideHustleSplitAtFullRatioSendsEverythingToGoal() {
        let rules = BuyCarTemplateRules()
        let split = rules.splitSideHustle(
            Decimal(1_000),
            requestedRatio: Decimal(1)
        )

        XCTAssertEqual(split.goal, Decimal(1_000))
        XCTAssertEqual(split.reserve, Decimal.zero)
    }

    func testCoachWarnsBeforeBudgetIsExhausted() {
        let tip = FinanceCoach.dailyTip(
            context: FinanceCoachContext(
                monthIncome: Decimal(5_000),
                monthExpense: Decimal(900),
                budgetLimit: Decimal(1_000),
                budgetSpent: Decimal(900),
                transactionCount: 8
            )
        )

        XCTAssertEqual(tip.tag, "预算")
        XCTAssertTrue(tip.body.contains("只剩"))
    }

    func testCoachFlagsExpenseAboveIncome() {
        let tip = FinanceCoach.dailyTip(
            context: FinanceCoachContext(
                monthIncome: Decimal(3_000),
                monthExpense: Decimal(3_500),
                transactionCount: 5
            )
        )

        XCTAssertEqual(tip.tag, "现金流")
        XCTAssertTrue(tip.body.contains("支出比收入多"))
    }

    func testCoachMentionsActiveGoal() {
        let tip = FinanceCoach.dailyTip(
            context: FinanceCoachContext(
                monthIncome: Decimal(8_000),
                monthExpense: Decimal(3_000),
                goalName: "旅行基金",
                goalTarget: Decimal(10_000),
                goalCurrent: Decimal(2_000),
                transactionCount: 12
            )
        )

        XCTAssertEqual(tip.tag, "目标")
        XCTAssertTrue(tip.body.contains("旅行基金"))
    }

    func testCoachStartsWithFirstEntryWhenLedgerIsEmpty() {
        let tip = FinanceCoach.dailyTip(
            context: FinanceCoachContext(
                monthIncome: .zero,
                monthExpense: .zero,
                transactionCount: 0
            )
        )

        XCTAssertEqual(tip.tag, "开始")
    }

    func testSurplusAllocationPrioritizesRepairThenCarThenOverflow() {
        let rules = BuyCarTemplateRules()

        let insideCar = rules.allocateSurplus(
            Decimal(1_000),
            repairCurrent: Decimal(4_000),
            carCurrent: Decimal(24_000)
        )
        XCTAssertEqual(insideCar.repair, Decimal(400))
        XCTAssertEqual(insideCar.car, Decimal(600))
        XCTAssertEqual(insideCar.overflow, Decimal.zero)

        let overflow = rules.allocateSurplus(
            Decimal(1_000),
            repairCurrent: Decimal(4_400),
            carCurrent: Decimal(25_000)
        )
        XCTAssertEqual(overflow.repair, Decimal.zero)
        XCTAssertEqual(overflow.car, Decimal.zero)
        XCTAssertEqual(overflow.overflow, Decimal(1_000))
    }
}

private struct MockTransaction: TransactionProviding {
    let financeType: TransactionType
    let financeCategoryID: UUID?
    let financeAccountID: UUID
    let financeAmount: Decimal
    let financeDate: Date
}
