import Foundation
import XCTest
@testable import LedgerlyCore

final class DuplicateDetectorTests: XCTestCase {
    private let base = T.date(2026, 4, 15, 12, 0, 0)

    private func tx(_ amount: String, _ merchant: String, secondsAfter: TimeInterval, method: PaymentMethod = .cash) -> TransactionRecord {
        let date = base.addingTimeInterval(secondsAfter)
        return TransactionRecord(amount: T.d(amount), merchant: merchant, date: date, paymentMethod: method, createdAt: date)
    }

    func testSameAmountAndMerchantWithinWindow() {
        XCTAssertTrue(DuplicateDetector.isDuplicate(tx("12.40", "Starbucks", secondsAfter: 0), tx("12.40", "STARBUCKS #1234", secondsAfter: 60)))
    }
    func testAt179Seconds() {
        XCTAssertTrue(DuplicateDetector.isDuplicate(tx("12.40", "Starbucks", secondsAfter: 0), tx("12.40", "Starbucks", secondsAfter: 179)))
    }
    func testExactly180SecondsIsInclusive() {
        XCTAssertTrue(DuplicateDetector.isDuplicate(tx("12.40", "Starbucks", secondsAfter: 0), tx("12.40", "Starbucks", secondsAfter: 180)))
    }
    func testAt181SecondsIsNotDuplicate() {
        XCTAssertFalse(DuplicateDetector.isDuplicate(tx("12.40", "Starbucks", secondsAfter: 0), tx("12.40", "Starbucks", secondsAfter: 181)))
    }
    func testWindowWorksBackwardsInTime() {
        XCTAssertTrue(DuplicateDetector.isDuplicate(tx("12.40", "Starbucks", secondsAfter: 0), tx("12.40", "Starbucks", secondsAfter: -170)))
        XCTAssertFalse(DuplicateDetector.isDuplicate(tx("12.40", "Starbucks", secondsAfter: 0), tx("12.40", "Starbucks", secondsAfter: -181)))
    }
    func testDifferentAmountIsNotDuplicate() {
        XCTAssertFalse(DuplicateDetector.isDuplicate(tx("12.40", "Starbucks", secondsAfter: 0), tx("12.41", "Starbucks", secondsAfter: 10)))
    }
    func testDifferentMerchantAndNoCardIsNotDuplicate() {
        XCTAssertFalse(DuplicateDetector.isDuplicate(tx("12.40", "Starbucks", secondsAfter: 0), tx("12.40", "Dunkin", secondsAfter: 10)))
    }
    func testSameCardDifferentMerchantIsDuplicate() {
        let a = tx("12.40", "Starbucks", secondsAfter: 0, method: .walletCard("Apple Card"))
        let b = tx("12.40", "", secondsAfter: 30, method: .walletCard("apple card "))
        XCTAssertTrue(DuplicateDetector.isDuplicate(a, b))
    }
    func testDifferentCardsDifferentMerchants() {
        let a = tx("12.40", "Starbucks", secondsAfter: 0, method: .walletCard("Apple Card"))
        let b = tx("12.40", "Dunkin", secondsAfter: 30, method: .walletCard("Chase Freedom"))
        XCTAssertFalse(DuplicateDetector.isDuplicate(a, b))
    }
    func testBlankMerchantsDoNotMatchOnMerchant() {
        XCTAssertFalse(DuplicateDetector.isDuplicate(tx("12.40", "", secondsAfter: 0), tx("12.40", " ", secondsAfter: 5)))
    }
    func testCashAndOtherCardNeverMatchOnCard() {
        let a = tx("5.00", "A", secondsAfter: 0, method: .otherCard)
        let b = tx("5.00", "B", secondsAfter: 5, method: .otherCard)
        XCTAssertFalse(DuplicateDetector.isDuplicate(a, b))
    }
    func testDifferentCurrencyIsNotDuplicate() {
        var b = tx("12.40", "Starbucks", secondsAfter: 5)
        b.currencyCode = "EUR"
        XCTAssertFalse(DuplicateDetector.isDuplicate(tx("12.40", "Starbucks", secondsAfter: 0), b))
    }
    func testRecordIsNotItsOwnDuplicate() {
        let a = tx("12.40", "Starbucks", secondsAfter: 0)
        XCTAssertFalse(DuplicateDetector.isDuplicate(a, a))
        XCTAssertNil(DuplicateDetector.findDuplicate(of: a, in: [a]))
    }
    func testFindDuplicateReturnsTheMatch() {
        let existing = [tx("3.00", "Dunkin", secondsAfter: -20), tx("12.40", "Starbucks", secondsAfter: -30)]
        let found = DuplicateDetector.findDuplicate(of: tx("12.40", "starbucks", secondsAfter: 0), in: existing)
        XCTAssertEqual(found?.id, existing[1].id)
    }
    func testRefundsMatchOnSign() {
        XCTAssertFalse(DuplicateDetector.isDuplicate(tx("12.40", "Target", secondsAfter: 0), tx("-12.40", "Target", secondsAfter: 5)))
        XCTAssertTrue(DuplicateDetector.isDuplicate(tx("-12.40", "Target", secondsAfter: 0), tx("-12.40", "Target", secondsAfter: 5)))
    }
}

final class TransactionIngestorTests: XCTestCase {
    private let now = T.date(2026, 4, 15, 12, 0, 0)
    private var ingestor: TransactionIngestor { TransactionIngestor(categorizer: Categorizer(), locale: T.us) }

    private func incoming(_ amount: String, _ merchant: String?, card: String? = "Apple Card", at date: Date? = nil) -> IncomingTransaction {
        IncomingTransaction(rawAmount: amount, merchant: merchant, cardName: card, date: date ?? now, source: .walletShortcut)
    }

    func testCleanWalletTransaction() {
        let fixedID = UUID()
        let result = ingestor.ingest(incoming("$12.40", "Starbucks"), existing: [], now: now, id: fixedID)
        let record = result.record
        XCTAssertEqual(record.id, fixedID)
        XCTAssertEqual(record.amount, T.d("12.40"))
        XCTAssertEqual(record.merchant, "Starbucks")
        XCTAssertEqual(record.categoryID, T.id("food"))
        XCTAssertEqual(record.paymentMethod, .walletCard("Apple Card"))
        XCTAssertEqual(record.source, .walletShortcut)
        XCTAssertEqual(record.currencyCode, "USD")
        XCTAssertEqual(record.date, now)
        XCTAssertEqual(record.createdAt, now)
        XCTAssertFalse(record.needsReview)
        XCTAssertFalse(record.isPossibleDuplicate)
        XCTAssertTrue(result.reviewReasons.isEmpty)
        XCTAssertEqual(result.categorization.reason, .builtInKeyword)
    }
    func testZeroAmountNeedsReview() {
        let result = ingestor.ingest(incoming("0", "Starbucks"), now: now)
        XCTAssertEqual(result.record.amount, T.d("0"))
        XCTAssertTrue(result.record.needsReview)
        XCTAssertEqual(result.reviewReasons, [.zeroAmount])
        XCTAssertEqual(result.record.categoryID, T.id("food"))
    }
    func testBlankAmountNeedsReviewAndStoresZero() {
        let result = ingestor.ingest(incoming("", "Starbucks"), now: now)
        XCTAssertEqual(result.record.amount, T.d("0"))
        XCTAssertTrue(result.record.needsReview)
        XCTAssertEqual(result.reviewReasons, [.unparseableAmount])
    }
    func testGarbageAmountNeedsReview() {
        let result = ingestor.ingest(incoming("twelve dollars", "Starbucks"), now: now)
        XCTAssertEqual(result.record.amount, T.d("0"))
        XCTAssertEqual(result.reviewReasons, [.unparseableAmount])
    }
    func testBlankMerchantNeedsReviewAndIsOther() {
        let result = ingestor.ingest(incoming("12.40", "   "), now: now)
        XCTAssertEqual(result.record.merchant, "")
        XCTAssertEqual(result.record.amount, T.d("12.40"))
        XCTAssertTrue(result.record.needsReview)
        XCTAssertEqual(result.reviewReasons, [.blankMerchant])
        XCTAssertEqual(result.record.categoryID, T.id("other"))
    }
    func testNilMerchantAndZeroAmount() {
        let result = ingestor.ingest(incoming("0", nil), now: now)
        XCTAssertEqual(result.record.merchant, "")
        XCTAssertTrue(result.record.needsReview)
        XCTAssertEqual(result.reviewReasons, [.zeroAmount, .blankMerchant])
    }
    func testDuplicateIsFlaggedNotDropped() {
        let first = ingestor.ingest(incoming("12.40", "Starbucks"), now: now).record
        let again = ingestor.ingest(incoming("12.40", "Starbucks", at: now.addingTimeInterval(90)), existing: [first], now: now.addingTimeInterval(90))
        XCTAssertTrue(again.record.isPossibleDuplicate)
        XCTAssertTrue(again.record.needsReview)
        XCTAssertEqual(again.reviewReasons, [.possibleDuplicate])
        XCTAssertEqual(again.duplicateOfID, first.id)
        XCTAssertEqual(again.record.amount, T.d("12.40"))
    }
    func testNotDuplicateAfterWindow() {
        let first = ingestor.ingest(incoming("12.40", "Starbucks"), now: now).record
        let later = ingestor.ingest(incoming("12.40", "Starbucks", at: now.addingTimeInterval(181)), existing: [first], now: now)
        XCTAssertFalse(later.record.isPossibleDuplicate)
        XCTAssertFalse(later.record.needsReview)
    }
    func testDuplicateBySameCardWhenMerchantDiffers() {
        let first = ingestor.ingest(incoming("12.40", "Starbucks"), now: now).record
        let second = ingestor.ingest(incoming("12.40", "SBUX 0042", at: now.addingTimeInterval(20)), existing: [first], now: now)
        XCTAssertTrue(second.record.isPossibleDuplicate)
    }
    func testZeroAmountsAreNotCalledDuplicates() {
        let first = ingestor.ingest(incoming("0", "Starbucks"), now: now).record
        let second = ingestor.ingest(incoming("0", "Starbucks", at: now.addingTimeInterval(20)), existing: [first], now: now)
        XCTAssertFalse(second.record.isPossibleDuplicate)
        XCTAssertEqual(second.reviewReasons, [.zeroAmount])
    }
    func testDuplicateCheckCanBeSkipped() {
        let first = ingestor.ingest(incoming("12.40", "Starbucks"), now: now).record
        let second = ingestor.ingest(incoming("12.40", "Starbucks"), existing: [first], now: now, checkDuplicates: false)
        XCTAssertFalse(second.record.isPossibleDuplicate)
    }
    func testLearnedRuleIsApplied() {
        let rules = [MerchantRule(normalizedMerchant: "STARBUCKS", categoryID: T.id("recreation"))]
        let custom = TransactionIngestor(categorizer: Categorizer(rules: rules), locale: T.us)
        let result = custom.ingest(incoming("4.75", "Starbucks #991"), now: now)
        XCTAssertEqual(result.record.categoryID, T.id("recreation"))
        XCTAssertEqual(result.categorization.reason, .learnedRule)
    }
    func testNoCardBecomesOtherCard() {
        XCTAssertEqual(ingestor.ingest(incoming("5", "Shell", card: nil), now: now).record.paymentMethod, .otherCard)
        XCTAssertEqual(ingestor.ingest(incoming("5", "Shell", card: "  "), now: now).record.paymentMethod, .otherCard)
        XCTAssertEqual(ingestor.ingest(incoming("5", "Shell", card: "Cash"), now: now).record.paymentMethod, .cash)
    }
    func testNegativeAmountIsARefund() {
        let result = ingestor.ingest(incoming("-$25.00", "Target"), now: now)
        XCTAssertEqual(result.record.amount, T.d("-25.00"))
        XCTAssertFalse(result.record.needsReview)
        XCTAssertTrue(result.record.isRefund)
    }
    func testNegateAmountFlag() {
        var item = incoming("-25.00", "Target")
        item.negateAmount = true
        XCTAssertEqual(ingestor.ingest(item, now: now).record.amount, T.d("25.00"))
    }
    func testLocaleIsUsedForAmbiguousAmounts() {
        let german = TransactionIngestor(categorizer: Categorizer(), locale: Locale(identifier: "de_DE"))
        XCTAssertEqual(german.ingest(incoming("1.234", "Aldi"), now: now).record.amount, T.d("1234"))
        XCTAssertEqual(ingestor.ingest(incoming("1.234", "Aldi"), now: now).record.amount, T.d("1.234"))
    }
    func testCurrencyOverride() {
        var item = incoming("12,40", "Aldi")
        item.currencyCode = "eur"
        XCTAssertEqual(ingestor.ingest(item, now: now).record.currencyCode, "EUR")
    }

    // Notification text

    func testNotificationTextForCleanTransaction() {
        let record = ingestor.ingest(incoming("$12.40", "Starbucks"), now: now).record
        XCTAssertEqual(
            TransactionIngestor.notificationText(for: record, categoryName: "Food & Dining", locale: T.us),
            "Logged $12.40 at Starbucks · Food & Dining"
        )
        XCTAssertEqual(TransactionIngestor.notificationTitle(for: record), "Transaction logged")
    }
    func testNotificationTextForRefund() {
        let record = ingestor.ingest(incoming("-5", "Target"), now: now).record
        XCTAssertEqual(TransactionIngestor.notificationText(for: record, categoryName: "Shopping", locale: T.us), "Logged $5.00 refund from Target · Shopping")
    }
    func testNotificationTextForMissingAmount() {
        let record = ingestor.ingest(incoming("0", "Starbucks"), now: now).record
        XCTAssertEqual(
            TransactionIngestor.notificationText(for: record, categoryName: "Food & Dining", locale: T.us),
            "Saved a purchase at Starbucks, but the amount is missing. Tap to review."
        )
        XCTAssertEqual(TransactionIngestor.notificationTitle(for: record), "Needs review")
    }
    func testNotificationTextForMissingMerchant() {
        let record = ingestor.ingest(incoming("12.40", ""), now: now).record
        XCTAssertEqual(
            TransactionIngestor.notificationText(for: record, categoryName: "Other", locale: T.us),
            "Logged $12.40, but the merchant is missing. Tap to review."
        )
    }
    func testNotificationTextForNothingUsable() {
        let record = ingestor.ingest(incoming("", nil), now: now).record
        XCTAssertEqual(
            TransactionIngestor.notificationText(for: record, categoryName: nil, locale: T.us),
            "Saved a Wallet transaction with missing details. Tap to review."
        )
    }
    func testNotificationTextForDuplicate() {
        let first = ingestor.ingest(incoming("12.40", "Starbucks"), now: now).record
        let second = ingestor.ingest(incoming("12.40", "Starbucks"), existing: [first], now: now).record
        XCTAssertEqual(
            TransactionIngestor.notificationText(for: second, categoryName: "Food & Dining", locale: T.us),
            "Possible duplicate: $12.40 at Starbucks. Tap to review."
        )
        XCTAssertEqual(TransactionIngestor.notificationTitle(for: second), "Possible duplicate")
    }
    func testNotificationTextWithoutCategory() {
        let record = ingestor.ingest(incoming("1,234.5", "Best Buy"), now: now).record
        XCTAssertEqual(TransactionIngestor.notificationText(for: record, categoryName: nil, locale: T.us), "Logged $1,234.50 at Best Buy")
    }
}

final class MoneyFormatTests: XCTestCase {
    func testCurrencyString() {
        XCTAssertEqual(MoneyFormat.string(T.d("12.4"), locale: T.us), "$12.40")
        XCTAssertEqual(MoneyFormat.string(T.d("1234.56"), locale: T.us), "$1,234.56")
        XCTAssertEqual(MoneyFormat.string(T.d("0"), locale: T.us), "$0.00")
    }
    func testNegativeCurrencyString() { XCTAssertEqual(MoneyFormat.string(T.d("-5"), locale: T.us), "-$5.00") }
    func testVeryLargeAmountKeepsItsCents() {
        XCTAssertEqual(MoneyFormat.string(T.d("99999999999.99"), locale: T.us), "$99,999,999,999.99")
    }
    func testPlainRoundingIsHalfAwayFromZero() {
        XCTAssertEqual(MoneyFormat.round(T.d("0.125")), T.d("0.13"))
        XCTAssertEqual(MoneyFormat.round(T.d("0.135")), T.d("0.14"))
        XCTAssertEqual(MoneyFormat.round(T.d("-0.125")), T.d("-0.13"))
        XCTAssertEqual(MoneyFormat.round(T.d("2.5"), scale: 0), T.d("3"))
        XCTAssertEqual(MoneyFormat.round(T.d("0.124")), T.d("0.12"))
        XCTAssertEqual(MoneyFormat.string(T.d("0.125"), locale: T.us), "$0.13")
    }
    func testTruncate() {
        XCTAssertEqual(MoneyFormat.truncate(T.d("1.999")), T.d("1.99"))
        XCTAssertEqual(MoneyFormat.truncate(T.d("-1.999")), T.d("-1.99"))
    }
    func testWholeDollars() {
        XCTAssertEqual(MoneyFormat.whole(T.d("309.5"), locale: T.us), "$310")
        XCTAssertEqual(MoneyFormat.whole(T.d("219.49"), locale: T.us), "$219")
        XCTAssertEqual(MoneyFormat.whole(T.d("-4.6"), locale: T.us), "-$5")
        XCTAssertEqual(MoneyFormat.whole(T.d("1234"), locale: T.us), "$1,234")
    }
    func testCompact() {
        XCTAssertEqual(MoneyFormat.compact(T.d("45"), locale: T.us), "$45")
        XCTAssertEqual(MoneyFormat.compact(T.d("44.37"), locale: T.us), "$44.37")
        XCTAssertEqual(MoneyFormat.compact(T.d("44.5"), locale: T.us), "$44.50")
    }
    func testPlain() {
        XCTAssertEqual(MoneyFormat.plain(T.d("12.4")), "12.40")
        XCTAssertEqual(MoneyFormat.plain(T.d("-5")), "-5.00")
        XCTAssertEqual(MoneyFormat.plain(T.d("1234.567")), "1234.567")
        XCTAssertEqual(MoneyFormat.plain(T.d("99999999999.99")), "99999999999.99")
        XCTAssertEqual(MoneyFormat.plain(T.d("0")), "0.00")
    }
    func testPercent() {
        XCTAssertEqual(MoneyFormat.percent(T.d("0.4")), "40%")
        XCTAssertEqual(MoneyFormat.percent(T.d("0.4090909")), "41%")
        XCTAssertEqual(MoneyFormat.percent(T.d("1.5")), "150%")
    }
    func testOtherCurrencyAndLocale() {
        let text = MoneyFormat.string(T.d("1234.5"), currencyCode: "EUR", locale: Locale(identifier: "de_DE"))
        XCTAssertTrue(text.contains("1.234,50"), text)
        XCTAssertTrue(text.contains("€"), text)
    }
}

final class ModelTests: XCTestCase {
    func testPaymentMethodRoundTripThroughStoredParts() {
        for method in [PaymentMethod.cash, .otherCard, .walletCard("Apple Card")] {
            XCTAssertEqual(PaymentMethod(kindRaw: method.kindRaw, cardName: method.cardName), method)
        }
        XCTAssertEqual(PaymentMethod.cash.kindRaw, "cash")
        XCTAssertEqual(PaymentMethod.otherCard.kindRaw, "otherCard")
        XCTAssertEqual(PaymentMethod.walletCard("X").kindRaw, "walletCard")
    }
    func testPaymentMethodFallbacks() {
        XCTAssertEqual(PaymentMethod(kindRaw: "walletCard", cardName: nil), .otherCard)
        XCTAssertEqual(PaymentMethod(kindRaw: "walletCard", cardName: "  "), .otherCard)
        XCTAssertEqual(PaymentMethod(kindRaw: "bogus", cardName: "X"), .otherCard)
    }
    func testPaymentMethodDisplayNames() {
        XCTAssertEqual(PaymentMethod.cash.displayName, "Cash")
        XCTAssertEqual(PaymentMethod.otherCard.displayName, "Other card")
        XCTAssertEqual(PaymentMethod.walletCard("Apple Card").displayName, "Apple Card")
    }
    func testTransactionRecordDefaults() {
        let date = T.date(2026, 4, 1)
        let record = TransactionRecord(amount: T.d("1"), merchant: "M", date: date, createdAt: date)
        XCTAssertEqual(record.currencyCode, "USD")
        XCTAssertNil(record.categoryID)
        XCTAssertEqual(record.paymentMethod, .cash)
        XCTAssertEqual(record.source, .manual)
        XCTAssertEqual(record.notes, "")
        XCTAssertFalse(record.needsReview)
        XCTAssertFalse(record.isPossibleDuplicate)
    }
    func testCodableRoundTripKeepsDecimalExact() throws {
        let date = T.date(2026, 4, 1)
        let record = TransactionRecord(
            amount: T.d("99999999999.99"), merchant: "Big", categoryID: T.id("shopping"), date: date,
            paymentMethod: .walletCard("Apple Card"), source: .walletShortcut, notes: "n", needsReview: true, isPossibleDuplicate: true, createdAt: date
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(TransactionRecord.self, from: data)
        XCTAssertEqual(decoded.id, record.id)
        XCTAssertEqual(decoded.paymentMethod, record.paymentMethod)
        XCTAssertEqual(decoded.source, record.source)
        XCTAssertEqual(MoneyFormat.round(decoded.amount), T.d("99999999999.99"))
    }
    func testMonthKeyArithmetic() {
        XCTAssertEqual(MonthKey(year: 2026, month: 1).previous, MonthKey(year: 2025, month: 12))
        XCTAssertEqual(MonthKey(year: 2025, month: 12).next, MonthKey(year: 2026, month: 1))
        XCTAssertEqual(MonthKey(year: 2026, month: 3).adding(months: -15), MonthKey(year: 2024, month: 12))
        XCTAssertEqual(MonthKey(year: 2026, month: 13), MonthKey(year: 2027, month: 1))
        XCTAssertEqual(MonthKey(year: 2026, month: 0), MonthKey(year: 2025, month: 12))
    }
    func testMonthKeyOrdering() {
        XCTAssertLessThan(MonthKey(year: 2025, month: 12), MonthKey(year: 2026, month: 1))
        XCTAssertLessThan(MonthKey(year: 2026, month: 1), MonthKey(year: 2026, month: 2))
        XCTAssertFalse(MonthKey(year: 2026, month: 2) < MonthKey(year: 2026, month: 2))
    }
    func testMonthKeyStrings() {
        XCTAssertEqual(MonthKey(year: 2026, month: 3).stringValue, "2026-03")
        XCTAssertEqual(MonthKey(year: 2026, month: 11).stringValue, "2026-11")
        XCTAssertEqual(MonthKey(string: "2026-03"), MonthKey(year: 2026, month: 3))
        XCTAssertNil(MonthKey(string: "2026-13"))
        XCTAssertNil(MonthKey(string: "March"))
        XCTAssertNil(MonthKey(string: ""))
    }
    func testMonthKeyFromDateUsesTheCalendarTimeZone() {
        // 04:30 UTC on April 1 is still March 31 in Chicago.
        let instant = T.date(2026, 4, 1, 4, 30, calendar: T.utc)
        XCTAssertEqual(MonthKey(date: instant, calendar: T.utc), MonthKey(year: 2026, month: 4))
        XCTAssertEqual(MonthKey(date: instant, calendar: T.chicago), MonthKey(year: 2026, month: 3))
    }
    func testSourceKindRawValues() {
        XCTAssertEqual(SourceKind.allCases.map { $0.rawValue }, ["walletShortcut", "financeKit", "manual", "csvImport"])
    }
}
