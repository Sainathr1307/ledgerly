import Foundation
import XCTest
@testable import LedgerlyCore

final class CSVTests: XCTestCase {
    private let cal = T.chicago
    private let now = T.date(2026, 4, 20)
    private var ingestor: TransactionIngestor { TransactionIngestor(categorizer: Categorizer(), locale: T.us) }

    // MARK: Parsing

    func testParseSimpleRows() {
        XCTAssertEqual(CSV.parse("a,b,c\n1,2,3\n"), [["a", "b", "c"], ["1", "2", "3"]])
    }
    func testParseQuotedCells() {
        let text = "Date,Merchant,Amount\n04/03/2026,\"Smith, Jones & Co\",\"1,234.56\"\n04/04/2026,\"The \"\"Best\"\" Deli\",5\n"
        XCTAssertEqual(CSV.parse(text), [
            ["Date", "Merchant", "Amount"],
            ["04/03/2026", "Smith, Jones & Co", "1,234.56"],
            ["04/04/2026", "The \"Best\" Deli", "5"]
        ])
    }
    func testParseLineBreakInsideQuotes() {
        XCTAssertEqual(CSV.parse("a,\"line one\nline two\",c\r\nd,e,f"), [["a", "line one\nline two", "c"], ["d", "e", "f"]])
    }
    func testParseLineEndingsAndBlankLines() {
        XCTAssertEqual(CSV.parse("a,b\r\n\r\nc,d\r\re,f\n\n"), [["a", "b"], ["c", "d"], ["e", "f"]])
    }
    func testParseByteOrderMarkAndEmptyCells() {
        XCTAssertEqual(CSV.parse("\u{FEFF}a,,c\n,\"\",\n"), [["a", "", "c"], ["", "", ""]])
    }
    func testParseNoTrailingNewline() {
        XCTAssertEqual(CSV.parse("a,b"), [["a", "b"]])
        XCTAssertEqual(CSV.parse(""), [])
    }
    func testDelimiterDetection() {
        XCTAssertEqual(CSV.parse("Datum;Betrag;Empfänger\n03.04.2026;-12,40;REWE\n"), [["Datum", "Betrag", "Empfänger"], ["03.04.2026", "-12,40", "REWE"]])
        XCTAssertEqual(CSV.parse("a\tb\n1\t2\n"), [["a", "b"], ["1", "2"]])
        XCTAssertEqual(CSV.detectDelimiter("a;b;c"), ";")
        XCTAssertEqual(CSV.detectDelimiter("\"x;y\",b,c"), ",")
        XCTAssertEqual(CSV.parse("a;b,c", delimiter: ","), [["a;b", "c"]])
    }
    func testEscapeAndWrite() {
        XCTAssertEqual(CSV.escape("plain"), "plain")
        XCTAssertEqual(CSV.escape("a,b"), "\"a,b\"")
        XCTAssertEqual(CSV.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(CSV.escape("two\nlines"), "\"two\nlines\"")
        let rows = [["a,b", "c\"d", "e"], ["", " padded ", "x\ny"]]
        XCTAssertEqual(CSV.parse(CSV.write(rows)), rows)
    }

    // MARK: Mapping

    func testGuessMappingForAppleCardExport() {
        let text = """
        Transaction Date,Clearing Date,Description,Merchant,Category,Type,Amount (USD),Purchased By
        04/03/2026,04/04/2026,"STARBUCKS #1234 CHICAGO IL",Starbucks,Restaurants,Purchase,12.40,Sai
        04/05/2026,04/06/2026,"SHELL OIL 57444",Shell,Gas,Purchase,45.10,Sai
        04/07/2026,04/07/2026,"ACH DEPOSIT",Payment,Payment,Payment,-200.00,Sai
        """
        let rows = CSV.parse(text)
        let mapping = CSVImporter.guessMapping(rows: rows, locale: T.us)
        XCTAssertTrue(mapping.hasHeader)
        XCTAssertEqual(mapping.date, 0)
        XCTAssertEqual(mapping.merchant, 3)
        XCTAssertEqual(mapping.category, 4)
        XCTAssertEqual(mapping.amount, 6)
        XCTAssertEqual(mapping.dateFormat, .monthDayYear)
        XCTAssertTrue(mapping.expensesArePositive)
        XCTAssertTrue(mapping.isComplete)
    }
    func testGuessMappingForBankExportWithNegativePurchases() {
        let text = """
        Transaction Date,Post Date,Description,Category,Type,Amount,Memo
        04/03/2026,04/04/2026,TRADER JOE'S #552,Groceries,Sale,-61.20,
        04/05/2026,04/06/2026,NETFLIX.COM,Bills,Sale,-15.49,monthly
        04/06/2026,04/06/2026,Payment Thank You,,Payment,500.00,
        """
        let mapping = CSVImporter.guessMapping(rows: CSV.parse(text), locale: T.us)
        XCTAssertEqual(mapping.date, 0)
        XCTAssertEqual(mapping.merchant, 2)
        XCTAssertEqual(mapping.category, 3)
        XCTAssertEqual(mapping.amount, 5)
        XCTAssertEqual(mapping.notes, 6)
        XCTAssertFalse(mapping.expensesArePositive)
    }
    func testGuessMappingWithoutHeader() {
        let rows = CSV.parse("2026-04-03,-12.40,STARBUCKS #1234\n2026-04-14,-45.00,SHELL OIL 57444\n")
        let mapping = CSVImporter.guessMapping(rows: rows, locale: T.us)
        XCTAssertFalse(mapping.hasHeader)
        XCTAssertEqual(mapping.date, 0)
        XCTAssertEqual(mapping.amount, 1)
        XCTAssertEqual(mapping.merchant, 2)
        XCTAssertEqual(mapping.dateFormat, .yearMonthDay)
        XCTAssertFalse(mapping.expensesArePositive)
    }
    func testHeaderDetection() {
        XCTAssertTrue(CSVImporter.hasHeader([["Date", "Amount", "Payee"]]))
        XCTAssertTrue(CSVImporter.hasHeader([["Wann", "Wieviel", "Wo"]]))
        XCTAssertFalse(CSVImporter.hasHeader([["2026-04-03", "12.40", "Starbucks"]]))
        XCTAssertFalse(CSVImporter.hasHeader([]))
    }
    func testSniffDateFormat() {
        XCTAssertEqual(CSVImporter.sniffDateFormat(["2026-04-03", "2026-04-14"]), .yearMonthDay)
        XCTAssertEqual(CSVImporter.sniffDateFormat(["04/03/2026", "04/14/2026"]), .monthDayYear)
        XCTAssertEqual(CSVImporter.sniffDateFormat(["03/04/2026", "14/04/2026"]), .dayMonthYear)
        XCTAssertEqual(CSVImporter.sniffDateFormat(["14.04.2026"]), .dayMonthYear)
        XCTAssertEqual(CSVImporter.sniffDateFormat(["03/04/2026", "05/06/2026"]), .monthDayYear)     // ambiguous → US
        XCTAssertEqual(CSVImporter.sniffDateFormat(["2026-04-03 14:05:09"]), .yearMonthDay)
        XCTAssertNil(CSVImporter.sniffDateFormat(["Starbucks"]))
        XCTAssertNil(CSVImporter.sniffDateFormat(["12.40"]))
        XCTAssertNil(CSVImporter.sniffDateFormat([]))
    }
    func testParseDateVariants() {
        let expected = T.date(2026, 4, 3, 0)
        XCTAssertEqual(CSVImporter.parseDate("2026-04-03", format: .yearMonthDay, calendar: cal), expected)
        XCTAssertEqual(CSVImporter.parseDate("04/03/2026", format: .monthDayYear, calendar: cal), expected)
        XCTAssertEqual(CSVImporter.parseDate("4/3/26", format: .monthDayYear, calendar: cal), expected)
        XCTAssertEqual(CSVImporter.parseDate("03/04/2026", format: .dayMonthYear, calendar: cal), expected)
        XCTAssertEqual(CSVImporter.parseDate("03.04.2026", format: .dayMonthYear, calendar: cal), expected)
        // A four-digit first part is always the year, whatever the mapping says.
        XCTAssertEqual(CSVImporter.parseDate("2026/04/03", format: .monthDayYear, calendar: cal), expected)
    }
    func testParseDateWithTime() {
        XCTAssertEqual(CSVImporter.parseDate("2026-04-03 14:05:09", format: .yearMonthDay, calendar: cal), T.date(2026, 4, 3, 14, 5, 9))
        XCTAssertEqual(CSVImporter.parseDate("2026-04-03T14:05", format: .yearMonthDay, calendar: cal), T.date(2026, 4, 3, 14, 5))
        XCTAssertEqual(CSVImporter.parseDate("04/03/2026 2:05 PM", format: .monthDayYear, calendar: cal), T.date(2026, 4, 3, 14, 5))
        XCTAssertEqual(CSVImporter.parseDate("04/03/2026 12:00 AM", format: .monthDayYear, calendar: cal), T.date(2026, 4, 3, 0, 0))
        XCTAssertEqual(CSVImporter.parseDate("2026-04-03T14:05:09Z", format: .yearMonthDay, calendar: cal), T.date(2026, 4, 3, 14, 5, 9, calendar: T.utc))
    }
    func testParseDateRejectsBadInput() {
        XCTAssertNil(CSVImporter.parseDate("", format: .monthDayYear, calendar: cal))
        XCTAssertNil(CSVImporter.parseDate("yesterday", format: .monthDayYear, calendar: cal))
        XCTAssertNil(CSVImporter.parseDate("02/30/2026", format: .monthDayYear, calendar: cal))
        XCTAssertNil(CSVImporter.parseDate("13/13/2026", format: .monthDayYear, calendar: cal))
        XCTAssertNil(CSVImporter.parseDate("04/03/2026 25:00", format: .monthDayYear, calendar: cal))
        XCTAssertNil(CSVImporter.parseDate("12.40", format: .monthDayYear, calendar: cal))
    }

    // MARK: Import

    func testImportRowsBecomeCategorizedRecords() {
        let text = """
        Date,Description,Amount,Category
        04/03/2026,STARBUCKS #1234,12.40,
        04/05/2026,Corner Hardware,"1,045.10",Shopping
        04/06/2026,TARGET 00012345,-25.00,
        """
        let prepared = CSVImporter.prepare(text: text, existing: [], ingestor: ingestor, calendar: cal, now: now)
        let records = prepared.result.newRecords
        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(records.map { $0.amount }, [T.d("12.40"), T.d("1045.10"), T.d("-25.00")])
        XCTAssertEqual(records.map { $0.merchant }, ["STARBUCKS #1234", "Corner Hardware", "TARGET 00012345"])
        XCTAssertEqual(records.map { $0.categoryID }, [T.id("food"), T.id("shopping"), T.id("shopping")])
        XCTAssertEqual(records.map { $0.date }, [T.date(2026, 4, 3, 0), T.date(2026, 4, 5, 0), T.date(2026, 4, 6, 0)])
        XCTAssertTrue(records.allSatisfy { $0.source == .csvImport && $0.createdAt == now && !$0.needsReview && $0.paymentMethod == .otherCard })
        XCTAssertEqual(prepared.result.rows.map { $0.rowNumber }, [2, 3, 4])
        XCTAssertEqual(prepared.result.failedCount, 0)
    }
    func testImportFlipsSignForBankExports() {
        let rows = CSV.parse("Date,Description,Amount\n04/03/2026,TRADER JOE'S #552,-61.20\n04/04/2026,AMAZON REFUND,18.00\n")
        var mapping = CSVImporter.guessMapping(rows: rows, locale: T.us)
        mapping.expensesArePositive = false
        let result = CSVImporter.prepare(rows: rows, mapping: mapping, existing: [], ingestor: ingestor, calendar: cal, now: now)
        XCTAssertEqual(result.newRecords.map { $0.amount }, [T.d("61.20"), T.d("-18.00")])
        XCTAssertEqual(result.newRecords[0].categoryID, T.id("groceries"))
    }
    func testImportDuplicateDetection() {
        let existing = [
            T.tx("12.40", "Starbucks", "food", on: T.date(2026, 4, 3, 8, 15)),     // same day, amount, merchant (store number differs)
            T.tx("45.00", "Shell", "gas", on: T.date(2026, 4, 4, 9)),              // different day
            T.tx("9.99", "Netflix", "subscriptions", on: T.date(2026, 4, 5, 9))    // different amount
        ]
        let text = """
        Date,Description,Amount
        04/03/2026,STARBUCKS #1234,12.40
        04/05/2026,SHELL,45.00
        04/05/2026,NETFLIX,15.49
        04/05/2026,NETFLIX,15.49
        """
        let result = CSVImporter.prepare(text: text, existing: existing, ingestor: ingestor, calendar: cal, now: now).result
        XCTAssertEqual(result.rows.map { $0.isDuplicate }, [true, false, false, false])
        XCTAssertEqual(result.duplicateCount, 1)
        XCTAssertEqual(result.newRecords.count, 3)          // identical rows inside one file are both kept
        XCTAssertEqual(result.duplicateRecords.count, 1)
        XCTAssertTrue(result.duplicateRecords[0].isPossibleDuplicate)
        XCTAssertTrue(CSVImporter.isImportDuplicate(existing[0], result.duplicateRecords[0], calendar: cal))
    }
    func testImportingTheSameFileTwiceFlagsEverything() {
        let text = "Date,Description,Amount\n04/03/2026,STARBUCKS #1234,12.40\n04/05/2026,SHELL,45.00\n"
        let first = CSVImporter.prepare(text: text, existing: [], ingestor: ingestor, calendar: cal, now: now).result
        let second = CSVImporter.prepare(text: text, existing: first.newRecords, ingestor: ingestor, calendar: cal, now: now).result
        XCTAssertEqual(second.duplicateCount, 2)
        XCTAssertTrue(second.newRecords.isEmpty)
    }
    func testImportProblemRows() {
        let text = """
        Date,Description,Amount
        not a date,STARBUCKS,12.40
        04/05/2026,SHELL,
        04/06/2026,,7.00
        ,,
        """
        let result = CSVImporter.prepare(text: text, existing: [], ingestor: ingestor, calendar: cal, now: now).result
        XCTAssertEqual(result.rows.count, 3)                // the all-blank row is skipped
        XCTAssertNil(result.rows[0].record)
        XCTAssertEqual(result.rows[0].problem, "Couldn't read the date \"not a date\".")
        XCTAssertEqual(result.failedCount, 1)
        // Missing amount / merchant still import, flagged for review — same rule as the Wallet shortcut.
        XCTAssertEqual(result.rows[1].record?.amount, T.d("0"))
        XCTAssertEqual(result.rows[1].record?.needsReview, true)
        XCTAssertEqual(result.rows[2].record?.merchant, "")
        XCTAssertEqual(result.rows[2].record?.needsReview, true)
        XCTAssertEqual(result.needsReviewCount, 2)
    }
    func testImportUsesLearnedRules() {
        let rules = [MerchantRule(normalizedMerchant: "CORNER HARDWARE", categoryID: T.id("bills"))]
        let custom = TransactionIngestor(categorizer: Categorizer(rules: rules), locale: T.us)
        let text = "Date,Description,Amount,Category\n04/05/2026,Corner Hardware,10,Shopping\n"
        let result = CSVImporter.prepare(text: text, existing: [], ingestor: custom, calendar: cal, now: now).result
        XCTAssertEqual(result.newRecords.first?.categoryID, T.id("bills"))
    }
    func testImportEuropeanFile() {
        let text = "Datum;Betrag;Empfänger\n03.04.2026;-12,40;ALDI SUED 123\n14.04.2026;-1.234,56;IKEA\n"
        let rows = CSV.parse(text)
        var mapping = CSVColumnMapping(date: 0, amount: 1, merchant: 2, hasHeader: true, dateFormat: .dayMonthYear, expensesArePositive: false)
        XCTAssertEqual(CSVImporter.sniffDateFormat(rows.dropFirst().map { $0[0] }), .dayMonthYear)
        mapping.currency = nil
        let german = TransactionIngestor(categorizer: Categorizer(), locale: Locale(identifier: "de_DE"), defaultCurrencyCode: "EUR")
        let result = CSVImporter.prepare(rows: rows, mapping: mapping, existing: [], ingestor: german, calendar: cal, now: now)
        XCTAssertEqual(result.newRecords.map { $0.amount }, [T.d("12.40"), T.d("1234.56")])
        XCTAssertEqual(result.newRecords.map { $0.date }, [T.date(2026, 4, 3, 0), T.date(2026, 4, 14, 0)])
        XCTAssertEqual(result.newRecords.map { $0.currencyCode }, ["EUR", "EUR"])
        XCTAssertEqual(result.newRecords.map { $0.categoryID }, [T.id("groceries"), T.id("shopping")])
    }

    // MARK: Export

    func testExportFormat() {
        let txs = [
            T.tx("12.40", "Starbucks", "food", on: T.date(2026, 4, 3, 8, 5, 9), method: .walletCard("Apple Card"), source: .walletShortcut),
            T.tx("-20", "Smith, Jones & \"Co\"", "shopping", on: T.date(2026, 4, 2, 23, 59, 59), method: .cash, notes: "line one\nline two")
        ]
        let text = CSV.export(transactions: txs, categories: T.categories, calendar: cal)
        let rows = CSV.parse(text)
        XCTAssertEqual(rows[0], ["Date", "Amount", "Currency", "Merchant", "Category", "Payment Method", "Source", "Notes", "Needs Review"])
        XCTAssertEqual(rows[1], ["2026-04-02 23:59:59", "-20.00", "USD", "Smith, Jones & \"Co\"", "Shopping", "Cash", "manual", "line one\nline two", "no"])
        XCTAssertEqual(rows[2], ["2026-04-03 08:05:09", "12.40", "USD", "Starbucks", "Food & Dining", "Apple Card", "walletShortcut", "", "no"])
        XCTAssertTrue(text.hasPrefix("Date,Amount,Currency,Merchant,Category,Payment Method,Source,Notes,Needs Review\r\n"))
    }
    func testExportThenImportRoundTrip() {
        let pets = CategoryRecord(name: "Pets", colorHex: "#123456", symbolName: "pawprint.fill", sortOrder: 10)
        let categories = T.categories + [pets]
        let original = [
            T.tx("12.40", "Starbucks #1234", "food", on: T.date(2026, 4, 3, 8, 5, 9), method: .walletCard("Apple Card"), source: .walletShortcut),
            T.tx("-20.00", "Smith, Jones & \"Co\"", "shopping", on: T.date(2026, 4, 2, 23, 59, 59), method: .cash, notes: "two\nlines, with comma"),
            T.tx("99999999999.99", "Yacht Club", "recreation", on: T.date(2026, 3, 8, 3, 30), method: .otherCard),
            TransactionRecord(amount: T.d("31.07"), merchant: "Happy Paws Vet", categoryID: pets.id, date: T.date(2026, 11, 1, 23, 30), createdAt: now),
            T.tx("7.5", "Zzyzx Unknown", nil, on: T.date(2026, 1, 1, 0, 0, 0))
        ]
        let text = CSV.export(transactions: original, categories: categories, calendar: cal)
        let importer = TransactionIngestor(categorizer: Categorizer(categories: categories), locale: T.us)
        let prepared = CSVImporter.prepare(text: text, existing: [], ingestor: importer, calendar: cal, now: now)

        XCTAssertEqual(prepared.mapping.date, 0)
        XCTAssertEqual(prepared.mapping.amount, 1)
        XCTAssertEqual(prepared.mapping.currency, 2)
        XCTAssertEqual(prepared.mapping.merchant, 3)
        XCTAssertEqual(prepared.mapping.category, 4)
        XCTAssertEqual(prepared.mapping.card, 5)
        XCTAssertEqual(prepared.mapping.notes, 7)
        XCTAssertEqual(prepared.mapping.dateFormat, .yearMonthDay)
        XCTAssertTrue(prepared.mapping.expensesArePositive)

        let imported = prepared.result.newRecords
        let expected = original.sorted { $0.date < $1.date }
        XCTAssertEqual(imported.count, expected.count)
        for (a, b) in zip(imported, expected) {
            XCTAssertEqual(a.date, b.date, b.merchant)
            XCTAssertEqual(a.amount, b.amount, b.merchant)
            XCTAssertEqual(a.merchant, b.merchant)
            XCTAssertEqual(a.notes, b.notes)
            XCTAssertEqual(a.currencyCode, b.currencyCode)
            XCTAssertEqual(a.paymentMethod, b.paymentMethod, b.merchant)
            XCTAssertEqual(a.categoryID, b.categoryID ?? T.id("other"), b.merchant)
            XCTAssertEqual(a.source, .csvImport)
        }
        // Importing the export on top of the originals flags every row as a duplicate.
        let again = CSVImporter.prepare(text: text, existing: original, ingestor: importer, calendar: cal, now: now).result
        XCTAssertEqual(again.duplicateCount, original.count)
    }
    func testExportEmptyAndFileName() {
        XCTAssertEqual(CSV.parse(CSV.export(transactions: [], categories: T.categories, calendar: cal)).count, 1)
        XCTAssertEqual(CSV.exportFileName(now: T.date(2026, 3, 14, 23, 59), calendar: cal), "ledgerly-2026-03-14.csv")
        XCTAssertEqual(CSV.timestamp(T.date(2026, 11, 1, 1, 30), calendar: cal), "2026-11-01 01:30:00")
    }
}

final class DemoDataTests: XCTestCase {
    private let cal = T.chicago
    private let now = T.date(2026, 11, 11, 15, 30)
    private var demo: DemoDataSet { DemoData.generate(now: now, calendar: cal) }

    private func snapshot(_ data: DemoDataSet, now: Date) -> BudgetSnapshot {
        BudgetEngine.snapshot(
            month: MonthKey(date: now, calendar: cal), now: now, transactions: data.transactions, earnings: data.earnings,
            goal: DemoData.goalAmount, categories: data.categories, calendar: cal
        )
    }

    func testDeterministic() {
        XCTAssertEqual(DemoData.generate(now: now, calendar: cal), DemoData.generate(now: now, calendar: cal))
        XCTAssertEqual(DemoData.generate(now: now, calendar: cal, seed: 5), DemoData.generate(now: now, calendar: cal, seed: 5))
    }
    func testDifferentSeedGivesDifferentData() {
        XCTAssertNotEqual(DemoData.generate(now: now, calendar: cal, seed: 1).transactions, DemoData.generate(now: now, calendar: cal, seed: 2).transactions)
    }
    func testSplitMix64KnownValues() {
        // Reference outputs for seed 0 (from the published SplitMix64 algorithm).
        var rng = SplitMix64(seed: 0)
        XCTAssertEqual(rng.next(), 0xE220A8397B1DCDAF)
        XCTAssertEqual(rng.next(), 0x6E789E6AA1B965F4)
        XCTAssertEqual(rng.next(), 0x06C45D188009454F)
        var a = SplitMix64(seed: 42), b = SplitMix64(seed: 42)
        XCTAssertEqual(a.uuid(), b.uuid())
        XCTAssertTrue((0..<200).allSatisfy { _ in (3...9).contains(a.int(in: 3...9)) })
    }
    func testCoversThreeMonthsUpToNow() {
        let data = demo
        let start = cal.monthStart(MonthKey(year: 2026, month: 9))
        XCTAssertTrue(data.transactions.allSatisfy { $0.date >= start && $0.date <= now })
        let months = Set(data.transactions.map { MonthKey(date: $0.date, calendar: cal) })
        XCTAssertEqual(months, [MonthKey(year: 2026, month: 9), MonthKey(year: 2026, month: 10), MonthKey(year: 2026, month: 11)])
        XCTAssertGreaterThan(data.transactions.count, 120)
        XCTAssertEqual(data.transactions.map { $0.date }, data.transactions.map { $0.date }.sorted())
        XCTAssertEqual(Set(data.transactions.map { $0.id }).count, data.transactions.count)
    }
    func testUsesEveryCategoryAndOnlyKnownOnes() {
        let data = demo
        let used = Set(data.transactions.compactMap { $0.categoryID })
        XCTAssertEqual(used, Set(DefaultCategories.all.map { $0.id }))
        XCTAssertEqual(data.categories, DefaultCategories.all)
        XCTAssertTrue(data.transactions.allSatisfy { $0.categoryID != nil })
    }
    func testMerchantsAreRecognizedByTheCategorizer() {
        let data = demo
        let categorizer = Categorizer()
        for tx in data.transactions where !tx.merchant.isEmpty {
            XCTAssertEqual(tx.categoryID, categorizer.categorize(merchant: tx.merchant).categoryID, tx.merchant)
        }
        let recognized = data.transactions.filter { Categorizer.builtInSystemKey(for: $0.merchant) != nil }.count
        XCTAssertGreaterThan(recognized * 100 / data.transactions.count, 90)
        XCTAssertGreaterThan(Set(data.transactions.map { $0.merchant }).count, 30)
    }
    func testHasRefundsCashWalletAndRecurringSubscriptions() {
        let data = demo
        XCTAssertGreaterThanOrEqual(data.transactions.filter { $0.amount < 0 }.count, 3)
        XCTAssertTrue(data.transactions.contains { $0.paymentMethod == .cash })
        XCTAssertTrue(data.transactions.contains { $0.paymentMethod == .walletCard("Apple Card") && $0.source == .walletShortcut })
        let netflixMonths = Set(data.transactions.filter { $0.merchant == "Netflix" }.map { MonthKey(date: $0.date, calendar: cal) })
        XCTAssertEqual(netflixMonths.count, 3)
        XCTAssertTrue(data.transactions.filter { $0.merchant == "Netflix" }.allSatisfy { $0.amount == T.d("15.49") })
    }
    func testNeedsReviewItems() {
        let review = demo.transactions.filter { $0.needsReview }
        XCTAssertEqual(review.count, 2)
        XCTAssertTrue(review.contains { $0.amount == 0 && !$0.merchant.isEmpty })
        XCTAssertTrue(review.contains { $0.amount > 0 && $0.merchant.isEmpty })
    }
    func testEarningsSkipTheMostRecentCompletedWeek() {
        let data = demo
        // November 11, 2026 is a Wednesday: last completed week starts Monday November 2.
        let missing = T.date(2026, 11, 2, 0)
        XCTAssertFalse(data.earnings.contains { $0.weekStart == missing })
        XCTAssertTrue(EarningsReminder.isLastWeekMissing(earnings: data.earnings, now: now, calendar: cal))
        XCTAssertTrue(data.earnings.allSatisfy { cal.weekday($0.weekStart) == 2 && cal.startOfDay($0.weekStart) == $0.weekStart })
        XCTAssertTrue(data.earnings.allSatisfy { $0.weekStart < missing && $0.amount > 0 })
        // September and October 2026 have four Mondays each.
        XCTAssertEqual(data.earnings.count, 8)
        XCTAssertEqual(Set(data.earnings.map { $0.weekStart }).count, 8)
    }
    func testGoals() {
        XCTAssertEqual(demo.goals, [9, 10, 11].map { MonthlyGoal(month: MonthKey(year: 2026, month: $0), amount: T.d("200")) })
    }
    func testWeekendHeavyRecreation() {
        let recreation = demo.transactions.filter { $0.categoryID == T.id("recreation") }
        let weekend = recreation.filter { cal.isWeekend($0.date) }.count
        XCTAssertGreaterThan(weekend * 2, recreation.count)
    }
    func testCurrentMonthTellsAStoryOnManyDates() {
        // Mid-month dates in 4- and 5-Monday months, around DST changes and across a year boundary.
        let dates = [(2026, 11, 11), (2026, 11, 1), (2026, 3, 8), (2026, 2, 14), (2026, 1, 3), (2026, 8, 20), (2026, 6, 2), (2026, 12, 25), (2027, 3, 15), (2026, 5, 5), (2024, 2, 20)]
        for (year, month, day) in dates {
            let at = T.date(year, month, day, 15, 30)
            let data = DemoData.generate(now: at, calendar: cal)
            let s = snapshot(data, now: at)
            let label = "\(year)-\(month)-\(day)"
            XCTAssertNotNil(s.projectedSavings, label)
            XCTAssertLessThan(s.projectedSavings ?? 0, T.d("200"), label)

            let food = T.id("food")
            let usual = s.usualByThisDayByCategory[food] ?? 0
            XCTAssertGreaterThan(usual, 0, label)
            XCTAssertGreaterThanOrEqual(s.spentByCategory[food] ?? 0, usual * InsightsEngine.overPaceRatio + 10, "Food & Dining over pace on \(label)")

            let cards = InsightsEngine.insights(snapshot: s, transactions: data.transactions, categories: data.categories, calendar: cal, locale: T.us)
            XCTAssertTrue(cards.contains { $0.kind == .overPace }, label)
            let plan = cards.first { $0.kind == .gapPlan }?.gapPlan
            XCTAssertNotNil(plan, label)
            XCTAssertFalse(plan?.cuts.isEmpty ?? true, "gap plan has cuts on \(label)")
            XCTAssertEqual(plan?.totalCuts, min(plan?.gap ?? 0, (plan?.gap ?? 0) - (plan?.uncovered ?? 0)), label)
            XCTAssertTrue(EarningsReminder.isLastWeekMissing(earnings: data.earnings, now: at, calendar: cal), label)
            XCTAssertTrue(data.transactions.allSatisfy { $0.date <= at }, label)
        }
    }
    func testCoffeeRunsShowUpByMidMonth() {
        let at = T.date(2026, 8, 20, 15, 30)
        let data = DemoData.generate(now: at, calendar: cal)
        let cards = InsightsEngine.insights(snapshot: snapshot(data, now: at), transactions: data.transactions, categories: data.categories, calendar: cal, locale: T.us)
        XCTAssertTrue(cards.contains { $0.id == "frequent-coffee" })
        XCTAssertTrue(cards.contains { $0.kind == .topMerchants })
    }
    func testFirstInstantOfAMonth() {
        // Midnight on the 1st: nothing can be dated later than "now", and nothing crashes.
        let at = T.date(2026, 6, 1, 0, 0, 0)
        let data = DemoData.generate(now: at, calendar: cal)
        XCTAssertTrue(data.transactions.allSatisfy { $0.date <= at })
        XCTAssertEqual(data.goals.count, 3)
        XCTAssertEqual(snapshot(data, now: at).dayOfMonth, 1)
    }
}
