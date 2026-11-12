import Foundation
import XCTest
@testable import LedgerlyCore

/// "Now" is April 15, 2026 (day 15 of 30). With no history, projections are exactly double what is spent so far.
final class InsightsEngineTests: XCTestCase {
    private let april = MonthKey(year: 2026, month: 4)
    private let now = T.date(2026, 4, 15)
    private var income2000: [WeeklyEarning] { [T.earning("500", weekOf: T.date(2026, 4, 6)), T.earning("500", weekOf: T.date(2026, 4, 13))] }

    private func insights(
        _ txs: [TransactionRecord], earnings: [WeeklyEarning] = [], goal: String = "200",
        month: MonthKey? = nil, now: Date? = nil, categories: [CategoryRecord] = T.categories
    ) -> [Insight] {
        InsightsEngine.insights(
            month: month ?? april, now: now ?? self.now, transactions: txs, earnings: earnings, goal: T.d(goal),
            categories: categories, calendar: T.chicago, locale: T.us, currencyCode: "USD"
        )
    }
    private func plan(_ txs: [TransactionRecord], earnings: [WeeklyEarning], goal: String = "200", now: Date? = nil, categories: [CategoryRecord] = T.categories) -> GapPlan? {
        let snapshot = T.snapshot(april, now: now ?? self.now, txs, earnings: earnings, goal: goal, categories: categories)
        return InsightsEngine.gapPlan(snapshot: snapshot, transactions: txs, categories: categories, calendar: T.chicago, locale: T.us)
    }
    private func sum(_ plan: GapPlan) -> Decimal { plan.cuts.reduce(Decimal(0)) { $0 + $1.amount } }

    // MARK: Over pace / under usual

    func testOverPaceCategoryCopy() {
        let txs = [T.tx("440", "Chipotle", "food", on: T.date(2026, 3, 10)), T.tx("308", "Chipotle", "food", on: T.date(2026, 4, 10))]
        let card = insights(txs).first { $0.kind == .overPace }
        XCTAssertEqual(card?.body, "Food & Dining is at $308, 40% above your usual $220 by this point in the month.")
        XCTAssertEqual(card?.amount, T.d("88"))
        XCTAssertEqual(card?.categoryID, T.id("food"))
        XCTAssertEqual(card?.sentiment, .warning)
        XCTAssertEqual(card?.title, "Food & Dining is running high")
    }
    func testNotOverPaceBelowFifteenPercent() {
        // 250 vs usual 220 is 13.6 % over.
        let txs = [T.tx("440", "A", "food", on: T.date(2026, 3, 10)), T.tx("250", "A", "food", on: T.date(2026, 4, 10))]
        XCTAssertFalse(insights(txs).contains { $0.kind == .overPace })
    }
    func testOverPaceAtExactlyFifteenPercent() {
        // 253 vs usual 220 is exactly 15 % and $33 over.
        let txs = [T.tx("440", "A", "food", on: T.date(2026, 3, 10)), T.tx("253", "A", "food", on: T.date(2026, 4, 10))]
        XCTAssertTrue(insights(txs).contains { $0.kind == .overPace })
    }
    func testNotOverPaceWhenLessThanTenDollarsOver() {
        // 28 vs usual 20 is 40 % over but only $8.
        let txs = [T.tx("40", "A", "food", on: T.date(2026, 3, 10)), T.tx("28", "A", "food", on: T.date(2026, 4, 10))]
        XCTAssertFalse(insights(txs).contains { $0.kind == .overPace })
    }
    func testOverPaceUsesTimesWordingWhenFarOver() {
        let txs = [T.tx("40", "A", "shopping", on: T.date(2026, 3, 10)), T.tx("110", "A", "shopping", on: T.date(2026, 4, 10))]
        XCTAssertEqual(
            insights(txs).first { $0.kind == .overPace }?.body,
            "Shopping is at $110, about 5.5 times your usual $20 by this point in the month."
        )
    }
    func testNoPaceInsightsWithoutHistory() {
        let cards = insights([T.tx("500", "A", "food", on: T.date(2026, 4, 10))])
        XCTAssertFalse(cards.contains { $0.kind == .overPace || $0.kind == .underUsual })
    }
    func testBillsAndSubscriptionsAreNotPaceCheckedMidMonth() {
        // A bill that is charged on the 3rd is not "over pace" on the 15th.
        let txs = [
            T.tx("100", "ComEd", "bills", on: T.date(2026, 3, 3)), T.tx("100", "ComEd", "bills", on: T.date(2026, 4, 3)),
            T.tx("30", "Netflix", "subscriptions", on: T.date(2026, 3, 3)), T.tx("30", "Netflix", "subscriptions", on: T.date(2026, 4, 3))
        ]
        XCTAssertFalse(insights(txs).contains { $0.kind == .overPace })
        // …but a finished month is compared in full.
        let past = [T.tx("100", "ComEd", "bills", on: T.date(2026, 3, 3)), T.tx("150", "ComEd", "bills", on: T.date(2026, 4, 3))]
        let card = insights(past, now: T.date(2026, 5, 10)).first { $0.kind == .overPace }
        XCTAssertEqual(card?.body, "Bills & Utilities came to $150 in April, 50% above your usual $100.")
    }
    func testAtMostThreeOverPaceCardsLargestFirst() {
        var txs: [TransactionRecord] = []
        for (key, over) in [("food", "300"), ("shopping", "500"), ("recreation", "200"), ("gas", "400"), ("groceries", "250")] {
            txs.append(T.tx("100", "M", key, on: T.date(2026, 3, 10)))     // usual by day 15 = 50
            txs.append(T.tx(over, "M", key, on: T.date(2026, 4, 10)))
        }
        let cards = insights(txs).filter { $0.kind == .overPace }
        XCTAssertEqual(cards.map { $0.categoryID }, [T.id("shopping"), T.id("gas"), T.id("food")])
        XCTAssertEqual(cards.map { $0.amount }, [T.d("450"), T.d("350"), T.d("250")])
    }
    func testUnderUsualIsPositiveReinforcement() {
        let txs = [T.tx("400", "Aldi", "groceries", on: T.date(2026, 3, 10)), T.tx("100", "Aldi", "groceries", on: T.date(2026, 4, 10))]
        let card = insights(txs).first { $0.kind == .underUsual }
        XCTAssertEqual(card?.body, "Groceries is at $100, 50% below your usual $200 by this point in the month. Nice work.")
        XCTAssertEqual(card?.sentiment, .positive)
        XCTAssertEqual(card?.amount, T.d("100"))
    }
    func testUnderUsualWithNothingSpent() {
        let txs = [T.tx("400", "Shell", "gas", on: T.date(2026, 3, 10)), T.tx("5", "X", "other", on: T.date(2026, 4, 10))]
        XCTAssertEqual(
            insights(txs).first { $0.kind == .underUsual }?.body,
            "You haven't spent anything on Gas this month. You've usually spent $200 by now. Nice work."
        )
    }
    func testUnderUsualNeedsAWeekOfData() {
        let txs = [T.tx("400", "Aldi", "groceries", on: T.date(2026, 3, 10)), T.tx("10", "Aldi", "groceries", on: T.date(2026, 4, 2))]
        XCTAssertFalse(insights(txs, now: T.date(2026, 4, 6)).contains { $0.kind == .underUsual })
        XCTAssertTrue(insights(txs, now: T.date(2026, 4, 7)).contains { $0.kind == .underUsual })
    }

    // MARK: Income and goal

    func testUnknownIncomeAsksForEarningsInsteadOfGuessing() {
        let cards = insights([T.tx("310", "Chipotle", "food", on: T.date(2026, 4, 10))])
        XCTAssertEqual(cards.first?.kind, .missingIncome)
        XCTAssertEqual(cards.first?.title, "Add your earnings")
        XCTAssertEqual(cards.first?.body, "Add your weekly earnings to see projected savings and a safe-to-spend number. So far you've spent $310 this month.")
        XCTAssertFalse(cards.contains { $0.kind == .gapPlan || $0.kind == .goalOnTrack || $0.kind == .goalMissed })
    }
    func testUnknownIncomeWithNoSpending() {
        let cards = insights([])
        XCTAssertEqual(cards.map { $0.kind }, [.missingIncome])
        XCTAssertEqual(cards[0].body, "Add your weekly earnings to see projected savings and a safe-to-spend number.")
    }
    func testEstimatedIncomeNotice() {
        let earnings = [T.earning("500", weekOf: T.date(2026, 3, 23)), T.earning("700", weekOf: T.date(2026, 3, 30))]
        let card = insights([], earnings: earnings).first { $0.kind == .incomeEstimated }
        XCTAssertEqual(card?.body, "No earnings entered for April yet, so income is estimated at $2,400 from your recent weeks. Enter a week to firm it up.")
        XCTAssertEqual(card?.amount, T.d("2400"))
    }
    func testGoalOnTrack() {
        // Spent 310 → projected 620; income 2000 → savings 1380.
        let cards = insights([T.tx("310", "Chipotle", "food", on: T.date(2026, 4, 10))], earnings: income2000)
        let card = cards.first { $0.kind == .goalOnTrack }
        XCTAssertEqual(card?.body, "You're on track to save $1,380 this month, $1,180 over your $200 goal.")
        XCTAssertEqual(card?.sentiment, .positive)
        XCTAssertEqual(card?.amount, T.d("1380"))
        XCTAssertFalse(cards.contains { $0.kind == .gapPlan })
    }
    func testGoalExactlyMet() {
        let cards = insights([T.tx("900", "Rent", "bills", on: T.date(2026, 4, 10))], earnings: income2000)
        XCTAssertEqual(cards.first { $0.kind == .goalOnTrack }?.body, "You're on track to save $200 this month, right at your $200 goal.")
    }
    func testPastMonthGoalMet() {
        let cards = insights([T.tx("1750", "Rent", "bills", on: T.date(2026, 4, 10))], earnings: income2000, now: T.date(2026, 5, 10))
        XCTAssertEqual(cards.first { $0.kind == .goalOnTrack }?.body, "You saved $250 in April, $50 over your $200 goal.")
        XCTAssertFalse(cards.contains { $0.kind == .gapPlan })
    }
    func testPastMonthGoalMissed() {
        let cards = insights([T.tx("1880", "Rent", "bills", on: T.date(2026, 4, 10))], earnings: income2000, now: T.date(2026, 5, 10))
        let card = cards.first { $0.kind == .goalMissed }
        XCTAssertEqual(card?.body, "You saved $120 in April, $80 short of your $200 goal.")
        XCTAssertEqual(card?.sentiment, .warning)
        XCTAssertFalse(cards.contains { $0.kind == .gapPlan })
    }
    func testPastMonthOverspent() {
        let cards = insights([T.tx("2080", "Rent", "bills", on: T.date(2026, 4, 10))], earnings: income2000, now: T.date(2026, 5, 10))
        XCTAssertEqual(cards.first { $0.kind == .goalMissed }?.body, "You spent $80 more than you earned in April, missing your $200 goal by $280.")
    }

    // MARK: Gap plan

    /// March is exactly twice April-so-far in every category, so projections are exactly double what is spent.
    private var specExample: [TransactionRecord] {
        [
            T.tx("180", "Chipotle", "food", on: T.date(2026, 3, 10)),
            T.tx("120", "Target", "shopping", on: T.date(2026, 3, 11)),
            T.tx("12", "Spotify", "subscriptions", on: T.date(2026, 3, 14)),
            T.tx("18", "Netflix", "subscriptions", on: T.date(2026, 3, 8)),
            T.tx("30", "Hulu", "subscriptions", on: T.date(2026, 3, 25)),
            T.tx("1530", "Rent", "bills", on: T.date(2026, 3, 1)),
            T.tx("90", "Chipotle", "food", on: T.date(2026, 4, 10)),
            T.tx("60", "Target", "shopping", on: T.date(2026, 4, 11)),
            T.tx("12", "Spotify", "subscriptions", on: T.date(2026, 4, 14)),
            T.tx("18", "Netflix", "subscriptions", on: T.date(2026, 4, 8)),
            T.tx("765", "Rent", "bills", on: T.date(2026, 4, 1))
        ]
    }

    func testGapPlanMatchesTheSpecExample() {
        let snapshot = T.snapshot(april, now: now, specExample, earnings: income2000)
        XCTAssertEqual(snapshot.projectedSpending, T.d("1890"))
        XCTAssertEqual(snapshot.projectedSavings, T.d("110"))

        let card = insights(specExample, earnings: income2000).first { $0.kind == .gapPlan }
        XCTAssertEqual(card?.body, "To hit $200: cut dining out by $45, shopping by $30, and pause one subscription ($15).")
        XCTAssertEqual(card?.title, "How to hit $200")
        XCTAssertEqual(card?.amount, T.d("90"))
        XCTAssertEqual(card?.sentiment, .warning)

        let plan = card!.gapPlan!
        XCTAssertEqual(plan.gap, T.d("90"))
        XCTAssertEqual(plan.cuts.map { $0.categoryID }, [T.id("food"), T.id("shopping"), T.id("subscriptions")])
        XCTAssertEqual(plan.cuts.map { $0.amount }, [T.d("45"), T.d("30"), T.d("15")])
        XCTAssertEqual(plan.cuts.map { $0.note }, ["Cut dining out by $45", "Cut shopping by $30", "Pause one subscription ($15)"])
        XCTAssertEqual(plan.cuts.map { $0.categoryName }, ["Food & Dining", "Shopping", "Subscriptions"])
        XCTAssertEqual(plan.cuts[2].suggestion, "Spotify is $12.00 a month.")
        XCTAssertEqual(sum(plan), T.d("90"))
        XCTAssertEqual(plan.totalCuts, plan.gap)
        XCTAssertEqual(plan.uncovered, T.d("0"))
        XCTAssertTrue(plan.closesGap)
    }
    func testGapPlanCutsAddUpToTheGapToTheCent() {
        // No history: projected = 2 × spent. Spent 1000 → projected 2000 → savings 0 → gap 200.
        let txs = [
            T.tx("300", "Chipotle", "food", on: T.date(2026, 4, 3)),
            T.tx("200", "Target", "shopping", on: T.date(2026, 4, 4)),
            T.tx("100", "AMC", "recreation", on: T.date(2026, 4, 5)),
            T.tx("50", "Netflix", "subscriptions", on: T.date(2026, 4, 6)),
            T.tx("300", "ComEd", "bills", on: T.date(2026, 4, 7)),
            T.tx("50", "CVS", "health", on: T.date(2026, 4, 8))
        ]
        let plan = plan(txs, earnings: income2000)!
        XCTAssertEqual(plan.gap, T.d("200"))
        // 200 split 300 : 200 : 100 : 50 → 92.3077, 61.5385, 30.7692, 15.3846
        XCTAssertEqual(plan.cuts.map { $0.amount }, [T.d("92.31"), T.d("61.54"), T.d("30.77"), T.d("15.38")])
        XCTAssertEqual(sum(plan), T.d("200.00"))
        XCTAssertEqual(plan.uncovered, T.d("0"))
        let body = insights(txs, earnings: income2000).first { $0.kind == .gapPlan }?.body
        XCTAssertEqual(body, "To hit $200: cut dining out by $92.31, shopping by $61.54, recreation by $30.77, and subscriptions by $15.38.")
    }
    func testRoundingRemainderGoesToTheLargestCut() {
        // Three equal categories and a gap of 100: 33.33 × 3 = 99.99, the last cent goes to the first (largest, tie → first).
        let txs = [
            T.tx("450", "Chipotle", "food", on: T.date(2026, 4, 3)),
            T.tx("450", "Target", "shopping", on: T.date(2026, 4, 4)),
            T.tx("50", "AMC", "recreation", on: T.date(2026, 4, 5)),
            T.tx("0.01", "X", "recreation", on: T.date(2026, 4, 5))
        ]
        // spent 950.01 → projected 1900.02 → savings 99.98 → gap 100.02
        let plan = plan(txs, earnings: income2000)!
        XCTAssertEqual(plan.gap, T.d("100.02"))
        XCTAssertEqual(sum(plan), T.d("100.02"))
        XCTAssertEqual(InsightsEngine.allocate(target: T.d("100"), capacities: [T.d("50"), T.d("50"), T.d("50")]), [T.d("33.34"), T.d("33.33"), T.d("33.33")])
    }
    func testProtectedAndEssentialCategoriesAreNeverCut() {
        let txs = [
            T.tx("500", "ComEd", "bills", on: T.date(2026, 4, 3)),
            T.tx("200", "CVS", "health", on: T.date(2026, 4, 4)),
            T.tx("150", "Aldi", "groceries", on: T.date(2026, 4, 5)),
            T.tx("80", "Shell", "gas", on: T.date(2026, 4, 6)),
            T.tx("40", "Ventra", "transportation", on: T.date(2026, 4, 6)),
            T.tx("20", "Misc", "other", on: T.date(2026, 4, 6)),
            T.tx("60", "Chipotle", "food", on: T.date(2026, 4, 7))
        ]
        // spent 1050 → projected 2100 → savings −100 → gap 300; only food (60) can be cut.
        let plan = plan(txs, earnings: income2000)!
        XCTAssertEqual(plan.gap, T.d("300"))
        XCTAssertEqual(plan.cuts.map { $0.categoryID }, [T.id("food")])
        XCTAssertEqual(plan.cuts[0].amount, T.d("60"))
        XCTAssertEqual(plan.uncovered, T.d("240"))
        XCTAssertFalse(plan.closesGap)
    }
    func testShortfallIsReportedHonestly() {
        let txs = [T.tx("1900", "Rent", "bills", on: T.date(2026, 4, 1)), T.tx("50", "Chipotle", "food", on: T.date(2026, 4, 7))]
        // spent 1950 → projected 3900 → savings −1900 → gap 2100; cuttable 50.
        let card = insights(txs, earnings: income2000).first { $0.kind == .gapPlan }!
        XCTAssertEqual(card.gapPlan?.gap, T.d("2100"))
        XCTAssertEqual(card.gapPlan?.totalCuts, T.d("50"))
        XCTAssertEqual(card.gapPlan?.uncovered, T.d("2050"))
        XCTAssertEqual(card.body, "To hit $200: cut dining out by $50. That still leaves $2,050 to find; the rest is already spent or goes to essentials.")
    }
    func testNothingLeftToCut() {
        let txs = [T.tx("1900", "Rent", "bills", on: T.date(2026, 4, 1))]
        let card = insights(txs, earnings: income2000).first { $0.kind == .gapPlan }!
        XCTAssertEqual(card.gapPlan?.cuts.count, 0)
        XCTAssertEqual(card.gapPlan?.uncovered, T.d("2000"))
        XCTAssertEqual(card.body, "You're projected to miss your $200 goal by $2,000, and there's nothing left to trim in dining, shopping, recreation or subscriptions this month.")
    }
    func testNoGapPlanWhenOnTrackOrIncomeUnknownOrMonthOver() {
        let txs = [T.tx("300", "Chipotle", "food", on: T.date(2026, 4, 3))]
        XCTAssertNil(plan(txs, earnings: income2000))
        XCTAssertNil(plan([T.tx("3000", "Chipotle", "food", on: T.date(2026, 4, 3))], earnings: []))
        let past = T.snapshot(april, now: T.date(2026, 5, 10), [T.tx("3000", "Chipotle", "food", on: T.date(2026, 4, 3))], earnings: income2000)
        XCTAssertNil(InsightsEngine.gapPlan(snapshot: past, transactions: [], categories: T.categories, calendar: T.chicago, locale: T.us))
    }
    func testUserMadeCategoriesComeAfterBuiltInOnesAndArchivedAreSkipped() {
        var categories = T.categories
        let pets = CategoryRecord(name: "Pets", colorHex: "#123456", symbolName: "pawprint.fill", sortOrder: 11)
        let hobbies = CategoryRecord(name: "Hobbies", colorHex: "#654321", symbolName: "paintbrush.fill", sortOrder: 10)
        let old = CategoryRecord(name: "Old", colorHex: "#111111", symbolName: "archivebox.fill", sortOrder: 12, isArchived: true)
        categories += [pets, hobbies, old]
        func tx(_ amount: String, _ category: CategoryRecord) -> TransactionRecord {
            TransactionRecord(amount: T.d(amount), merchant: category.name, categoryID: category.id, date: T.date(2026, 4, 5), createdAt: now)
        }
        let txs = [
            tx("100", pets), tx("100", hobbies), tx("100", old),
            T.tx("100", "AMC", "recreation", on: T.date(2026, 4, 5)),
            T.tx("700", "Rent", "bills", on: T.date(2026, 4, 1))
        ]
        // spent 1100 → projected 2200 → gap 400; cuttable: recreation 100, hobbies 100, pets 100.
        let plan = plan(txs, earnings: income2000, categories: categories)!
        XCTAssertEqual(plan.cuts.map { $0.categoryID }, [T.id("recreation"), hobbies.id, pets.id])
        XCTAssertEqual(plan.cuts.map { $0.note }, ["Cut recreation by $100", "Cut Hobbies by $100", "Cut Pets by $100"])
        XCTAssertEqual(plan.uncovered, T.d("100"))
    }
    func testSubscriptionWordingWithoutARecurringCandidate() {
        let txs = [T.tx("50", "Netflix", "subscriptions", on: T.date(2026, 4, 6)), T.tx("1000", "Rent", "bills", on: T.date(2026, 4, 1))]
        let plan = plan(txs, earnings: income2000)!
        XCTAssertEqual(plan.cuts.map { $0.note }, ["Cut subscriptions by $50"])
        XCTAssertNil(plan.cuts[0].suggestion)
    }
    func testAllocateEdgeCases() {
        XCTAssertEqual(InsightsEngine.allocate(target: T.d("10"), capacities: [T.d("1"), T.d("2")]), [T.d("1"), T.d("2")])
        XCTAssertEqual(InsightsEngine.allocate(target: T.d("0"), capacities: [T.d("1"), T.d("2")]), [T.d("0"), T.d("0")])
        XCTAssertEqual(InsightsEngine.allocate(target: T.d("5"), capacities: []), [])
        XCTAssertEqual(InsightsEngine.allocate(target: T.d("0.01"), capacities: [T.d("1"), T.d("1"), T.d("1")]).reduce(Decimal(0), +), T.d("0.01"))
        XCTAssertEqual(InsightsEngine.allocate(target: T.d("100"), capacities: [T.d("33.33"), T.d("33.33"), T.d("33.34")]), [T.d("33.33"), T.d("33.33"), T.d("33.34")])
        XCTAssertEqual(InsightsEngine.allocate(target: T.d("7"), capacities: [T.d("-3"), T.d("10")]), [T.d("0"), T.d("7")])
    }
    func testAllocateAlwaysSumsExactlyAcrossSeededScenarios() {
        var rng = SplitMix64(seed: 99)
        for _ in 0..<500 {
            let count = rng.int(in: 1...7)
            let capacities = (0..<count).map { _ in Decimal(rng.int(in: 0...50_000)) / 100 }
            let target = Decimal(rng.int(in: 0...120_000)) / 100
            let shares = InsightsEngine.allocate(target: target, capacities: capacities)
            let total = capacities.reduce(Decimal(0), +)
            XCTAssertEqual(shares.reduce(Decimal(0), +), min(target, total), "target \(target) caps \(capacities)")
            for (share, capacity) in zip(shares, capacities) {
                XCTAssertGreaterThanOrEqual(share, 0)
                XCTAssertLessThanOrEqual(share, capacity)
                XCTAssertEqual(MoneyFormat.round(share), share)
            }
        }
    }
    func testGapPlanAddsUpAcrossSeededRandomMonths() {
        var rng = SplitMix64(seed: 7)
        let keys = DefaultCategories.systemKeys
        var plansChecked = 0
        var fullyCovered = 0
        var shortfalls = 0
        for scenario in 0..<60 {
            let day = rng.int(in: 1...29)
            let scenarioNow = T.date(2026, 4, day, 18)
            var txs: [TransactionRecord] = []
            // History in March for most scenarios.
            if scenario % 4 != 0 {
                for _ in 0..<rng.int(in: 5...40) {
                    txs.append(T.tx(MoneyFormat.plain(Decimal(rng.int(in: 100...12_000)) / 100), "H", keys[rng.int(in: 0...9)], on: T.date(2026, 3, rng.int(in: 1...31))))
                }
            }
            for _ in 0..<rng.int(in: 3...45) {
                var cents = rng.int(in: 100...15_000)
                if rng.chance(8) { cents = -cents }          // refunds
                txs.append(T.tx(MoneyFormat.plain(Decimal(cents) / 100), "M", keys[rng.int(in: 0...9)], on: T.date(2026, 4, rng.int(in: 1...day), 9)))
            }
            let earnings = [
                T.earning(MoneyFormat.plain(Decimal(rng.int(in: 20_000...90_000)) / 100), weekOf: T.date(2026, 3, 30)),
                T.earning(MoneyFormat.plain(Decimal(rng.int(in: 20_000...90_000)) / 100), weekOf: T.date(2026, 3, 23))
            ]
            let goal = Decimal(rng.int(in: 0...60_000)) / 100
            let snapshot = BudgetEngine.snapshot(month: april, now: scenarioNow, transactions: txs, earnings: earnings, goal: goal, categories: T.categories, calendar: T.chicago)
            let plan = InsightsEngine.gapPlan(snapshot: snapshot, transactions: txs, categories: T.categories, calendar: T.chicago, locale: T.us)
            let savings = snapshot.projectedSavings!
            guard savings < goal, MoneyFormat.round(goal - savings) > 0 else {
                XCTAssertNil(plan, "scenario \(scenario)")
                continue
            }
            guard let plan else { return XCTFail("scenario \(scenario): expected a plan") }
            plansChecked += 1

            // Independent calculation of what can be cut.
            var cuttable: [UUID: Decimal] = [:]
            for key in ["food", "shopping", "recreation", "subscriptions"] {
                let id = T.id(key)
                let room = MoneyFormat.truncate(max(0, (snapshot.projectedByCategory[id] ?? 0) - (snapshot.spentByCategory[id] ?? 0)))
                if room > 0 { cuttable[id] = room }
            }
            let totalCuttable = cuttable.values.reduce(Decimal(0), +)
            let gap = MoneyFormat.round(goal - savings)

            XCTAssertEqual(plan.gap, gap, "scenario \(scenario)")
            XCTAssertEqual(sum(plan), min(gap, totalCuttable), "scenario \(scenario): cuts must add up exactly")
            XCTAssertEqual(plan.uncovered, gap - sum(plan), "scenario \(scenario)")
            XCTAssertGreaterThanOrEqual(plan.uncovered, 0)
            for cut in plan.cuts {
                XCTAssertGreaterThan(cut.amount, 0)
                XCTAssertEqual(MoneyFormat.round(cut.amount), cut.amount, "scenario \(scenario): whole cents")
                XCTAssertLessThanOrEqual(cut.amount, cuttable[cut.categoryID] ?? 0, "scenario \(scenario): cannot cut more than is unspent")
                XCTAssertNotEqual(cut.categoryID, T.id("bills"))
                XCTAssertNotEqual(cut.categoryID, T.id("health"))
                XCTAssertNotNil(cuttable[cut.categoryID], "scenario \(scenario): only discretionary categories")
            }
            if plan.uncovered == 0 { fullyCovered += 1 } else { shortfalls += 1 }
        }
        // The scenarios must actually exercise both outcomes.
        XCTAssertGreaterThan(plansChecked, 20)
        XCTAssertGreaterThan(fullyCovered, 3)
        XCTAssertGreaterThan(shortfalls, 3)
    }

    // MARK: Frequent small purchases

    func testCoffeeRunsCopyMatchesTheSpec() {
        var txs: [TransactionRecord] = []
        for day in 1...12 { txs.append(T.tx("5.00", day % 2 == 0 ? "Starbucks #1234" : "Dunkin", "food", on: T.date(2026, 4, day, 8))) }
        txs.append(T.tx("6.00", "Colectivo Coffee", "food", on: T.date(2026, 4, 13, 8)))
        txs.append(T.tx("6.00", "Starbucks", "food", on: T.date(2026, 4, 14, 8)))
        let card = insights(txs).first { $0.kind == .frequentSmallPurchases }
        XCTAssertEqual(card?.body, "14 coffee runs this month = $72. Halving that saves $36.")
        XCTAssertEqual(card?.amount, T.d("72"))
        XCTAssertEqual(card?.id, "frequent-coffee")
    }
    func testSmallPurchasesAtOneMerchant() {
        let txs = (1...5).map { T.tx("3.50", "7-Eleven #\(1000 + $0)", "other", on: T.date(2026, 4, $0)) }
        XCTAssertEqual(
            insights(txs).first { $0.kind == .frequentSmallPurchases }?.body,
            "5 small purchases at 7-Eleven #1005 this month = $18. Halving that saves $9."
        )
    }
    func testThreePurchasesAreNotFrequent() {
        let txs = (1...3).map { T.tx("5", "Starbucks", "food", on: T.date(2026, 4, $0)) }
        XCTAssertFalse(insights(txs).contains { $0.kind == .frequentSmallPurchases })
    }
    func testPurchasesOverFifteenDollarsAreNotSmall() {
        var txs = (1...3).map { T.tx("15.00", "Starbucks", "food", on: T.date(2026, 4, $0)) }
        txs += (4...9).map { T.tx("15.01", "Starbucks", "food", on: T.date(2026, 4, $0)) }
        XCTAssertFalse(insights(txs).contains { $0.kind == .frequentSmallPurchases })
        txs.append(T.tx("15.00", "Starbucks", "food", on: T.date(2026, 4, 10)))
        XCTAssertEqual(insights(txs).first { $0.kind == .frequentSmallPurchases }?.body, "4 coffee runs this month = $60. Halving that saves $30.")
    }
    func testRefundsAndOtherMonthsAreNotCounted() {
        var txs = (1...3).map { T.tx("5", "Starbucks", "food", on: T.date(2026, 4, $0)) }
        txs.append(T.tx("-5", "Starbucks", "food", on: T.date(2026, 4, 4)))
        txs.append(T.tx("5", "Starbucks", "food", on: T.date(2026, 3, 30)))
        XCTAssertFalse(insights(txs).contains { $0.kind == .frequentSmallPurchases })
    }

    // MARK: Top merchants and weekend pattern

    func testTopMerchantsWithChangeVersusLastMonth() {
        let txs = [
            T.tx("205", "Jewel-Osco", "groceries", on: T.date(2026, 3, 10)),
            T.tx("200", "Target", "shopping", on: T.date(2026, 3, 11)),
            T.tx("140", "Jewel-Osco", "groceries", on: T.date(2026, 4, 6)),
            T.tx("100", "JEWEL OSCO #3456", "groceries", on: T.date(2026, 4, 3)),
            T.tx("180", "Target", "shopping", on: T.date(2026, 4, 7)),
            T.tx("120", "Shell", "gas", on: T.date(2026, 4, 8))
        ]
        let card = insights(txs).first { $0.kind == .topMerchants }
        XCTAssertEqual(card?.body, "Jewel-Osco is your top merchant this month at $240 (up $35 from last month). Next: Target $180 (down $20 from last month) and Shell $120 (new this month).")
        XCTAssertEqual(card?.merchants.map { $0.normalizedMerchant }, ["JEWEL OSCO", "TARGET", "SHELL"])
        XCTAssertEqual(card?.amount, T.d("240"))
    }
    func testNoTopMerchantsForAnEmptyMonth() {
        XCTAssertFalse(insights([T.tx("50", "Target", "shopping", on: T.date(2026, 3, 10))]).contains { $0.kind == .topMerchants })
    }
    func testWeekendVersusWeekday() {
        // April 1–15, 2026 has 4 weekend days (4, 5, 11, 12) and 11 weekdays.
        let txs = [
            T.tx("170", "Topgolf", "recreation", on: T.date(2026, 4, 4)),
            T.tx("170", "Chipotle", "food", on: T.date(2026, 4, 11)),
            T.tx("440", "Aldi", "groceries", on: T.date(2026, 4, 2)),
            T.tx("1000", "Rent", "bills", on: T.date(2026, 4, 1))        // fixed charges are ignored
        ]
        let card = insights(txs).first { $0.kind == .weekendVsWeekday }
        XCTAssertEqual(card?.body, "You spend about $85 a day on weekends and $40 on weekdays. That's 113% more on weekends.")
        XCTAssertEqual(card?.title, "Weekends cost more")
        XCTAssertEqual(card?.amount, T.d("45"))
    }
    func testWeekdayHeavyPattern() {
        let txs = [T.tx("40", "Topgolf", "recreation", on: T.date(2026, 4, 4)), T.tx("880", "Aldi", "groceries", on: T.date(2026, 4, 2))]
        XCTAssertEqual(
            insights(txs).first { $0.kind == .weekendVsWeekday }?.body,
            "You spend about $80 a day on weekdays and $10 on weekends. That's 700% more on weekdays."
        )
    }
    func testNoWeekendInsightWhenSimilar() {
        // Weekend 4 × 44 = 176, weekdays 11 × 40 = 440: only 10 % apart.
        let txs = [T.tx("176", "A", "food", on: T.date(2026, 4, 4)), T.tx("440", "B", "groceries", on: T.date(2026, 4, 2))]
        XCTAssertFalse(insights(txs).contains { $0.kind == .weekendVsWeekday })
    }
    func testNoWeekendInsightTooEarlyInTheMonth() {
        // April 3 (Friday): no weekend day has happened yet.
        let txs = [T.tx("500", "A", "food", on: T.date(2026, 4, 2))]
        XCTAssertFalse(insights(txs, now: T.date(2026, 4, 3)).contains { $0.kind == .weekendVsWeekday })
    }

    // MARK: Ordering

    func testInsightsAreSortedByPriorityAndTopThree() {
        var txs = specExample
        for day in 1...6 { txs.append(T.tx("5", "Starbucks", "food", on: T.date(2026, 4, day, 8))) }
        let cards = insights(txs, earnings: income2000)
        XCTAssertEqual(cards.map { $0.priority }, cards.map { $0.priority }.sorted(by: >))
        XCTAssertEqual(cards.first?.kind, .gapPlan)
        XCTAssertEqual(Set(cards.map { $0.id }).count, cards.count)
        let top = InsightsEngine.top(cards)
        XCTAssertEqual(top.count, 3)
        XCTAssertEqual(top.map { $0.id }, Array(cards.prefix(3)).map { $0.id })
        for card in cards {
            XCTAssertFalse(card.title.isEmpty)
            XCTAssertTrue(card.body.contains("$"), card.body)
        }
    }
    func testMissingIncomeComesFirst() {
        var txs = specExample
        for day in 1...6 { txs.append(T.tx("5", "Starbucks", "food", on: T.date(2026, 4, day, 8))) }
        XCTAssertEqual(insights(txs).first?.kind, .missingIncome)
    }
    func testInsightsAreDeterministic() {
        let a = insights(specExample, earnings: income2000)
        let b = insights(specExample.reversed(), earnings: income2000.reversed())
        XCTAssertEqual(a, b)
    }
    func testSnapshotOverloadMatchesConvenience() {
        let snapshot = T.snapshot(april, now: now, specExample, earnings: income2000)
        let viaSnapshot = InsightsEngine.insights(snapshot: snapshot, transactions: specExample, categories: T.categories, calendar: T.chicago, locale: T.us)
        XCTAssertEqual(viaSnapshot, insights(specExample, earnings: income2000))
    }
}
