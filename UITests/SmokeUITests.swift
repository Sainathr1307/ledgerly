import XCTest

@MainActor
final class SmokeUITests: XCTestCase {
    func testLaunches() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Ledgerly smoke build"].waitForExistence(timeout: 20))
    }
}
