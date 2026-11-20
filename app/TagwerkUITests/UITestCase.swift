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
        // A failed test prints what the app showed, so a failure in a CI log can be understood without a rerun.
        addTeardownBlock { [weak self] in
            guard let self, let run = self.testRun, !run.hasSucceeded, let app = self.app else { return }
            print("UI TEST FAILED, accessibility tree:\n\(app.debugDescription)")
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

    /// Polls until `condition` holds; fails with `message` after the timeout. Only used where an element query cannot express the wait.
    func eventually(timeout: TimeInterval = UITestCase.timeout, _ message: String, file: StaticString = #filePath, line: UInt = #line,
                    _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertTrue(condition(), message, file: file, line: line)
    }

    /// The first element of this type with a label matching the predicate format that is on screen (waits for it).
    /// "Planen" and "Erfassen" keep the neighbouring days as page previews in the tree, and a sheet leaves the tab behind
    /// it in the tree, so a plain label query can find a copy that cannot be tapped.
    func onScreen(_ type: XCUIElement.ElementType = .button, label: String, matching: Bool = false,
                  timeout: TimeInterval = UITestCase.timeout, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let query = app.descendants(matching: type)
        let candidates = { query.matching(NSPredicate(format: matching ? "label MATCHES %@" : "label == %@", label)).allElementsBoundByIndex }
        var found: XCUIElement?
        eventually(timeout: timeout, "\(label) is not on screen", file: file, line: line) {
            found = candidates().first { $0.isHittable }
            return found != nil
        }
        return found ?? query.matching(identifier: label).firstMatch
    }

    /// Scrolls a list or form up until the element exists and is hittable.
    func scrollTo(_ element: XCUIElement, maxSwipes: Int = 8, file: StaticString = #filePath, line: UInt = #line) {
        var swipes = 0
        while !(element.exists && element.isHittable), swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.exists && element.isHittable, "\(element) is not reachable by scrolling", file: file, line: line)
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

    /// Replaces the text of a field: a tap at its right end puts the cursor behind the text, then the old text is deleted.
    func replaceText(of field: XCUIElement, with text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(field.waitForExistence(timeout: Self.timeout), "Field missing", file: file, line: line)
        let current = (field.value as? String) ?? ""
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text)
    }

    /// Waits until the element is gone.
    func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = UITestCase.timeout,
                       file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForNonExistence(timeout: timeout), "\(element) did not disappear", file: file, line: line)
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

// MARK: Screens shared by several tests

extension UITestCase {
    /// Aufgaben › Einkaufsliste.
    func openShoppingList(file: StaticString = #filePath, line: UInt = #line) {
        tab("Aufgaben", file: file, line: line)
        let entry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Einkaufsliste")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: Self.timeout), "Shopping list entry missing", file: file, line: line)
        entry.tap()
        XCTAssertTrue(app.textFields["Artikel hinzufügen"].waitForExistence(timeout: Self.timeout),
                      "Shopping list did not open", file: file, line: line)
    }

    /// Opens the search sheet with the magnifier of the current tab and types the text.
    func openSearch(typing text: String, file: StaticString = #filePath, line: UInt = #line) {
        app.buttons["Suchen"].firstMatch.tap()
        let field = app.textFields["Suchen"]
        XCTAssertTrue(field.waitForExistence(timeout: Self.timeout), "Search field missing", file: file, line: line)
        field.tap()
        field.typeText(text)
    }

    /// Aufgaben › Notizen.
    func openNotes(file: StaticString = #filePath, line: UInt = #line) {
        tab("Aufgaben", file: file, line: line)
        let entry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Notizen")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: Self.timeout), "Notes entry missing", file: file, line: line)
        entry.tap()
        XCTAssertTrue(app.navigationBars["Notizen"].waitForExistence(timeout: Self.timeout), "Notes did not open", file: file, line: line)
    }
}
