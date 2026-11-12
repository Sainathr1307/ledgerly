# Ledgerly

A personal expense tracker for iPhone. It records what you buy, sorts each purchase into a category, shows where the money is going, and tells you what to cut to hit a monthly savings goal ($200 by default).

Everything stays on the phone. There is no account, no server, no analytics and no network code at all.

Repo: <https://github.com/Sainathr1307/ledgerly>

## What's in it

- **Quick add**: amount keypad first, category chips, merchant autocomplete, Cash in one tap.
- **Wallet logging** through a Shortcuts automation that calls the app's "Log Wallet Transaction" action in the background (details and limits below, please read them).
- **Auto-categorization**: your own "always categorize X as Y" rules first, then a built-in keyword table, then Other.
- **Needs Review** inbox for purchases that arrived without an amount or a merchant, and for possible duplicates.
- **Monthly savings goal**, weekly earnings (Monday to Sunday weeks), projected savings and a safe-to-spend-per-day number.
- **Insights** with real figures: over-pace categories, a cut list that adds up to the gap, frequent small purchases, top merchants, weekend vs weekday.
- **Charts** (Swift Charts): category donut, weekly spending vs earnings, cumulative spending vs an on-track line, month-over-month, top merchants.
- **CSV import and export**, optional Face ID lock, erase all data.

## Requirements

- A Mac with **Xcode 16 or later** (iOS 18 SDK). The app targets iOS 18.0 and is iPhone only.
- **XcodeGen**: `brew install xcodegen`

No Mac that can run Xcode 16? See [No Mac that can run Xcode?](#no-mac-that-can-run-xcode) further down.

## Opening the project

The Xcode project isn't checked in. It is generated from `project.yml`, so it is always reproducible.

```sh
git clone https://github.com/Sainathr1307/ledgerly.git
cd ledgerly
xcodegen generate
open Ledgerly.xcodeproj
```

Pick an iPhone simulator and press Run. Simulator builds need no signing setup.

Run `xcodegen generate` again whenever you add files or change `project.yml`. `App/Resources/Info.plist` is written by XcodeGen each time, so change its values under `info: properties:` in `project.yml`, not in the plist.

## Bundle ID and signing team

The repo ships with the bundle ID `com.example.ledgerly` and an empty signing team. Both have to change before the app can go on a real phone, because a bundle ID has to be unique across everyone's apps and `com.example.ledgerly` isn't yours.

**In `project.yml` (survives regenerating the project):**

- `PRODUCT_BUNDLE_IDENTIFIER: com.example.ledgerly` under `targets: Ledgerly: settings: base:`. Change it to something of your own, like `com.yourname.ledgerly`. Change the UI test target's `com.example.ledgerly.uitests` to match.
- `DEVELOPMENT_TEAM: ""` under the top-level `settings: base:`. Put your 10-character Team ID between the quotes. (`bundleIdPrefix: com.example` near the top is only the default prefix for targets that don't set their own ID.)

Then run `xcodegen generate` again.

**Or in Xcode (quicker, but lost the next time you regenerate):** click the Ledgerly project in the sidebar, the Ledgerly target, then Signing & Capabilities. Tick "Automatically manage signing", choose your Team, and edit the Bundle Identifier.

You don't need a paid developer account. Add your Apple ID under Xcode > Settings > Accounts and a free "Personal Team" appears in the Team menu. Its Team ID is shown in the same place if you want to put it in `project.yml`.

## Installing on your own iPhone

1. Set the bundle ID and team as above.
2. Connect the iPhone with a cable and tap Trust on the phone. After the first time, Xcode can also reach it over Wi-Fi when both are on the same network.
3. On the phone, turn on **Developer Mode**: Settings > Privacy & Security > Developer Mode, then restart when asked. The switch only shows up after the phone has been connected to Xcode once.
4. In Xcode, choose your iPhone in the device menu at the top and press Run.
5. The first launch is blocked with an "Untrusted Developer" message. On the phone go to Settings > General > VPN & Device Management, tap your Apple ID under Developer App, and tap Trust. Run again.

With a free Apple ID the app stops opening after **7 days**. Connect the phone and press Run again to renew it; your data is kept. A paid Apple Developer Program membership ($99 a year) stretches that to a year.

Pressing Run makes a Debug build, and Debug builds fill an empty app with demo data (see [Demo data](#demo-data)). For a clean app on your own phone, switch the scheme to Release first: Product > Scheme > Edit Scheme > Run > Build Configuration > Release.

## No Mac that can run Xcode?

This project was written on a machine that couldn't run Xcode at all, so the repo includes a GitHub Actions workflow that does the building on a cloud Mac: `.github/workflows/ci.yml`.

What it does, on every push to `main` or a `ci/**` branch, or when you start it by hand from the Actions tab: on a `macos-15` runner it installs XcodeGen, generates the project, builds the app and tests, and runs the unit and UI tests on an iOS 18 iPhone simulator. It uploads the build log, the test log and the UI-test screenshots as an artifact called `ledgerly-ci`, which you can download from the run's page. So you can change the code and see whether it builds, passes and what it looks like without owning a Mac.

What it doesn't do: it builds for the simulator, unsigned. It does not produce something you can put on a phone. Getting it onto an iPhone without a Mac means extending the workflow to archive a device build, and then one of two routes. I haven't tested either from this repo, so take these as the options, not as instructions:

- **Paid Apple Developer Program + TestFlight.** Sign the build in the workflow with your distribution certificate and provisioning profile (stored as GitHub secrets), upload it to App Store Connect, and install it through the TestFlight app. Builds last 90 days. This is the supported way, and it costs $99 a year.
- **Free sideloading.** Have the workflow export an unsigned `.ipa`, then use a tool such as Sideloadly or AltStore on a Windows or Mac computer to re-sign it with your own Apple ID and install it. It's free, but it has the same 7-day limit as a free Xcode install, so it needs refreshing every week, and these are third-party tools that ask for your Apple ID. Whether App Intents and the Shortcuts action survive that kind of re-signing is something I can't promise.

If you can borrow a Mac with Xcode 16 for ten minutes a week, the section above is far less trouble than either.

## Running the tests

```sh
scripts/verify.sh
```

That generates the project, builds, and runs every test (the Core unit tests and the UI tests) on the first available iPhone simulator on iOS 18 or later, then prints a summary with warning and error counts. To use a particular simulator: `SIM_UDID=<udid> scripts/verify.sh`. Logs land in `build/`.

The logic lives in a plain Swift package with no UI imports, so its tests also run on their own, on a Mac or on Linux:

```sh
cd Packages/LedgerlyCore
swift test
```

That covers amount parsing, merchant cleanup, categorization, duplicate detection, calendar edges (5-Monday months, daylight saving), the budget math, the gap plan, every insight, chart series, CSV and the demo data.

The UI tests cover: adding a cash transaction, changing its category and accepting "always categorize", entering weekly earnings, setting the monthly goal, and resolving a Needs Review item.

## Setting up the Wallet automation

iOS won't let any third-party app read your Wallet history. What it does have is a personal automation in the Shortcuts app that fires when you tap a Wallet card to pay, and can pass the amount, merchant and card name to an app. Ledgerly provides the action for it to call. You build the automation once, by hand; Apple doesn't let apps create it for you.

The same walkthrough is in the app: in onboarding, and in Settings under the Wallet automation guide.

1. Open the **Shortcuts** app.
2. Go to the **Automation** tab (bottom middle).
3. Tap **+** in the top right. If it's your first automation, tap New Automation.
4. Choose **Transaction**. On newer iOS versions it's called **Wallet**. Scroll down or search for it.
5. Tick the **cards** you want tracked. Leave the merchant and category filters alone so everything is caught.
6. Choose **Run Immediately**, and turn off **Notify When Run**. Tap **Next**.
7. Tap **New Blank Automation**.
8. Tap the action search field, search for **Ledgerly**, and pick **Log Wallet Transaction**.
9. Fill in the three fields from the Shortcut Input:
   - Tap **Amount**, choose **Shortcut Input**, then tap the Shortcut Input bubble that appears and pick **Amount**.
   - Tap **Merchant**, choose **Shortcut Input**, tap the bubble and pick **Merchant**.
   - Tap **Card**, choose **Shortcut Input**, tap the bubble and pick **Card or Pass**.
10. Tap **Done**.

Now pay for something by tapping your phone. Within a few seconds you should get a notification like "Logged $12.40 at Starbucks · Food & Dining", and the purchase is in the app.

To check Ledgerly's side without buying anything, use the **Test it** button at the bottom of that guide in Settings. It runs the same code as the automation with a sample purchase ($12.40 at Starbucks) and shows you what was saved and whether a notification could be posted. It saves a real transaction; there's a button to remove it.

### Troubleshooting

- **"Log Wallet Transaction" doesn't show up in Shortcuts.** Open Ledgerly once after installing, then try the search again. If it's still missing, restart the phone; Shortcuts can be slow to notice a newly installed app's actions.
- **There's no Transaction or Wallet trigger in the list.** It needs iOS 17 or later and at least one payment card in Wallet.
- **Nothing happens when I pay.** In Shortcuts > Automation, open the automation and check it's set to Run Immediately and that the card you used is ticked. Also check how you paid: only a tap of this iPhone counts (see the limits below).
- **It asks me to confirm every time.** The automation is on "Run After Confirmation". Change it to Run Immediately.
- **The purchase is saved but lands in Needs Review.** iOS sent it without an amount or without a merchant. That happens, and there's nothing the app can do about it except save what it got. Open it from Needs Review and fill in the blank.
- **The amount or merchant is always missing.** The fields probably aren't mapped. Open the automation and make sure each one shows a Shortcut Input bubble with the right property (Amount, Merchant, Card or Pass), not typed text and not the whole Shortcut Input.
- **Everything is logged twice.** You likely have two automations for the same card. Delete one. Ledgerly flags the second copy as a possible duplicate (same amount and same merchant or card within three minutes) instead of hiding it, so you'll see them in Needs Review.
- **No notification.** Notifications are off for Ledgerly. Purchases are still logged. Turn them on in the Settings app > Notifications > Ledgerly if you want the confirmations.
- **It stopped working after a week.** With a free Apple ID the app expires after 7 days, and an expired app can't run its action. Reinstall from Xcode.

## Demo data

Debug builds load three months of made-up transactions, weekly earnings and goals the first time they start with an empty store, so every chart and insight has something to show. The current month is tuned to run over in Food & Dining and fall short of the goal, so the gap plan appears. Two Needs Review items are included, and last week's earnings are left out on purpose so the earnings card shows.

The data is generated relative to today from a fixed seed, so it looks the same on every run. Release builds contain none of it: the seeder's body is inside `#if DEBUG`. It is also skipped during UI tests.

To get rid of it, use Erase All Data in Settings. To avoid it altogether, run a Release build.

## CSV import and export

**Import** (in Settings): pick a `.csv` file from Files. The app guesses which column is the date, amount, merchant, category, notes and card, and you can correct any of them. You also choose the date order (month/day/year, day/month/year, year-month-day) and whether purchases are negative numbers, which they are in most bank exports and aren't in Apple Card's. A preview shows the first rows exactly as they'll be imported. Rows that match something you already have (same day, same amount, same merchant) are listed as possible duplicates and left out unless you choose to include them. Rows with an unreadable date are skipped and listed. Everything else is categorized and saved in one go; rows with no amount or no merchant go to Needs Review.

**Export** (in Settings): writes every transaction, with its category name, to `Ledgerly-export-yyyy-MM-dd.csv` and hands it to the share sheet. The file can be imported back.

## FinanceKit (optional, off, and probably not for you)

FinanceKit can read Apple Card, Apple Cash and Apple Savings transactions directly, in the US only. It needs the `com.apple.developer.financekit` entitlement, which Apple grants on request to organisations. Individual developer accounts can't get it, and Xcode won't sign a build that claims an entitlement the account doesn't have.

So the integration is written (`App/Services/FinanceKit/`) but compiled out. The default build contains no FinanceKit code, and it has never been compiled or run by me, because I had no way to. Treat it as a starting point.

If you do have the entitlement:

1. In `project.yml`, uncomment the `entitlements:` block under the Ledgerly target. XcodeGen will then generate `App/Resources/Ledgerly.entitlements`. (`App/Resources/Ledgerly.entitlements.example` shows what ends up in it.)
2. In `project.yml`, uncomment `SWIFT_ACTIVE_COMPILATION_CONDITIONS: $(inherited) FINANCEKIT_ENABLED`.
3. Run `xcodegen generate` and build. Expect to fix a few compile errors in the FinanceKit files.
4. In the app, turn on the Apple accounts switch in Settings and tap Sync now.

## Privacy

- All data is stored on the device with SwiftData. Nothing is uploaded anywhere, because there is no networking code in the app.
- No accounts, no analytics, no ads, no third-party packages.
- The "Open Shortcuts" button opens another app on the phone; it isn't a network request.
- Notifications are local ones scheduled by the app itself.
- The privacy manifest (`App/Resources/PrivacyInfo.xcprivacy`) declares no tracking and no collected data. The one required-reason API it lists is UserDefaults, used for the app's own settings.
- If the optional on-device rewording of insights is available (Apple's Foundation Models, iOS 26 and later), it runs on the phone too, and it is only allowed to change wording: a rewrite is discarded unless its numbers match the originals exactly.
- Face ID is used only for the optional app lock.

Uninstalling the app deletes everything. There is no backup other than your normal iPhone backup and the CSV export.

## Known limitations

The Wallet ones first, because they matter most:

- **No app can read your Wallet history.** Ledgerly only knows about purchases that the Shortcuts automation hands to it, from the moment you set it up. Nothing from before, and nothing it wasn't told about.
- **The automation only fires for tap-to-pay with a card in Wallet on that iPhone.** As far as the trigger goes, it does not fire for online or in-app Apple Pay, for payments made from an Apple Watch, or for swiping, inserting or typing in the physical card. Those need adding by hand or via CSV import.
- **The amount or the merchant can arrive empty or as 0.** That's iOS, not something the app can fix. Those purchases are saved and put in Needs Review.
- **You have to build the automation yourself**, about ten taps, and again on a new phone. Apple doesn't let apps install personal automations.
- **Don't count on refunds coming through the automation.** Enter them by hand as a refund.
- **FinanceKit is not usable** without an entitlement individuals can't get, and that code is untested.

Others:

- **No app icon is included.** The app shows the blank placeholder. To add one, put a 1024×1024 PNG in `App/Resources/Assets.xcassets/AppIcon.appiconset/` and add `"filename" : "YourIcon.png"` to the image entry in that folder's `Contents.json`.
- One currency at a time. Amounts aren't converted.
- No iCloud sync and no iPad layout.
- The projection is simple. Early in the month one large purchase (rent on the 1st, say) makes that category's projection look far too high until more days have passed or there is past data to blend with.
- Insight text is English only.
- A free Apple ID install expires every 7 days.

See `DECISIONS.md` for the assumptions behind the numbers, and `PLAN.md` for the architecture.
