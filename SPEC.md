# Build "Ledgerly" (working title): a personal expense tracker for iPhone

You're building a complete, production-quality iOS app from scratch. I won't be around to answer questions while you work, so make sensible decisions yourself and write each one down in `DECISIONS.md` with a sentence on why. Don't stop to ask me anything. The job is done when the app builds, all tests pass, and every feature below works in the iOS Simulator.

## What the app is for

I want one place that records every purchase I make, sorts it into a category, shows me where my money is going, and tells me exactly where to cut back so I can hit a monthly savings goal (by default $200/month). It should be fast and easy to use every day: adding a purchase by hand should take under 5 seconds.

## Important platform reality: how Wallet transactions get into the app

iOS does not let third-party apps read all Apple Wallet transactions in the background. Don't fake this, and don't build features that can't work. Use these sources, in this order:

1. **Shortcuts Wallet automation (main source, required).** iOS 17+ Shortcuts has a personal automation trigger called "Transaction" ("Wallet" on newer iOS). It fires when the user taps a Wallet card to pay and passes the amount, the merchant and the card name. Expose an App Intent called **"Log Wallet Transaction"** with parameters for amount, merchant and card name. It should run in the background (`openAppWhenRun = false`), save the transaction, auto-categorize it, and post a local notification like "Logged $12.40 at Starbucks · Food & Dining". Expect this trigger to sometimes send an amount of 0 or a blank merchant. When that happens, still save the transaction, but put it in a **Needs Review** inbox and badge it in the UI so the user can fix it with one tap. Accept the amount as a String or a Decimal-friendly type and parse it carefully (handle currency symbols, commas and locale formats).
2. **FinanceKit (optional, off by default).** This only covers Apple Card, Apple Cash and Apple Savings in the US, and it needs a managed entitlement that individual developer accounts can't get. Put it behind a `TransactionSource` protocol and a feature flag, write the integration code, and keep it compiled out or disabled unless the entitlement exists. The app must build and run fully without it.
3. **Manual entry (required).** This covers cash, online purchases, cards not in Wallet, and anything the automation missed.
4. **CSV import (nice to have).** Let the user import an Apple Card or bank CSV export, with a column-mapping step and duplicate detection.

The onboarding flow needs a clear, illustrated walkthrough (text + SF Symbols is fine) that teaches the user how to set up the Shortcuts automation: Automation tab → + → Wallet/Transaction → choose cards → Run Immediately → add "Log Wallet Transaction" → map Shortcut Input → Amount / Merchant / Card. Put the same guide in Settings too. Add a "Test it" button that runs the intent with sample data so the user can confirm it works.

**Duplicate protection:** if a new transaction matches an existing one on amount and merchant (or card) within 3 minutes, flag it as a possible duplicate instead of silently adding a second copy.

## Core features

### Transactions
- Each transaction stores: id, amount (`Decimal`, never `Double`), currency, merchant, category, date and time, payment method (the Wallet card name, Cash, or Other card), source (wallet shortcut / FinanceKit / manual / import), notes, `needsReview`, and `createdAt`.
- Refunds are negative amounts and reduce spending in the right category.
- The list is grouped by day with daily totals, searchable by merchant or notes, and filterable by category, source, payment method and date range. Swipe to edit or delete, with undo.
- **Quick-add screen:** big amount keypad first, category chips, merchant field that autocompletes from past merchants, payment method (Cash is one tap), and date/time defaulting to now. The Save button is always reachable.

### Categories and auto-categorization
- Default categories: Food & Dining, Groceries, Gas, Shopping, Recreation & Entertainment, Bills & Utilities, Transportation, Health, Subscriptions, Other. Each has a color and an SF Symbol. Users can add, rename, recolor, reorder and archive categories.
- Categorize in this order: (1) the user's learned merchant→category rule, (2) built-in keyword rules (e.g. Shell/Chevron/BP/Speedway → Gas; Starbucks/McDonald's/Chipotle → Food & Dining; Target/Amazon/Walmart → Shopping; Jewel-Osco/Aldi/Trader Joe's → Groceries; Netflix/Spotify → Subscriptions), (3) Other.
- Whenever the user changes a transaction's category, offer "Always categorize [merchant] as [category]?" and save that as a rule.
- Normalize merchant names before matching (case, punctuation, store numbers like "SHELL OIL 57444").

### Monthly savings goal
- On the first app open of each new month (and on first launch), show a sheet: "How much do you want to save this month?" Pre-fill it with last month's goal, or $200 the first time. The goal can be edited any time.
- The dashboard shows progress toward the goal: projected savings at month-end, plus a **safe-to-spend per day** number for the rest of the month.

### Weekly earnings (every Monday)
- Weeks run Monday to Sunday.
- Schedule a repeating local notification for every Monday at 8:00 AM local time: "New week! What did you earn last week?" Tapping it opens the earnings entry screen. The time can be changed in Settings.
- Inside the app, if last week's earnings haven't been entered, show a card at the top of the dashboard until they are.
- Earnings for any past week can be entered or edited. Each weekly amount counts toward the month its Monday falls in (note this in `DECISIONS.md`).

### The math (put it in one pure, fully unit-tested `BudgetEngine`)
- Income this month = the weekly earnings entered for this month. Expected income = income so far + (the average of entered weeks × the remaining weeks in the month). If there's no data yet, show the gap clearly instead of guessing wildly.
- Spending this month = the sum of expenses minus refunds.
- Projected spending = this month's spending pace, blended with the trailing 3-month average for each category once history exists.
- Projected savings = expected income − projected spending.
- Safe to spend per day = (expected income − savings goal − spent so far) ÷ days left (minimum 0).
- All money math uses `Decimal`, rounded to cents only for display.

### Insights: "where am I overspending and how do I save the $200?"
Build a deterministic insights engine that runs on the device. No server and no network. Each insight is a short, plain-English card with a real dollar figure. Include at least:
- **Over-pace categories:** "Food & Dining is at $310, 40% above your usual $220 by this point in the month."
- **Gap-closing plan:** if projected savings < goal, produce a concrete cut list across discretionary categories (Food & Dining, Shopping, Recreation, Subscriptions first; never Bills or Health) whose amounts add up to the gap. Example: "To hit $200: cut dining out by $45, shopping by $30, and pause one subscription ($15)."
- **Frequent small purchases:** "14 coffee runs this month = $72. Halving that saves $36."
- **Top merchants** by spending this month, and how they changed versus last month.
- **Weekend vs weekday** spending pattern when it differs a lot.
- **Positive reinforcement** when a category is under its usual amount or the goal is on track.
- Optional extra: if Apple's on-device Foundation Models framework is available, use it only to rephrase the engine's insights more naturally. All numbers still come from `BudgetEngine`, and if the model is unavailable, fall back silently.

### Visuals (Swift Charts)
- Donut chart of spending by category for the selected month, tappable to drill into that category's transactions.
- Bar chart of spending per week alongside earnings per week.
- Line chart of cumulative spending through the month vs. an "on-track" budget line (expected income − goal, spread evenly across the month).
- Month-over-month category comparison (grouped bars).
- Top merchants list with mini bars.
- A month picker to browse past months.

### Screens (tab bar)
1. **Home:** goal progress ring, safe-to-spend per day, earnings-needed card (when due), donut chart, top 3 insights, Needs Review count, recent transactions.
2. **Transactions:** full list, search and filters.
3. **(+) Add:** the quick-add sheet, reachable from every tab.
4. **Insights:** all charts and all insight cards.
5. **Settings:** goal, Monday reminder time, categories and merchant rules, Wallet automation guide plus test button, CSV import/export, optional Face ID lock, erase all data (with confirmation).

## Technical requirements
- Swift 6, SwiftUI, SwiftData, Swift Charts, App Intents, UserNotifications. Minimum deployment target iOS 18.0. iPhone only, portrait-first, full Dark Mode and Dynamic Type support, VoiceOver labels on every control and chart.
- Architecture: SwiftData models → repository layer → `BudgetEngine` / `InsightsEngine` / `Categorizer` (pure Swift, no UI imports) → `@Observable` view models → views. The App Intent and the app must share one `ModelContainer` so data logged in the background appears right away.
- 100% local and private: no accounts, no analytics SDKs, no network calls. Add the needed Info.plist usage strings and a privacy manifest.
- Generate the Xcode project with XcodeGen (`project.yml`) so it's reproducible. Leave the bundle ID as `com.example.ledgerly` and the signing team blank, and explain in the README how to set both.
- Include sample/demo data that loads in DEBUG builds only (3 months of realistic transactions and weekly earnings), so every chart and insight can be checked visually.
- Handle edge cases: the first day of a month, months with 5 Mondays, time zone and daylight saving changes, empty states for every screen, very large amounts, refunds larger than a category's spending, and notification permission denied (the in-app card still works).

## How to work
Use subagents to split the work and run things in parallel where it makes sense. For example:
1. **Plan first:** write `PLAN.md` with the architecture, data model, screen list and test plan before writing any feature code.
2. **Parallel build:** one agent on the data layer and `BudgetEngine`/`InsightsEngine`/`Categorizer` with unit tests; one on SwiftUI screens and charts; one on App Intents, notifications, onboarding and FinanceKit stubs.
3. **Integrate,** then build with `xcodebuild` and run all tests on an iPhone simulator.
4. **Independent review:** have a fresh agent that didn't write the code review it against this prompt line by line. Fix everything it finds, then rebuild and retest.
5. **Repeat** until the definition of done is met.

## Tests (required)
- Unit tests for: savings and safe-to-spend math, month and week boundaries, refund handling, amount parsing from Shortcuts input (including "$1,234.56", "0", blank and locale variants), categorization rules and learned rules, duplicate detection, and the gap-closing plan (the cuts must add up to the gap).
- UI tests for: adding a manual cash transaction, editing its category and accepting "always categorize", entering weekly earnings, setting the monthly goal, and resolving a Needs Review item.

## Definition of done
- [ ] `xcodebuild build` and `xcodebuild test` pass on the iOS Simulator with zero errors, zero warnings and no failing tests
- [ ] Every feature above works with the DEBUG demo data, and every screen looks right in Light and Dark Mode
- [ ] Running the "Log Wallet Transaction" intent with sample input creates a categorized transaction and a notification; amount 0 or a blank merchant lands in Needs Review
- [ ] The Monday 8 AM notification is scheduled, and the in-app earnings card appears when last week is missing
- [ ] The monthly goal prompt appears on the first open of a new month
- [ ] Insights show real numbers, and the gap-closing plan adds up
- [ ] `README.md` explains: opening the project, setting the signing team, installing on a personal iPhone, and setting up the Shortcuts Wallet automation step by step
- [ ] `DECISIONS.md` lists every assumption you made

When you're done, give me a short summary: what was built, what's verified, any known limitations (be honest about the Wallet ones), and the exact steps to get it onto my iPhone.