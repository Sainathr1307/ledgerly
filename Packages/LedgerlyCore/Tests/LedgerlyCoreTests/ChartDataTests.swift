import Foundation
import XCTest
@testable import LedgerlyCore

final class ChartDataTests: XCTestCase {
    private let april = MonthKey(year: 2026, month: 4)
    private let cal = T.chicago

    // MARK: Donut

    func testCategoryBreakdown() {
        let txs = [
            T.tx("60", "Chipotle", "food", on: T.date(2026, 4, 2)),
            T.tx("40", "Aldi", "groceries", on: T.date(2026, 4, 3)),
            T.tx("999", "Old", "food", on: T.date(2026, 3, 3))
        ]
        let slices = ChartData.categoryBreakdown(month: april, transactions: txs, categories: T.categories, calendar: cal)
        XCTAssertEqual(slices.map { $0.categoryID }, [T.id("food"), T.id("groceries")])
        XCTAssertEqual(slices.map { $0.amount }, [T.d("60"), T.d("40")])
        XCTAssertEqual(slices.map { $0.fraction }, [T.d("0.6"), T.d("0.4")])
        XCTAssertEqual(slices[0].name, "Food & Dining")
        XCTAssertEqual(slices[0].symbolName, "fork.knife")
        XCTAssertEqual(slices[0].colorHex, "#E8590C")
        XCTAssertEqual(slices[0].value, 60)
    }
    func testBreakdownLeavesOutCategoriesWhereRefundsExceedSpending() {
        let txs = [
            T.tx("30", "Target", "shopping", on: T.date(2026, 4, 2)),
            T.tx("-100", "Target", "shopping", on: T.date(2026, 4, 3)),
            T.tx("50", "Chipotle", "food", on: T.date(2026, 4, 4)),
            T.tx("20", "Shell", "gas", on: T.date(2026, 4, 4)),
            T.tx("-20", "Shell", "gas", on: T.date(2026, 4, 5))
        ]
        let slices = ChartData.categoryBreakdown(month: april, transactions: txs, categories: T.categories, calendar: cal)
        XCTAssertEqual(slices.map { $0.categoryID }, [T.id("food")])
        XCTAssertEqual(slices[0].fraction, T.d("1"))
    }
    func testBreakdownPutsUncategorizedUnderOther() {
        let slices = ChartData.categoryBreakdown(month: april, transactions: [T.tx("9", "?", nil, on: T.date(2026, 4, 2))], categories: T.categories, calendar: cal)
        XCTAssertEqual(slices.map { $0.name }, ["Other"])
    }
    func testBreakdownEmptyMonth() {
        XCTAssertTrue(ChartData.categoryBreakdown(month: april, transactions: [], categories: T.categories, calendar: cal).isEmpty)
    }

    // MARK: Weekly bars

    func testWeeklyBarsPairSpendingWithEarnings() {
        let txs = [
            T.tx("11", on: T.date(2026, 4, 3)),              // week of March 30 → not an April bar
            T.tx("20", on: T.date(2026, 4, 6, 0, 0, 0)),     // Monday 00:00 starts week 1
            T.tx("5", on: T.date(2026, 4, 12, 23, 59, 59)),  // Sunday night still week 1
            T.tx("7", on: T.date(2026, 4, 13, 0, 0, 0)),     // week 2
            T.tx("-2", on: T.date(2026, 4, 14)),             // refund in week 2
            T.tx("40", on: T.date(2026, 4, 30)),             // week 4
            T.tx("60", on: T.date(2026, 5, 3))               // Sunday May 3 is still the week of April 27
        ]
        let earnings = [T.earning("500", weekOf: T.date(2026, 4, 6)), T.earning("610.50", weekOf: T.date(2026, 4, 27)), T.earning("999", weekOf: T.date(2026, 3, 30))]
        let bars = ChartData.weeklyBars(month: april, transactions: txs, earnings: earnings, calendar: cal)
        XCTAssertEqual(bars.map { $0.weekStart }, [6, 13, 20, 27].map { T.date(2026, 4, $0, 0) })
        XCTAssertEqual(bars.map { $0.spending }, [T.d("25"), T.d("5"), T.d("0"), T.d("100")])
        XCTAssertEqual(bars.map { $0.earnings }, [T.d("500"), nil, nil, T.d("610.50")])
        XCTAssertEqual(bars.map { $0.weekNumber }, [1, 2, 3, 4])
        XCTAssertEqual(bars[3].weekLastDay, T.date(2026, 5, 3, 0))
        XCTAssertEqual(bars[0].spendingValue, 25)
        XCTAssertEqual(bars[1].earningsValue, 0)
    }
    func testFiveMondayMonthHasFiveBars() {
        let bars = ChartData.weeklyBars(month: MonthKey(year: 2026, month: 3), transactions: [], earnings: [], calendar: cal)
        XCTAssertEqual(bars.count, 5)
        XCTAssertEqual(bars.last?.weekStart, T.date(2026, 3, 30, 0))
    }
    func testWeeklyBarsAcrossDaylightSaving() {
        // Week of Monday March 2, 2026 ends on the spring-forward Sunday.
        let txs = [T.tx("10", on: T.date(2026, 3, 8, 23, 59)), T.tx("20", on: T.date(2026, 3, 9, 0, 0))]
        let bars = ChartData.weeklyBars(month: MonthKey(year: 2026, month: 3), transactions: txs, earnings: [], calendar: cal)
        XCTAssertEqual(bars[0].spending, T.d("10"))
        XCTAssertEqual(bars[1].spending, T.d("20"))
    }

    // MARK: Cumulative line

    func testCumulativeSeries() {
        let now = T.date(2026, 4, 15)
        let txs = [
            T.tx("10", on: T.date(2026, 4, 1, 0, 0, 0)),
            T.tx("20", on: T.date(2026, 4, 3)),
            T.tx("-5", on: T.date(2026, 4, 3, 18)),
            T.tx("100", on: T.date(2026, 4, 15, 9)),
            T.tx("77", on: T.date(2026, 3, 31))
        ]
        let points = ChartData.cumulativeSeries(month: april, now: now, transactions: txs, expectedIncome: T.d("2000"), goal: T.d("200"), calendar: cal)
        XCTAssertEqual(points.count, 30)
        XCTAssertEqual(points[0].day, 1)
        XCTAssertEqual(points[0].date, T.date(2026, 4, 1, 0))
        XCTAssertEqual(points[0].cumulativeSpending, T.d("10"))
        XCTAssertEqual(points[1].cumulativeSpending, T.d("10"))
        XCTAssertEqual(points[2].cumulativeSpending, T.d("25"))
        XCTAssertEqual(points[14].cumulativeSpending, T.d("125"))
        XCTAssertNil(points[15].cumulativeSpending)
        XCTAssertNil(points[29].cumulativeSpending)
        // On-track line: (2000 − 200) × day / 30.
        XCTAssertEqual(points[0].onTrack, T.d("60"))
        XCTAssertEqual(points[14].onTrack, T.d("900"))
        XCTAssertEqual(points[29].onTrack, T.d("1800"))
        XCTAssertEqual(points[14].cumulativeValue, 125)
        XCTAssertEqual(points[14].onTrackValue, 900)
    }
    func testCumulativeSeriesWithUnknownIncome() {
        let points = ChartData.cumulativeSeries(month: april, now: T.date(2026, 4, 15), transactions: [], expectedIncome: nil, goal: T.d("200"), calendar: cal)
        XCTAssertTrue(points.allSatisfy { $0.onTrack == nil })
        XCTAssertEqual(points[14].cumulativeSpending, T.d("0"))
    }
    func testCumulativeSeriesPastAndFutureMonths() {
        let txs = [T.tx("50", on: T.date(2026, 4, 30, 23))]
        let past = ChartData.cumulativeSeries(month: april, now: T.date(2026, 5, 10), transactions: txs, expectedIncome: T.d("100"), goal: T.d("200"), calendar: cal)
        XCTAssertEqual(past.last?.cumulativeSpending, T.d("50"))
        XCTAssertEqual(past.last?.onTrack, T.d("0"))          // goal above income → flat zero line
        let future = ChartData.cumulativeSeries(month: MonthKey(year: 2026, month: 6), now: T.date(2026, 5, 10), transactions: txs, expectedIncome: nil, goal: T.d("200"), calendar: cal)
        XCTAssertTrue(future.allSatisfy { $0.cumulativeSpending == nil })
    }
    func testCumulativeSeriesInDaylightSavingMonths() {
        let march = MonthKey(year: 2026, month: 3)
        let txs = [T.tx("10", on: T.date(2026, 3, 8, 23, 30)), T.tx("5", on: T.date(2026, 3, 9, 0, 30))]
        let points = ChartData.cumulativeSeries(month: march, now: T.date(2026, 3, 31, 23), transactions: txs, expectedIncome: nil, goal: T.d("0"), calendar: cal)
        XCTAssertEqual(points.count, 31)
        XCTAssertEqual(points[6].cumulativeSpending, T.d("0"))
        XCTAssertEqual(points[7].cumulativeSpending, T.d("10"))
        XCTAssertEqual(points[8].cumulativeSpending, T.d("15"))
        XCTAssertEqual(points[8].date, T.date(2026, 3, 9, 0))

        let november = ChartData.cumulativeSeries(
            month: MonthKey(year: 2026, month: 11), now: T.date(2026, 11, 30, 12),
            transactions: [T.tx("3", on: T.date(2026, 11, 1, 23, 59))], expectedIncome: nil, goal: T.d("0"), calendar: cal
        )
        XCTAssertEqual(november.count, 30)
        XCTAssertEqual(november[0].cumulativeSpending, T.d("3"))
        XCTAssertEqual(november[1].date, T.date(2026, 11, 2, 0))
    }

    // MARK: Month over month, merchants

    func testMonthOverMonth() {
        let txs = [
            T.tx("100", "A", "shopping", on: T.date(2026, 3, 5)),
            T.tx("80", "A", "food", on: T.date(2026, 3, 5)),
            T.tx("120", "A", "food", on: T.date(2026, 4, 5)),
            T.tx("30", "A", "gas", on: T.date(2026, 4, 5)),
            T.tx("-50", "A", "health", on: T.date(2026, 4, 5)),
            T.tx("500", "A", "bills", on: T.date(2026, 2, 5))
        ]
        let rows = ChartData.monthOverMonth(month: april, transactions: txs, categories: T.categories, calendar: cal)
        XCTAssertEqual(rows.map { $0.categoryID }, [T.id("food"), T.id("gas"), T.id("shopping")])
        XCTAssertEqual(rows.map { $0.current }, [T.d("120"), T.d("30"), T.d("0")])
        XCTAssertEqual(rows.map { $0.previous }, [T.d("80"), T.d("0"), T.d("100")])
        XCTAssertEqual(rows[0].change, T.d("40"))
    }
    func testTopMerchants() {
        let txs = [
            T.tx("40", "SHELL OIL 57444", "gas", on: T.date(2026, 4, 2)),
            T.tx("35", "Shell Oil #22", "gas", on: T.date(2026, 4, 9)),
            T.tx("200", "Target", "shopping", on: T.date(2026, 4, 3)),
            T.tx("-50", "Target", "shopping", on: T.date(2026, 4, 4)),
            T.tx("20", "Amazon", "shopping", on: T.date(2026, 4, 4)),
            T.tx("-30", "Amazon", "shopping", on: T.date(2026, 4, 5)),
            T.tx("9", "", "other", on: T.date(2026, 4, 5)),
            T.tx("60", "Shell Oil", "gas", on: T.date(2026, 3, 9)),
            T.tx("10", "Dunkin", "food", on: T.date(2026, 4, 6))
        ]
        let merchants = ChartData.topMerchants(month: april, transactions: txs, calendar: cal, limit: 2)
        XCTAssertEqual(merchants.map { $0.normalizedMerchant }, ["TARGET", "SHELL OIL"])
        XCTAssertEqual(merchants.map { $0.amount }, [T.d("150"), T.d("75")])
        XCTAssertEqual(merchants[1].displayName, "Shell Oil #22")
        XCTAssertEqual(merchants[1].transactionCount, 2)
        XCTAssertEqual(merchants[1].previousAmount, T.d("60"))
        XCTAssertEqual(merchants[1].change, T.d("15"))
        XCTAssertEqual(merchants[1].fractionOfTop, T.d("0.5"))
        XCTAssertEqual(merchants[0].fractionOfTop, T.d("1"))
        XCTAssertTrue(merchants[0].isNew)
        let all = ChartData.topMerchants(month: april, transactions: txs, calendar: cal)
        XCTAssertEqual(all.map { $0.normalizedMerchant }, ["TARGET", "SHELL OIL", "DUNKIN"])   // Amazon nets negative, blank is skipped
    }

    // MARK: List helpers

    private var listSample: [TransactionRecord] {
        [
            T.tx("12.40", "Starbucks", "food", on: T.date(2026, 4, 15, 8, 5), method: .walletCard("Apple Card"), source: .walletShortcut),
            T.tx("45.00", "Shell", "gas", on: T.date(2026, 4, 15, 17, 30), method: .walletCard("Chase Freedom"), source: .walletShortcut),
            T.tx("-20.00", "Target", "shopping", on: T.date(2026, 4, 14, 23, 59, 59), method: .otherCard, source: .manual, notes: "Returned lamp"),
            T.tx("8.00", "Café Olé", "food", on: T.date(2026, 4, 14, 0, 0, 0), method: .cash, source: .manual, notes: "birthday treat"),
            T.tx("0", "", nil, on: T.date(2026, 4, 10, 12), method: .walletCard("Apple Card"), source: .walletShortcut, needsReview: true),
            T.tx("30.00", "Aldi", "groceries", on: T.date(2026, 3, 31, 12), method: .cash, source: .csvImport)
        ]
    }

    func testGroupByDayWithDailyTotals() {
        let groups = ChartData.groupByDay(listSample.shuffled(), calendar: cal)
        XCTAssertEqual(groups.map { $0.day }, [T.date(2026, 4, 15, 0), T.date(2026, 4, 14, 0), T.date(2026, 4, 10, 0), T.date(2026, 3, 31, 0)])
        XCTAssertEqual(groups.map { $0.total }, [T.d("57.40"), T.d("-12.00"), T.d("0"), T.d("30.00")])
        XCTAssertEqual(groups[0].transactions.map { $0.merchant }, ["Shell", "Starbucks"])
        XCTAssertEqual(groups[1].transactions.map { $0.merchant }, ["Target", "Café Olé"])
    }
    func testGroupByDayUsesLocalDays() {
        // 03:00 UTC is the previous evening in Chicago.
        let instant = T.date(2026, 4, 15, 3, 0, calendar: T.utc)
        let tx = TransactionRecord(amount: T.d("1"), merchant: "X", date: instant, createdAt: instant)
        XCTAssertEqual(ChartData.groupByDay([tx], calendar: cal).first?.day, T.date(2026, 4, 14, 0))
        XCTAssertEqual(ChartData.groupByDay([tx], calendar: T.utc).first?.day, T.date(2026, 4, 15, 0, calendar: T.utc))
    }
    func testGroupByDayOnDaylightSavingDays() {
        let txs = [T.tx("1", on: T.date(2026, 11, 1, 0, 30)), T.tx("2", on: T.date(2026, 11, 1, 23, 59)), T.tx("4", on: T.date(2026, 11, 2, 0, 0))]
        let groups = ChartData.groupByDay(txs, calendar: cal)
        XCTAssertEqual(groups.map { $0.total }, [T.d("4"), T.d("3")])
    }
    func testSearchByMerchantOrNotes() {
        XCTAssertEqual(ChartData.search(listSample, text: "star").map { $0.merchant }, ["Starbucks"])
        XCTAssertEqual(ChartData.search(listSample, text: "LAMP").map { $0.merchant }, ["Target"])
        XCTAssertEqual(ChartData.search(listSample, text: "cafe ole").map { $0.merchant }, ["Café Olé"])
        XCTAssertEqual(ChartData.search(listSample, text: "birthday café").map { $0.merchant }, ["Café Olé"])
        XCTAssertTrue(ChartData.search(listSample, text: "zzz").isEmpty)
        XCTAssertEqual(ChartData.search(listSample, text: "   ").count, listSample.count)
    }
    func testFilterByCategory() {
        var filter = TransactionFilter(categoryIDs: [T.id("food")])
        XCTAssertEqual(ChartData.filter(listSample, with: filter).map { $0.merchant }, ["Starbucks", "Café Olé"])
        // With the category list, uncategorized transactions are found under Other.
        filter.categoryIDs = [T.id("other")]
        XCTAssertEqual(ChartData.filter(listSample, with: filter, categories: T.categories).count, 1)
        XCTAssertEqual(ChartData.filter(listSample, with: filter).count, 0)
    }
    func testFilterBySource() {
        XCTAssertEqual(ChartData.filter(listSample, with: TransactionFilter(sources: [.csvImport])).map { $0.merchant }, ["Aldi"])
        XCTAssertEqual(ChartData.filter(listSample, with: TransactionFilter(sources: [.manual, .csvImport])).count, 3)
    }
    func testFilterByPaymentMethod() {
        XCTAssertEqual(ChartData.filter(listSample, with: TransactionFilter(paymentMethods: [.cash])).map { $0.merchant }, ["Café Olé", "Aldi"])
        XCTAssertEqual(ChartData.filter(listSample, with: TransactionFilter(paymentMethods: [.walletCard("Apple Card")])).count, 2)
        XCTAssertEqual(ChartData.filter(listSample, with: TransactionFilter(paymentMethods: [.walletCard("Chase Freedom"), .otherCard])).count, 2)
    }
    func testFilterByDateRangeIncludesTheWholeLastDay() {
        var filter = TransactionFilter()
        filter.setDayRange(from: T.date(2026, 4, 14, 15), through: T.date(2026, 4, 14, 9), calendar: cal)
        XCTAssertEqual(ChartData.filter(listSample, with: filter).map { $0.merchant }, ["Target", "Café Olé"])
        filter.setDayRange(from: T.date(2026, 4, 10), through: T.date(2026, 4, 14), calendar: cal)
        XCTAssertEqual(ChartData.filter(listSample, with: filter).count, 3)
        filter.setMonth(MonthKey(year: 2026, month: 3), calendar: cal)
        XCTAssertEqual(ChartData.filter(listSample, with: filter).map { $0.merchant }, ["Aldi"])
    }
    func testCombinedFiltersAndFlags() {
        var filter = TransactionFilter(searchText: "s", categoryIDs: [T.id("food"), T.id("gas")], sources: [.walletShortcut])
        XCTAssertEqual(ChartData.filter(listSample, with: filter).map { $0.merchant }, ["Starbucks", "Shell"])
        XCTAssertFalse(filter.isEmpty)
        XCTAssertTrue(filter.hasNonSearchFilters)
        filter = TransactionFilter(needsReviewOnly: true)
        XCTAssertEqual(ChartData.filter(listSample, with: filter).count, 1)
        XCTAssertTrue(TransactionFilter().isEmpty)
        XCTAssertFalse(TransactionFilter(searchText: "x").hasNonSearchFilters)
    }
    func testNeedsReviewRecentAndPaymentMethods() {
        XCTAssertEqual(ChartData.needsReview(listSample).count, 1)
        XCTAssertEqual(ChartData.recent(listSample, limit: 2).map { $0.merchant }, ["Shell", "Starbucks"])
        XCTAssertEqual(ChartData.paymentMethods(in: listSample), [.cash, .otherCard, .walletCard("Apple Card"), .walletCard("Chase Freedom")])
    }
    func testMerchantSuggestions() {
        let past = ["Starbucks", "Shell", "starbucks", "Stan's Donuts", "Target", "Starbucks", " ", "Best Buy"]
        // Prefix matches first (most used first), then names that merely contain the text ("Be-st Buy").
        XCTAssertEqual(ChartData.merchantSuggestions(prefix: "st", from: past), ["Starbucks", "Stan's Donuts", "Best Buy"])
        XCTAssertEqual(ChartData.merchantSuggestions(prefix: "bu", from: past), ["Starbucks", "Best Buy"])
        XCTAssertEqual(ChartData.merchantSuggestions(prefix: "", from: past, limit: 2), ["Starbucks", "Shell"])
        XCTAssertTrue(ChartData.merchantSuggestions(prefix: "zz", from: past).isEmpty)
    }
}
