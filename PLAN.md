# Ledgerly — Plan

Written before any feature code. The full product spec is the original prompt (kept as `SPEC.md` in this folder).

## 0. Build environment reality

The project was authored in a Linux workspace. Only `Packages/LedgerlyCore` (pure Swift, Foundation only) could be compiled and tested there, with a Swift 5.10 Linux toolchain and strict concurrency checking on. Everything under `App/` and `UITests/` needs Xcode 16+ and was written without a compiler. Because of that, the plan pushes as much logic as possible into `LedgerlyCore` and keeps the app layer thin.

## 1. Architecture

```
SwiftData @Model classes (App/Data/Models)
        │  map to/from value records
        ▼
LedgerRepository (App/Data)  ── one shared ModelContainer (SharedModelContainer.shared)
        │  hands out LedgerlyCore value types only
        ▼
LedgerlyCore (pure Swift package, no UI imports)
  AmountParser · MerchantNormalizer · Categorizer · DuplicateDetector · TransactionIngestor
  LedgerCalendar · BudgetEngine · InsightsEngine · ChartData · CSV · DemoData · MoneyFormat
        ▼
@Observable view models (App/ViewModels)  →  SwiftUI views (App/Views)
App Intent "Log Wallet Transaction" (App/Intents) uses the same repository + container.
```

Rules:
- `LedgerlyCore` imports Foundation only. No SwiftUI, SwiftData, Charts, UIKit, `FormatStyle` APIs (not on Linux Foundation) — use `NumberFormatter`/`DateFormatter` there.
- All money is `Decimal`. Rounding to cents happens only in `MoneyFormat` and in the gap plan's final allocation.
- Every Core type is `Sendable`. Engines are stateless structs/enums with static or pure instance functions that take `now: Date` and a `LedgerCalendar` explicitly (no hidden `Date()`).
- The intent lives in the app target (no extension), so one process-wide `ModelContainer` at the default store URL is shared; no App Group is needed.

## 2. Folder layout

```
Ledgerly/
  project.yml  README.md  PLAN.md  DECISIONS.md  SPEC.md
  scripts/verify.sh                     # xcodegen → build → test on a simulator
  Packages/LedgerlyCore/
    Package.swift                       # tools 5.9 (Linux 5.10 toolchain), StrictConcurrency on
    Package@swift-6.0.swift             # tools 6.0, Swift 6 language mode, iOS 18 (what Xcode uses)
    Sources/LedgerlyCore/**
    Tests/LedgerlyCoreTests/**          # XCTest
  App/
    LedgerlyApp.swift  AppState.swift
    Data/        Models/*.swift, Mappers.swift, SharedModelContainer.swift, LedgerRepository.swift, AppSettings.swift
    Services/    NotificationService, AppLockService, DemoDataSeeder, FinanceKit/, InsightRephraser
    Intents/     LogWalletTransactionIntent, LedgerlyShortcuts
    ViewModels/
    Views/       Home/ Transactions/ Add/ Insights/ Settings/ Onboarding/ Components/
    Resources/   Info.plist, PrivacyInfo.xcprivacy, Assets.xcassets
  UITests/
```

## 3. Data model (contract — implement exactly)

Core value types (`Packages/LedgerlyCore/Sources/LedgerlyCore/Models/`), all `public`, `Hashable`, `Codable`, `Sendable`, with public memberwise inits (defaults where shown):

```swift
public enum SourceKind: String, Codable, CaseIterable, Sendable { case walletShortcut, financeKit, manual, csvImport }

public enum PaymentMethod: Hashable, Codable, Sendable {
    case cash, otherCard, walletCard(String)
    public var kindRaw: String { get }          // "cash" | "otherCard" | "walletCard"
    public var cardName: String? { get }
    public init(kindRaw: String, cardName: String?)
    public var displayName: String { get }      // "Cash", "Other card", or the card name
}

public struct TransactionRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID = UUID()
    public var amount: Decimal                  // > 0 expense, < 0 refund
    public var currencyCode: String = "USD"
    public var merchant: String
    public var categoryID: UUID?
    public var date: Date
    public var paymentMethod: PaymentMethod = .cash
    public var source: SourceKind = .manual
    public var notes: String = ""
    public var needsReview: Bool = false
    public var isPossibleDuplicate: Bool = false
    public var createdAt: Date
}

public struct CategoryRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var colorHex: String                 // "#RRGGBB"
    public var symbolName: String               // SF Symbol
    public var sortOrder: Int
    public var isArchived: Bool = false
    public var systemKey: String?               // food, groceries, gas, shopping, recreation, bills, transportation, health, subscriptions, other; nil for user-made
    public var isDiscretionary: Bool { get }    // food, shopping, recreation, subscriptions (+ user-made)
    public var isProtected: Bool { get }        // bills, health — never in a cut list
}

public enum DefaultCategories {
    public static let all: [CategoryRecord]     // the 10 defaults, fixed UUIDs, colors, symbols
    public static func id(_ systemKey: String) -> UUID
}

public struct MerchantRule: Hashable, Codable, Sendable { public var normalizedMerchant: String; public var categoryID: UUID }
public struct WeeklyEarning: Hashable, Codable, Sendable { public var weekStart: Date; public var amount: Decimal }   // weekStart = Monday 00:00 local
public struct MonthKey: Hashable, Comparable, Codable, Sendable {
    public var year: Int; public var month: Int
    public init(year: Int, month: Int)
    public init(date: Date, calendar: LedgerCalendar)
    public var previous: MonthKey { get }; public var next: MonthKey { get }
}
public struct MonthlyGoal: Hashable, Codable, Sendable { public var month: MonthKey; public var amount: Decimal }
```

SwiftData mirrors (`App/Data/Models`): `TransactionEntity`, `CategoryEntity`, `MerchantRuleEntity`, `WeeklyEarningEntity`, `MonthlyGoalEntity`. `Decimal` stored as `Decimal`; enums stored as raw strings; `paymentKindRaw` + `cardName`; goal stored as `year`, `month`, `amount`. No relationships — `categoryID` is a plain UUID so archived/deleted categories never cascade.

`LedgerRepository` (`@ModelActor` actor or `@MainActor` final class over a `ModelContext`; pick whichever is simplest and Swift 6 clean) exposes only Core value types:
`transactions(in: DateInterval?)`, `allTransactions()`, `upsert(_ TransactionRecord)`, `deleteTransaction(id:)`, `categories(includeArchived:)`, `upsert(_ CategoryRecord)`, `reorderCategories([UUID])`, `rules()`, `setRule(merchant:categoryID:)`, `deleteRule(normalizedMerchant:)`, `earnings()`, `setEarning(weekStart:amount:)`, `deleteEarning(weekStart:)`, `goal(for: MonthKey)`, `latestGoal(before: MonthKey)`, `setGoal(_:for:)`, `seedDefaultCategoriesIfNeeded()`, `eraseAll()`, `knownMerchants()`. Posts `Notification.Name.ledgerDidChange` after every write so view models reload (this is how background intent writes show up right away).

`AppSettings` (UserDefaults wrapper): `hasCompletedOnboarding`, `lastGoalPromptMonth` ("yyyy-MM"), `reminderHour`/`reminderMinute` (default 8:00), `faceIDLockEnabled`, `financeKitEnabled` (default false), `currencyCode` (default "USD"), `demoDataLoaded`.

## 4. Core modules

| Module | Responsibility |
|---|---|
| `LedgerCalendar` | Wraps `Calendar` with `firstWeekday = 2`. `weekStart(for:)`, `monthInterval(_:)`, `daysInMonth(_:)`, `dayOfMonth(_:)`, `mondays(in:)`, `startOfDay`, `lastCompletedWeekStart(now:)`. All DST/time-zone handling lives here (calendar arithmetic, never `86400 *`). |
| `AmountParser` | `parse(String, locale:) -> Decimal?`. Handles `$`, `€`, currency codes, spaces, `1,234.56`, `1.234,56`, `12,40`, `(5.00)`/`-5.00`, blank → nil, `"0"` → 0. |
| `MerchantNormalizer` | Uppercase → strip punctuation/diacritics → drop store numbers and trailing `#123`/long digit runs → collapse spaces. `"SHELL OIL 57444"` → `"SHELL OIL"`. |
| `Categorizer` | (1) learned rule on normalized merchant, (2) built-in keyword table → systemKey, (3) Other. Returns category id + reason. Skips archived categories. |
| `DuplicateDetector` | Same amount AND (same normalized merchant OR same wallet card name) within 180 s. |
| `TransactionIngestor` | Pure: `IncomingTransaction` (raw amount string, merchant?, card?, date, source) → `TransactionRecord` with category, `needsReview` (amount 0/unparseable or blank merchant), `isPossibleDuplicate`. Used by the intent, FinanceKit, CSV import. Also builds the notification text. |
| `BudgetEngine` | All month math → `BudgetSnapshot` (see §5). |
| `InsightsEngine` | Deterministic insight cards (see §6). |
| `ChartData` | Series for donut, weekly spend vs earnings, cumulative vs on-track, month-over-month by category, top merchants, daily groups with totals, list filtering/search. |
| `CSV` | RFC-4180 parser, header detection, column mapping guess (date/amount/merchant/category/notes), date format sniffing, row → `IncomingTransaction`, export. Import duplicates = same day + amount + normalized merchant. |
| `DemoData` | Deterministic (seeded RNG) 3 months of transactions + weekly earnings + goals relative to `now`. |
| `MoneyFormat` | `NumberFormatter`-based currency strings, whole-dollar variant for insight copy. |
| `TransactionSource` protocol | `var kind: SourceKind`, `func isAvailable() async -> Bool`, `func fetch(since: Date?) async throws -> [IncomingTransaction]`. FinanceKit conforms in the app behind a flag. |

## 5. BudgetEngine definitions

For month M, `now` inside M (or M in the past → treated as fully elapsed):
- `daysInMonth`, `dayOfMonth` (today counts as elapsed for pace), `daysLeft` = daysInMonth − dayOfMonth + 1 (includes today).
- **Income so far** = sum of weekly earnings whose `weekStart` (a Monday) falls in M.
- **Remaining weeks** = Mondays in M with no entry.
- **Expected income** = income so far + average(entered weeks in M) × remaining weeks. If no weeks entered in M: use the average of the most recent ≤ 8 entered weeks from earlier months and mark `incomeBasis = .estimatedFromHistory`; if there is no earnings data at all, `expectedIncome = nil`, `incomeBasis = .unknown`, and dependent numbers are nil (UI shows "Add your earnings to see this").
- **Spent** = Σ amounts in M (refunds negative). Per-category too; category totals may go negative (refund larger than spend) and are clamped to 0 only for chart display.
- **Projected spending** per category: `dailyPace = spent / dayOfMonth`; `histDaily = trailing3MonthAvg / daysInMonth`; with history (≥ 1 of the 3 prior months has any transactions) `w = dayOfMonth / daysInMonth`, `projected = spent + (w·dailyPace + (1−w)·histDaily) × (daysInMonth − dayOfMonth)`; without history `projected = spent + dailyPace × (daysInMonth − dayOfMonth)`. Trailing average divides by the number of prior months that have data (1–3).
- **Projected savings** = expected income − projected spending.
- **Safe to spend / day** = max(0, (expected income − goal − spent) / daysLeft).
- **On-track line** = (expected income − goal) × day / daysInMonth.

## 6. Insights (all numbers from BudgetEngine / ChartData)

over-pace category (≥ 15% and ≥ $10 above usual-by-this-day, "usual" = trailing average × day/daysInMonth) · gap-closing plan · frequent small purchases (≥ 4 purchases ≤ $15 at one normalized merchant; "coffee runs" wording for coffee keywords) · top merchants + change vs last month · weekend vs weekday (per-day averages differ ≥ 30%) · positive reinforcement (category ≥ 15% under usual; goal on track) · missing-income notice.

**Gap plan:** `gap = goal − projectedSavings`. Cuttable per discretionary category = max(0, projected − spent) (you can't un-spend). Order: Food & Dining, Shopping, Recreation, Subscriptions, then user-made categories; never Bills or Health, and Groceries/Gas/Transportation are left out as needs. Allocate proportionally to cuttable, round each to cents, push the rounding remainder onto the largest cut so Σcuts == min(gap, Σcuttable) exactly. Subscriptions cut is phrased as "pause one subscription ($X)" using the smallest recurring subscription merchant when its amount ≤ the allocation. If Σcuttable < gap, the plan reports the uncovered remainder honestly.

## 7. Screens

Tab bar: Home · Transactions · (+) Add (center button opens sheet from any tab) · Insights · Settings.

- **Home**: month title, goal ring, safe-to-spend/day, earnings-needed card, Needs Review banner with count, donut, top 3 insights, recent transactions. Empty state.
- **Transactions**: day-grouped list with daily totals, `.searchable`, filter sheet (category, source, payment method, date range), swipe edit/delete, undo banner, Needs Review / possible-duplicate badges.
- **Add / Edit sheet**: keypad-first amount, category chips, merchant with autocomplete, payment method (Cash one tap), date/time, notes, refund toggle, pinned Save. Editing a category triggers "Always categorize … as …?".
- **Needs Review inbox**: list of flagged items; one tap opens the edit sheet; "Keep as is" / "Delete duplicate".
- **Insights**: month picker, donut (tap → category drill-down), weekly spend vs earnings bars, cumulative vs on-track line, month-over-month grouped bars, top merchants mini-bars, all insight cards.
- **Earnings entry**: list of weeks (Mon–Sun) with amounts, edit any past week.
- **Monthly goal sheet**: first launch and first open of each month.
- **Settings**: goal, reminder time, categories editor (add/rename/recolor/reorder/archive), merchant rules, Wallet automation guide + Test it, CSV import/export, Face ID lock, FinanceKit toggle (shown only when the build flag is on), erase all data.
- **Onboarding**: welcome → Wallet automation walkthrough → notifications permission → goal.

UI-test launch arguments: `-uiTesting` (in-memory store, onboarding skipped, no demo data, no auto goal prompt, lock off), `-uiTestingGoalPrompt` (force the monthly goal sheet), `-uiTestingSeedReview` (insert one zero-amount blank-merchant wallet transaction).

## 8. Test plan

Core unit tests (XCTest, run on Linux and in Xcode): amount parsing ("$1,234.56", "0", "", " ", "1.234,56" de_DE, "12,40" fr_FR, "€12.40", "(5.00)", "-3", garbage) · merchant normalization · categorizer order (rule beats keyword, keyword beats Other, archived skipped) · duplicate window edges (179 s / 181 s, merchant vs card) · ingest → needsReview paths · calendar (Monday weeks, 5-Monday months, first day of month, DST spring/fall in America/Chicago, year rollover) · budget math (income so far, expected income, unknown income, safe-to-spend floor at 0, refunds, refund > category spend, very large amounts, day 1) · projection blend with/without history · gap plan (Σcuts == gap to the cent, protected categories never appear, shortfall case) · each insight type · chart series · CSV parse/mapping/duplicates/export round-trip · demo data determinism.

UI tests (XCUITest, need Xcode): add manual cash transaction · edit its category and accept "Always categorize" · enter weekly earnings · set monthly goal · resolve a Needs Review item.

## 9. Work split

1. Plan (this file).
2. Parallel: **Core agent** (package + tests, compiled on Linux) ∥ **Scaffold agent** (project.yml, resources, SwiftData layer, repository, settings, notification + lock services, verify.sh).
3. Parallel, once Core's real API exists: **UI agent** (view models, all screens, charts, UI tests) ∥ **Platform agent** (App Intent, onboarding/Wallet guide, FinanceKit, rephraser, CSV screens, demo seeder, README).
4. Integrate, re-run Core tests.
5. Fresh reviewer agent checks everything against SPEC.md line by line; fix; re-test.
