import CoreData
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    static var writableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = String(decoding: data, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Local-only CSV export. No credentials, no network, no cloud. [边界11]
enum CSVExporter {
    static func makeCSV(
        transactions: [LedgerTransaction],
        accounts: [Account],
        categories: [Category]
    ) -> String {
        let accountsByID = Dictionary(
            uniqueKeysWithValues: accounts.map { ($0.id, $0) }
        )
        let categoriesByID = Dictionary(
            uniqueKeysWithValues: categories.map { ($0.id, $0) }
        )

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let amountFormatter = NumberFormatter()
        amountFormatter.locale = Locale(identifier: "en_US_POSIX")
        amountFormatter.numberStyle = .decimal
        amountFormatter.usesGroupingSeparator = false
        amountFormatter.minimumFractionDigits = 2
        amountFormatter.maximumFractionDigits = 2

        var rows: [String] = [
            [
                "日期", "类型", "金额", "分类", "账户", "转入账户", "备注", "模板标签"
            ]
            .map { escape($0) }
            .joined(separator: ",")
        ]

        let sorted = transactions.sorted { $0.date < $1.date }
        for transaction in sorted {
            let categoryName = transaction.categoryId
                .flatMap { categoriesByID[$0]?.name } ?? "未分类"
            let accountName = accountsByID[transaction.accountId]?.name ?? "未知账户"
            let toAccountName = transaction.toAccountId
                .flatMap { accountsByID[$0]?.name } ?? ""
            let amount = amountFormatter.string(
                from: NSDecimalNumber(decimal: transaction.amountValue)
            ) ?? "0.00"

            rows.append(
                [
                    dateFormatter.string(from: transaction.date),
                    transaction.transactionType.displayName,
                    amount,
                    categoryName,
                    accountName,
                    toAccountName,
                    transaction.note ?? "",
                    transaction.templateTag ?? ""
                ]
                .map { escape($0) }
                .joined(separator: ",")
            )
        }

        // UTF-8 BOM keeps Chinese headers readable in Excel on Windows.
        return "\u{FEFF}" + rows.joined(separator: "\r\n")
    }

    private static func escape(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
