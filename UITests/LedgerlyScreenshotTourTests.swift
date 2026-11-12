// LedgerlyScreenshotTourTests.swift — walks every tab with the demo data loaded and attaches screenshots,
// once in Light Mode and once in Dark Mode, so the screens can be checked by eye from the test report.

import XCTest

@MainActor
final class LedgerlyScreenshotTourTests: XCTestCase {

    func testScreenshotTourLight() {
        continueAfterFailure = false
        let app = UITestSupport.launch(["-uiTestingDemoData"])
        tour(app, suffix: "light")
    }

    func testScreenshotTourDark() {
        continueAfterFailure = false
        let app = UITestSupport.launch(["-uiTestingDemoData", "-uiTestingDark"])
        tour(app, suffix: "dark")
    }

    private func tour(_ app: XCUIApplication, suffix: String) {
        // Home
        UITestSupport.require("goalAmountLabel", in: app)
        UITestSupport.require("recent_row_0", in: app)
        UITestSupport.attachScreenshot(named: "01-home-\(suffix)", to: self)

        // Weekly earnings (the demo data leaves last week empty, so the Home card is showing)
        UITestSupport.tap("earningsCard", in: app)
        UITestSupport.require("earningsField_0", in: app)
        UITestSupport.attachScreenshot(named: "10-earnings-\(suffix)", to: self)
        UITestSupport.tap("closeEarningsButton", in: app)
        UITestSupport.waitForDisappearance(of: "saveEarningsButton", in: app)

        // Lower half of Home
        app.swipeUp()
        UITestSupport.attachScreenshot(named: "02-home-lower-\(suffix)", to: self)

        // Transactions
        UITestSupport.tap("tab_transactions", in: app)
        UITestSupport.require("transaction_row_0", in: app)
        UITestSupport.attachScreenshot(named: "03-transactions-\(suffix)", to: self)

        // Quick add (from the Transactions tab, to show it is reachable from anywhere)
        UITestSupport.tap("addButton", in: app)
        UITestSupport.require("keypad_1", in: app)
        UITestSupport.typeOnKeypad("12.40", in: app)
        UITestSupport.attachScreenshot(named: "04-quick-add-\(suffix)", to: self)
        UITestSupport.tap("cancelTransactionButton", in: app)
        UITestSupport.waitForDisappearance(of: "saveTransactionButton", in: app)

        // Insights
        UITestSupport.tap("tab_insights", in: app)
        UITestSupport.require("selectedMonthLabel", in: app)
        UITestSupport.attachScreenshot(named: "05-insights-\(suffix)", to: self)
        app.swipeUp()
        UITestSupport.attachScreenshot(named: "06-insights-charts-\(suffix)", to: self)
        app.swipeUp()
        UITestSupport.attachScreenshot(named: "07-insights-more-\(suffix)", to: self)
        app.swipeUp()
        UITestSupport.attachScreenshot(named: "08-insights-cards-\(suffix)", to: self)

        // Settings
        UITestSupport.tap("tab_settings", in: app)
        UITestSupport.require("settingsGoalRow", in: app)
        UITestSupport.attachScreenshot(named: "09-settings-\(suffix)", to: self)
    }
}
