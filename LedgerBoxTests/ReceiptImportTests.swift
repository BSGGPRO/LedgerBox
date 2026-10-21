import CoreData
import CoreGraphics
import XCTest
@testable import LedgerBox

final class ReceiptImportTests: XCTestCase {

    private let testCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }()

    private var temporaryFiles: [URL] = []

    override func tearDown() {
        for url in temporaryFiles {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryFiles.removeAll()
        super.tearDown()
    }

    // MARK: - Parser

    func testWeChatReceiptParsesAmountMerchantAndSource() {
        let now = date(2026, 10, 21, 12, 0)
        let text = """
        微信支付
        商户名称：瑞幸咖啡(国贸店)
        支付时间：2026-10-20 09:12
        实付金额：¥25.50
        订单号：4200001234567890
        """

        let fields = ReceiptParser.parse(text, now: now, calendar: testCalendar)

        XCTAssertEqual(fields.source, .wechat)
        XCTAssertEqual(fields.amount, decimal("25.50"))
        XCTAssertEqual(fields.merchantText, "瑞幸咖啡(国贸店)")
        XCTAssertNil(fields.fee)
        XCTAssertEqual(fields.occurredAt, date(2026, 10, 20, 9, 12))
        XCTAssertNotNil(fields.orderIDHash)
        XCTAssertFalse(fields.warnings.contains(.missingAmount))
        XCTAssertFalse(fields.warnings.contains(.missingDate))
        XCTAssertFalse(fields.warnings.contains(.ambiguousAmount))
    }

    func testThousandSeparatorAmountIsParsedExactly() {
        let text = """
        微信支付
        商户：京东
        实付：¥1,234.56
        时间：2026-10-20 09:12
        """

        let fields = ReceiptParser.parse(
            text,
            now: date(2026, 10, 21, 12, 0),
            calendar: testCalendar
        )

        XCTAssertEqual(fields.amount, decimal("1234.56"))
        XCTAssertEqual(fields.merchantText, "京东")
        XCTAssertEqual(fields.source, .wechat)
        XCTAssertEqual(fields.occurredAt, date(2026, 10, 20, 9, 12))
    }

    func testFullWidthCurrencyAndDigitsAreNormalized() {
        let text = """
        微信支付
        实付：￥２０．５０
        """

        let fields = ReceiptParser.parse(
            text,
            now: date(2026, 10, 21, 12, 0),
            calendar: testCalendar
        )

        XCTAssertEqual(fields.amount, decimal("20.50"))
        XCTAssertTrue(fields.normalizedText.contains("¥20.50"))
    }

    func testYearlessFutureDateRollsBackOneYear() {
        let now = date(2026, 1, 2, 12, 0)
        let text = """
        微信支付
        实付 ¥20.00
        12月31日 09:12
        """

        let fields = ReceiptParser.parse(text, now: now, calendar: testCalendar)

        XCTAssertEqual(fields.occurredAt, date(2025, 12, 31, 9, 12))
    }

    func testYesterdayTimeUsesInjectedCalendar() {
        let now = date(2026, 10, 21, 12, 0)
        let text = """
        微信支付
        实付 ¥20.00
        昨天 20:57
        """

        let fields = ReceiptParser.parse(text, now: now, calendar: testCalendar)

        XCTAssertEqual(fields.amount, decimal("20.00"))
        XCTAssertEqual(fields.occurredAt, date(2026, 10, 20, 20, 57))
        XCTAssertFalse(fields.warnings.contains(.missingDate))
    }

    func testOrderIDIsHashedInsteadOfStored() {
        let rawOrderID = "4200001234567890"
        let text = """
        微信支付
        商户：瑞幸咖啡
        实付 ¥25.50
        2026-10-20 09:12
        订单号：\(rawOrderID)
        """
        let now = date(2026, 10, 21, 12, 0)

        let fields = ReceiptParser.parse(text, now: now, calendar: testCalendar)
        let later = ReceiptParser.parse(
            text,
            now: now.addingTimeInterval(3_600),
            calendar: testCalendar
        )

        XCTAssertEqual(fields.orderIDHash, ReceiptParser.sha256Hex(rawOrderID))
        XCTAssertEqual(fields.orderIDHash?.count, 64)
        XCTAssertFalse(fields.orderIDHash?.contains(rawOrderID) ?? true)
        XCTAssertEqual(fields.orderIDHash, later.orderIDHash)
        XCTAssertEqual(fields.dedupeKey, later.dedupeKey)
    }

    func testWithdrawalFeeSplitDefaultsAndCanSwitch() {
        let text = """
        微信零钱提现
        提现金额：¥1,000.00
        服务费：¥0.10
        到账金额：¥999.90
        """

        let split = ReceiptParser.transferSplit(in: text)
        XCTAssertEqual(split?.principal, decimal("1000.00"))
        XCTAssertEqual(split?.fee, decimal("0.10"))
        XCTAssertEqual(split?.credited, decimal("999.90"))
        XCTAssertEqual(split?.cashOut, decimal("1000.00"))
        XCTAssertEqual(split?.mode, .feeDeductedFromPrincipal)

        let alternate = split?.switching(to: .feePaidSeparately)
        XCTAssertEqual(alternate?.credited, decimal("1000.00"))
        XCTAssertEqual(alternate?.cashOut, decimal("1000.10"))
        XCTAssertEqual(alternate?.mode, .feePaidSeparately)

        let fields = ReceiptParser.parse(
            text,
            now: date(2026, 10, 21, 12, 0),
            calendar: testCalendar
        )
        XCTAssertEqual(fields.amount, decimal("1000.00"))
        XCTAssertEqual(fields.fee, decimal("0.10"))
        XCTAssertTrue(fields.warnings.contains(.feeSplitAmbiguous))
    }

    func testDedupeKeyUsesOrderHashThenMinuteFallback() {
        let now = date(2026, 10, 21, 12, 0)
        let withOrder = """
        微信支付
        商户：瑞幸咖啡
        实付 ¥25.50
        2026-10-20 09:12
        订单号：4200001234567890
        """
        let first = ReceiptParser.parse(withOrder, now: now, calendar: testCalendar)
        let second = ReceiptParser.parse(
            withOrder,
            now: now.addingTimeInterval(300),
            calendar: testCalendar
        )
        XCTAssertEqual(first.dedupeKey, second.dedupeKey)

        let fallbackText = """
        微信支付
        商户：瑞幸咖啡
        实付 ¥25.50
        2026-10-20 09:12
        """
        let fallback = ReceiptParser.parse(
            fallbackText,
            now: now,
            calendar: testCalendar
        )
        let fallbackAgain = ReceiptParser.parse(
            fallbackText,
            now: now.addingTimeInterval(30),
            calendar: testCalendar
        )
        let nextMinute = ReceiptParser.parse(
            fallbackText.replacingOccurrences(of: "09:12", with: "09:13"),
            now: now,
            calendar: testCalendar
        )

        XCTAssertNil(fallback.orderIDHash)
        XCTAssertEqual(fallback.dedupeKey, fallbackAgain.dedupeKey)
        XCTAssertNotEqual(fallback.dedupeKey, nextMinute.dedupeKey)
    }

    func testMissingAmountAndDateWarnings() {
        let now = date(2026, 10, 21, 12, 0)
        let noAmount = ReceiptParser.parse(
            """
            微信支付
            商户：便利店
            支付时间：2026-10-20 09:12
            """,
            now: now,
            calendar: testCalendar
        )

        XCTAssertNil(noAmount.amount)
        XCTAssertTrue(noAmount.warnings.contains(.missingAmount))
        XCTAssertFalse(noAmount.warnings.contains(.missingDate))

        let noDate = ReceiptParser.parse(
            """
            微信支付
            实付 ¥20.00
            """,
            now: now,
            calendar: testCalendar
        )

        XCTAssertEqual(noDate.occurredAt, testCalendar.startOfDay(for: now))
        XCTAssertTrue(noDate.warnings.contains(.missingDate))
    }

    func testAmountIgnoresBalanceAndDiscountLines() {
        let text = """
        微信支付
        商品金额 ¥100.00
        优惠 ¥10.00
        余额 ¥500.00
        实付 ¥90.00
        2026-10-20 09:12
        """

        let fields = ReceiptParser.parse(
            text,
            now: date(2026, 10, 21, 12, 0),
            calendar: testCalendar
        )

        XCTAssertEqual(fields.amount, decimal("90.00"))
        XCTAssertTrue(fields.warnings.contains(.ambiguousAmount))
    }

    // MARK: - Lexicon and classifier

    func testMerchantLexiconMatchesLuckinDiDiAndTraditionalMeituan() {
        let lexicon = MerchantLexicon.shared

        let luckin = lexicon.match("瑞幸咖啡(国贸店)")
        XCTAssertEqual(luckin?.canonical, "瑞幸咖啡")
        XCTAssertEqual(luckin?.category, .food)

        let didi = lexicon.match("滴滴出行 快车")
        XCTAssertEqual(didi?.canonical, "滴滴出行")
        XCTAssertEqual(didi?.category, .transport)

        let meituan = lexicon.match("美團外賣")
        XCTAssertEqual(meituan?.canonical, "美团")
        XCTAssertEqual(meituan?.category, .food)

        let fuzzy = lexicon.match("美田外卖")
        XCTAssertEqual(fuzzy?.canonical, "美团")

        let fullWidth = lexicon.match("ＳＴＡＲＢＵＣＫＳ")
        XCTAssertEqual(fullWidth?.canonical, "星巴克")
        XCTAssertEqual(fullWidth?.category, .food)
    }

    func testClassifierFallsBackToOtherWithoutSignal() {
        let classifier = LedgerCategoryClassifier(
            lexicon: MerchantLexicon(entries: []),
            probe: { _, _ in nil }
        )
        let fields = ReceiptParser.parse(
            "??",
            now: date(2026, 10, 21, 12, 0),
            calendar: testCalendar
        )

        let result = classifier.classify("??", fields: fields)

        XCTAssertEqual(result.category, .other)
        XCTAssertTrue(result.needsReview)
        XCTAssertFalse(result.usedLexicon)
        XCTAssertNil(result.modelIntent)
    }

    func testClassifierUsesLexiconForFood() {
        let text = "瑞幸咖啡 实付 ¥32.00"
        let fields = ReceiptParser.parse(
            text,
            now: date(2026, 10, 21, 12, 0),
            calendar: testCalendar
        )

        let result = LedgerCategoryClassifier.shared.classify(text, fields: fields)

        XCTAssertEqual(result.category, .food)
        XCTAssertTrue(result.usedLexicon)
        XCTAssertGreaterThan(result.confidence, 0.6)
    }

    func testModelIntentMapsSubscriptionToShopping() {
        let probe = FinanceBrainProbe(
            predictions: [
                FinanceIntentPrediction(intent: .subscription, confidence: 0.90),
                FinanceIntentPrediction(intent: .recordExpense, confidence: 0.20)
            ],
            latencyMilliseconds: 1,
            featureCount: 1,
            bucketCount: 1,
            parameterCount: 1
        )
        let classifier = LedgerCategoryClassifier(
            lexicon: MerchantLexicon(entries: []),
            probe: { _, _ in probe }
        )
        let text = "NETFLIX 订阅 实付 ¥30.00"
        let fields = ReceiptParser.parse(
            text,
            now: date(2026, 10, 21, 12, 0),
            calendar: testCalendar
        )

        let result = classifier.classify(text, fields: fields)

        XCTAssertEqual(result.category, .shopping)
        XCTAssertEqual(result.modelIntent, "subscription")
        XCTAssertFalse(result.usedLexicon)
        XCTAssertFalse(result.needsReview)
    }

    // MARK: - History, commit and undo

    func testCommitAndUndoRestoreBalance() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let account = try XCTUnwrap(try context.fetch(Account.fetchRequest()).first)
        account.setBalance(decimal("1000.00"))
        try context.save()

        let categories = try context.fetch(Category.fetchRequest())
        let food = categories.first(where: { $0.name == "餐饮" })
        XCTAssertNotNil(food)

        let text = """
        微信支付
        商户：瑞幸咖啡
        实付 ¥25.50
        昨天 20:57
        """
        let ocr = OCRResult(lines: [OCRLine(text: text, confidence: 0.95)])
        let draft = try XCTUnwrap(
            ImportCommitService.makeDraft(
                from: ocr,
                now: Date(),
                calendar: testCalendar
            )
        )
        XCTAssertEqual(draft.type, .expense)
        XCTAssertEqual(draft.category, .food)

        let history = makeHistory()
        let session = try ImportCommitService.commit(
            draft,
            account: account,
            category: food,
            context: context,
            history: history
        )

        XCTAssertEqual(session.status, .committed)
        XCTAssertEqual(account.balanceValue, decimal("974.50"))
        XCTAssertEqual(try context.count(for: LedgerTransaction.fetchRequest()), 1)
        XCTAssertEqual(history.duplicate(for: draft.dedupeKey)?.id, session.id)

        try ImportCommitService.undo(
            sessionID: session.id,
            context: context,
            history: history
        )

        XCTAssertEqual(account.balanceValue, decimal("1000.00"))
        XCTAssertEqual(history.session(id: session.id)?.status, .undone)
        XCTAssertNil(history.duplicate(for: draft.dedupeKey))
        XCTAssertEqual(try context.count(for: LedgerTransaction.fetchRequest()), 0)
    }

    func testTransferCommitRecordsFeeAndUndoRestoresBothAccounts() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let source = try XCTUnwrap(try context.fetch(Account.fetchRequest()).first)
        source.setBalance(decimal("1000.00"))

        let destination = Account(context: context)
        destination.id = UUID()
        destination.name = "零钱"
        destination.type = AccountType.cash.rawValue
        destination.balance = NSDecimalNumber(decimal: decimal("0.00"))
        destination.currencyCode = "CNY"
        destination.locked = false
        destination.sortOrder = 1
        destination.createdAt = Date()
        destination.updatedAt = Date()
        try context.save()

        let draft = ImportDraft(
            source: .wechat,
            rawText: "微信零钱提现",
            cleanText: "微信零钱提现",
            merchant: "微信零钱",
            amount: decimal("1000.00"),
            fee: decimal("0.10"),
            date: Date().addingTimeInterval(-60),
            category: .transfer,
            type: .transfer,
            dedupeKey: "transfer-test-key",
            transferSplit: nil
        )
        let history = makeHistory()

        let session = try ImportCommitService.commit(
            draft,
            account: source,
            toAccount: destination,
            category: nil,
            context: context,
            history: history
        )

        XCTAssertEqual(session.transactionIDs.count, 2)
        XCTAssertEqual(source.balanceValue, decimal("0.00"))
        XCTAssertEqual(destination.balanceValue, decimal("999.90"))
        XCTAssertEqual(try context.count(for: LedgerTransaction.fetchRequest()), 2)

        try ImportCommitService.undo(
            sessionID: session.id,
            context: context,
            history: history
        )

        XCTAssertEqual(source.balanceValue, decimal("1000.00"))
        XCTAssertEqual(destination.balanceValue, decimal("0.00"))
        XCTAssertEqual(try context.count(for: LedgerTransaction.fetchRequest()), 0)
    }

    func testDuplicateCommitIsRejectedBeforeSecondWrite() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let account = try XCTUnwrap(try context.fetch(Account.fetchRequest()).first)
        account.setBalance(decimal("1000.00"))
        try context.save()

        let categories = try context.fetch(Category.fetchRequest())
        let food = categories.first(where: { $0.name == "餐饮" })

        let text = """
        微信支付
        商户：瑞幸咖啡
        实付 ¥25.50
        昨天 20:57
        """
        let ocr = OCRResult(lines: [OCRLine(text: text, confidence: 0.95)])
        let draft = try XCTUnwrap(
            ImportCommitService.makeDraft(
                from: ocr,
                now: Date(),
                calendar: testCalendar
            )
        )
        let history = makeHistory()

        let first = try ImportCommitService.commit(
            draft,
            account: account,
            category: food,
            context: context,
            history: history
        )

        XCTAssertThrowsError(
            try ImportCommitService.commit(
                draft,
                account: account,
                category: food,
                context: context,
                history: history
            )
        ) { error in
            guard let importError = error as? ImportError,
                  case .duplicate(let existingID) = importError else {
                XCTFail("Expected ImportError.duplicate, got \(error)")
                return
            }
            XCTAssertEqual(existingID, first.id)
        }

        XCTAssertEqual(try context.count(for: LedgerTransaction.fetchRequest()), 1)
        XCTAssertEqual(account.balanceValue, decimal("974.50"))
    }

    func testImportHistoryPersistsAndMarksUndone() throws {
        let url = temporaryHistoryURL()
        let store = ImportHistoryStore(fileURL: url)
        let session = ImportSession(
            dedupeKey: "dedupe-key",
            transactionIDs: [UUID(), UUID()],
            status: .committed
        )

        try store.add(session)

        let reloaded = ImportHistoryStore(fileURL: url)
        XCTAssertEqual(reloaded.session(id: session.id)?.dedupeKey, "dedupe-key")
        XCTAssertEqual(reloaded.duplicate(for: "dedupe-key")?.id, session.id)

        try reloaded.markUndone(id: session.id)

        let afterUndo = ImportHistoryStore(fileURL: url)
        XCTAssertEqual(afterUndo.session(id: session.id)?.status, .undone)
        XCTAssertNil(afterUndo.duplicate(for: "dedupe-key"))
    }

    func testLowConfidenceOCRAddsReviewWarning() throws {
        let text = """
        微信支付
        实付 ¥20.00
        昨天 20:57
        """
        let ocr = OCRResult(
            lines: [OCRLine(text: text, confidence: 0.32)]
        )

        let draft = try XCTUnwrap(
            ImportCommitService.makeDraft(
                from: ocr,
                now: Date(),
                calendar: testCalendar
            )
        )

        XCTAssertTrue(draft.warnings.contains(.lowOCRConfidence))
        XCTAssertTrue(draft.needsReview)
        XCTAssertEqual(draft.amount, decimal("20.00"))
    }

    // MARK: - Multi-bill segmentation

    func testSegmenterSplitsThreeVerticalBillCards() {
        let lines = [
            ocrLine("微信支付", y: 0.96),
            ocrLine("商户：瑞幸咖啡", y: 0.925),
            ocrLine("实付 ¥18.00", y: 0.89),
            ocrLine("2026-10-20 09:12", y: 0.855),
            ocrLine("微信支付", y: 0.70),
            ocrLine("商户：地铁", y: 0.665),
            ocrLine("实付 ¥4.00", y: 0.63),
            ocrLine("2026-10-20 08:30", y: 0.595),
            ocrLine("微信支付", y: 0.44),
            ocrLine("商户：京东", y: 0.405),
            ocrLine("实付 ¥299.00", y: 0.37),
            ocrLine("2026-10-19 21:00", y: 0.335)
        ]

        let segments = ReceiptSegmenter.segments(from: lines)

        XCTAssertEqual(segments.count, 3)
        XCTAssertTrue(segments[0].text.contains("瑞幸"))
        XCTAssertTrue(segments[1].text.contains("地铁"))
        XCTAssertTrue(segments[2].text.contains("京东"))
    }

    func testSegmenterKeepsSingleReceiptTogether() {
        let lines = [
            ocrLine("微信支付", y: 0.96),
            ocrLine("商户：瑞幸咖啡", y: 0.925),
            ocrLine("实付 ¥18.00", y: 0.89),
            ocrLine("2026-10-20 09:12", y: 0.855)
        ]

        let segments = ReceiptSegmenter.segments(from: lines)

        XCTAssertEqual(segments.count, 1)
        XCTAssertTrue(segments[0].text.contains("实付"))
    }

    func testMakeDraftsProducesOneDraftPerBill() {
        let lines = [
            ocrLine("微信支付", y: 0.96),
            ocrLine("商户：瑞幸咖啡", y: 0.925),
            ocrLine("实付 ¥18.00", y: 0.89),
            ocrLine("2026-10-20 09:12", y: 0.855),
            ocrLine("支付宝", y: 0.70),
            ocrLine("商户：地铁", y: 0.665),
            ocrLine("实付 ¥4.00", y: 0.63),
            ocrLine("2026-10-20 08:30", y: 0.595),
            ocrLine("微信支付", y: 0.44),
            ocrLine("商户：京东", y: 0.405),
            ocrLine("实付 ¥299.00", y: 0.37),
            ocrLine("2026-10-19 21:00", y: 0.335)
        ]
        let drafts = ImportCommitService.makeDrafts(
            from: OCRResult(lines: lines),
            now: date(2026, 10, 21, 12, 0),
            calendar: testCalendar
        )

        XCTAssertEqual(drafts.count, 3)
        XCTAssertEqual(Set(drafts.map(\.amount)), Set([
            decimal("18.00"),
            decimal("4.00"),
            decimal("299.00")
        ]))
        XCTAssertEqual(Set(drafts.map(\.dedupeKey)).count, 3)
    }

    func testMakeDraftsCollapsesDuplicateOrderHash() {
        let sharedOrder = "订单号：420000ABC123"
        let lines = [
            ocrLine("微信支付", y: 0.96),
            ocrLine("商户：瑞幸咖啡", y: 0.925),
            ocrLine("实付 ¥18.00", y: 0.89),
            ocrLine(sharedOrder, y: 0.855),
            ocrLine("微信支付", y: 0.70),
            ocrLine("商户：瑞幸咖啡", y: 0.665),
            ocrLine("实付 ¥18.00", y: 0.63),
            ocrLine(sharedOrder, y: 0.595)
        ]
        let drafts = ImportCommitService.makeDrafts(
            from: OCRResult(lines: lines),
            now: date(2026, 10, 21, 12, 0),
            calendar: testCalendar
        )

        XCTAssertEqual(drafts.count, 1)
    }

    // MARK: - Helpers

    private func ocrLine(
        _ text: String,
        y: CGFloat,
        height: CGFloat = 0.025
    ) -> OCRLine {
        OCRLine(
            text: text,
            confidence: 0.95,
            boundingBox: CGRect(
                x: 0.05,
                y: y,
                width: 0.90,
                height: height
            )
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0
    ) -> Date {
        testCalendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private func temporaryHistoryURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImportHistory-\(UUID().uuidString).json")
        temporaryFiles.append(url)
        return url
    }

    private func makeHistory() -> ImportHistoryStore {
        ImportHistoryStore(fileURL: temporaryHistoryURL())
    }
}

final class LedgerBackupTests: XCTestCase {

    func testBackupRoundTripRestoresAccountBalance() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let account = try XCTUnwrap(try context.fetch(Account.fetchRequest()).first)
        account.setBalance(Decimal(string: "1234.56", locale: Locale(identifier: "en_US_POSIX"))!)
        try context.save()

        let data = try LedgerBackupService.makeBackup(context: context)
        account.setBalance(Decimal.zero)
        try context.save()

        let summary = try LedgerBackupService.restore(data: data, context: context)
        XCTAssertEqual(summary.accountCount, 1)

        let restored = try XCTUnwrap(try context.fetch(Account.fetchRequest()).first)
        XCTAssertEqual(restored.balanceValue, Decimal(string: "1234.56"))
    }

    func testUnsupportedSchemaVersionIsRejected() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let data = try LedgerBackupService.makeBackup(context: context)

        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["schemaVersion"] = 99
        let mutated = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(
            try LedgerBackupService.restore(data: mutated, context: context)
        ) { error in
            guard let backupError = error as? BackupError,
                  case .unsupportedSchemaVersion(let version) = backupError else {
                XCTFail("Expected unsupportedSchemaVersion, got \(error)")
                return
            }
            XCTAssertEqual(version, 99)
        }
    }
}
