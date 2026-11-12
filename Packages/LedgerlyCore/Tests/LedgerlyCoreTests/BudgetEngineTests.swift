#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif
import XCTest
@testable import LedgerlyCore

/// April 2026 has 30 days and four Mondays (6, 13, 20, 27). "Now" is usually April 15 at noon:
/// day 15, 16 days left (today included), 15 days remaining for projections.
final class BudgetEngineTests: XCTestCase {
    private let april = MonthKey(year: 2026, month: 4)
    private let now = T.date(2026, 4, 15)
    private var twoWeeks: [WeeklyEarning] { [T.earning("500", weekOf: T.date(2026, 4, 6)), T.earning("700", weekOf: T.date(2026, 4, 13))] }

    // MARK: Days

    func testDayCountsMidMonth() {
        let s = T.snapshot(april, now: now)
        XCTAssertEqual(s.daysInMonth, 30)
        XCTAssertEqual(s.dayOfMonth, 15)
        XCTAssertEqual(s.daysLeft, 16)
        XCTAssertTrue(s.isCurrentMonth)
        XCTAssertFalse(s.isPastMonth)
    }
    func testFirstDayOfMonth() {
        let first = T.date(2026, 4, 1, 0, 0, 0)
        let earnings = [2, 9, 16, 23, 30].map { T.earning("500", weekOf: T.date(2026, 3, $0)) }
        let s = T.snapshot(april, now: first, [T.tx("30", "Aldi", "groceries", on: first)], earnings: earnings)
        XCTAssertEqual(s.dayOfMonth, 1)
        XCTAssertEqual(s.daysLeft, 30)
        XCTAssertEqual(s.spent, T.d("30"))
        // No April history-month data (the March earnings are not transactions): 30 + 30/1 × 29.
        XCTAssertEqual(s.projectedSpending, T.d("900"))
        XCTAssertEqual(s.incomeBasis, .estimatedFromHistory)
        XCTAssertEqual(s.expectedIncome, T.d("2000"))
        // (2000 − 200 − 30) / 30
        XCTAssertEqual(s.safeToSpendPerDay, T.d("59"))
    }
    func testFirstDayOfMonthWithNothingYet() {
        let s = T.snapshot(april, now: T.date(2026, 4, 1, 0, 0, 0), earnings: twoWeeks)
        XCTAssertEqual(s.spent, T.d("0"))
        XCTAssertEqual(s.projectedSpending, T.d("0"))
        // (2400 − 200 − 0) / 30
        XCTAssertEqual(MoneyFormat.round(s.safeToSpendPerDay!), T.d("73.33"))
    }
    func testLastDayOfMonth() {
        let last = T.date(2026, 4, 30, 23, 59, 59)
        let s = T.snapshot(april, now: last, [T.tx("300", on: T.date(2026, 4, 10))], earnings: twoWeeks)
        XCTAssertEqual(s.dayOfMonth, 30)
        XCTAssertEqual(s.daysLeft, 1)
        XCTAssertEqual(s.projectedSpending, T.d("300"))
        XCTAssertEqual(s.safeToSpendPerDay, T.d("1900"))
    }
    func testPastMonthIsFullyElapsed() {
        let s = T.snapshot(april, now: T.date(2026, 5, 10), [T.tx("300", on: T.date(2026, 4, 10))], earnings: twoWeeks)
        XCTAssertTrue(s.isPastMonth)
        XCTAssertFalse(s.isCurrentMonth)
        XCTAssertEqual(s.dayOfMonth, 30)
        XCTAssertEqual(s.daysLeft, 0)
        XCTAssertEqual(s.projectedSpending, s.spent)
        XCTAssertEqual(s.projectedSavings, T.d("2100"))
        XCTAssertEqual(s.safeToSpendPerDay, T.d("0"))
        XCTAssertEqual(s.isOnTrack, true)
    }
    func testFutureMonth() {
        let may = MonthKey(year: 2026, month: 5)
        let s = T.snapshot(may, now: now, [T.tx("300", "Chipotle", "food", on: T.date(2026, 4, 10))], earnings: twoWeeks)
        XCTAssertEqual(s.dayOfMonth, 0)
        XCTAssertEqual(s.daysLeft, 31)
        XCTAssertEqual(s.spent, T.d("0"))
        XCTAssertEqual(s.historyMonthCount, 1)
        // Nothing spent yet, so the projection is last month's level.
        XCTAssertEqual(s.projectedSpending, T.d("300"))
        XCTAssertEqual(s.incomeBasis, .estimatedFromHistory)
    }

    // MARK: Income

    func testIncomeSoFarOnlyCountsWeeksWhoseMondayIsInTheMonth() {
        let earnings = twoWeeks + [T.earning("999", weekOf: T.date(2026, 3, 30)), T.earning("1", weekOf: T.date(2026, 5, 4))]
        let s = T.snapshot(april, now: now, earnings: earnings)
        XCTAssertEqual(s.incomeSoFar, T.d("1200"))
        XCTAssertEqual(s.enteredWeeks, 2)
        XCTAssertEqual(s.remainingWeeks, 2)
        XCTAssertEqual(s.totalWeeks, 4)
        XCTAssertEqual(s.averageWeeklyIncome, T.d("600"))
        XCTAssertEqual(s.expectedIncome, T.d("2400"))
        XCTAssertEqual(s.incomeBasis, .entered)
    }
    func testWeekStartingMarch30CountsTowardMarch() {
        // Monday March 30 – Sunday April 5: the earnings belong to March.
        let earnings = [T.earning("800", weekOf: T.date(2026, 4, 3))]
        let march = T.snapshot(MonthKey(year: 2026, month: 3), now: now, earnings: earnings)
        XCTAssertEqual(march.incomeSoFar, T.d("800"))
        let aprilSnapshot = T.snapshot(april, now: now, earnings: earnings)
        XCTAssertEqual(aprilSnapshot.incomeSoFar, T.d("0"))
        XCTAssertEqual(aprilSnapshot.incomeBasis, .estimatedFromHistory)
    }
    func testFiveMondayMonthExpectedIncome() {
        let march = MonthKey(year: 2026, month: 3)
        let earnings = [T.earning("500", weekOf: T.date(2026, 3, 2)), T.earning("700", weekOf: T.date(2026, 3, 9))]
        let s = T.snapshot(march, now: T.date(2026, 3, 12), earnings: earnings)
        XCTAssertEqual(s.totalWeeks, 5)
        XCTAssertEqual(s.remainingWeeks, 3)
        // 1200 + 600 × 3
        XCTAssertEqual(s.expectedIncome, T.d("3000"))
    }
    func testAllWeeksEntered() {
        let earnings = [6, 13, 20, 27].map { T.earning("610.25", weekOf: T.date(2026, 4, $0)) }
        let s = T.snapshot(april, now: T.date(2026, 4, 28), earnings: earnings)
        XCTAssertEqual(s.incomeSoFar, T.d("2441.00"))
        XCTAssertEqual(s.expectedIncome, T.d("2441.00"))
        XCTAssertEqual(s.remainingWeeks, 0)
    }
    func testEstimateFromHistoryUsesMostRecentEightWeeks() {
        // Ten earlier weeks: the newest eight are 400, the two oldest are 4000 and must be ignored.
        var earnings: [WeeklyEarning] = []
        var monday = T.date(2026, 3, 30, 0)
        for index in 0..<10 {
            earnings.append(WeeklyEarning(weekStart: monday, amount: index < 8 ? T.d("400") : T.d("4000")))
            monday = T.chicago.startOfDay(monday, addingDays: -7)
        }
        let s = T.snapshot(april, now: now, earnings: earnings)
        XCTAssertEqual(s.incomeBasis, .estimatedFromHistory)
        XCTAssertEqual(s.incomeSoFar, T.d("0"))
        XCTAssertEqual(s.averageWeeklyIncome, T.d("400"))
        XCTAssertEqual(s.expectedIncome, T.d("1600"))
        XCTAssertEqual(s.enteredWeeks, 0)
        XCTAssertEqual(s.remainingWeeks, 4)
    }
    func testUnknownIncomeLeavesDependentNumbersNil() {
        let s = T.snapshot(april, now: now, [T.tx("300", on: T.date(2026, 4, 10))])
        XCTAssertEqual(s.incomeBasis, .unknown)
        XCTAssertNil(s.expectedIncome)
        XCTAssertNil(s.projectedSavings)
        XCTAssertNil(s.safeToSpendPerDay)
        XCTAssertNil(s.isOnTrack)
        XCTAssertNil(s.gap)
        XCTAssertNil(s.goalProgress)
        XCTAssertNil(s.spendingBudget)
        XCTAssertNil(s.averageWeeklyIncome)
        // Spending is still reported.
        XCTAssertEqual(s.spent, T.d("300"))
        XCTAssertEqual(s.projectedSpending, T.d("600"))
    }
    func testOnlyFutureEarningsIsStillUnknown() {
        let s = T.snapshot(april, now: now, earnings: [T.earning("500", weekOf: T.date(2026, 5, 4))])
        XCTAssertEqual(s.incomeBasis, .unknown)
        XCTAssertNil(s.expectedIncome)
    }
    func testZeroEarningCountsAsEntered() {
        let s = T.snapshot(april, now: now, earnings: [T.earning("0", weekOf: T.date(2026, 4, 6))])
        XCTAssertEqual(s.incomeBasis, .entered)
        XCTAssertEqual(s.enteredWeeks, 1)
        XCTAssertEqual(s.expectedIncome, T.d("0"))
        XCTAssertEqual(s.safeToSpendPerDay, T.d("0"))
    }
    func testLaterEntryForTheSameWeekWins() {
        let earnings = [T.earning("500", weekOf: T.date(2026, 4, 6)), WeeklyEarning(weekStart: T.date(2026, 4, 8, 9), amount: T.d("650"))]
        let s = T.snapshot(april, now: now, earnings: earnings)
        XCTAssertEqual(s.incomeSoFar, T.d("650"))
        XCTAssertEqual(s.enteredWeeks, 1)
    }
    func testCentsInIncomeStayExact() {
        let earnings = [T.earning("512.37", weekOf: T.date(2026, 4, 6)), T.earning("498.13", weekOf: T.date(2026, 4, 13))]
        let s = T.snapshot(april, now: now, earnings: earnings)
        XCTAssertEqual(s.incomeSoFar, T.d("1010.50"))
        XCTAssertEqual(s.averageWeeklyIncome, T.d("505.25"))
        XCTAssertEqual(s.expectedIncome, T.d("2021.00"))
    }

    // MARK: Spending and refunds

    func testSpendingIsExpensesMinusRefunds() {
        let txs = [
            T.tx("50", "Chipotle", "food", on: T.date(2026, 4, 2)),
            T.tx("30.10", "Starbucks", "food", on: T.date(2026, 4, 3)),
            T.tx("-20.05", "Chipotle", "food", on: T.date(2026, 4, 4)),
            T.tx("40", "Aldi", "groceries", on: T.date(2026, 4, 5))
        ]
        let s = T.snapshot(april, now: now, txs)
        XCTAssertEqual(s.spent, T.d("100.05"))
        XCTAssertEqual(s.spentByCategory[T.id("food")], T.d("60.05"))
        XCTAssertEqual(s.spentByCategory[T.id("groceries")], T.d("40"))
        XCTAssertNil(s.spentByCategory[T.id("gas")])
    }
    func testRefundLargerThanCategorySpending() {
        let txs = [
            T.tx("30", "Target", "shopping", on: T.date(2026, 4, 2)),
            T.tx("-100", "Target", "shopping", on: T.date(2026, 4, 4)),
            T.tx("60", "Chipotle", "food", on: T.date(2026, 4, 5))
        ]
        let s = T.snapshot(april, now: now, txs, earnings: twoWeeks)
        // The category total really is negative, and it lowers the month's spending.
        XCTAssertEqual(s.spentByCategory[T.id("shopping")], T.d("-70"))
        XCTAssertEqual(s.spent, T.d("-10"))
        // A negative total is not extrapolated: shopping stays at −70, food doubles to 120.
        XCTAssertEqual(s.projectedByCategory[T.id("shopping")], T.d("-70"))
        XCTAssertEqual(s.projectedByCategory[T.id("food")], T.d("120"))
        XCTAssertEqual(s.projectedSpending, T.d("50"))
        // (2400 − 200 − (−10)) / 16
        XCTAssertEqual(s.safeToSpendPerDay, T.d("138.125"))
    }
    func testRefundOnlyMonth() {
        let s = T.snapshot(april, now: now, [T.tx("-45.50", "Amazon", "shopping", on: T.date(2026, 4, 2))], earnings: twoWeeks)
        XCTAssertEqual(s.spent, T.d("-45.50"))
        XCTAssertEqual(s.projectedSpending, T.d("-45.50"))
        XCTAssertEqual(s.projectedSavings, T.d("2445.50"))
    }
    func testUncategorizedAndUnknownCategoriesCountAsOther() {
        let txs = [
            T.tx("10", "Mystery", nil, on: T.date(2026, 4, 2)),
            TransactionRecord(amount: T.d("5"), merchant: "Gone", categoryID: UUID(), date: T.date(2026, 4, 3), createdAt: T.date(2026, 4, 3)),
            T.tx("2", "Misc", "other", on: T.date(2026, 4, 4))
        ]
        let s = T.snapshot(april, now: now, txs)
        XCTAssertEqual(s.spentByCategory, [T.id("other"): T.d("17")])
    }
    func testArchivedCategoryStillCountsUnderItsOwnID() {
        var categories = T.categories
        let pets = CategoryRecord(name: "Pets", colorHex: "#123456", symbolName: "pawprint.fill", sortOrder: 10, isArchived: true)
        categories.append(pets)
        let tx = TransactionRecord(amount: T.d("25"), merchant: "Vet", categoryID: pets.id, date: T.date(2026, 4, 3), createdAt: now)
        let s = T.snapshot(april, now: now, [tx], categories: categories)
        XCTAssertEqual(s.spentByCategory, [pets.id: T.d("25")])
    }
    func testZeroAmountReviewItemsDoNotChangeSpending() {
        let txs = [T.tx("0", "Shell", "gas", on: T.date(2026, 4, 2), needsReview: true), T.tx("12", "Shell", "gas", on: T.date(2026, 4, 3))]
        XCTAssertEqual(T.snapshot(april, now: now, txs).spent, T.d("12"))
    }
    func testMonthBoundariesAreExact() {
        let txs = [
            T.tx("1", on: T.date(2026, 3, 31, 23, 59, 59)),
            T.tx("2", on: T.date(2026, 4, 1, 0, 0, 0)),
            T.tx("4", on: T.date(2026, 4, 30, 23, 59, 59)),
            T.tx("8", on: T.date(2026, 5, 1, 0, 0, 0))
        ]
        XCTAssertEqual(T.snapshot(april, now: now, txs).spent, T.d("6"))
        XCTAssertEqual(T.snapshot(MonthKey(year: 2026, month: 3), now: now, txs).spent, T.d("1"))
        XCTAssertEqual(T.snapshot(MonthKey(year: 2026, month: 5), now: T.date(2026, 5, 2), txs).spent, T.d("8"))
    }
    func testVeryLargeAmounts() {
        let tenth = T.date(2026, 4, 10)
        let txs = [T.tx("99999999999.99", "Yacht", "shopping", on: T.date(2026, 4, 2)), T.tx("0.01", "Gum", "shopping", on: T.date(2026, 4, 3))]
        let s = T.snapshot(april, now: tenth, txs, earnings: twoWeeks)
        XCTAssertEqual(s.spent, T.d("100000000000.00"))
        // Day 10 of 30, no history: spent + spent/10 × 20.
        XCTAssertEqual(s.projectedSpending, T.d("300000000000.00"))
        XCTAssertEqual(s.projectedSavings, T.d("-299999997600.00"))
        XCTAssertEqual(s.safeToSpendPerDay, T.d("0"))
        XCTAssertEqual(s.isOnTrack, false)
        XCTAssertEqual(s.gap, T.d("299999997800.00"))
        XCTAssertEqual(s.goalProgress, T.d("0"))
    }
    func testVeryLargeAmountWithCentsIsNotRounded() {
        let s = T.snapshot(april, now: T.date(2026, 4, 10), [T.tx("99999999999.99", on: T.date(2026, 4, 2))])
        XCTAssertEqual(s.spent, T.d("99999999999.99"))
        // 99999999999.99 + 9999999999.999 × 20
        XCTAssertEqual(s.projectedSpending, T.d("299999999999.97"))
    }

    // MARK: Safe to spend

    func testSafeToSpendPerDay() {
        let s = T.snapshot(april, now: now, [T.tx("300", on: T.date(2026, 4, 10))], earnings: twoWeeks)
        // (2400 − 200 − 300) / 16
        XCTAssertEqual(s.safeToSpendPerDay, T.d("118.75"))
        XCTAssertEqual(s.spendingBudget, T.d("2200"))
        XCTAssertEqual(s.remainingBudget, T.d("1900"))
        XCTAssertEqual(s.savedSoFar, T.d("900"))
    }
    func testSafeToSpendIsFlooredAtZero() {
        let s = T.snapshot(april, now: now, [T.tx("2500", on: T.date(2026, 4, 10))], earnings: twoWeeks)
        XCTAssertEqual(s.safeToSpendPerDay, T.d("0"))
        XCTAssertEqual(s.remainingBudget, T.d("-300"))
    }
    func testSafeToSpendWithGoalAboveIncome() {
        let s = T.snapshot(april, now: now, earnings: twoWeeks, goal: "5000")
        XCTAssertEqual(s.safeToSpendPerDay, T.d("0"))
    }
    func testSafeToSpendCountsTodayAsADayLeft() {
        // April 30: one day left, the whole remaining budget is today's.
        let s = T.snapshot(april, now: T.date(2026, 4, 30, 9), [T.tx("2000", on: T.date(2026, 4, 10))], earnings: twoWeeks)
        XCTAssertEqual(s.safeToSpendPerDay, T.d("200"))
    }

    // MARK: Projection

    func testProjectionWithoutHistoryIsPurePace() {
        let s = T.snapshot(april, now: now, [T.tx("300", "Chipotle", "food", on: T.date(2026, 4, 10))], earnings: twoWeeks)
        XCTAssertFalse(s.hasHistory)
        // 300 + (300 / 15) × 15
        XCTAssertEqual(s.projectedSpending, T.d("600"))
        XCTAssertEqual(s.projectedByCategory[T.id("food")], T.d("600"))
        XCTAssertEqual(s.projectedSavings, T.d("1800"))
        XCTAssertEqual(s.isOnTrack, true)
        XCTAssertEqual(s.gap, T.d("0"))
        XCTAssertEqual(s.goalProgress, T.d("1"))
        XCTAssertTrue(s.trailingAverageByCategory.isEmpty)
    }
    func testProjectionBlendsPaceWithHistory() {
        let txs = [
            T.tx("600", "Chipotle", "food", on: T.date(2026, 3, 10)),
            T.tx("150", "Chipotle", "food", on: T.date(2026, 4, 10))
        ]
        let s = T.snapshot(april, now: now, txs)
        XCTAssertEqual(s.historyMonthCount, 1)
        XCTAssertEqual(s.trailingAverageByCategory[T.id("food")], T.d("600"))
        // pace 10/day, history 20/day, weight 0.5 → 150 + (5 + 10) × 15
        XCTAssertEqual(s.projectedByCategory[T.id("food")], T.d("375"))
        XCTAssertEqual(s.usualByThisDayByCategory[T.id("food")], T.d("300"))
    }
    func testProjectionLeansOnHistoryEarlyInTheMonth() {
        // Day 3 of 30: weight 0.1. pace 30/3 = 10, history 600/30 = 20 → 30 + (1 + 18) × 27.
        let txs = [T.tx("600", "Aldi", "groceries", on: T.date(2026, 3, 10)), T.tx("30", "Aldi", "groceries", on: T.date(2026, 4, 2))]
        let s = T.snapshot(april, now: T.date(2026, 4, 3), txs)
        XCTAssertEqual(s.projectedByCategory[T.id("groceries")], T.d("543"))
    }
    func testCategoryOnlyInHistoryIsStillProjected() {
        let txs = [T.tx("600", "ComEd", "bills", on: T.date(2026, 3, 10)), T.tx("150", "Chipotle", "food", on: T.date(2026, 4, 10))]
        let s = T.snapshot(april, now: now, txs)
        // Nothing spent on bills yet: 0 + (0 + 0.5 × 20) × 15
        XCTAssertEqual(s.projectedByCategory[T.id("bills")], T.d("150"))
        // Food has no history: 150 + (0.5 × 10 + 0) × 15
        XCTAssertEqual(s.projectedByCategory[T.id("food")], T.d("225"))
        XCTAssertEqual(s.projectedSpending, T.d("375"))
    }
    func testTrailingAverageDividesByMonthsThatHaveData() {
        let txs = [
            T.tx("5000", "Old", "food", on: T.date(2025, 12, 10)),       // four months back: ignored
            T.tx("900", "Chipotle", "food", on: T.date(2026, 1, 10)),
            // February: nothing at all
            T.tx("300", "Chipotle", "food", on: T.date(2026, 3, 10)),
            T.tx("90", "Shell", "gas", on: T.date(2026, 3, 11))
        ]
        let s = T.snapshot(april, now: now, txs)
        XCTAssertEqual(s.historyMonthCount, 2)
        XCTAssertEqual(s.trailingAverageByCategory[T.id("food")], T.d("600"))
        // Gas appears in one of the two months that have data → 90 / 2.
        XCTAssertEqual(s.trailingAverageByCategory[T.id("gas")], T.d("45"))
        XCTAssertEqual(s.usualByThisDayByCategory[T.id("food")], T.d("300"))
        XCTAssertEqual(s.usualByThisDayByCategory[T.id("gas")], T.d("22.5"))
    }
    func testThreeMonthsOfHistory() {
        let txs = [
            T.tx("100", "A", "food", on: T.date(2026, 1, 10)),
            T.tx("200", "A", "food", on: T.date(2026, 2, 10)),
            T.tx("600", "A", "food", on: T.date(2026, 3, 10))
        ]
        let s = T.snapshot(april, now: now, txs)
        XCTAssertEqual(s.historyMonthCount, 3)
        XCTAssertEqual(s.trailingAverageByCategory[T.id("food")], T.d("300"))
    }
    func testHistoryAcrossYearBoundary() {
        let january = MonthKey(year: 2026, month: 1)
        let txs = [T.tx("310", "A", "food", on: T.date(2025, 12, 20)), T.tx("620", "A", "food", on: T.date(2025, 10, 5))]
        let s = T.snapshot(january, now: T.date(2026, 1, 15), txs)
        XCTAssertEqual(s.historyMonthCount, 2)
        XCTAssertEqual(s.trailingAverageByCategory[T.id("food")], T.d("465"))
    }
    func testRefundsLowerTheHistoricalAverage() {
        let txs = [T.tx("400", "Target", "shopping", on: T.date(2026, 3, 10)), T.tx("-100", "Target", "shopping", on: T.date(2026, 3, 12))]
        XCTAssertEqual(T.snapshot(april, now: now, txs).trailingAverageByCategory[T.id("shopping")], T.d("300"))
    }

    // MARK: Savings and goal

    func testProjectedSavingsBelowGoal() {
        // Spent 1150 by day 15 with no history → projected 2300; income 2400 → savings 100.
        let s = T.snapshot(april, now: now, [T.tx("1150", on: T.date(2026, 4, 10))], earnings: twoWeeks)
        XCTAssertEqual(s.projectedSavings, T.d("100"))
        XCTAssertEqual(s.isOnTrack, false)
        XCTAssertEqual(s.gap, T.d("100"))
        XCTAssertEqual(s.goalProgress, T.d("0.5"))
        XCTAssertEqual(s.goalProgressValue, 0.5)
    }
    func testProjectedSavingsExactlyAtGoalIsOnTrack() {
        let s = T.snapshot(april, now: now, [T.tx("1100", on: T.date(2026, 4, 10))], earnings: twoWeeks)
        XCTAssertEqual(s.projectedSavings, T.d("200"))
        XCTAssertEqual(s.isOnTrack, true)
        XCTAssertEqual(s.goalProgress, T.d("1"))
    }
    func testNegativeProjectedSavings() {
        let s = T.snapshot(april, now: now, [T.tx("1500", on: T.date(2026, 4, 10))], earnings: twoWeeks)
        XCTAssertEqual(s.projectedSavings, T.d("-600"))
        XCTAssertEqual(s.goalProgress, T.d("0"))
        XCTAssertEqual(s.gap, T.d("800"))
    }
    func testZeroGoal() {
        let s = T.snapshot(april, now: now, [T.tx("300", on: T.date(2026, 4, 10))], earnings: twoWeeks, goal: "0")
        XCTAssertEqual(s.goalProgress, T.d("1"))
        XCTAssertEqual(s.isOnTrack, true)
        XCTAssertEqual(s.safeToSpendPerDay, T.d("131.25"))
    }
    func testEmptyMonth() {
        let s = T.snapshot(april, now: now)
        XCTAssertTrue(s.isEmpty)
        XCTAssertEqual(s.spent, T.d("0"))
        XCTAssertEqual(s.projectedSpending, T.d("0"))
        XCTAssertTrue(s.spentByCategory.isEmpty)
    }

    // MARK: Time zones and daylight saving

    func testSameInstantLandsInDifferentMonthsByTimeZone() {
        // 03:00 UTC on May 1 is 22:00 on April 30 in Chicago.
        let instant = T.date(2026, 5, 1, 3, 0, calendar: T.utc)
        let tx = TransactionRecord(amount: T.d("40"), merchant: "Late", date: instant, createdAt: instant)
        let later = T.date(2026, 5, 2, 12, 0, calendar: T.utc)
        XCTAssertEqual(T.snapshot(april, now: later, [tx], calendar: T.chicago).spent, T.d("40"))
        XCTAssertEqual(T.snapshot(april, now: later, [tx], calendar: T.utc).spent, T.d("0"))
        XCTAssertEqual(T.snapshot(MonthKey(year: 2026, month: 5), now: later, [tx], calendar: T.utc).spent, T.d("40"))
    }
    func testSpringForwardMonth() {
        // March 2026 loses an hour on the 8th but still has 31 days.
        let march = MonthKey(year: 2026, month: 3)
        let txs = [
            T.tx("10", on: T.date(2026, 3, 8, 1, 59)),
            T.tx("20", on: T.date(2026, 3, 8, 3, 0)),
            T.tx("30", on: T.date(2026, 3, 31, 23, 59, 59))
        ]
        let s = T.snapshot(march, now: T.date(2026, 3, 8, 23, 30), txs)
        XCTAssertEqual(s.daysInMonth, 31)
        XCTAssertEqual(s.dayOfMonth, 8)
        XCTAssertEqual(s.daysLeft, 24)
        XCTAssertEqual(s.spent, T.d("60"))
    }
    func testFallBackMonth() {
        // November 1, 2026 is 25 hours long; 23:30 that day is still day 1, and a week whose Monday is
        // November 2 starts at local midnight even though the offset changed.
        let november = MonthKey(year: 2026, month: 11)
        let earnings = [T.earning("500", weekOf: T.date(2026, 11, 2)), T.earning("900", weekOf: T.date(2026, 10, 26))]
        let txs = [T.tx("15", on: T.date(2026, 11, 1, 23, 30)), T.tx("99", on: T.date(2026, 10, 31, 23, 59, 59))]
        let s = T.snapshot(november, now: T.date(2026, 11, 1, 23, 45), txs, earnings: earnings)
        XCTAssertEqual(s.dayOfMonth, 1)
        XCTAssertEqual(s.daysLeft, 30)
        XCTAssertEqual(s.spent, T.d("15"))
        XCTAssertEqual(s.totalWeeks, 5)
        // The October 26 week (which contains November 1) belongs to October.
        XCTAssertEqual(s.incomeSoFar, T.d("500"))
        XCTAssertEqual(s.expectedIncome, T.d("2500"))
    }
    func testEarningStoredInAnotherOffsetStillMatchesItsWeek() {
        // A week start saved as "Monday 00:00 CST" before the clocks changed must still match in CDT season and vice versa.
        let stored = T.date(2026, 3, 9, 0)      // first Monday after spring forward
        let s = T.snapshot(MonthKey(year: 2026, month: 3), now: T.date(2026, 3, 20), earnings: [WeeklyEarning(weekStart: stored, amount: T.d("700"))])
        XCTAssertEqual(s.incomeSoFar, T.d("700"))
        XCTAssertEqual(s.enteredWeeks, 1)
    }

    // MARK: Helpers

    func testIncomeEstimateDirectly() {
        let estimate = BudgetEngine.incomeEstimate(month: april, earnings: twoWeeks, calendar: T.chicago)
        XCTAssertEqual(estimate.soFar, T.d("1200"))
        XCTAssertEqual(estimate.expected, T.d("2400"))
        XCTAssertEqual(estimate.basis, .entered)
    }
    func testTransactionsInMonthAndEffectiveCategory() {
        let txs = [T.tx("1", on: T.date(2026, 3, 31)), T.tx("2", on: T.date(2026, 4, 1)), T.tx("3", on: T.date(2026, 4, 30))]
        XCTAssertEqual(BudgetEngine.transactions(in: april, from: txs, calendar: T.chicago).map { $0.amount }, [T.d("2"), T.d("3")])
        XCTAssertEqual(BudgetEngine.effectiveCategoryID(nil, categories: T.categories), T.id("other"))
        XCTAssertEqual(BudgetEngine.effectiveCategoryID(T.id("gas"), categories: T.categories), T.id("gas"))
    }
    func testSnapshotIsDeterministic() {
        let txs = (1...15).map { T.tx("\($0).37", "M\($0)", ["food", "gas", "shopping"][$0 % 3], on: T.date(2026, 4, $0)) }
        XCTAssertEqual(T.snapshot(april, now: now, txs, earnings: twoWeeks), T.snapshot(april, now: now, txs.reversed(), earnings: twoWeeks.reversed()))
    }
}
