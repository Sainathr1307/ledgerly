// LedgerlyUITestSupport.swift — shared helpers for the UI tests. Everything that touches XCUIApplication or
// XCUIElement is main-actor isolated, as the Swift 6 SDK requires.

import XCTest

@MainActor
enum UITestSupport {
    static let timeout: TimeInterval = 15

    /// Launches the app with a fresh in-memory store ("-uiTesting") plus any extra flags.
    static func launch(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + extraArguments
        app.launch()
        return app
    }

    /// Finds any element by accessibility identifier.
    static func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Waits for the element, fails the test if it never shows up, and returns it.
    @discardableResult
    static func require(
        _ identifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let found = element(identifier, in: app)
        XCTAssertTrue(
            found.waitForExistence(timeout: timeout),
            "Expected element \"\(identifier)\" to appear",
            file: file,
            line: line
        )
        return found
    }

    /// Waits for the element and taps it.
    static func tap(
        _ identifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let found = require(identifier, in: app, file: file, line: line)
        found.tap()
    }

    /// Waits until the element is gone.
    static func waitForDisappearance(
        of identifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let found = element(identifier, in: app)
        let gone = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: gone, object: found)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(
            result,
            .completed,
            "Expected element \"\(identifier)\" to disappear",
            file: file,
            line: line
        )
    }

    /// Types an amount such as "12.50" on the custom keypad of the quick-add sheet.
    static func typeOnKeypad(_ amount: String, in app: XCUIApplication) {
        for character in amount {
            if character == "." {
                tap("keypad_dot", in: app)
            } else {
                tap("keypad_\(character)", in: app)
            }
        }
    }

    /// Types into the merchant field of the open editor, scrolling first if the pinned Save bar covers the field.
    static func typeMerchant(_ merchant: String, in app: XCUIApplication) {
        let field = require("merchantField", in: app)
        let saveButton = require("saveTransactionButton", in: app)
        if field.frame.maxY > saveButton.frame.minY - 8 {
            app.swipeUp()
        }
        field.tap()
        field.typeText(merchant)
    }

    /// Opens quick add, types the amount (and a merchant if given) and saves.
    static func addTransaction(amount: String, merchant: String?, in app: XCUIApplication) {
        tap("addButton", in: app)
        require("amountDisplay", in: app)
        typeOnKeypad(amount, in: app)
        if let merchant {
            typeMerchant(merchant, in: app)
        }
        tap("saveTransactionButton", in: app)
        waitForDisappearance(of: "saveTransactionButton", in: app)
    }

    /// Attaches a screenshot of the whole screen to the test, kept even when the test passes.
    static func attachScreenshot(named name: String, to testCase: XCTestCase) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }
}
