# Decisions and assumptions

Everything the spec left open, what was chosen, and why. Grouped by area. `PLAN.md` has the architecture; this file is the list of judgment calls.

## Platform & Wallet

- **The app was written without Xcode.** The author's machine can't run Xcode, so the pure-logic package (`Packages/LedgerlyCore`) was compiled and unit-tested on Linux, and the app itself is compiled and tested on a cloud Mac by GitHub Actions (`.github/workflows/ci.yml`). This is why as much logic as possible lives in the package and the app layer is kept thin.
- **The Wallet automation is the only automatic source, and the app says so.** iOS doesn't let third-party apps read Wallet history, so nothing in the app pretends to; onboarding, the guide in Settings and the README all state what the trigger does and doesn't catch.
- **The App Intent lives in the app target, not an extension.** One process means one `ModelContainer` at the default store location shared by the app and the intent, with no App Group to configure, which also keeps free-account signing simple.
- **The intent and the "Test it" button share one function** (`WalletTransactionLogger.log`). The test then proves the real path, not a lookalike.
- **"Test it" saves a real transaction** ($12.40 at Starbucks on "Test Card") and offers a button to remove it. A dry run that saves nothing wouldn't prove that saving, categorizing and the notification work.
- **All three intent parameters are optional text.** The spec asks for amount as a String or Decimal-friendly type; text accepts "$12.40", "12,40" and plain numbers (Shortcuts converts a number variable to text), and optional parameters stop Shortcuts from halting a background automation to ask for a value when iOS sends nothing.
- **Bad input is never an error.** Amount 0, an unreadable amount or a blank merchant is saved with `needsReview` set; the intent only throws when the store itself fails to save, so Shortcuts reports a real failure and nothing else.
- **An unreadable amount is stored as 0.** The record needs some amount, and 0 changes no totals while it waits in Needs Review.
- **A blank card name becomes "Other card"; a card literally named "Cash" becomes Cash.** A Wallet tap is never cash, but the same ingest code also reads CSV files, where that column can say Cash.
- **The currency for Wallet transactions is the app's currency setting** (USD by default). The trigger doesn't reliably pass a currency code.
- **The intent returns a short dialog with the same text as the notification.** It's invisible in a Run Immediately automation and useful when the action is run by hand in Shortcuts.
- **Notifications are skipped under UI tests**, so no permission prompt or banner can cover the screen mid-test.
- **Tapping a "logged" notification opens the Transactions tab; a "needs review" one opens Needs Review.** The tap should land where the next action is.
- **An App Shortcut is registered** so the action appears in Shortcuts and Spotlight without setup. Its phrases include the app name because the system requires it.
- **The guide opens Shortcuts with the `shortcuts://` URL.** It's a local app-to-app link, not a network call, and iOS has no deep link to the automation editor itself.
- **FinanceKit is compiled out behind `FINANCEKIT_ENABLED`**, with a runtime switch (off by default) on top. The entitlement isn't available to individual accounts, so the default build must not reference the framework; the code is written but has never been compiled.
- **FinanceKit: money out is an expense; money in is kept only when it is a refund.** Card payments, deposits and interest aren't spending and would otherwise show up as negative spending.
- **FinanceKit: a transaction already imported (same FinanceKit id) is skipped, anything else that looks like a copy is flagged.** Re-syncing must not overwrite the user's edits, and a cross-source lookalike must not be dropped silently.
- **Foundation Models rewording is guarded twice** (`#if canImport(FoundationModels)` and `#available(iOS 26)`) and can only change an insight's body text. A rewrite is discarded unless it has exactly the same numbers (digits and number words) as the original, so every figure still comes from the engine. This branch is not compiled by the Xcode 16 CI.
- **No app icon is included.** The asset catalog declares the slot so the build is clean; drawing an icon was out of scope.
- **Portrait-first, but landscape isn't blocked.** The spec says portrait-first, not portrait-only.

## Data layer

- **SwiftData entities mirror plain value types, and only the value types leave the repository.** Views, engines and the intent never touch a `@Model` object, which keeps everything `Sendable` and testable off-device.
- **No relationships between entities; a transaction stores a plain `categoryID`.** Archiving or deleting a category can then never cascade into transactions.
- **A transaction whose category is missing counts under Other.** Totals must always add up, even with stale ids.
- **The repository is a `@ModelActor` actor.** Background intent writes and UI reads go through one serial queue without blocking the main thread.
- **Every write posts `ledgerDidChange` on the main thread, once per call.** That is how a purchase logged in the background shows up on an open screen straight away; bulk calls post once so imports don't cause a storm of reloads.
- **Reads return empty on failure, writes throw and roll back.** A failed read shouldn't crash a screen; a failed write must be reported and must not leak half a change into the next save.
- **If the on-disk store can't be opened, the app runs on a temporary in-memory store and says so.** A visible warning beats a crash loop.
- **Default categories have fixed ids.** Rules, demo data and tests can refer to them, and erasing then re-seeding gives the same categories back.
- **Categories are archived, not deleted.** Old transactions keep their category; archived ones just stop being offered or auto-picked.
- **Settings live in UserDefaults, not SwiftData.** They're a handful of flags, and the intent needs to read the currency without touching the main actor.
- **"Erase all data" empties the store and puts the default categories back.** An app with no categories at all isn't usable.
- **Under `-uiTesting` the store is in memory and settings use a throwaway suite.** Each UI test starts from the same clean state.
- **Demo data loads only in Debug, only into an empty store, and only once.** It must never mix with real data; the seeder's body sits inside `#if DEBUG` so release builds contain none of it.

## Budget math

- **Weekly earnings count toward the month their Monday falls in.** The spec asks for this; it means a week that straddles two months is never split or counted twice.
- **Weeks are Monday to Sunday regardless of the device's region setting.** The spec defines them that way, so the calendar is pinned to Monday instead of following the locale.
- **All date math uses calendar arithmetic in the device's time zone**, never "86,400 seconds". Daylight-saving days are 23 or 25 hours long.
- **Today counts as an elapsed day for pace, and as a remaining day for safe-to-spend.** On the 10th you have spent ten days' worth, and today's allowance is still yours to spend.
- **Remaining weeks = every Monday in the month without an earnings entry, including past weeks you skipped.** A skipped week is treated as "not entered yet", not as zero income; enter 0 for a week with no income.
- **Expected income with nothing entered this month is estimated from up to the last 8 entered weeks, and labelled as an estimate.** That's a reasonable guess that doesn't reach back too far.
- **With no earnings at all, income-dependent numbers are blank, not guessed.** The spec says to show the gap clearly; the app asks for earnings instead of inventing a figure.
- **Projection blends this month's pace with the trailing three-month average, weighted by how far through the month it is.** Early on, history is the better guide; by month end, the month itself is.
- **The trailing average divides by the number of prior months that have data (1 to 3).** A new user's single month of history shouldn't be diluted by two empty ones.
- **Known weakness: a large charge on day 1 (rent, say) inflates that category's projection early in the month.** Pace is spent ÷ days elapsed, so one big early purchase extrapolates badly until more days pass or history exists to blend with. Left as is because the spec asks for a pace-based projection; noted in the README.
- **Pace is floored at 0 for a category whose refunds exceed its spending.** Otherwise a net refund would be extrapolated into ever larger negative spending.
- **Category totals may go negative (a refund larger than the spending); charts clamp them to 0.** The math stays true, and a donut can't draw a negative slice.
- **Safe-to-spend never goes below 0.** A negative daily allowance isn't actionable; the gap plan covers being over.
- **A past month is treated as fully elapsed** (projection = actual spending, safe-to-spend 0), and a future month projects from history only.
- **Money is `Decimal` throughout and rounded only for display, with `.plain` rounding** (half away from zero), which is what people expect from currency: $0.125 shows as $0.13, and -$0.125 as -$0.13.
- **One currency.** Amounts in other currencies are stored with their code but summed as is; conversion would need exchange rates, and the app has no network.

## Insights

- **Over-pace means at least 15% and at least $10 above the usual amount by this day of the month**, where usual is the trailing average scaled to the day. Two thresholds stop tiny categories and tiny differences from producing noise.
- **At most a few over-pace cards, largest overshoot first.** A wall of warnings gets ignored.
- **The gap plan can only cut money that hasn't been spent yet** (projected minus spent, per category). You can't un-spend.
- **Cut order: Food & Dining, Shopping, Recreation, Subscriptions, then user-made categories. Never Bills or Health.** That's the spec's order; Groceries, Gas and Transportation are also left out because they're needs.
- **Cuts are split in proportion to what's cuttable, rounded to cents, with the rounding remainder put on the largest cut.** The amounts then add up to the gap exactly.
- **If discretionary spending can't cover the gap, the plan says how much is left uncovered.** An honest shortfall is better than a plan that doesn't add up.
- **The subscriptions cut is worded "pause one subscription" using the smallest recurring one that fits.** It's the most concrete action available.
- **Frequent small purchases: 4 or more purchases of $15 or less at one merchant; coffee shops are worded "coffee runs".** Small and frequent is the pattern worth pointing out.
- **Weekend vs weekday appears only when per-day averages differ by 30% or more.** The spec says "when it differs a lot".
- **With unknown income the list starts with "add your earnings" and has no gap plan or on-track card.** Both depend on income.
- **Insight text is English and built in code.** Localization was out of scope.
- **Home shows the top three by priority.** Shortfalls and warnings rank above praise.

## Categorization & duplicates

- **Order: learned rule, then a category name supplied with the data (CSV), then built-in keywords, then Other.** The user's word beats everything; a bank's category beats a guess.
- **A learned rule for "STARBUCKS" also covers "STARBUCKS CHICAGO IL".** Rules match as a whole-word prefix, so one correction covers every branch.
- **Brand keywords beat generic ones, and longer beats shorter.** "UBER EATS" is food, not transport.
- **Merchant cleanup drops store numbers and processor prefixes but keeps numbers that are part of a name** ("7 ELEVEN", "PHILLIPS 66", "MOTEL 6").
- **An archived category is never auto-picked**, even if a rule or keyword points at it.
- **A blank merchant is filed under Other and flagged for review when it arrives from outside.**
- **Manual entries with a blank merchant are allowed.** Adding a purchase has to take under five seconds; amount and category are enough for the math.
- **Live duplicate rule: same amount and currency, and the same merchant or the same Wallet card, within 180 seconds inclusive.** That's the spec's rule; a blank merchant never counts as "the same merchant".
- **A possible duplicate is saved and flagged, never dropped or merged.** The user decides; two real identical purchases do happen.
- **Zero-amount transactions are never called duplicates.** They're already in Needs Review, and "same amount: 0" means nothing.
- **Accepting "always categorize" saves the rule for the cleaned merchant name.** One answer then covers every spelling of that merchant.

## Earnings & goals

- **The goal sheet pre-fills last month's goal, or $200 the first time.** Straight from the spec.
- **"First open of a new month" is tracked by storing the month the sheet was last shown for.** A changed clock or time zone can't cause repeat prompts within a month.
- **An entered amount of 0 counts as entered.** A week without income is real information, and the card should go away.
- **The Monday reminder is one repeating calendar trigger at the chosen local time.** iOS keeps it at the same wall-clock time through daylight-saving and time-zone changes.
- **The reminder is scheduled as soon as notifications are allowed in onboarding**, at the time saved in Settings (8:00 by default).
- **Onboarding has a plain "Not now" for notifications, and the app works without them.** The dashboard card asks for last week's earnings either way.
- **Onboarding doesn't ask for the goal itself.** The monthly goal sheet appears right after it, and asking twice would be silly.
- **Onboarding can be skipped from any page.** The Wallet guide is also in Settings.

## CSV

- **The parser follows RFC 4180** and also accepts semicolons, tabs, a byte-order mark and any line ending. Bank exports vary.
- **Files are read as UTF-8 first, then UTF-16 (only with a byte-order mark), then Windows-1252.** Older bank exports aren't UTF-8.
- **The column mapping is guessed and then confirmed by the user.** Guessing saves time, confirming prevents silent garbage.
- **Ambiguous dates such as 03/04/2026 are read month-first.** The app's defaults are US; the date order can be changed in the mapping step.
- **A "purchases are negative" switch, guessed from the data.** Apple Card lists purchases as positive, most banks as negative.
- **CSV duplicate rule: same calendar day, amount and cleaned merchant.** Bank exports carry dates without times, so the three-minute rule can't apply.
- **Possible duplicates are left out by default; if the user includes them they are imported flagged for review.** Leaving them out is the safe default, and an included one should still be easy to find.
- **Identical rows inside one file are not treated as duplicates of each other.** Two $4 coffees on one day are common.
- **Rows with an unreadable date are skipped and listed; rows missing an amount or merchant are imported into Needs Review.** A transaction has to have a date to sit anywhere in the app; the rest can be fixed later.
- **Import saves everything in one batch.** One save and one refresh.
- **Export writes local timestamps, plain decimal amounts and category names, oldest first**, and the file imports back into the app.
- **The export file goes to the temporary folder as `Ledgerly-export-yyyy-MM-dd.csv`.** The share sheet needs a file URL, and the system cleans the folder up.

## UI

UI decisions are merged from `App/UI_NOTES.md`.

## Testing & tooling

- **XcodeGen generates the Xcode project from `project.yml`.** The project file is reproducible and never conflicts in git.
- **Bundle ID `com.example.ledgerly` and a blank signing team are left in the repo**, as the spec asks; the README explains how to set both.
- **Swift 6 language mode with complete concurrency checking, iOS 18.0 minimum, no third-party packages.**
- **The Core package has two manifests**: tools 5.9 for the Linux toolchain used during authoring, and a Swift 6 one that Xcode 16 picks up.
- **Core is tested with XCTest**, which runs the same on Linux and in Xcode.
- **Core never reads the clock or the device time zone.** `now` and the calendar are always passed in, so month and daylight-saving edges can be tested exactly.
- **Demo data is generated from a fixed seed relative to today.** The same data on every run makes screens comparable, and it always covers the current month.
- **UI tests start the app with launch arguments** (`-uiTesting`, `-uiTestingGoalPrompt`, `-uiTestingSeedReview`, `-uiTestingDemoData`) to get a known state without tapping through setup.
- **CI builds for the simulator with signing off, runs unit and UI tests, and uploads logs and screenshots.** It checks the code; it doesn't produce an installable build.
- **`scripts/verify.sh` does the same locally** and reports warnings as well as errors, because the goal is zero of both.
- **The FinanceKit code and the Foundation Models branch are not covered by CI.** Neither can be compiled there (missing entitlement, older SDK); both are isolated behind compile-time checks so they can't break the default build.
