// LedgerlyUITests.swift — the five required flows. Each test launches its own app with a fresh in-memory store.

import XCTest

@MainActor
final class LedgerlyUITests: XCTestCase {

    /// 1. Add a manual cash transaction: + → amount on the keypad → Save. Nothing else is needed.
    func testAddManualCashTransaction() {
        continueAfterFailure = false
        let app = UITestSupport.launch()

        UITestSupport.tap("addButton", in: app)
        UITestSupport.require("payment_cash", in: app)
        UITestSupport.typeOnKeypad("12.50", in: app)

        let display = UITestSupport.require("amountDisplay", in: app)
        let shown = (display.value as? String ?? "") + " " + display.label
        XCTAssertTrue(shown.contains("12.50"), "The amount display should show what was typed, got: \(shown)")

        UITestSupport.tap("saveTransactionButton", in: app)
        UITestSupport.waitForDisappearance(of: "saveTransactionButton", in: app)

        UITestSupport.tap("tab_transactions", in: app)
        let row = UITestSupport.require("transaction_row_0", in: app)
        XCTAssertTrue(row.label.contains("12.50"), "The new transaction should be listed, got: \(row.label)")
        XCTAssertTrue(row.label.contains("Cash"), "The new transaction should be a cash payment, got: \(row.label)")
    }

    /// 2. Edit a transaction's category and accept "Always categorize": the rule shows up in Settings.
    func testEditCategoryAndAcceptAlwaysCategorize() {
        continueAfterFailure = false
        let app = UITestSupport.launch()

        UITestSupport.addTransaction(amount: "8", merchant: "Corner Cafe", in: app)

        UITestSupport.tap("tab_transactions", in: app)
        UITestSupport.tap("transaction_row_0", in: app)

        UITestSupport.tap("category_chip_groceries", in: app)
        UITestSupport.tap("saveTransactionButton", in: app)

        UITestSupport.tap("alwaysCategorizeButton", in: app)
        UITestSupport.waitForDisappearance(of: "alwaysCategorizeButton", in: app)

        UITestSupport.tap("tab_settings", in: app)
        UITestSupport.tap("settingsMerchantRules", in: app)
        let rule = UITestSupport.require("rule_row_0", in: app)
        XCTAssertTrue(
            rule.label.uppercased().contains("CORNER CAFE"),
            "The rule should be for the edited merchant, got: \(rule.label)"
        )
        XCTAssertTrue(
            rule.label.contains("Groceries"),
            "The rule should point at the new category, got: \(rule.label)"
        )
    }

    /// 3. Enter weekly earnings: the Home card is there, and goes away once last week is entered.
    func testEnterWeeklyEarnings() {
        continueAfterFailure = false
        let app = UITestSupport.launch()

        UITestSupport.tap("earningsCard", in: app)

        let field = UITestSupport.require("earningsField_0", in: app)
        field.tap()
        field.typeText("500")
        UITestSupport.tap("saveEarningsButton", in: app)

        UITestSupport.waitForDisappearance(of: "saveEarningsButton", in: app)
        UITestSupport.waitForDisappearance(of: "earningsCard", in: app)
        UITestSupport.require("goalAmountLabel", in: app)
    }

    /// 4. Set the monthly goal from the monthly prompt: Home shows the new goal.
    func testSetMonthlyGoal() {
        continueAfterFailure = false
        let app = UITestSupport.launch(["-uiTestingGoalPrompt"])

        let field = UITestSupport.require("goalField", in: app)
        XCTAssertEqual(field.value as? String, "200", "The goal should start at the default of 200")

        UITestSupport.tap("goalClearButton", in: app)
        field.tap()
        field.typeText("350")
        UITestSupport.tap("saveGoalButton", in: app)
        UITestSupport.waitForDisappearance(of: "saveGoalButton", in: app)

        let goalLabel = UITestSupport.require("goalAmountLabel", in: app)
        let expected = NSPredicate(format: "label CONTAINS %@", "350")
        let expectation = XCTNSPredicateExpectation(predicate: expected, object: goalLabel)
        let result = XCTWaiter.wait(for: [expectation], timeout: UITestSupport.timeout)
        XCTAssertEqual(result, .completed, "Home should show the new goal, got: \(goalLabel.label)")
    }

    /// 5. Resolve a Needs Review item: open the inbox from Home, fix the amount and merchant, save.
    func testResolveNeedsReviewItem() {
        continueAfterFailure = false
        let app = UITestSupport.launch(["-uiTestingSeedReview"])

        UITestSupport.tap("needsReviewBanner", in: app)
        UITestSupport.tap("review_row_0", in: app)

        UITestSupport.require("amountDisplay", in: app)
        UITestSupport.typeOnKeypad("4.50", in: app)
        UITestSupport.typeMerchant("Starbucks", in: app)
        UITestSupport.tap("saveTransactionButton", in: app)
        UITestSupport.waitForDisappearance(of: "saveTransactionButton", in: app)

        UITestSupport.require("reviewEmptyState", in: app)
        UITestSupport.tap("reviewDoneButton", in: app)

        UITestSupport.waitForDisappearance(of: "needsReviewBanner", in: app)
        UITestSupport.require("goalAmountLabel", in: app)
    }
}
