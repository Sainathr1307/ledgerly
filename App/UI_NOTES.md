# UI layer notes (for DECISIONS.md)

Written without a compiler (Linux, no Xcode). Nothing here has been built or run yet.

## (a) Decisions and assumptions

- Custom tab bar instead of `TabView`: four tab buttons plus a centre (+) button in a plain `HStack` under the content. Reason: the (+) must open quick add from every tab, and custom buttons get stable accessibility identifiers (`tab_home`, `addButton`, …) that system tab items don't.
- All four tabs stay alive in a `ZStack`; the unselected ones are transparent, not hit-testable and hidden from accessibility. Reason: scroll position, search text and the selected Insights month survive a tab switch.
- The tab container ignores the keyboard safe area. Reason: otherwise the custom tab bar rides up on top of the keyboard while searching.
- When the app lock is on and the app locks, the tabs are removed from the view tree (not just covered). Reason: a sheet showing transactions would otherwise stay on top of the lock screen. Side effect: unsaved input in an open sheet is lost when the app locks.
- The store reloads through `.onReceive(NotificationCenter.default.publisher(for: .ledgerDidChange))` on the root view, and again when the scene becomes active. Reason: this form is known to compile under Swift 6; the async `notifications(named:)` sequence has Sendable problems.
- Every write also reloads directly, without waiting for the change notification. Reason: the UI (and the UI tests) see the result immediately; the second reload from the notification is harmless.
- "Now" is the time of the last reload (`LedgerStore.now`). Reason: every number in one render uses the same instant. It refreshes on each data change and each time the app becomes active.
- `LedgerCalendar.current` is created fresh on every use, never cached. Reason: time-zone changes are picked up.
- A month's goal is: the goal stored for that month, else the most recent earlier goal, else $200. Reason: past months without their own entry still get a sensible goal.
- Monthly goal prompt: `lastGoalPromptMonth` is written when the sheet is shown, not when it is saved. Closing the sheet without saving stores the pre-filled amount as this month's goal. Reason: the prompt appears once per month and there is always a goal.
- The goal sheet's pre-fill is this month's goal if one exists, else last month's, else $200.
- The goal field has a clear (x) button. Reason: easier to replace the pre-filled amount, and the UI test needs a reliable way to empty the field.
- Under `-uiTesting` the goal prompt appears only with `-uiTestingGoalPrompt`, and then once per launch.
- The `-uiTestingSeedReview` item is built by the UI layer itself with Core's `TransactionIngestor` (amount "0", no merchant, card "Test Card") and saved through the repository, not through `WalletTransactionLogger`. Reason: no notification code runs and the UI tests don't depend on the intent layer.
- Added launch arguments `-uiTestingDark` (forces Dark Mode) and `-uiTestingDemoData` (loads the demo data under `-uiTesting`), used only by the screenshot tour test.
- Manual entries with a blank merchant are saved with merchant `""` and are NOT flagged Needs Review. Reason: cash purchases must take under five seconds (open, type amount, Save).
- A new manual entry that matches an existing transaction (Core's `DuplicateDetector`: same amount and merchant within 3 minutes) is saved with `isPossibleDuplicate = true`, so it gets a badge and shows in the Needs Review inbox. `needsReview` itself stays false.
- Saving any edit clears `needsReview` and `isPossibleDuplicate`.
- Save is disabled until the amount is non-zero, for edits too. A zero-amount Wallet item can be kept unchanged with the "Keep" action in the inbox.
- The keypad allows 9 whole digits and 2 decimals. The typed text always uses "." and is parsed with `AmountParser` in the `en_US_POSIX` locale. The big amount shows currency symbol + typed digits (e.g. "$12.5") rather than a re-formatted number, so typing feels direct.
- Refund is a toggle; the amount is stored negative.
- Category auto-selection: while adding, the category follows `Categorizer` as the merchant is typed until the user taps a chip. While editing, the existing category is kept unless the merchant was blank (a Needs Review item), in which case it follows the typed merchant.
- "Always categorize [merchant] as [category]?" is offered only when editing an existing transaction, the user tapped a different category chip, and the merchant is not blank. A category that changed only through auto-categorization does not trigger it. It is not offered for brand-new entries.
- The "Always categorize" question is a card inside the edit sheet with "Always" and "Just this once" buttons, not a system alert. Reason: system alert buttons don't reliably carry accessibility identifiers for UI tests.
- Category chips are a wrapping grid, not a sideways scroller. Reason: every category is visible and tappable without scrolling sideways.
- Payment method is a row of buttons: Cash (pre-selected), Other card, then each Wallet card seen so far. Cash needs no tap.
- Merchant suggestions (from `knownMerchants()`) appear under the field only while it has focus.
- Needs Review inbox lists transactions with `needsReview` OR `isPossibleDuplicate`. Tapping opens the editor; swipe or long-press gives "Keep" (clears both flags) and "Delete".
- Transactions list: delete shows an Undo bar for 6 seconds; Undo re-inserts the same record (same id) with `upsert`. Only the most recent delete can be undone.
- Transactions filter: categories, sources, payment methods, an optional from/through day range, and "needs review only". Archived categories are listed too (marked) so old transactions can be found.
- Rows with a blank merchant show the category name as the title.
- Earnings screen lists the last 26 completed weeks, newest first. Clearing a field and saving deletes that week's entry; an entered 0 counts as entered. The current (unfinished) week is not listed.
- The Home earnings card depends only on stored data (`EarningsReminder.isLastWeekMissing`), so it works with notifications denied.
- Home shows the month in the navigation title. With unknown income the goal card says "Add your earnings to see this" and shows spending only; no guessed numbers.
- Insights month picker goes back without limit and stops at the current month.
- Donut drill-down: every legend row is a `NavigationLink` to that category's transactions for the month; tapping the donut itself (`chartAngleSelection`) does the same. Home's donut is not tappable (it has a "See all charts" button).
- Month-over-month chart uses horizontal grouped bars and hides categories with no spending in either month. Reason: ten category names don't fit under vertical bars.
- Top merchants use `ProgressView` as the mini bar.
- Chart colors: spending orange, earnings / on-track green, previous month gray, current month accent color (system colors, so they adapt to Dark Mode). The line chart also varies the dash style, so it doesn't rely on color alone.
- Insight rephrasing: engine insights are shown first; reworded ones replace them when `InsightRephraser` returns. Home caches the last rephrase result so unchanged insights are not reworded again.
- Category icons are a white symbol on the category color, and selected chips use white text on the category color. A very light custom color will have weak contrast; no automatic contrast fix was added.
- "Other" can't be archived (it is the fallback for uncategorized transactions). New categories get a blue color, the `tag.fill` symbol and are placed last.
- Category symbols come from a fixed list of 30 SF Symbols.
- CSV export is two steps: "Export all transactions as CSV" creates the file, then a `ShareLink` row appears for it. Reason: `ShareLink` needs the URL up front and this avoids a UIKit wrapper.
- Erase all data: erases the store, resets settings, then sets `hasCompletedOnboarding = true` and `demoDataLoaded = true`. Reason: erasing shouldn't replay onboarding, and DEBUG builds must not silently re-seed the demo data on next launch. The monthly goal prompt will appear again on the next open because `lastGoalPromptMonth` is reset.
- Reminder time: changing the picker saves hour/minute and reschedules at once. When permission is denied a note and an "Open Settings" button appear; when not yet asked, a "Turn on the Monday reminder" button asks for permission.
- Write failures show an alert on the root view with the system's error text.
- `LedgerlyApp` attaches `.modelContainer(SharedModelContainer.shared)` to the root view even though views don't use `@Query`. Reason: it makes the single shared container explicit and opens the store at launch.

## (b) Places least sure to compile or behave

1. `CategoryDonutChart.swift`: `.chartAngleSelection(value:)` with a `Binding<Double?>`. The API should exist on iOS 17+, but it is unverified whether a scroll that starts on the donut can trigger a selection (which navigates). If it misbehaves, delete the `angleSelection` argument in `InsightsView.donutCard`; the legend links still give the drill-down.
2. `InsightsView.swift`: `.navigationDestination(item:)` (iOS 17) fed by that chart selection.
3. `InsightsCharts.swift`: `.chartForegroundStyleScale(domain:range:)` with `[String]` / `[Color]`, `.lineStyle(by:)`, `.position(by:)`, and `accessibilityLabel`/`accessibilityValue` on marks with `String` arguments.
4. `MainTabView.swift` / several views: `Bindable(router).isAddSheetPresented`, `Bindable(sheets).active`, `Bindable(model).x` used inline instead of `@Bindable var`.
5. `RootView.swift`: `.onReceive(...)` closure calling the main-actor `store.requestReload()`; `@State private var store = LedgerStore()` (main-actor initializer as a default value).
6. `TransactionEditorModel.swift`: an `@Observable` class whose `init` first sets its three `let` constants and then assigns observed properties.
7. `HomeView.swift`, `NeedsReviewView.swift`, `MerchantRulesView.swift`: `ForEach(Array(x.enumerated()), id: \.element.id) { index, item in … }` (tuple destructuring in the closure).
8. `SettingsView.swift`: `#if FINANCEKIT_ENABLED` / `#if DEBUG` blocks inside the `Form` builder; `UIApplication.openSettingsURLString`.
9. `MainTabView.swift`: hiding unselected tabs with `.accessibilityHidden(true)` on `NavigationStack`s. If XCUITest still sees elements of hidden tabs, identifiers are unique per tab (`recent_row_N` on Home vs `transaction_row_N` on Transactions), so lookups should still be unambiguous.
10. UI tests: the merchant field can sit behind the pinned Save bar on small screens; `UITestSupport.typeMerchant` swipes up first when the frames overlap. `testSetMonthlyGoal` expects the goal field's value to be exactly "200". Row label assertions (`contains("12.50")`, `contains("Cash")`) assume the button's accessibility label is the row's combined label.
11. Zero-warning risk: none known, but nothing was compiled.
