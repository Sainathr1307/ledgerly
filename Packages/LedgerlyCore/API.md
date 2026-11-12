# LedgerlyCore API reference

Pure Swift, Foundation only. `import LedgerlyCore`. Every signature below is copied from the sources
(`Sources/LedgerlyCore/`); default argument values are real. Everything public is `Sendable`, and every public
struct has a public memberwise `init` (shown).

Verified on Linux with Swift 5.10 + `StrictConcurrency` (374 XCTest tests, zero warnings). Not compiled with
Xcode / Swift 6 by the author; see "Things to know" at the end.

## How the pieces fit (cheat sheet)

```swift
let cal = LedgerCalendar.current                      // or LedgerCalendar(timeZone:) — pass it everywhere
let month = MonthKey(date: now, calendar: cal)

// Dashboard
let snap = BudgetEngine.snapshot(month: month, now: now, transactions: allTx, earnings: allEarnings,
                                 goal: goalAmount, categories: allCategoriesIncludingArchived, calendar: cal)
snap.safeToSpendPerDay      // Decimal?  nil → show "Add your earnings to see this"
snap.projectedSavings       // Decimal?
snap.goalProgressValue      // Double? 0...1 for the ring
let cards = InsightsEngine.insights(snapshot: snap, transactions: allTx, categories: cats, calendar: cal)
let top3  = InsightsEngine.top(cards)                 // already sorted by priority

// Charts
ChartData.categoryBreakdown(month: month, transactions: allTx, categories: cats, calendar: cal)
ChartData.weeklyBars(month: month, transactions: allTx, earnings: allEarnings, calendar: cal)
ChartData.cumulativeSeries(month: month, now: now, transactions: allTx,
                           expectedIncome: snap.expectedIncome, goal: snap.goal, calendar: cal)
ChartData.monthOverMonth(month: month, transactions: allTx, categories: cats, calendar: cal)
ChartData.topMerchants(month: month, transactions: allTx, calendar: cal)

// Transaction list
let visible = ChartData.filter(allTx, with: filter, categories: cats)
let groups  = ChartData.groupByDay(visible, calendar: cal)      // [DayGroup] with daily totals

// "Log Wallet Transaction" intent
let ingestor = TransactionIngestor(categorizer: Categorizer(rules: rules, categories: cats))
let result = ingestor.ingest(IncomingTransaction(rawAmount: amountText, merchant: merchant, cardName: card, date: now),
                             existing: recentTx, now: now)
// save result.record (always — bad input is flagged needsReview, never dropped), then notify:
TransactionIngestor.notificationTitle(for: result.record)
TransactionIngestor.notificationText(for: result.record, categoryName: categoryName)

// Manual add / edit
Categorizer(rules: rules, categories: cats).categorize(merchant: text).categoryID
MerchantRule(normalizedMerchant: MerchantNormalizer.normalize(tx.merchant), categoryID: newID)   // "Always categorize…"
ChartData.merchantSuggestions(prefix: typed, from: knownMerchants)
AmountParser.parse(text)                                                                         // Decimal?

// Monthly goal sheet / Monday reminder
GoalPrompt.shouldPrompt(lastPromptMonth: settings.lastGoalPromptMonth, now: now, calendar: cal)
GoalPrompt.monthString(now: now, calendar: cal)      // store after showing
GoalPrompt.prefillAmount(previousGoal: lastGoal)     // $200 the first time
EarningsReminder.isLastWeekMissing(earnings: allEarnings, now: now, calendar: cal)   // dashboard card
EarningsReminder.lastWeekStart(now: now, calendar: cal)                              // the weekStart to save
EarningsReminder.weeklyTriggerComponents(hour: 8, minute: 0)                         // UNCalendarNotificationTrigger(repeats: true)

// CSV
let prepared = CSVImporter.prepare(text: fileText, existing: allTx, ingestor: ingestor, calendar: cal, now: now)
// show prepared.mapping for the mapping step; after edits re-run CSVImporter.prepare(rows:mapping:…)
// save prepared.result.newRecords
CSV.export(transactions: allTx, categories: cats, calendar: cal)

// DEBUG demo data
let demo = DemoData.generate(now: now, calendar: cal)   // .transactions .earnings .goals .categories

// Display
MoneyFormat.string(amount)   // "$12.40"      MoneyFormat.whole(amount)   // "$310"
```

## Behaviour that is easy to get wrong

- **Money** is `Decimal` everywhere. Snapshot values are unrounded; format with `MoneyFormat` (rounding mode `.plain`,
  half away from zero). `Double` accessors (`value`, `…Value`) exist only on chart types, for plotting.
- **`now` and `LedgerCalendar` are always passed in.** Nothing in the package calls `Date()`. (`TransactionRecord.init`'s
  `id` default and `ingest`'s `id` default call `UUID()`.) `TransactionRecord.createdAt` has no default.
- **`locale:` parameters default to `.current`**; tests pass `Locale(identifier: "en_US")`.
- **Categories:** pass every category (archived too) to `BudgetEngine`, `ChartData` and `InsightsEngine`. A transaction with
  `categoryID == nil`, or an id that is not in the list, is counted under the category whose `systemKey == "other"`.
  `Categorizer` never picks an archived category.
- **Weeks** are Monday–Sunday; a week (and its earnings) belongs to the month its Monday falls in. `WeeklyEarning.weekStart`
  should be `calendar.weekStart(for:)`; the engines re-normalize it anyway. If two entries land in one week the later array element wins.
- **Intervals** are half-open `[start, end)`. `LedgerCalendar.monthInterval` returns a `DateInterval` whose `contains`
  includes the end instant — use `calendar.contains(_:in:)` or compare by hand.
- **`BudgetSnapshot` optionals** (`expectedIncome`, `projectedSavings`, `safeToSpendPerDay`, `isOnTrack`, `gap`, `goalProgress`,
  `spendingBudget`, `remainingBudget`) are nil exactly when `incomeBasis == .unknown`.
- **Past month:** `dayOfMonth == daysInMonth`, `daysLeft == 0`, `projectedSpending == spent`, `safeToSpendPerDay == 0`
  (when income is known). **Future month:** `dayOfMonth == 0`, `daysLeft == daysInMonth`, projection = trailing average.
- **Remaining weeks** = every Monday in the month without an entry (including past weeks the user skipped).
- **`spentByCategory` can be negative** (refund larger than spending). Chart types clamp at 0 and drop such slices.
- **Needs Review:** `ingest` flags amount 0 (`.zeroAmount`), blank/unparseable amount (`.unparseableAmount`, stored as 0),
  blank merchant (`.blankMerchant`, stored as `""`) and possible duplicates (`.possibleDuplicate`, also sets
  `isPossibleDuplicate`). Zero-amount transactions are never reported as duplicates.
- **Duplicates (live):** same amount + currency AND (same non-blank normalized merchant OR same Wallet card name,
  case-insensitive) with dates ≤ 180 s apart (inclusive). **Duplicates (CSV):** same calendar day + amount + normalized merchant.
- **Insights:** `Insight.gapPlan` is non-nil only for `.gapPlan`; `Insight.merchants` only for `.topMerchants`.
  With unknown income the list starts with `.missingIncome` and has no `.gapPlan` / `.goalOnTrack`.
  `GapPlan.cuts` sum exactly to `gap − uncovered`; `cuts` can be empty (nothing left to trim) with `uncovered == gap`.
- **`PaymentMethod` Codable** encodes as `{"kind": kindRaw, "cardName": …}`. For SwiftData store `kindRaw` + `cardName`
  and rebuild with `PaymentMethod(kindRaw:cardName:)`.
- **Default category ids** are `4C454447-4552-4C59-8000-0000000000NN` with NN = 01…0A in the order food, groceries, gas,
  shopping, recreation, bills, transportation, health, subscriptions, other.

| systemKey | name | colorHex | symbolName |
|---|---|---|---|
| food | Food & Dining | #E8590C | fork.knife |
| groceries | Groceries | #2F9E44 | cart.fill |
| gas | Gas | #E03131 | fuelpump.fill |
| shopping | Shopping | #7048E8 | bag.fill |
| recreation | Recreation & Entertainment | #D6336C | gamecontroller.fill |
| bills | Bills & Utilities | #F59F00 | bolt.fill |
| transportation | Transportation | #1C7ED6 | car.fill |
| health | Health | #0CA678 | cross.case.fill |
| subscriptions | Subscriptions | #AE3EC9 | repeat |
| other | Other | #868E96 | ellipsis.circle.fill |

# Signatures by file

Trailing `// …` comments are the first sentence of each doc comment; the sources have the full text.
Computed properties are shown without their bodies. `case` lines are enum cases.

## Models.swift

```swift

/// Where a transaction came from.
public enum SourceKind: String, Codable, CaseIterable, Sendable {
    case walletShortcut, financeKit, manual, csvImport
    public var displayName: String   // Short human-readable label for filters and badges
}

/// How a purchase was paid for.
public enum PaymentMethod: Hashable, Codable, Sendable {
    case cash, otherCard, walletCard(String)
    public var kindRaw: String   // "cash" | "otherCard" | "walletCard" — the string stored by the SwiftData mirror
    public var cardName: String?   // The Wallet card name, only for `.walletCard`
    public init(kindRaw: String, cardName: String?)   // Rebuilds a payment method from its stored parts
    public var displayName: String   // "Cash", "Other card", or the card name
    public init(from decoder: Decoder) throws
    public func encode(to encoder: Encoder) throws
}

/// One purchase or refund.
public struct TransactionRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var amount: Decimal   // > 0 expense, < 0 refund
    public var currencyCode: String
    public var merchant: String
    public var categoryID: UUID?
    public var date: Date
    public var paymentMethod: PaymentMethod
    public var source: SourceKind
    public var notes: String
    public var needsReview: Bool
    public var isPossibleDuplicate: Bool
    public var createdAt: Date
    public init(id: UUID = UUID(), amount: Decimal, currencyCode: String = "USD", merchant: String, categoryID: UUID? = nil, date: Date, paymentMethod: PaymentMethod = .cash, source: SourceKind = .manual, notes: String = "", needsReview: Bool = false, isPossibleDuplicate: Bool = false, createdAt: Date)
    public var isRefund: Bool   // True for refunds (negative amounts)
}

/// A spending category.
public struct CategoryRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var colorHex: String   // "#RRGGBB"
    public var symbolName: String   // SF Symbol name
    public var sortOrder: Int
    public var isArchived: Bool
    public var systemKey: String?   // food, groceries, gas, shopping, recreation, bills, transportation, health, subscriptions, other; nil for user-made
    public init(id: UUID = UUID(), name: String, colorHex: String, symbolName: String, sortOrder: Int, isArchived: Bool = false, systemKey: String? = nil)
    public var isDiscretionary: Bool   // Food & Dining, Shopping, Recreation, Subscriptions and every user-made category
    public var isProtected: Bool   // Bills & Utilities and Health — never part of a cut list
    public static let discretionaryKeys: [String]   // System keys of the built-in discretionary categories, in gap-plan cut order
}

/// The ten built-in categories.
public enum DefaultCategories {
    public static let all: [CategoryRecord]
    public static let systemKeys: [String]   // All system keys in default order
    public static func id(_ systemKey: String) -> UUID   // Fixed id of a default category
    public static func category(_ systemKey: String) -> CategoryRecord?   // The default record for a system key, if the key is known
    public static var otherID: UUID   // Id of the "Other" category
}

/// A learned "always categorize this merchant as…" rule.
public struct MerchantRule: Hashable, Codable, Sendable {
    public var normalizedMerchant: String
    public var categoryID: UUID
    public init(normalizedMerchant: String, categoryID: UUID)
}

/// Earnings for one Monday–Sunday week.
public struct WeeklyEarning: Hashable, Codable, Sendable {
    public var weekStart: Date
    public var amount: Decimal
    public init(weekStart: Date, amount: Decimal)
}

/// A calendar month (Gregorian).
public struct MonthKey: Hashable, Comparable, Codable, Sendable {
    public var year: Int
    public var month: Int
    public init(year: Int, month: Int)   // Out-of-range months are carried into the year (month 13 → January of next year, month 0 → December of the previous one)
    public init(date: Date, calendar: LedgerCalendar)
    public var previous: MonthKey
    public var next: MonthKey
    public func adding(months count: Int) -> MonthKey   // The month `count` months later (negative = earlier)
    public var stringValue: String   // "yyyy-MM", e.g. "2026-03"
    public init?(string: String)   // Parses "yyyy-MM"
    public static func < (lhs: MonthKey, rhs: MonthKey) -> Bool
}

/// The savings goal for one month.
public struct MonthlyGoal: Hashable, Codable, Sendable {
    public var month: MonthKey
    public var amount: Decimal
    public init(month: MonthKey, amount: Decimal)
}
```

## LedgerCalendar.swift

```swift

/// The one place that knows about weeks, months, time zones and daylight saving.
public struct LedgerCalendar: Hashable, Sendable {
    public let calendar: Calendar   // Gregorian calendar with `firstWeekday = 2` (Monday) in the chosen time zone
    public var timeZone: TimeZone
    public init(timeZone: TimeZone = .current)   // A ledger calendar in the given time zone (default: the device's current zone)
    public init(calendar: Calendar)   // Uses the time zone of `calendar`
    public init?(timeZoneIdentifier: String)   // Convenience for tests and previews
    public static var current: LedgerCalendar   // The device's current time zone
    public func startOfDay(_ date: Date) -> Date
    public func startOfDay(_ date: Date, addingDays days: Int) -> Date   // Start of the day `days` calendar days after the day containing `date` (negative = before)
    public func date(byAddingDays days: Int, to date: Date) -> Date   // Adds calendar days keeping the wall-clock time where possible
    public func isSameDay(_ a: Date, _ b: Date) -> Bool
    public func weekday(_ date: Date) -> Int   // 1 = Sunday, 2 = Monday … 7 = Saturday
    public func isWeekend(_ date: Date) -> Bool   // Saturday or Sunday
    public func dayOfMonth(_ date: Date) -> Int   // Day of the month, 1-based
    public func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0) -> Date?   // Builds a date from wall-clock parts in this calendar's time zone
    public func weekStart(for date: Date) -> Date   // Monday 00:00 of the week containing `date`
    public func nextWeekStart(after date: Date) -> Date   // Monday 00:00 of the following week
    public func weekInterval(for date: Date) -> DateInterval   // Monday 00:00 up to (not including) the next Monday 00:00
    public func weekLastDay(for date: Date) -> Date   // Start of the Sunday that ends the week containing `date`
    public func lastCompletedWeekStart(now: Date) -> Date   // Monday 00:00 of the most recent week that has fully ended (the week before the one containing `now`)
    public func monthKey(forWeekContaining date: Date) -> MonthKey   // The month a week counts toward: the month its Monday falls in
    public func monthKey(for date: Date) -> MonthKey
    public func monthStart(_ month: MonthKey) -> Date   // First instant of the month
    public func monthInterval(_ month: MonthKey) -> DateInterval   // First instant of the month up to the first instant of the next month
    public func contains(_ date: Date, in month: MonthKey) -> Bool   // True when `date` falls inside the month (end exclusive)
    public func daysInMonth(_ month: MonthKey) -> Int
    public func date(day: Int, of month: MonthKey) -> Date   // Start of the given day of the month
    public func days(in month: MonthKey) -> [Date]   // Start of every day in the month, in order
    public func mondays(in month: MonthKey) -> [Date]   // Every Monday (00:00) that falls in the month — four or five of them
}
```

## AmountParser.swift

```swift

/// Turns the text Shortcuts (or a CSV cell) hands us into a `Decimal`.
public enum AmountParser {
    public static func parse(_ text: String, locale: Locale = .current) -> Decimal?   // Parses an amount
}
```

## MerchantNormalizer.swift

```swift

/// Cleans merchant names so "SHELL OIL 57444", "Shell Oil #57444" and "shell oil" all match.
public enum MerchantNormalizer {
    public static func normalize(_ raw: String) -> String   // Normalizes a merchant name for matching: uppercase → strip diacritics → drop apostrophes → other punctuation becomes a space → drop processor prefixes ("SQ *") → drop st…
    public static func tokens(_ normalized: String) -> [String]   // Splits a normalized name into its words
    public static func displayName(_ raw: String) -> String   // Trims and collapses whitespace but otherwise keeps the name as the user/Wallet wrote it
    public static func isBlank(_ raw: String?) -> Bool   // True when the name is empty or only whitespace
    public static func searchKey(_ text: String) -> String   // Lowercases and strips diacritics — the folding used by search so "cafe" finds "Café"
}
```

## Categorizer.swift

```swift

/// Why a category was chosen.
public enum CategorizationReason: String, Codable, Sendable {
    case learnedRule   // The user's own "always categorize X as Y" rule
    case categoryHint   // A category name supplied with the data (e.g. a CSV "Category" column)
    case builtInKeyword   // The built-in keyword table
    case fallback   // Nothing matched → Other
}

public struct CategorizationResult: Hashable, Sendable {
    public var categoryID: UUID
    public var reason: CategorizationReason
    public var matchedKeyword: String?   // The built-in keyword (normalized) that matched, for `.builtInKeyword`
    public init(categoryID: UUID, reason: CategorizationReason, matchedKeyword: String? = nil)
}

/// One row of the built-in keyword table.
public struct KeywordRule: Hashable, Sendable {
    public var tokens: [String]   // Normalized words that must appear next to each other as whole words, e.g. ["TRADER", "JOES"]
    public var systemKey: String
    public var isGeneric: Bool   // Generic words ("PIZZA", "PHARMACY") lose to brand names
    public init(tokens: [String], systemKey: String, isGeneric: Bool = false)
    public var keyword: String
}

/// Picks a category for a merchant: (1) learned rule, (2) built-in keywords, (3) Other.
public struct Categorizer: Sendable {
    public let rules: [MerchantRule]
    public let categories: [CategoryRecord]
    public init(rules: [MerchantRule] = [], categories: [CategoryRecord] = DefaultCategories.all)   // - Parameters: - rules: learned merchant → category rules (`normalizedMerchant` is re-normalized defensively)
    public func categorize(merchant: String, categoryHint: String? = nil) -> CategorizationResult   // Categorizes a raw merchant name
    public func categoryID(forName name: String) -> UUID?   // Finds a non-archived category by its name (case-insensitive), or by a common bank-export category word ("Restaurants", "Grocery", "Entertainment", …)
    public var fallbackCategoryID: UUID   // The category id used when nothing matches
    public static func builtInSystemKey(for merchant: String) -> String?   // The system key the built-in table gives a raw merchant name, ignoring learned rules
    public static func isCoffeeMerchant(_ merchant: String) -> Bool   // True for coffee shops ("STARBUCKS", "… COFFEE", "CAFE …")
    public static let builtInKeywords: [KeywordRule]   // The whole built-in table, normalized
}
```

## DuplicateDetector.swift

```swift

/// Detects "the same purchase logged twice".
public enum DuplicateDetector {
    public static let windowSeconds: TimeInterval   // Three minutes, inclusive
    public static func isDuplicate(_ a: TransactionRecord, _ b: TransactionRecord) -> Bool   // True when `a` and `b` look like the same purchase
    public static func findDuplicate(of candidate: TransactionRecord, in existing: [TransactionRecord]) -> TransactionRecord?   // The first existing record that `candidate` duplicates, if any
    public static func findDuplicate(amount: Decimal, currencyCode: String = "USD", merchant: String, paymentMethod: PaymentMethod, date: Date, in existing: [TransactionRecord]) -> TransactionRecord?   // Same check for a transaction that has not been built yet
}
```

## Ingest.swift

```swift

/// A transaction as it arrives from outside: the Wallet shortcut, FinanceKit or a CSV row.
public struct IncomingTransaction: Hashable, Codable, Sendable {
    public var rawAmount: String   // The amount exactly as received ("$12.40", "12,40", "", …)
    public var merchant: String?
    public var cardName: String?   // Wallet card name, if any
    public var date: Date
    public var source: SourceKind
    public var currencyCode: String?   // Nil → the ingestor's default currency
    public var notes: String
    public var categoryHint: String?   // A category name that came with the data (CSV "Category" column)
    public var negateAmount: Bool   // Flip the sign after parsing
    public init(rawAmount: String, merchant: String? = nil, cardName: String? = nil, date: Date, source: SourceKind = .walletShortcut, currencyCode: String? = nil, notes: String = "", categoryHint: String? = nil, negateAmount: Bool = false)
}

/// Why an ingested transaction was sent to Needs Review.
public enum ReviewReason: String, Codable, CaseIterable, Sendable {
    case zeroAmount   // The amount parsed to exactly 0
    case unparseableAmount   // The amount was blank or not a number; it is stored as 0
    case blankMerchant   // No merchant name; it is stored as ""
    case possibleDuplicate   // Matches an existing transaction within three minutes
}

public struct IngestResult: Hashable, Sendable {
    public var record: TransactionRecord   // The record to save
    public var categorization: CategorizationResult
    public var reviewReasons: [ReviewReason]   // Empty when the transaction is clean
    public var duplicateOfID: UUID?   // The id of the existing transaction this one seems to duplicate
    public init(record: TransactionRecord, categorization: CategorizationResult, reviewReasons: [ReviewReason] = [], duplicateOfID: UUID? = nil)
}

/// Pure pipeline: `IncomingTransaction` → parsed, categorized, duplicate-checked `TransactionRecord`.
public struct TransactionIngestor: Sendable {
    public let categorizer: Categorizer
    public let defaultCurrencyCode: String
    public init(categorizer: Categorizer, locale: Locale = .current, defaultCurrencyCode: String = "USD")   // - Parameter locale: used by `AmountParser` for ambiguous amounts such as "1,234"
    public var locale: Locale
    public func ingest(_ incoming: IncomingTransaction, existing: [TransactionRecord] = [], now: Date, id: UUID = UUID(), checkDuplicates: Bool = true) -> IngestResult   // Builds the record to save
    public static func notificationTitle(for record: TransactionRecord) -> String   // Title for the local notification posted after logging
    public static func notificationText(for record: TransactionRecord, categoryName: String?, locale: Locale = .current) -> String   // Body for the local notification: - clean: "Logged $12.40 at Starbucks · Food & Dining" (refund: "Logged $5.00 refund from Target · Shopping") - duplicate: "Possible dupl…
}

/// A place transactions can be pulled from (FinanceKit conforms in the app, behind a flag).
public protocol TransactionSource: Sendable {
    var kind: SourceKind { get }
    func isAvailable() async -> Bool                                   // false when the source can't work on this device/build
    func fetch(since: Date?) async throws -> [IncomingTransaction]     // nil = everything the source has
}

/// When to show the monthly "How much do you want to save this month?" sheet.
public enum GoalPrompt {
    public static var defaultGoal: Decimal   // $200 — the goal used the very first time
    public static func monthString(now: Date, calendar: LedgerCalendar) -> String   // "yyyy-MM" for the month containing `now` — store this in `AppSettings.lastGoalPromptMonth` after showing the sheet
    public static func shouldPrompt(lastPromptMonth: String?, now: Date, calendar: LedgerCalendar) -> Bool   // True on first launch (nil/blank/garbled `lastPromptMonth`) and on the first open of any month other than the one last prompted for
    public static func prefillAmount(previousGoal: Decimal?) -> Decimal   // What to pre-fill: last month's goal, or $200 the first time
}

/// The Monday "what did you earn last week?" reminder.
public enum EarningsReminder {
    public static let notificationTitle: String  // = "New week!"
    public static let notificationBody: String  // = "What did you earn last week?"
    public static func lastWeekStart(now: Date, calendar: LedgerCalendar) -> Date   // Monday 00:00 of the week that just ended
    public static func isLastWeekMissing(earnings: [WeeklyEarning], now: Date, calendar: LedgerCalendar) -> Bool   // True when no earning is stored for the week that just ended (an entered amount of 0 counts as entered)
    public static func missingWeekStarts(earnings: [WeeklyEarning], now: Date, calendar: LedgerCalendar, weeksBack: Int = 4) -> [Date]   // Past weeks with no entry, oldest first, going back `weeksBack` completed weeks
    public static func weeklyTriggerComponents(hour: Int = 8, minute: Int = 0) -> DateComponents   // Components for a repeating `UNCalendarNotificationTrigger`: every Monday at hour:minute local time
    public static func nextReminderDate(after now: Date, hour: Int = 8, minute: Int = 0, calendar: LedgerCalendar) -> Date   // The next time the reminder fires strictly after `now`: today if it is Monday before hour:minute, otherwise next Monday
    public static func nextReminderComponents(after now: Date, hour: Int = 8, minute: Int = 0, calendar: LedgerCalendar) -> DateComponents   // Year/month/day/hour/minute (plus weekday 2) of `nextReminderDate`, for a one-off trigger
}
```

## BudgetEngine.swift

```swift

/// Where the expected-income number came from.
public enum IncomeBasis: String, Codable, Sendable {
    case entered   // At least one week of earnings is entered for the month
    case estimatedFromHistory   // Nothing entered for the month yet; estimated from the most recent (up to 8) earlier weeks
    case unknown   // No earnings data at all — income-dependent numbers are nil
}

/// Everything the dashboard needs for one month.
public struct BudgetSnapshot: Hashable, Sendable {
    public var month: MonthKey
    public var isCurrentMonth: Bool   // `now` falls inside `month`
    public var isPastMonth: Bool   // `month` ended before `now` (treated as fully elapsed)
    public var daysInMonth: Int
    public var dayOfMonth: Int   // Days elapsed, today included
    public var daysLeft: Int   // Days left, today included (`daysInMonth − dayOfMonth + 1`)
    public var incomeSoFar: Decimal   // Sum of weekly earnings whose Monday falls in the month
    public var expectedIncome: Decimal?   // `incomeSoFar + average(entered weeks) × remainingWeeks`; estimated from history when nothing is entered; nil when unknown
    public var incomeBasis: IncomeBasis
    public var enteredWeeks: Int   // Mondays in the month that have an earnings entry
    public var remainingWeeks: Int   // Mondays in the month with no entry yet
    public var averageWeeklyIncome: Decimal?   // The weekly average used for the remaining weeks (nil when unknown)
    public var spent: Decimal   // Expenses minus refunds this month
    public var spentByCategory: [UUID: Decimal]   // Per category; may be negative when refunds exceed spending
    public var projectedSpending: Decimal   // Sum of `projectedByCategory`
    public var projectedByCategory: [UUID: Decimal]
    public var trailingAverageByCategory: [UUID: Decimal]   // Average monthly total per category over the prior months (up to 3) that have data
    public var usualByThisDayByCategory: [UUID: Decimal]   // `trailingAverage × dayOfMonth / daysInMonth` — what is usual by this point in the month
    public var historyMonthCount: Int   // How many of the 3 prior months have any transactions (0–3)
    public var projectedSavings: Decimal?   // `expectedIncome − projectedSpending`; nil when income is unknown
    public var goal: Decimal
    public var safeToSpendPerDay: Decimal?   // `max(0, (expectedIncome − goal − spent) / daysLeft)`; nil when income is unknown; 0 for a past month
    public var isOnTrack: Bool?   // `projectedSavings ≥ goal`; nil when income is unknown
    public init(month: MonthKey, isCurrentMonth: Bool, isPastMonth: Bool, daysInMonth: Int, dayOfMonth: Int, daysLeft: Int, incomeSoFar: Decimal, expectedIncome: Decimal?, incomeBasis: IncomeBasis, enteredWeeks: Int, remainingWeeks: Int, averageWeeklyIncome: Decimal?, spent: Decimal, spentByCategory: [UUID: Decimal], projectedSpending: Decimal, projectedByCategory: [UUID: Decimal], trailingAverageByCategory: [UUID: Decimal], usualByThisDayByCategory: [UUID: Decimal], historyMonthCount: Int, projectedSavings: Decimal?, goal: Decimal, safeToSpendPerDay: Decimal?, isOnTrack: Bool?)
    public var totalWeeks: Int   // Mondays in the month
    public var hasHistory: Bool   // At least one of the three prior months has transactions
    public var savedSoFar: Decimal   // `incomeSoFar − spent`: what has actually been kept so far
    public var spendingBudget: Decimal?   // `expectedIncome − goal`: the month's spending budget
    public var remainingBudget: Decimal?   // `spendingBudget − spent`, may be negative
    public var gap: Decimal?   // `max(0, goal − projectedSavings)`: how far short of the goal the month is heading
    public var goalProgress: Decimal?   // Progress toward the goal for a ring: `projectedSavings / goal` clamped to 0...1 (1 when the goal is 0)
    public var goalProgressValue: Double?   // `goalProgress` as a `Double` for drawing
    public var isEmpty: Bool   // True when there is neither spending nor income for the month
}

/// All month math.
public enum BudgetEngine {
    public static func snapshot(month: MonthKey, now: Date, transactions: [TransactionRecord], earnings: [WeeklyEarning], goal: Decimal, categories: [CategoryRecord], calendar: LedgerCalendar) -> BudgetSnapshot   // Builds the snapshot for `month` as seen at `now`
    public struct IncomeEstimate: Hashable, Sendable {   // Income numbers for a month
        public var soFar: Decimal
        public var expected: Decimal?
        public var basis: IncomeBasis
        public var enteredWeeks: Int
        public var remainingWeeks: Int
        public var weeklyAverage: Decimal?
        public init(soFar: Decimal, expected: Decimal?, basis: IncomeBasis, enteredWeeks: Int, remainingWeeks: Int, weeklyAverage: Decimal?)
    }
    public static func incomeEstimate(month: MonthKey, earnings: [WeeklyEarning], calendar: LedgerCalendar) -> IncomeEstimate   // Income so far and expected income for `month`
    public static func spendingByCategory(from start: Date, to end: Date, transactions: [TransactionRecord], categories: [CategoryRecord]) -> [UUID: Decimal]   // Net spending (expenses minus refunds) per category for transactions dated in `[start, end)`
    public static func transactions(in month: MonthKey, from transactions: [TransactionRecord], calendar: LedgerCalendar) -> [TransactionRecord]   // The transactions dated inside `month`
    public static func effectiveCategoryID(_ categoryID: UUID?, categories: [CategoryRecord]) -> UUID   // The category id a transaction is counted under: its own when that category exists, otherwise "other"
}
```

## InsightsEngine.swift

```swift

public enum InsightKind: String, Codable, CaseIterable, Sendable {
    case missingIncome   // No earnings data: "add your earnings" instead of guessed numbers
    case gapPlan   // Projected savings are below the goal: the cut list
    case goalOnTrack   // Projected savings meet the goal (or, for a past month, the goal was met)
    case goalMissed   // A past month that ended below its goal
    case overPace   // A category well above its usual amount for this point in the month
    case frequentSmallPurchases   // Many small purchases at one place (or coffee runs)
    case topMerchants   // Top merchants and how they changed versus last month
    case weekendVsWeekday   // Weekend and weekday daily spending differ a lot
    case underUsual   // A category well under its usual amount
    case incomeEstimated   // Expected income is an estimate from earlier weeks
}

public enum InsightSentiment: String, Codable, Sendable {
    case warning, positive, neutral
}

/// One line of a gap-closing plan.
public struct GapCut: Identifiable, Hashable, Sendable {
    public var categoryID: UUID
    public var categoryName: String
    public var amount: Decimal   // How much to cut, to the cent
    public var note: String   // Standalone wording, e.g. "Cut dining out by $45" or "Pause one subscription ($15)"
    public var suggestion: String?   // Extra hint for the Subscriptions cut, e.g. "Spotify is $11.99 a month." Nil otherwise
    public init(categoryID: UUID, categoryName: String, amount: Decimal, note: String, suggestion: String? = nil)
    public var id: UUID
}

/// The concrete "how to still hit the goal" plan.
public struct GapPlan: Hashable, Sendable {
    public var goal: Decimal
    public var gap: Decimal   // `goal − projectedSavings`, rounded to cents (always > 0)
    public var cuts: [GapCut]   // Cuts in order: Food & Dining, Shopping, Recreation, Subscriptions, then user-made categories
    public var uncovered: Decimal   // `gap − sum(cuts)`: what cannot be covered by cutting discretionary spending (0 when the plan closes the gap)
    public init(goal: Decimal, gap: Decimal, cuts: [GapCut], uncovered: Decimal)
    public var totalCuts: Decimal   // Sum of the cut amounts
    public var closesGap: Bool   // The cuts cover the whole gap
}

/// A plain-English insight card.
public struct Insight: Identifiable, Hashable, Sendable {
    public var id: String   // Stable for a given kind + subject (e.g. "overPace-<category uuid>")
    public var kind: InsightKind
    public var title: String
    public var body: String   // One or two sentences with real dollar figures
    public var amount: Decimal?   // The headline figure: overPace/underUsual → amount above/below usual; gapPlan → the gap; frequentSmallPurchases → total spent; topMerchants → top merchant's total; weeken…
    public var sentiment: InsightSentiment
    public var priority: Int   // Higher = more important
    public var categoryID: UUID?   // The category the card is about, when there is one (tap to drill in)
    public var gapPlan: GapPlan?   // Only for `.gapPlan`
    public var merchants: [MerchantSpend]   // Only for `.topMerchants`
    public init(id: String, kind: InsightKind, title: String, body: String, amount: Decimal? = nil, sentiment: InsightSentiment, priority: Int, categoryID: UUID? = nil, gapPlan: GapPlan? = nil, merchants: [MerchantSpend] = [])
}

/// Deterministic, on-device insights.
public enum InsightsEngine {
    public static var overPaceRatio: Decimal   // A category is over pace at ≥ 15 % and ≥ $10 above usual-by-this-day
    public static var underUsualRatio: Decimal
    public static var minimumPaceDifference: Decimal
    public static var smallPurchaseLimit: Decimal   // "Small purchase" ceiling and minimum count
    public static var smallPurchaseMinimumCount: Int
    public static var weekendDifferenceRatio: Decimal   // Weekend vs weekday daily averages must differ by ≥ 30 %
    public static var maximumOverPaceCards: Int   // At most this many over-pace cards (the largest overshoots) are produced
    public static func insights(month: MonthKey, now: Date, transactions: [TransactionRecord], earnings: [WeeklyEarning], goal: Decimal, categories: [CategoryRecord], calendar: LedgerCalendar, locale: Locale = .current, currencyCode: String = "USD") -> [Insight]   // All insights for `month`, most important first
    public static func insights(snapshot: BudgetSnapshot, transactions: [TransactionRecord], categories: [CategoryRecord], calendar: LedgerCalendar, locale: Locale = .current, currencyCode: String = "USD") -> [Insight]   // All insights for an existing snapshot, most important first (ties broken by id)
    public static func top(_ insights: [Insight], count: Int = 3) -> [Insight]   // The first `count` insights (the Home screen shows three)
    public static func gapPlan(snapshot: BudgetSnapshot, transactions: [TransactionRecord], categories: [CategoryRecord], calendar: LedgerCalendar, locale: Locale = .current, currencyCode: String = "USD") -> GapPlan?   // The gap-closing plan, or nil when income is unknown, the goal is on track, or the month is over
    public static func allocate(target: Decimal, capacities: [Decimal]) -> [Decimal]   // Splits `target` (cents) across `capacities` (cents) in proportion, never exceeding a capacity, with the result summing to exactly `min(target, Σcapacities)`
}
```

## ChartData.swift

```swift

/// One slice of the spending-by-category donut.
public struct CategorySlice: Identifiable, Hashable, Sendable {
    public var categoryID: UUID
    public var name: String
    public var colorHex: String
    public var symbolName: String
    public var amount: Decimal   // Net spending clamped at 0 — what the chart draws
    public var netAmount: Decimal   // Net spending before clamping (negative when refunds exceed spending)
    public var fraction: Decimal   // Share of the donut, 0...1
    public init(categoryID: UUID, name: String, colorHex: String, symbolName: String, amount: Decimal, netAmount: Decimal, fraction: Decimal)
    public var id: UUID
    public var value: Double   // For plotting only
    public var fractionValue: Double
}

/// One Monday–Sunday week: spending next to the earnings entered for that week.
public struct WeeklyBar: Identifiable, Hashable, Sendable {
    public var weekStart: Date   // Monday 00:00
    public var weekLastDay: Date   // Start of the Sunday that ends the week
    public var spending: Decimal   // Net spending for the whole Monday–Sunday week (it may run into the next month)
    public var earnings: Decimal?   // Earnings entered for the week; nil when not entered
    public var weekNumber: Int   // 1-based position within the month
    public init(weekStart: Date, weekLastDay: Date, spending: Decimal, earnings: Decimal?, weekNumber: Int)
    public var id: Date
    public var spendingValue: Double   // For plotting only (clamped at 0)
    public var earningsValue: Double   // For plotting only (0 when not entered)
}

/// One day on the cumulative-spending line chart.
public struct CumulativePoint: Identifiable, Hashable, Sendable {
    public var day: Int   // Day of the month, 1-based
    public var date: Date   // Start of that day
    public var cumulativeSpending: Decimal?   // Net spending from the 1st through this day; nil for days that have not happened yet
    public var onTrack: Decimal?   // `(expectedIncome − goal) × day / daysInMonth`, floored at 0; nil when income is unknown
    public init(day: Int, date: Date, cumulativeSpending: Decimal?, onTrack: Decimal?)
    public var id: Int
    public var cumulativeValue: Double?
    public var onTrackValue: Double?
}

/// One category in the month-over-month grouped bars.
public struct CategoryComparison: Identifiable, Hashable, Sendable {
    public var categoryID: UUID
    public var name: String
    public var colorHex: String
    public var current: Decimal   // Selected month, clamped at 0
    public var previous: Decimal   // The month before, clamped at 0
    public init(categoryID: UUID, name: String, colorHex: String, current: Decimal, previous: Decimal)
    public var id: UUID
    public var change: Decimal
    public var currentValue: Double
    public var previousValue: Double
}

/// One row of the top-merchants list.
public struct MerchantSpend: Identifiable, Hashable, Sendable {
    public var normalizedMerchant: String
    public var displayName: String   // The merchant as most recently written
    public var amount: Decimal   // Net spending this month (> 0)
    public var previousAmount: Decimal   // Net spending last month (0 if none; clamped at 0)
    public var transactionCount: Int
    public var fractionOfTop: Decimal   // `amount / top merchant's amount`, 0...1 — the mini-bar length
    public init(normalizedMerchant: String, displayName: String, amount: Decimal, previousAmount: Decimal, transactionCount: Int, fractionOfTop: Decimal)
    public var id: String
    public var change: Decimal   // This month minus last month
    public var isNew: Bool
    public var value: Double
    public var fractionOfTopValue: Double
}

/// One day of the transaction list.
public struct DayGroup: Identifiable, Hashable, Sendable {
    public var day: Date   // Start of the day
    public var total: Decimal   // Net total for the day (refunds subtract)
    public var transactions: [TransactionRecord]   // Newest first
    public init(day: Date, total: Decimal, transactions: [TransactionRecord])
    public var id: Date
}

/// Search and filter settings for the transaction list.
public struct TransactionFilter: Hashable, Sendable {
    public var searchText: String   // Matches merchant or notes; case- and accent-insensitive; every space-separated word must appear
    public var categoryIDs: Set<UUID>
    public var sources: Set<SourceKind>
    public var paymentMethods: Set<PaymentMethod>
    public var startDate: Date?   // Inclusive lower bound on the transaction date
    public var endDate: Date?   // Exclusive upper bound on the transaction date
    public var needsReviewOnly: Bool
    public init(searchText: String = "", categoryIDs: Set<UUID> = [], sources: Set<SourceKind> = [], paymentMethods: Set<PaymentMethod> = [], startDate: Date? = nil, endDate: Date? = nil, needsReviewOnly: Bool = false)
    public var isEmpty: Bool   // True when nothing is restricted
    public var hasNonSearchFilters: Bool   // True when anything other than the search text is set (for a "filters active" badge)
    public mutating func setDayRange(from firstDay: Date, through lastDay: Date, calendar: LedgerCalendar)   // Sets the date range to whole days: from the start of `firstDay` through the end of `lastDay`
    public mutating func setMonth(_ month: MonthKey, calendar: LedgerCalendar)   // Restricts to one month
    public func matches(_ transaction: TransactionRecord, categories: [CategoryRecord] = []) -> Bool   // Whether one transaction passes
}

/// Series for every chart, plus the list helpers.
public enum ChartData {
    public static func categoryBreakdown(month: MonthKey, transactions: [TransactionRecord], categories: [CategoryRecord], calendar: LedgerCalendar) -> [CategorySlice]   // Donut: net spending per category for the month, largest first
    public static func weeklyBars(month: MonthKey, transactions: [TransactionRecord], earnings: [WeeklyEarning], calendar: LedgerCalendar) -> [WeeklyBar]   // Weekly bars: one per Monday that falls in the month (4 or 5)
    public static func cumulativeSeries(month: MonthKey, now: Date, transactions: [TransactionRecord], expectedIncome: Decimal?, goal: Decimal, calendar: LedgerCalendar) -> [CumulativePoint]   // Line chart: cumulative net spending per day, next to the on-track budget line `(expectedIncome − goal) × day / daysInMonth` (floored at 0, nil when `expectedIncome` is n…
    public static func monthOverMonth(month: MonthKey, transactions: [TransactionRecord], categories: [CategoryRecord], calendar: LedgerCalendar) -> [CategoryComparison]   // Grouped bars: each category's spending this month vs the month before (both clamped at 0), in category sort order
    public static func topMerchants(month: MonthKey, transactions: [TransactionRecord], calendar: LedgerCalendar, limit: Int = 5) -> [MerchantSpend]   // Top merchants by net spending this month, with last month's figure for comparison
    public static func groupByDay(_ transactions: [TransactionRecord], calendar: LedgerCalendar) -> [DayGroup]   // Groups transactions by calendar day, newest day first, newest transaction first within a day, each with its net daily total
    public static func filter(_ transactions: [TransactionRecord], with filter: TransactionFilter, categories: [CategoryRecord] = []) -> [TransactionRecord]   // Applies search and filters
    public static func search(_ transactions: [TransactionRecord], text: String) -> [TransactionRecord]   // Search only: merchant or notes contains the text (case- and accent-insensitive)
    public static func needsReview(_ transactions: [TransactionRecord]) -> [TransactionRecord]   // Transactions flagged for review, newest first
    public static func recent(_ transactions: [TransactionRecord], limit: Int = 5) -> [TransactionRecord]   // Most recent transactions, newest first
    public static func merchantSuggestions(prefix: String, from merchants: [String], limit: Int = 6) -> [String]   // Merchant autocomplete: distinct past merchant names whose text starts with (or, failing that, contains) `prefix`, most frequently used first
    public static func paymentMethods(in transactions: [TransactionRecord]) -> [PaymentMethod]   // Distinct payment methods used, Cash first, then Other card, then Wallet cards by name — for the filter sheet
}
```

## CSV.swift

```swift

/// RFC-4180 reading and writing.
public enum CSV {
    public static func parse(_ text: String, delimiter: Character? = nil) -> [[String]]   // Parses CSV text into rows of cells
    public static func detectDelimiter(_ text: String) -> Character   // The delimiter (",", ";" or tab) that appears most often outside quotes in the first line
    public static func escape(_ field: String, delimiter: Character = ",") -> String   // Quotes a cell when it contains the delimiter, a quote, a line break, or leading/trailing spaces
    public static func write(_ rows: [[String]], delimiter: Character = ",") -> String   // Joins rows into CSV text with CRLF line endings (RFC 4180)
    public static let exportHeader: [String]   // Header row written by `export`
    public static func export(transactions: [TransactionRecord], categories: [CategoryRecord], calendar: LedgerCalendar) -> String   // Exports transactions, oldest first
    public static func exportFileName(now: Date, calendar: LedgerCalendar) -> String   // A file name such as "ledgerly-2026-03-14.csv"
    public static func timestamp(_ date: Date, calendar: LedgerCalendar) -> String   // "yyyy-MM-dd HH:mm:ss" in the calendar's time zone
}

/// The order of the numbers in a CSV date.
public enum CSVDateFormat: String, Codable, CaseIterable, Sendable {
    case yearMonthDay   // 2026-03-14, 2026/03/14
    case monthDayYear   // 03/14/2026, 3/14/26 (US)
    case dayMonthYear   // 14/03/2026, 14.03.2026
    public var displayName: String
}

/// Which CSV column feeds which field.
public struct CSVColumnMapping: Hashable, Codable, Sendable {
    public var date: Int?
    public var amount: Int?
    public var merchant: Int?
    public var category: Int?
    public var notes: Int?
    public var card: Int?   // Card / account / payment-method column
    public var currency: Int?
    public var hasHeader: Bool   // Skip the first row
    public var dateFormat: CSVDateFormat
    public var expensesArePositive: Bool   // True when purchases are positive numbers (Apple Card export)
    public init(date: Int? = nil, amount: Int? = nil, merchant: Int? = nil, category: Int? = nil, notes: Int? = nil, card: Int? = nil, currency: Int? = nil, hasHeader: Bool = true, dateFormat: CSVDateFormat = .monthDayYear, expensesArePositive: Bool = true)
    public var isComplete: Bool   // Date, amount and merchant are all mapped — the minimum needed to import
}

/// One CSV row after mapping.
public struct CSVImportRow: Identifiable, Hashable, Sendable {
    public var rowNumber: Int   // 1-based row number in the file (the header is row 1 when present)
    public var cells: [String]
    public var record: TransactionRecord?   // The transaction this row would create; nil when the row cannot be imported
    public var isDuplicate: Bool   // Same day + amount + normalized merchant as a transaction already in the store
    public var problem: String?   // Why the row cannot be imported (nil when it can)
    public init(rowNumber: Int, cells: [String], record: TransactionRecord?, isDuplicate: Bool, problem: String?)
    public var id: Int
}

public struct CSVImportResult: Hashable, Sendable {
    public var rows: [CSVImportRow]
    public init(rows: [CSVImportRow])
    public var newRecords: [TransactionRecord]   // Records for rows that parsed and are not duplicates — what "Import" saves by default
    public var duplicateRecords: [TransactionRecord]   // Records for rows flagged as duplicates (each has `isPossibleDuplicate = true`), in case the user wants them anyway
    public var duplicateCount: Int
    public var failedCount: Int
    public var needsReviewCount: Int
}

/// CSV import: header detection, column guessing, date sniffing, rows → records, duplicate detection.
public enum CSVImporter {
    public static func hasHeader(_ rows: [[String]]) -> Bool   // True when the first row looks like column titles (a known title word, or no digits anywhere)
    public static func guessMapping(rows: [[String]], locale: Locale = .current) -> CSVColumnMapping   // Best-guess mapping for a parsed file
    public static func sniffDateFormat(_ samples: [String]) -> CSVDateFormat?   // Works out the order of the date parts from sample cells
    public static func parseDate(_ text: String, format: CSVDateFormat, calendar: LedgerCalendar) -> Date?   // Parses a CSV date cell: "2026-03-14", "03/14/2026", "3/14/26", "14.03.2026", optionally followed by a time ("14:05", "14:05:09", "2:05 PM", or ISO "T14:05:09")
    public static func prepare(rows: [[String]], mapping: CSVColumnMapping, existing: [TransactionRecord], ingestor: TransactionIngestor, calendar: LedgerCalendar, now: Date, idProvider: ((Int) -> UUID)? = nil) -> CSVImportResult   // Turns parsed rows into records using the mapping
    public static func prepare(text: String, existing: [TransactionRecord], ingestor: TransactionIngestor, calendar: LedgerCalendar, now: Date) -> (mapping: CSVColumnMapping, rows: [[String]], result: CSVImportResult)   // Convenience: parse the text, guess the mapping and prepare the rows in one go
    public static func isImportDuplicate(_ a: TransactionRecord, _ b: TransactionRecord, calendar: LedgerCalendar) -> Bool   // Import duplicate rule: same calendar day, same amount, same normalized merchant
}
```

## DemoData.swift

```swift

/// SplitMix64: a tiny deterministic generator, so demo data is the same on every run and every platform.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    public init(seed: UInt64)
    public mutating func next() -> UInt64
    public mutating func int(in range: ClosedRange<Int>) -> Int   // Uniform integer in a closed range (simple modulo; the tiny bias does not matter for demo data)
    public mutating func chance(_ percent: Int) -> Bool   // True `percent` times out of 100
    public mutating func uuid() -> UUID   // A deterministic (version-4 shaped) UUID
}

/// Everything the DEBUG demo seeder inserts.
public struct DemoDataSet: Hashable, Sendable {
    public var transactions: [TransactionRecord]   // Oldest first
    public var earnings: [WeeklyEarning]
    public var goals: [MonthlyGoal]
    public var categories: [CategoryRecord]
    public init(transactions: [TransactionRecord], earnings: [WeeklyEarning], goals: [MonthlyGoal], categories: [CategoryRecord])
}

/// Three months of realistic data relative to `now`: the two full months before the current one, and the current month up to `now`.
public enum DemoData {
    public static var goalAmount: Decimal   // $200, used for all three months
    public static func generate(now: Date, calendar: LedgerCalendar, seed: UInt64 = 20_240_607) -> DemoDataSet   // - Weekly earnings exist for every completed week whose Monday falls in the three months, except the most recent completed week, so the "enter last week's earnings" card …
}
```

## MoneyFormat.swift

```swift

/// Currency strings and the one rounding helper.
public enum MoneyFormat {
    public static func round(_ value: Decimal, scale: Int = 2) -> Decimal   // Rounds with `.plain` (half away from zero) to `scale` fraction digits
    public static func truncate(_ value: Decimal, scale: Int = 2) -> Decimal   // Rounds toward zero to `scale` fraction digits (1.999 → 1.99, -1.999 → -1.99)
    public static func string(_ amount: Decimal, currencyCode: String = "USD", locale: Locale = .current) -> String   // "$12.40", "-$5.00", "$1,234.56"
    public static func whole(_ amount: Decimal, currencyCode: String = "USD", locale: Locale = .current) -> String   // Whole dollars for insight copy: "$310", "-$5"
    public static func compact(_ amount: Decimal, currencyCode: String = "USD", locale: Locale = .current) -> String   // Whole dollars when the cents are zero ("$45"), otherwise cents ("$44.37")
    public static func plain(_ amount: Decimal) -> String   // Locale-independent number for CSV and text fields: "12.40", "-5.00", "1234.56" (no grouping, "." decimal, at least two fraction digits, more only if the value has them)
    public static func percent(_ fraction: Decimal) -> String   // "40%" from 0.4
    public static func currencySymbol(currencyCode: String = "USD", locale: Locale = .current) -> String   // The currency symbol a locale uses for a code ("$" for USD in en_US)
    public static func double(_ amount: Decimal) -> Double   // `Double` for plotting only
}
```

# Things to know

- **Imports.** Five source files start with `#if canImport(Darwin) import Foundation #else @preconcurrency import Foundation #endif`.
  On Linux Foundation 5.10 `Decimal` is not marked `Sendable`; on Apple platforms it is, so the plain import is used there
  and no `@preconcurrency` warning can appear.
- **`Package@swift-6.0.swift`** (tools 6.0, `swiftLanguageModes: [.v6]`, iOS 18 / macOS 14) is what Xcode 16 picks up. It has
  not been run through a Swift 6 toolchain. Forcing `-swift-version 6` on the 5.10 Linux compiler produced no diagnostics
  other than the Linux-only "`Decimal` is not Sendable" ones.
- **Formatting** goes through `NumberFormatter` created per call (never cached). Output for en_US/USD is asserted in tests on
  Linux ICU; Apple ICU may differ for other locales (spacing, symbol placement). Negative amounts are always written as
  `"-" + formatted magnitude`.
- **Insight copy is English only** and is built with string interpolation, not localized resources.
