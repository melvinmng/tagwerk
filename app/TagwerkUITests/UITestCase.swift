import XCTest

/// Base class of all UI tests: starts the app in the UI test mode (in-memory store, demo data, offline,
/// German) and waits until the demo data exists. Tests wait only with `waitForExistence`, never with `sleep`.
/// The simulator needs calendar and reminder access before the run (`app/test-all.sh` grants it with `simctl privacy`).
@MainActor
class UITestCase: XCTestCase {
    private(set) var app: XCUIApplication!

    /// Default wait for an element that the app shows after some work.
    static let timeout: TimeInterval = 10

    /// Extra launch arguments of a test class (e.g. a large text size); set before `launchApp`.
    var extraLaunchArguments: [String] { [] }

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        // Safety net for system dialogs; permissions are granted before the run, so none is expected.
        addUIInterruptionMonitor(withDescription: "System dialog") { alert in
            for title in ["Erlauben", "Allow", "Vollzugriff erlauben", "Allow Full Access", "OK"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
        launchApp()
    }

    /// Starts a fresh app process and waits for the marker the demo data sets when it is done.
    func launchApp() {
        let app = XCUIApplication()
        app.launchArguments = ["-TagwerkUITest", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"] + extraLaunchArguments
        app.launch()
        self.app = app
        let ready = app.descendants(matching: .any)[AccessibilityID.App.demoReady]
        XCTAssertTrue(ready.waitForExistence(timeout: 60), "The demo data was not created (calendar/reminder access granted?)")
    }

    // MARK: Helpers

    /// Taps a tab of the tab bar by its title.
    func tab(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.tabBars.buttons[title]
        XCTAssertTrue(button.waitForExistence(timeout: Self.timeout), "Tab \(title) missing", file: file, line: line)
        button.tap()
    }

    /// Taps the button with this title or identifier.
    @discardableResult
    func tapButton(_ title: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let button = app.buttons[title].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: Self.timeout), "Button \(title) missing", file: file, line: line)
        button.tap()
        return button
    }

    /// Types into the text field or text view with this label, placeholder or identifier.
    func typeIn(_ identifier: String, text: String, file: StaticString = #filePath, line: UInt = #line) {
        let field = app.textFields[identifier].firstMatch.exists ? app.textFields[identifier].firstMatch
            : app.textViews[identifier].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: Self.timeout), "Field \(identifier) missing", file: file, line: line)
        field.tap()
        field.typeText(text)
    }

    /// Waits for an element of any type with this label or identifier.
    @discardableResult
    func waitFor(_ text: String, timeout: TimeInterval = UITestCase.timeout,
                 file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let element = app.descendants(matching: .any)[text].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(text) did not appear", file: file, line: line)
        return element
    }
}
