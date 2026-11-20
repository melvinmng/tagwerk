import XCTest

final class LaunchUITests: UITestCase {
    func testLaunchShowsPlan() {
        // The demo appointment of today appears in the day view.
        waitFor("Sprechstunde")
        XCTAssertTrue(app.tabBars.buttons["Planen"].isSelected)
    }
}
