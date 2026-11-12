#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif

// MARK: - Chart value types

/// One slice of the spending-by-category donut.
public struct CategorySlice: Identifiable, Hashable, Sendable {
    public var categoryID: UUID
    public var name: String
    public var colorHex: String
    public var symbolName: String
    /// Net spending clamped at 0 — what the chart draws.
    public var amount: Decimal
    /// Net spending before clamping (negative when refunds exceed spending).
    public var netAmount: Decimal
    /// Share of the donut, 0...1.
    public var fraction: Decimal

    public init(categoryID: UUID, name: String, colorHex: String, symbolName: String, amount: Decimal, netAmount: Decimal, fraction: Decimal) {
        self.categoryID = categoryID
        self.name = name
        self.colorHex = colorHex
        self.symbolName = symbolName
        self.amount = amount
        self.netAmount = netAmount
        self.fraction = fraction
    }

    public var id: UUID { categoryID }
    /// For plotting only.
    public var value: Double { MoneyFormat.double(amount) }
    public var fractionValue: Double { MoneyFormat.double(fraction) }
}

/// One Monday–Sunday week: spending next to the earnings entered for that week.
public struct WeeklyBar: Identifiable, Hashable, Sendable {
    /// Monday 00:00.
    public var weekStart: Date
    /// Start of the Sunday that ends the week.
    public var weekLastDay: Date
    /// Net spending for the whole Monday–Sunday week (it may run into the next month).
    public var spending: Decimal
    /// Earnings entered for the week; nil when not entered.
    public var earnings: Decimal?
    /// 1-based position within the month.
    public var weekNumber: Int

    public init(weekStart: Date, weekLastDay: Date, spending: Decimal, earnings: Decimal?, weekNumber: Int) {
        self.weekStart = weekStart
        self.weekLastDay = weekLastDay
        self.spending = spending
        self.earnings = earnings
        self.weekNumber = weekNumber
    }

    public var id: Date { weekStart }
    /// For plotting only (clamped at 0).
    public var spendingValue: Double { MoneyFormat.double(max(0, spending)) }
    /// For plotting only (0 when not entered).
    public var earningsValue: Double { MoneyFormat.double(earnings ?? 0) }
}

/// One day on the cumulative-spending line chart.
public struct CumulativePoint: Identifiable, Hashable, Sendable {
    /// Day of the month, 1-based.
    public var day: Int
    /// Start of that day.
    public var date: Date
    /// Net spending from the 1st through this day; nil for days that have not happened yet.
    public var cumulativeSpending: Decimal?
    /// `(expectedIncome − goal) × day / daysInMonth`, floored at 0; nil when income is unknown.
    public var onTrack: Decimal?

    public init(day: Int, date: Date, cumulativeSpending: Decimal?, onTrack: Decimal?) {
        self.day = day
        self.date = date
        self.cumulativeSpending = cumulativeSpending
        self.onTrack = onTrack
    }

    public var id: Int { day }
    public var cumulativeValue: Double? { cumulativeSpending.map { MoneyFormat.double($0) } }
    public var onTrackValue: Double? { onTrack.map { MoneyFormat.double($0) } }
}

/// One category in the month-over-month grouped bars.
public struct CategoryComparison: Identifiable, Hashable, Sendable {
    public var categoryID: UUID
    public var name: String
    public var colorHex: String
    /// Selected month, clamped at 0.
    public var current: Decimal
    /// The month before, clamped at 0.
    public var previous: Decimal

    public init(categoryID: UUID, name: String, colorHex: String, current: Decimal, previous: Decimal) {
        self.categoryID = categoryID
        self.name = name
        self.colorHex = colorHex
        self.current = current
        self.previous = previous
    }

    public var id: UUID { categoryID }
    public var change: Decimal { current - previous }
    public var currentValue: Double { MoneyFormat.double(current) }
    public var previousValue: Double { MoneyFormat.double(previous) }
}

/// One row of the top-merchants list.
public struct MerchantSpend: Identifiable, Hashable, Sendable {
    public var normalizedMerchant: String
    /// The merchant as most recently written.
    public var displayName: String
    /// Net spending this month (> 0).
    public var amount: Decimal
    /// Net spending last month (0 if none; clamped at 0).
    public var previousAmount: Decimal
    public var transactionCount: Int
    /// `amount / top merchant's amount`, 0...1 — the mini-bar length.
    public var fractionOfTop: Decimal

    public init(normalizedMerchant: String, displayName: String, amount: Decimal, previousAmount: Decimal, transactionCount: Int, fractionOfTop: Decimal) {
        self.normalizedMerchant = normalizedMerchant
        self.displayName = displayName
        self.amount = amount
        self.previousAmount = previousAmount
        self.transactionCount = transactionCount
        self.fractionOfTop = fractionOfTop
    }

    public var id: String { normalizedMerchant }
    /// This month minus last month.
    public var change: Decimal { amount - previousAmount }
    public var isNew: Bool { previousAmount == 0 }
    public var value: Double { MoneyFormat.double(amount) }
    public var fractionOfTopValue: Double { MoneyFormat.double(fractionOfTop) }
}

/// One day of the transaction list.
public struct DayGroup: Identifiable, Hashable, Sendable {
    /// Start of the day.
    public var day: Date
    /// Net total for the day (refunds subtract).
    public var total: Decimal
    /// Newest first.
    public var transactions: [TransactionRecord]

    public init(day: Date, total: Decimal, transactions: [TransactionRecord]) {
        self.day = day
        self.total = total
        self.transactions = transactions
    }

    public var id: Date { day }
}

/// Search and filter settings for the transaction list. Empty sets / nil mean "no restriction".
public struct TransactionFilter: Hashable, Sendable {
    /// Matches merchant or notes; case- and accent-insensitive; every space-separated word must appear.
    public var searchText: String
    public var categoryIDs: Set<UUID>
    public var sources: Set<SourceKind>
    public var paymentMethods: Set<PaymentMethod>
    /// Inclusive lower bound on the transaction date.
    public var startDate: Date?
    /// Exclusive upper bound on the transaction date.
    public var endDate: Date?
    public var needsReviewOnly: Bool

    public init(
        searchText: String = "",
        categoryIDs: Set<UUID> = [],
        sources: Set<SourceKind> = [],
        paymentMethods: Set<PaymentMethod> = [],
        startDate: Date? = nil,
        endDate: Date? = nil,
        needsReviewOnly: Bool = false
    ) {
        self.searchText = searchText
        self.categoryIDs = categoryIDs
        self.sources = sources
        self.paymentMethods = paymentMethods
        self.startDate = startDate
        self.endDate = endDate
        self.needsReviewOnly = needsReviewOnly
    }

    /// True when nothing is restricted.
    public var isEmpty: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasNonSearchFilters
    }

    /// True when anything other than the search text is set (for a "filters active" badge).
    public var hasNonSearchFilters: Bool {
        !categoryIDs.isEmpty || !sources.isEmpty || !paymentMethods.isEmpty || startDate != nil || endDate != nil || needsReviewOnly
    }

    /// Sets the date range to whole days: from the start of `firstDay` through the end of `lastDay`.
    public mutating func setDayRange(from firstDay: Date, through lastDay: Date, calendar: LedgerCalendar) {
        let lower = min(firstDay, lastDay)
        let upper = max(firstDay, lastDay)
        startDate = calendar.startOfDay(lower)
        endDate = calendar.startOfDay(upper, addingDays: 1)
    }

    /// Restricts to one month.
    public mutating func setMonth(_ month: MonthKey, calendar: LedgerCalendar) {
        startDate = calendar.monthStart(month)
        endDate = calendar.monthStart(month.next)
    }

    /// Whether one transaction passes. `categories` lets the category filter treat nil/unknown ids as "Other";
    /// pass an empty array to compare raw ids only.
    public func matches(_ transaction: TransactionRecord, categories: [CategoryRecord] = []) -> Bool {
        if needsReviewOnly && !transaction.needsReview { return false }
        if !sources.isEmpty && !sources.contains(transaction.source) { return false }
        if !paymentMethods.isEmpty && !paymentMethods.contains(transaction.paymentMethod) { return false }
        if let start = startDate, transaction.date < start { return false }
        if let end = endDate, transaction.date >= end { return false }
        if !categoryIDs.isEmpty {
            let id: UUID?
            if categories.isEmpty {
                id = transaction.categoryID
            } else {
                id = CategoryResolver(categories: categories).resolve(transaction.categoryID)
            }
            guard let id, categoryIDs.contains(id) else { return false }
        }
        let words = MerchantNormalizer.searchKey(searchText).split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
        if !words.isEmpty {
            let haystack = MerchantNormalizer.searchKey(transaction.merchant) + "\n" + MerchantNormalizer.searchKey(transaction.notes)
            for word in words where !haystack.contains(word) { return false }
        }
        return true
    }
}

// MARK: - Builders

/// Series for every chart, plus the list helpers. All pure.
public enum ChartData {
    /// Donut: net spending per category for the month, largest first. Categories at or below 0 are left out.
    public static func categoryBreakdown(
        month: MonthKey, transactions: [TransactionRecord], categories: [CategoryRecord], calendar: LedgerCalendar
    ) -> [CategorySlice] {
        let resolver = CategoryResolver(categories: categories)
        let totals = BudgetEngine.spendingByCategory(
            from: calendar.monthStart(month), to: calendar.monthStart(month.next), transactions: transactions, categories: categories
        )
        let positiveTotal = totals.values.reduce(Decimal(0)) { $0 + max(0, $1) }
        var slices: [(slice: CategorySlice, order: Int)] = []
        for (id, net) in totals where net > 0 {
            let record = resolver.record(id)
            slices.append((
                CategorySlice(
                    categoryID: id, name: record.name, colorHex: record.colorHex, symbolName: record.symbolName,
                    amount: net, netAmount: net, fraction: positiveTotal > 0 ? net / positiveTotal : 0
                ),
                record.sortOrder
            ))
        }
        slices.sort {
            if $0.slice.amount != $1.slice.amount { return $0.slice.amount > $1.slice.amount }
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.slice.categoryID.uuidString < $1.slice.categoryID.uuidString
        }
        return slices.map { $0.slice }
    }

    /// Weekly bars: one per Monday that falls in the month (4 or 5). Each bar covers the whole Monday–Sunday week,
    /// paired with the earnings entered for that week.
    public static func weeklyBars(
        month: MonthKey, transactions: [TransactionRecord], earnings: [WeeklyEarning], calendar: LedgerCalendar
    ) -> [WeeklyBar] {
        let mondays = calendar.mondays(in: month)
        guard let first = mondays.first, let last = mondays.last else { return [] }
        let rangeEnd = calendar.startOfDay(last, addingDays: 7)
        var spending: [Date: Decimal] = [:]
        for transaction in transactions where transaction.date >= first && transaction.date < rangeEnd {
            spending[calendar.weekStart(for: transaction.date), default: 0] += transaction.amount
        }
        var earned: [Date: Decimal] = [:]
        for earning in earnings { earned[calendar.weekStart(for: earning.weekStart)] = earning.amount }
        return mondays.enumerated().map { index, monday in
            WeeklyBar(
                weekStart: monday, weekLastDay: calendar.startOfDay(monday, addingDays: 6),
                spending: spending[monday] ?? 0, earnings: earned[monday], weekNumber: index + 1
            )
        }
    }

    /// Line chart: cumulative net spending per day, next to the on-track budget line
    /// `(expectedIncome − goal) × day / daysInMonth` (floored at 0, nil when `expectedIncome` is nil).
    /// Days after `now` have `cumulativeSpending == nil`.
    public static func cumulativeSeries(
        month: MonthKey, now: Date, transactions: [TransactionRecord], expectedIncome: Decimal?, goal: Decimal, calendar: LedgerCalendar
    ) -> [CumulativePoint] {
        let daysInMonth = calendar.daysInMonth(month)
        let current = MonthKey(date: now, calendar: calendar)
        let lastElapsedDay: Int
        if month == current { lastElapsedDay = calendar.dayOfMonth(now) } else if month < current { lastElapsedDay = daysInMonth } else { lastElapsedDay = 0 }

        var perDay = [Decimal](repeating: 0, count: daysInMonth + 1)
        let start = calendar.monthStart(month)
        let end = calendar.monthStart(month.next)
        for transaction in transactions where transaction.date >= start && transaction.date < end {
            let day = calendar.dayOfMonth(transaction.date)
            if day >= 1 && day <= daysInMonth { perDay[day] += transaction.amount }
        }
        let budget = expectedIncome.map { max(0, $0 - goal) }
        var running: Decimal = 0
        var points: [CumulativePoint] = []
        for day in 1...max(daysInMonth, 1) {
            running += perDay[day]
            points.append(CumulativePoint(
                day: day,
                date: calendar.startOfDay(start, addingDays: day - 1),
                cumulativeSpending: day <= lastElapsedDay ? running : nil,
                onTrack: budget.map { $0 * Decimal(day) / Decimal(daysInMonth) }
            ))
        }
        return points
    }

    /// Grouped bars: each category's spending this month vs the month before (both clamped at 0),
    /// in category sort order. Categories with nothing in either month are left out.
    public static func monthOverMonth(
        month: MonthKey, transactions: [TransactionRecord], categories: [CategoryRecord], calendar: LedgerCalendar
    ) -> [CategoryComparison] {
        let resolver = CategoryResolver(categories: categories)
        let current = BudgetEngine.spendingByCategory(
            from: calendar.monthStart(month), to: calendar.monthStart(month.next), transactions: transactions, categories: categories
        )
        let previous = BudgetEngine.spendingByCategory(
            from: calendar.monthStart(month.previous), to: calendar.monthStart(month), transactions: transactions, categories: categories
        )
        var rows: [(row: CategoryComparison, order: Int)] = []
        for id in Set(current.keys).union(previous.keys) {
            let now = max(0, current[id] ?? 0)
            let before = max(0, previous[id] ?? 0)
            guard now > 0 || before > 0 else { continue }
            let record = resolver.record(id)
            rows.append((CategoryComparison(categoryID: id, name: record.name, colorHex: record.colorHex, current: now, previous: before), record.sortOrder))
        }
        rows.sort {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.row.categoryID.uuidString < $1.row.categoryID.uuidString
        }
        return rows.map { $0.row }
    }

    /// Top merchants by net spending this month, with last month's figure for comparison.
    /// Merchants are grouped by normalized name; blank merchants and merchants at or below 0 are left out.
    public static func topMerchants(
        month: MonthKey, transactions: [TransactionRecord], calendar: LedgerCalendar, limit: Int = 5
    ) -> [MerchantSpend] {
        let start = calendar.monthStart(month)
        let end = calendar.monthStart(month.next)
        let previousStart = calendar.monthStart(month.previous)

        struct Entry { var total: Decimal = 0; var count = 0; var name = ""; var latest = Date.distantPast }
        var current: [String: Entry] = [:]
        var previous: [String: Decimal] = [:]
        for transaction in transactions where transaction.date >= previousStart && transaction.date < end {
            let key = MerchantNormalizer.normalize(transaction.merchant)
            guard !key.isEmpty else { continue }
            if transaction.date >= start {
                var entry = current[key] ?? Entry()
                entry.total += transaction.amount
                entry.count += 1
                if transaction.date >= entry.latest {
                    entry.latest = transaction.date
                    entry.name = MerchantNormalizer.displayName(transaction.merchant)
                }
                current[key] = entry
            } else {
                previous[key, default: 0] += transaction.amount
            }
        }
        let ranked = current.filter { $0.value.total > 0 }.sorted {
            if $0.value.total != $1.value.total { return $0.value.total > $1.value.total }
            return $0.key < $1.key
        }
        guard let top = ranked.first?.value.total, top > 0 else { return [] }
        return ranked.prefix(max(0, limit)).map { key, entry in
            MerchantSpend(
                normalizedMerchant: key, displayName: entry.name, amount: entry.total,
                previousAmount: max(0, previous[key] ?? 0), transactionCount: entry.count, fractionOfTop: entry.total / top
            )
        }
    }

    // MARK: List helpers

    /// Groups transactions by calendar day, newest day first, newest transaction first within a day,
    /// each with its net daily total.
    public static func groupByDay(_ transactions: [TransactionRecord], calendar: LedgerCalendar) -> [DayGroup] {
        var buckets: [Date: [TransactionRecord]] = [:]
        for transaction in transactions {
            buckets[calendar.startOfDay(transaction.date), default: []].append(transaction)
        }
        return buckets.keys.sorted(by: >).map { day in
            let items = (buckets[day] ?? []).sorted {
                if $0.date != $1.date { return $0.date > $1.date }
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            return DayGroup(day: day, total: items.reduce(Decimal(0)) { $0 + $1.amount }, transactions: items)
        }
    }

    /// Applies search and filters. Order is preserved.
    public static func filter(_ transactions: [TransactionRecord], with filter: TransactionFilter, categories: [CategoryRecord] = []) -> [TransactionRecord] {
        if filter.isEmpty { return transactions }
        return transactions.filter { filter.matches($0, categories: categories) }
    }

    /// Search only: merchant or notes contains the text (case- and accent-insensitive).
    public static func search(_ transactions: [TransactionRecord], text: String) -> [TransactionRecord] {
        filter(transactions, with: TransactionFilter(searchText: text))
    }

    /// Transactions flagged for review, newest first.
    public static func needsReview(_ transactions: [TransactionRecord]) -> [TransactionRecord] {
        transactions.filter { $0.needsReview }.sorted { $0.date > $1.date }
    }

    /// Most recent transactions, newest first.
    public static func recent(_ transactions: [TransactionRecord], limit: Int = 5) -> [TransactionRecord] {
        Array(transactions.sorted { $0.date > $1.date }.prefix(max(0, limit)))
    }

    /// Merchant autocomplete: distinct past merchant names whose text starts with (or, failing that, contains)
    /// `prefix`, most frequently used first. An empty prefix returns the most used merchants.
    public static func merchantSuggestions(prefix: String, from merchants: [String], limit: Int = 6) -> [String] {
        let needle = MerchantNormalizer.searchKey(prefix).trimmingCharacters(in: .whitespacesAndNewlines)
        struct Entry { var name: String; var count: Int; var firstIndex: Int }
        var entries: [String: Entry] = [:]
        for (index, raw) in merchants.enumerated() {
            let name = MerchantNormalizer.displayName(raw)
            guard !name.isEmpty else { continue }
            let key = MerchantNormalizer.searchKey(name)
            if var entry = entries[key] {
                entry.count += 1
                entries[key] = entry
            } else {
                entries[key] = Entry(name: name, count: 1, firstIndex: index)
            }
        }
        func ranked(_ keys: [String]) -> [String] {
            keys.compactMap { entries[$0] }.sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.firstIndex < $1.firstIndex
            }.map { $0.name }
        }
        if needle.isEmpty { return Array(ranked(Array(entries.keys)).prefix(max(0, limit))) }
        let starts = entries.keys.filter { $0.hasPrefix(needle) }
        let contains = entries.keys.filter { !$0.hasPrefix(needle) && $0.contains(needle) }
        return Array((ranked(starts) + ranked(contains)).prefix(max(0, limit)))
    }

    /// Distinct payment methods used, Cash first, then Other card, then Wallet cards by name — for the filter sheet.
    public static func paymentMethods(in transactions: [TransactionRecord]) -> [PaymentMethod] {
        let all = Set(transactions.map { $0.paymentMethod })
        func rank(_ method: PaymentMethod) -> (Int, String) {
            switch method {
            case .cash: return (0, "")
            case .otherCard: return (1, "")
            case .walletCard(let name): return (2, name.lowercased())
            }
        }
        return all.sorted { rank($0) < rank($1) }
    }
}
