#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif

/// Where the expected-income number came from.
public enum IncomeBasis: String, Codable, Sendable {
    /// At least one week of earnings is entered for the month.
    case entered
    /// Nothing entered for the month yet; estimated from the most recent (up to 8) earlier weeks.
    case estimatedFromHistory
    /// No earnings data at all — income-dependent numbers are nil.
    case unknown
}

/// Everything the dashboard needs for one month. Money is full-precision `Decimal`; round only for display.
public struct BudgetSnapshot: Hashable, Sendable {
    public var month: MonthKey
    /// `now` falls inside `month`.
    public var isCurrentMonth: Bool
    /// `month` ended before `now` (treated as fully elapsed).
    public var isPastMonth: Bool

    public var daysInMonth: Int
    /// Days elapsed, today included. Past month → `daysInMonth`. Future month → 0.
    public var dayOfMonth: Int
    /// Days left, today included (`daysInMonth − dayOfMonth + 1`). Past month → 0. Future month → `daysInMonth`.
    public var daysLeft: Int

    /// Sum of weekly earnings whose Monday falls in the month.
    public var incomeSoFar: Decimal
    /// `incomeSoFar + average(entered weeks) × remainingWeeks`; estimated from history when nothing is entered; nil when unknown.
    public var expectedIncome: Decimal?
    public var incomeBasis: IncomeBasis
    /// Mondays in the month that have an earnings entry.
    public var enteredWeeks: Int
    /// Mondays in the month with no entry yet.
    public var remainingWeeks: Int
    /// The weekly average used for the remaining weeks (nil when unknown).
    public var averageWeeklyIncome: Decimal?

    /// Expenses minus refunds this month.
    public var spent: Decimal
    /// Per category; may be negative when refunds exceed spending. Uncategorized/unknown ids are under "other".
    public var spentByCategory: [UUID: Decimal]
    /// Sum of `projectedByCategory`.
    public var projectedSpending: Decimal
    public var projectedByCategory: [UUID: Decimal]
    /// Average monthly total per category over the prior months (up to 3) that have data.
    public var trailingAverageByCategory: [UUID: Decimal]
    /// `trailingAverage × dayOfMonth / daysInMonth` — what is usual by this point in the month.
    public var usualByThisDayByCategory: [UUID: Decimal]
    /// How many of the 3 prior months have any transactions (0–3). 0 = no history.
    public var historyMonthCount: Int

    /// `expectedIncome − projectedSpending`; nil when income is unknown.
    public var projectedSavings: Decimal?
    public var goal: Decimal
    /// `max(0, (expectedIncome − goal − spent) / daysLeft)`; nil when income is unknown; 0 for a past month.
    public var safeToSpendPerDay: Decimal?
    /// `projectedSavings ≥ goal`; nil when income is unknown.
    public var isOnTrack: Bool?

    public init(
        month: MonthKey, isCurrentMonth: Bool, isPastMonth: Bool,
        daysInMonth: Int, dayOfMonth: Int, daysLeft: Int,
        incomeSoFar: Decimal, expectedIncome: Decimal?, incomeBasis: IncomeBasis,
        enteredWeeks: Int, remainingWeeks: Int, averageWeeklyIncome: Decimal?,
        spent: Decimal, spentByCategory: [UUID: Decimal],
        projectedSpending: Decimal, projectedByCategory: [UUID: Decimal],
        trailingAverageByCategory: [UUID: Decimal], usualByThisDayByCategory: [UUID: Decimal],
        historyMonthCount: Int,
        projectedSavings: Decimal?, goal: Decimal, safeToSpendPerDay: Decimal?, isOnTrack: Bool?
    ) {
        self.month = month
        self.isCurrentMonth = isCurrentMonth
        self.isPastMonth = isPastMonth
        self.daysInMonth = daysInMonth
        self.dayOfMonth = dayOfMonth
        self.daysLeft = daysLeft
        self.incomeSoFar = incomeSoFar
        self.expectedIncome = expectedIncome
        self.incomeBasis = incomeBasis
        self.enteredWeeks = enteredWeeks
        self.remainingWeeks = remainingWeeks
        self.averageWeeklyIncome = averageWeeklyIncome
        self.spent = spent
        self.spentByCategory = spentByCategory
        self.projectedSpending = projectedSpending
        self.projectedByCategory = projectedByCategory
        self.trailingAverageByCategory = trailingAverageByCategory
        self.usualByThisDayByCategory = usualByThisDayByCategory
        self.historyMonthCount = historyMonthCount
        self.projectedSavings = projectedSavings
        self.goal = goal
        self.safeToSpendPerDay = safeToSpendPerDay
        self.isOnTrack = isOnTrack
    }

    /// Mondays in the month.
    public var totalWeeks: Int { enteredWeeks + remainingWeeks }
    /// At least one of the three prior months has transactions.
    public var hasHistory: Bool { historyMonthCount > 0 }
    /// `incomeSoFar − spent`: what has actually been kept so far.
    public var savedSoFar: Decimal { incomeSoFar - spent }
    /// `expectedIncome − goal`: the month's spending budget. Nil when income is unknown.
    public var spendingBudget: Decimal? { expectedIncome.map { $0 - goal } }
    /// `spendingBudget − spent`, may be negative. Nil when income is unknown.
    public var remainingBudget: Decimal? { spendingBudget.map { $0 - spent } }
    /// `max(0, goal − projectedSavings)`: how far short of the goal the month is heading. Nil when income is unknown.
    public var gap: Decimal? { projectedSavings.map { max(0, goal - $0) } }
    /// Progress toward the goal for a ring: `projectedSavings / goal` clamped to 0...1 (1 when the goal is 0). Nil when income is unknown.
    public var goalProgress: Decimal? {
        guard let savings = projectedSavings else { return nil }
        guard goal > 0 else { return 1 }
        return min(1, max(0, savings / goal))
    }
    /// `goalProgress` as a `Double` for drawing.
    public var goalProgressValue: Double? { goalProgress.map { MoneyFormat.double($0) } }
    /// True when there is neither spending nor income for the month.
    public var isEmpty: Bool { spentByCategory.isEmpty && enteredWeeks == 0 }
}

/// All month math. Pure: nothing here reads the clock or the device time zone.
public enum BudgetEngine {
    /// Builds the snapshot for `month` as seen at `now`.
    ///
    /// - `transactions` and `earnings` can be everything in the store; the engine picks what it needs
    ///   (the month itself plus the three months before it, and earlier earnings for the income estimate).
    /// - `categories` should include archived ones. A transaction with a nil category, or an id not in
    ///   the list, is counted under "other".
    /// - A month before the one containing `now` is treated as fully elapsed; a month after it has `dayOfMonth = 0`.
    ///
    /// Projection per category (PLAN §5): `pace = spent / dayOfMonth`, `histDaily = trailingAverage / daysInMonth`,
    /// `w = dayOfMonth / daysInMonth`; with history `projected = spent + (w·pace + (1−w)·histDaily) × daysRemaining`,
    /// without history `projected = spent + pace × daysRemaining`, where `daysRemaining = daysInMonth − dayOfMonth`.
    /// One deliberate refinement: `pace` is floored at 0, so a category whose refunds exceed its spending
    /// is not extrapolated into ever-larger negative spending.
    public static func snapshot(
        month: MonthKey,
        now: Date,
        transactions: [TransactionRecord],
        earnings: [WeeklyEarning],
        goal: Decimal,
        categories: [CategoryRecord],
        calendar: LedgerCalendar
    ) -> BudgetSnapshot {
        let currentMonth = MonthKey(date: now, calendar: calendar)
        let isCurrent = month == currentMonth
        let isPast = month < currentMonth
        let daysInMonth = calendar.daysInMonth(month)
        let dayOfMonth: Int
        let daysLeft: Int
        if isCurrent {
            dayOfMonth = calendar.dayOfMonth(now)
            daysLeft = daysInMonth - dayOfMonth + 1
        } else if isPast {
            dayOfMonth = daysInMonth
            daysLeft = 0
        } else {
            dayOfMonth = 0
            daysLeft = daysInMonth
        }

        // Spending, this month and the three before it.
        let resolver = CategoryResolver(categories: categories)
        let months = [month, month.previous, month.adding(months: -2), month.adding(months: -3)]
        let starts = months.map { calendar.monthStart($0) }
        let monthEnd = calendar.monthStart(month.next)
        var totals: [[UUID: Decimal]] = [[:], [:], [:], [:]]
        var hasData = [false, false, false, false]
        for transaction in transactions {
            let date = transaction.date
            guard date >= starts[3], date < monthEnd else { continue }
            let index: Int
            if date >= starts[0] { index = 0 } else if date >= starts[1] { index = 1 } else if date >= starts[2] { index = 2 } else { index = 3 }
            let id = resolver.resolve(transaction.categoryID)
            totals[index][id, default: 0] += transaction.amount
            hasData[index] = true
        }
        let spentByCategory = totals[0]
        let spent = spentByCategory.values.reduce(Decimal(0), +)

        let historyMonthCount = hasData[1...3].filter { $0 }.count
        var trailingAverage: [UUID: Decimal] = [:]
        if historyMonthCount > 0 {
            for index in 1...3 where hasData[index] {
                for (id, value) in totals[index] { trailingAverage[id, default: 0] += value }
            }
            for id in Array(trailingAverage.keys) {
                trailingAverage[id] = (trailingAverage[id] ?? 0) / Decimal(historyMonthCount)
            }
        }

        let dim = Decimal(daysInMonth)
        let day = Decimal(dayOfMonth)
        let daysRemaining = Decimal(daysInMonth - dayOfMonth)

        var usual: [UUID: Decimal] = [:]
        for (id, average) in trailingAverage { usual[id] = average * day / dim }

        // Same formulas as above, rearranged to multiply before dividing so that whole-cent inputs
        // give exact results more often (e.g. 1150 / 15 × 15 stays 1150):
        //   pace × daysRemaining                         = spent × daysRemaining / day
        //   (w·pace + (1−w)·histDaily) × daysRemaining   = (spent × daysRemaining + average × daysRemaining² / dim) / dim
        var projectedByCategory: [UUID: Decimal] = [:]
        for id in Set(spentByCategory.keys).union(trailingAverage.keys) {
            let categorySpent = spentByCategory[id] ?? 0
            let paceBase = max(0, categorySpent)
            let projected: Decimal
            if dayOfMonth == 0 {
                // Future month: nothing has happened yet, so history (if any) is the whole projection.
                projected = categorySpent + (trailingAverage[id] ?? 0)
            } else if historyMonthCount > 0 {
                let average = trailingAverage[id] ?? 0
                projected = categorySpent + (paceBase * daysRemaining + average * daysRemaining * daysRemaining / dim) / dim
            } else {
                projected = categorySpent + paceBase * daysRemaining / day
            }
            projectedByCategory[id] = projected
        }
        let projectedSpending = projectedByCategory.values.reduce(Decimal(0), +)

        // Income.
        let income = incomeEstimate(month: month, earnings: earnings, calendar: calendar)

        let projectedSavings = income.expected.map { $0 - projectedSpending }
        var safeToSpend: Decimal?
        if let expected = income.expected {
            if daysLeft > 0 {
                safeToSpend = max(0, (expected - goal - spent) / Decimal(daysLeft))
            } else {
                safeToSpend = 0
            }
        }

        return BudgetSnapshot(
            month: month, isCurrentMonth: isCurrent, isPastMonth: isPast,
            daysInMonth: daysInMonth, dayOfMonth: dayOfMonth, daysLeft: daysLeft,
            incomeSoFar: income.soFar, expectedIncome: income.expected, incomeBasis: income.basis,
            enteredWeeks: income.enteredWeeks, remainingWeeks: income.remainingWeeks, averageWeeklyIncome: income.weeklyAverage,
            spent: spent, spentByCategory: spentByCategory,
            projectedSpending: projectedSpending, projectedByCategory: projectedByCategory,
            trailingAverageByCategory: trailingAverage, usualByThisDayByCategory: usual,
            historyMonthCount: historyMonthCount,
            projectedSavings: projectedSavings, goal: goal, safeToSpendPerDay: safeToSpend,
            isOnTrack: projectedSavings.map { $0 >= goal }
        )
    }

    /// Income numbers for a month.
    public struct IncomeEstimate: Hashable, Sendable {
        public var soFar: Decimal
        public var expected: Decimal?
        public var basis: IncomeBasis
        public var enteredWeeks: Int
        public var remainingWeeks: Int
        public var weeklyAverage: Decimal?

        public init(soFar: Decimal, expected: Decimal?, basis: IncomeBasis, enteredWeeks: Int, remainingWeeks: Int, weeklyAverage: Decimal?) {
            self.soFar = soFar
            self.expected = expected
            self.basis = basis
            self.enteredWeeks = enteredWeeks
            self.remainingWeeks = remainingWeeks
            self.weeklyAverage = weeklyAverage
        }
    }

    /// Income so far and expected income for `month`.
    /// A week counts toward the month its Monday falls in. If two entries land in the same week, the later one in the array wins.
    public static func incomeEstimate(month: MonthKey, earnings: [WeeklyEarning], calendar: LedgerCalendar) -> IncomeEstimate {
        var byWeek: [Date: Decimal] = [:]
        for earning in earnings { byWeek[calendar.weekStart(for: earning.weekStart)] = earning.amount }

        let mondays = calendar.mondays(in: month)
        let entered = mondays.compactMap { byWeek[$0] }
        let soFar = entered.reduce(Decimal(0), +)
        let remaining = mondays.count - entered.count

        if !entered.isEmpty {
            let average = soFar / Decimal(entered.count)
            return IncomeEstimate(
                soFar: soFar, expected: soFar + average * Decimal(remaining), basis: .entered,
                enteredWeeks: entered.count, remainingWeeks: remaining, weeklyAverage: average
            )
        }

        let monthStart = calendar.monthStart(month)
        let earlier = byWeek.filter { $0.key < monthStart }.sorted { $0.key > $1.key }.prefix(8)
        if !earlier.isEmpty {
            let average = earlier.reduce(Decimal(0)) { $0 + $1.value } / Decimal(earlier.count)
            return IncomeEstimate(
                soFar: 0, expected: average * Decimal(mondays.count), basis: .estimatedFromHistory,
                enteredWeeks: 0, remainingWeeks: mondays.count, weeklyAverage: average
            )
        }
        return IncomeEstimate(soFar: 0, expected: nil, basis: .unknown, enteredWeeks: 0, remainingWeeks: mondays.count, weeklyAverage: nil)
    }

    /// Net spending (expenses minus refunds) per category for transactions dated in `[start, end)`.
    public static func spendingByCategory(
        from start: Date, to end: Date, transactions: [TransactionRecord], categories: [CategoryRecord]
    ) -> [UUID: Decimal] {
        let resolver = CategoryResolver(categories: categories)
        var totals: [UUID: Decimal] = [:]
        for transaction in transactions where transaction.date >= start && transaction.date < end {
            totals[resolver.resolve(transaction.categoryID), default: 0] += transaction.amount
        }
        return totals
    }

    /// The transactions dated inside `month`.
    public static func transactions(in month: MonthKey, from transactions: [TransactionRecord], calendar: LedgerCalendar) -> [TransactionRecord] {
        let start = calendar.monthStart(month)
        let end = calendar.monthStart(month.next)
        return transactions.filter { $0.date >= start && $0.date < end }
    }

    /// The category id a transaction is counted under: its own when that category exists, otherwise "other".
    public static func effectiveCategoryID(_ categoryID: UUID?, categories: [CategoryRecord]) -> UUID {
        CategoryResolver(categories: categories).resolve(categoryID)
    }
}

/// Maps nil / unknown category ids to "other".
struct CategoryResolver {
    let known: Set<UUID>
    let otherID: UUID
    let byID: [UUID: CategoryRecord]

    init(categories: [CategoryRecord]) {
        var map: [UUID: CategoryRecord] = [:]
        for category in categories where map[category.id] == nil { map[category.id] = category }
        byID = map
        known = Set(map.keys)
        otherID = categories.first(where: { $0.systemKey == "other" })?.id ?? DefaultCategories.otherID
    }

    func resolve(_ id: UUID?) -> UUID {
        guard let id, known.contains(id) else { return otherID }
        return id
    }

    /// The record for an id, falling back to the default "Other" record.
    func record(_ id: UUID) -> CategoryRecord {
        byID[id] ?? DefaultCategories.category("other") ?? CategoryRecord(
            id: id, name: "Other", colorHex: "#868E96", symbolName: "ellipsis.circle.fill", sortOrder: Int.max, systemKey: "other"
        )
    }
}
