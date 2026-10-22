import Foundation
import XCTest
@testable import LedgerBox

final class QuickEntryParserTests: XCTestCase {
    private let parser = QuickEntryParser()

    private let dining = QuickEntryParser.CategoryOption(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        name: "餐饮",
        kind: .expense
    )
    private let transport = QuickEntryParser.CategoryOption(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        name: "交通",
        kind: .expense
    )
    private let shopping = QuickEntryParser.CategoryOption(
        id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
        name: "购物",
        kind: .expense
    )
    private let salary = QuickEntryParser.CategoryOption(
        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        name: "工资",
        kind: .income
    )
    private let wechat = QuickEntryParser.AccountOption(
        id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
        name: "微信"
    )
    private let bank = QuickEntryParser.AccountOption(
        id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
        name: "银行卡"
    )

    func testParsesExpenseWithAmountAliasAndAccount() {
        let result = parser.parse(
            "微信买奶茶 15.5 元",
            categories: [dining, salary],
            accounts: [wechat, bank]
        )

        XCTAssertEqual(result.amount, Decimal(string: "15.5"))
        XCTAssertTrue(result.type == TransactionType.expense)
        XCTAssertEqual(result.typeSource, .keyword)
        XCTAssertTrue(result.category?.id == dining.id)
        XCTAssertTrue(result.account?.id == wechat.id)
        XCTAssertEqual(result.remark, "奶茶")
        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertTrue(result.isReadyToSave)
    }

    func testInfersExpenseFromUniquelyMatchedCategory() {
        let result = parser.parse(
            "微信餐饮 30",
            categories: [dining],
            accounts: [wechat]
        )

        XCTAssertEqual(result.amount, Decimal(string: "30"))
        XCTAssertTrue(result.type == TransactionType.expense)
        XCTAssertEqual(result.typeSource, .category)
        XCTAssertTrue(result.category?.id == dining.id)
        XCTAssertTrue(result.account?.id == wechat.id)
        XCTAssertEqual(result.remark, "极速记账")
        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertTrue(result.isReadyToSave)
    }

    func testMealAliasMatchesDiningAndKeepsRemark() {
        let result = parser.parse(
            "吃饭 30",
            categories: [dining],
            accounts: [wechat]
        )

        XCTAssertEqual(result.amount, Decimal(string: "30"))
        XCTAssertTrue(result.type == TransactionType.expense)
        XCTAssertEqual(result.typeSource, .category)
        XCTAssertTrue(result.category?.id == dining.id)
        XCTAssertEqual(result.remark, "吃饭")
        XCTAssertTrue(result.issues.contains(.missingAccount))
        XCTAssertFalse(result.isReadyToSave)
    }

    func testParsesSalaryButFlagsMissingAccount() {
        let result = parser.parse(
            "工资入账 5000",
            categories: [salary, dining],
            accounts: [bank]
        )

        XCTAssertEqual(result.amount, Decimal(string: "5000"))
        XCTAssertTrue(result.type == TransactionType.income)
        XCTAssertTrue(result.category?.id == salary.id)
        XCTAssertNil(result.account)
        XCTAssertEqual(result.remark, "极速记账")
        XCTAssertTrue(result.issues.contains(.missingAccount))
        XCTAssertFalse(result.isReadyToSave)
    }

    func testRejectsNegativeAmount() {
        let result = parser.parse(
            "买奶茶 -15 元",
            categories: [dining],
            accounts: [wechat]
        )

        XCTAssertNil(result.amount)
        XCTAssertTrue(result.type == TransactionType.expense)
        XCTAssertTrue(result.category?.id == dining.id)
        XCTAssertTrue(result.issues.contains(.negativeAmount))
        XCTAssertFalse(result.isReadyToSave)
    }

    func testRejectsMissingAmount() {
        let result = parser.parse(
            "买奶茶",
            categories: [dining],
            accounts: [wechat]
        )

        XCTAssertNil(result.amount)
        XCTAssertTrue(result.type == TransactionType.expense)
        XCTAssertTrue(result.category?.id == dining.id)
        XCTAssertEqual(result.remark, "奶茶")
        XCTAssertTrue(result.issues.contains(.missingAmount))
        XCTAssertFalse(result.isReadyToSave)
    }

    func testConflictingTypeKeywordsRequireUserChoice() {
        let result = parser.parse(
            "买奶茶收入30",
            categories: [dining],
            accounts: [wechat]
        )

        XCTAssertEqual(result.amount, Decimal(string: "30"))
        XCTAssertNil(result.type)
        XCTAssertEqual(result.typeSource, .none)
        XCTAssertTrue(result.issues.contains(.ambiguousType))
        XCTAssertFalse(result.isReadyToSave)
    }

    func testParsesFullWidthCurrencyAndNumber() {
        let result = parser.parse("￥２０")

        XCTAssertEqual(result.amount, Decimal(string: "20"))
        XCTAssertNil(result.type)
        XCTAssertTrue(result.issues.contains(.missingType))
        XCTAssertTrue(result.issues.contains(.missingCategory))
        XCTAssertTrue(result.issues.contains(.missingAccount))
        XCTAssertFalse(result.isReadyToSave)
    }

    func testLongInputIsTruncatedAndRejected() {
        let text = "买 15 元 " + String(repeating: "奶", count: 600)
        let result = parser.parse(
            text,
            categories: [dining],
            accounts: [wechat]
        )

        XCTAssertEqual(result.amount, Decimal(string: "15"))
        XCTAssertTrue(result.issues.contains(.inputTooLong))
        XCTAssertFalse(result.isReadyToSave)
    }

    func testUnmatchedCategoryAndAccountAreReported() {
        let result = parser.parse(
            "买书 45",
            categories: [dining],
            accounts: [wechat]
        )

        XCTAssertEqual(result.amount, Decimal(string: "45"))
        XCTAssertTrue(result.type == TransactionType.expense)
        XCTAssertNil(result.category)
        XCTAssertNil(result.account)
        XCTAssertEqual(result.remark, "书")
        XCTAssertTrue(result.issues.contains(.missingCategory))
        XCTAssertTrue(result.issues.contains(.missingAccount))
        XCTAssertFalse(result.isReadyToSave)
    }

    func testMultipleAmountsAreReportedAndBlockSave() {
        let result = parser.parse(
            "买奶茶15元 打车20元",
            categories: [dining, transport],
            accounts: []
        )

        XCTAssertEqual(result.amount, Decimal(string: "15"))
        XCTAssertTrue(result.issues.contains(.multipleAmounts))
        XCTAssertTrue(result.issues.contains(.ambiguousCategory))
        XCTAssertFalse(result.isReadyToSave)
    }

    func testParsesElectricBikeModelWithoutTreatingModelNumberAsAmount() {
        let result = parser.parse(
            "我买了一台电动车，9号M5200花费22000",
            categories: [transport, shopping],
            accounts: [wechat]
        )

        XCTAssertEqual(result.amount, Decimal(string: "22000"))
        XCTAssertTrue(result.type == TransactionType.expense)
        XCTAssertEqual(result.category?.id, transport.id)
        XCTAssertEqual(result.itemName, "电动车")
        XCTAssertTrue(result.remark.contains("电动车"))
        XCTAssertTrue(result.remark.lowercased().contains("m5200"))
        XCTAssertFalse(result.issues.contains(.multipleAmounts))
    }

    func testParsesLipstickItemPriceAndFlagsUnusualAmount() {
        let result = parser.parse(
            "今天财务报表。呃，发现有一项不对劲，这个物品是口红，但是口红价格是1000元",
            categories: [shopping],
            accounts: [wechat]
        )

        XCTAssertEqual(result.amount, Decimal(string: "1000"))
        XCTAssertTrue(result.type == TransactionType.expense)
        XCTAssertEqual(result.category?.id, shopping.id)
        XCTAssertEqual(result.itemName, "口红")
        XCTAssertEqual(result.remark, "口红")
        XCTAssertTrue(result.warnings.contains { $0.contains("高于常见区间") })
        XCTAssertTrue(result.issues.contains(.missingAccount))
        XCTAssertFalse(result.isReadyToSave)
    }

    func testQuantityDoesNotOutrankPrice() {
        let result = parser.parse(
            "我买了2台电动车，花22000",
            categories: [transport],
            accounts: [wechat]
        )

        XCTAssertEqual(result.amount, Decimal(string: "22000"))
        XCTAssertEqual(result.itemName, "电动车")
        XCTAssertFalse(result.issues.contains(.multipleAmounts))
    }
}


final class AIActionRouterTests: XCTestCase {

    func testExplicitRecordCommandKeepsAmountTextForParser() {
        let action = AIActionRouter.route("帮我记一笔 微信买奶茶15")
        XCTAssertEqual(action.intent, .record)
        XCTAssertEqual(action.recordText, "微信买奶茶15")
    }

    func testQuestionAboutSpendingRoutesToQuery() {
        XCTAssertEqual(AIActionRouter.route("这个月花了多少").intent, .query)
        XCTAssertEqual(AIActionRouter.route("预算还剩多少").intent, .query)
    }

    func testExportFormatsRouteToDistinctActions() {
        XCTAssertEqual(AIActionRouter.route("导出 JSON").intent, .backupJSON)
        XCTAssertEqual(AIActionRouter.route("导出 CSV").intent, .exportCSV)
    }

    func testImageCommandDoesNotBecomeRecord() {
        let action = AIActionRouter.route("截图记一笔")
        XCTAssertEqual(action.intent, .imageImport)
    }

    func testIncomeSentenceRoutesToRecord() {
        let action = AIActionRouter.route("工资到账 8000")
        XCTAssertEqual(action.intent, .record)
        XCTAssertNotNil(action.recordText)
    }
}

final class AIFinanceLogPromptTests: XCTestCase {
    func testPromptInsertsLedgerTextAndKeepsChatTemplate() {
        let prompt = AIFinanceLogPrompt.makePrompt(
            ledgerText: "【汇总】共 3 笔；支出 ¥45.00"
        )

        XCTAssertTrue(prompt.contains("【汇总】共 3 笔；支出 ¥45.00"))
        XCTAssertFalse(prompt.contains(AIFinanceLogPrompt.ledgerPlaceholder))
        XCTAssertTrue(prompt.hasPrefix("<|im_start|>system"))
        XCTAssertTrue(prompt.hasSuffix("<|im_start|>assistant"))
    }

    func testSystemPromptRequiresThreeMarkdownSections() {
        let prompt = AIFinanceLogPrompt.systemPrompt

        XCTAssertTrue(prompt.contains("资深个人财务规划师"))
        XCTAssertTrue(prompt.contains("拿铁因子"))
        XCTAssertTrue(prompt.contains("异常消费"))
        XCTAssertTrue(prompt.contains("## 【财务健康度体检】"))
        XCTAssertTrue(prompt.contains("## 【消费漏洞诊断】"))
        XCTAssertTrue(prompt.contains("## 【财务教练的 3 个建议】"))
        XCTAssertTrue(prompt.contains("不评判"))
    }
}
