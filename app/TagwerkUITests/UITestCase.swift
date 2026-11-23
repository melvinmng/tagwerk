import XCTest

/// Base class of all UI tests: starts the app in the UI test mode (in-memory store, demo data, offline,
/// German) and waits until the demo data exists. Tests wait only with `waitForExistence`, never with `sleep`;
/// `waitUntilScreenIsStable()` waits for a condition too (two identical snapshots of the screen in a row).
/// The simulator needs calendar and reminder access before the run (`app/test-all.sh` grants it with `simctl privacy`).
@MainActor
class UITestCase: XCTestCase {
    private(set) var app: XCUIApplication!

    /// Default wait for an element that the app shows after some work.
    static let timeout: TimeInterval = 10

    /// Pins the time of day of the app to the morning (the date stays today's; see `UITestMode.now`). Tests that depend on the
    /// time (the hour grid scrolls to "now", a new time block starts at the next full hour) use it, so they give the same result
    /// at every hour of the day, also shortly before midnight, when the next full hour is already the next day.
    static let morningClockArguments = ["-TagwerkUITestNow", "09:30"]

    /// The morning clock with the weekday pinned to Sunday, the day on which the wrap-up offers "Wochenplanung starten": the accessibility
    /// audits use it, so their screens contain the same elements on every day of the run (the audit of "Tagesabschluss" used to find
    /// other texts on a Sunday than on the other days).
    static let morningSundayClockArguments = morningClockArguments + sundayArguments

    /// Pins the time of day to the evening, after the end of work (18:00): "heute ist vorbei", so "Planen" and "Tagesabschluss" show the
    /// leftover row ("Unerledigtes verschieben"). With `-TagwerkUITest` today is a working day on every weekday (see
    /// `DemoData.uiTestWorkdayOverrides`), so only the clock decides, not the weekday.
    /// The weekday is pinned to Sunday as in `morningSundayClockArguments`; only the accessibility audits use this clock.
    static let eveningClockArguments = ["-TagwerkUITestNow", "19:30"] + sundayArguments

    /// Pins the weekday of the app to Sunday (1): the day is the latest Sunday up to and including today (see `UITestMode.pinnedNow`).
    static let sundayArguments = ["-TagwerkUITestWeekday", "1"]

    /// Extra launch arguments of a test class (e.g. a large text size).
    var extraLaunchArguments: [String] { [] }

    /// Whether `setUp` starts the app. A test that starts the app itself with other arguments for every screen it visits (see
    /// `launchApp(extraArguments:)`) turns this off, so the launch of `setUp` is not wasted.
    var launchesInSetUp: Bool { true }

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
        if launchesInSetUp { launchApp() }
    }

    /// Starts a fresh app process and waits for the marker the demo data sets when it is done. `extraArguments` come after
    /// `extraLaunchArguments`, e.g. `-TagwerkUITestScreen settings.siri` to open a screen directly.
    func launchApp(extraArguments: [String] = []) {
        let app = XCUIApplication()
        app.launchArguments = ["-TagwerkUITest", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"] + extraLaunchArguments + extraArguments
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

    /// Selects a segment of a segmented control in a sheet whose text field has focus on its own (the meal sheet). While the keyboard
    /// is open, a tap on a segment is swallowed by the window-wide tap that closes the keyboard (`KeyboardDismissal.swift`) and the
    /// segment stays unselected, so the keyboard is closed first with a tap on the sheet title, which is not an input.
    func selectSegment(_ title: String, inSheetTitled sheetTitle: String, file: StaticString = #filePath, line: UInt = #line) {
        let segment = app.buttons[title].firstMatch
        XCTAssertTrue(segment.waitForExistence(timeout: Self.timeout), "Segment \(title) missing", file: file, line: line)
        if app.keyboards.firstMatch.exists {
            app.navigationBars[sheetTitle].staticTexts[sheetTitle].firstMatch.tap()
            waitUntilGone(app.keyboards.firstMatch, file: file, line: line)
            waitUntilScreenIsStable(file: file, line: line)
        }
        segment.tap()
        eventually("Segment \(title) did not get selected", file: file, line: line) { segment.isSelected }
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

    /// Waits until the screen does not change any more: two snapshots of the accessibility tree in a row, 0.3 s apart, give the same
    /// signature (type, label, value and rounded frame of every element; activity indicators and scroll bars are left out). An element
    /// that exists is not an element that has finished loading, so a screen is only audited after this. It is a wait for a condition,
    /// not a `sleep`: a screen that never settles fails with the elements that kept changing, instead of an accidental audit finding.
    func waitUntilScreenIsStable(timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) {
        do {
            if let changing = try Self.unstableElements(of: app, timeout: timeout) {
                XCTFail("The screen did not settle within \(Int(timeout)) s; elements that changed last: \(changing)", file: file, line: line)
            }
        } catch {
            XCTFail("Could not take a snapshot of the screen: \(error)", file: file, line: line)
        }
    }

    /// `nil` when the screen is stable; otherwise the description of the elements that differed between the last two snapshots.
    static func unstableElements(of app: XCUIApplication, timeout: TimeInterval = 8, interval: TimeInterval = 0.3) throws -> String? {
        var previous = try screenSignature(of: app)
        var lastDifference = ""
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(interval))
            let current = try screenSignature(of: app)
            if current == previous { return nil }
            let before = Set(previous), after = Set(current)
            lastDifference = (after.subtracting(before).sorted().prefix(4) + before.subtracting(after).sorted().prefix(4).map { "was: " + $0 })
                .joined(separator: " | ")
            previous = current
        }
        return lastDifference
    }

    /// One line per element of the tree of the app; see `waitUntilScreenIsStable`.
    private static func screenSignature(of app: XCUIApplication) throws -> [String] {
        var lines: [String] = []
        func walk(_ node: any XCUIElementSnapshot, depth: Int) {
            if node.elementType != .activityIndicator && node.elementType != .scrollBar {
                let frame = node.frame
                lines.append("\(depth) \(node.elementType.rawValue) \(node.label) = \(node.value.map { String(describing: $0) } ?? "") "
                    + "@\(Int(frame.minX.rounded())),\(Int(frame.minY.rounded())),\(Int(frame.width.rounded())),\(Int(frame.height.rounded()))")
            }
            for child in node.children { walk(child, depth: depth + 1) }
        }
        walk(try app.snapshot(), depth: 0)
        return lines
    }

    /// Waits until the element is gone.
    func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = UITestCase.timeout,
                       file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForNonExistence(timeout: timeout), "\(element) did not disappear", file: file, line: line)
    }

    /// Waits until the element is gone and stays gone for `seconds`. A notice that is replaced by the next one (the shopping list
    /// counts "1 hinzugefügt", "2 hinzugefügt") can be missing for a moment before the new one shows; a plain wait for
    /// non-existence ends in that gap, and the audit then runs while the notice is on screen.
    func waitUntilStaysGone(_ element: XCUIElement, for seconds: TimeInterval = 1.5, timeout: TimeInterval = UITestCase.timeout + 5,
                            file: StaticString = #filePath, line: UInt = #line) {
        var goneSince: Date?
        eventually(timeout: timeout, "\(element) did not stay gone", file: file, line: line) {
            if element.exists {
                goneSince = nil
                return false
            }
            let since = goneSince ?? Date()
            goneSince = since
            return Date().timeIntervalSince(since) >= seconds
        }
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

    /// Scrolls the settings list in small steps (a lazy list only creates the rows near the screen, and a full-page swipe can jump
    /// over a row) to the row that starts with this title and opens it. The scroll position stays when a page is left, so
    /// the search goes to the top first; a fresh launch starts at the top already (`fromTop: false`).
    func openSettingsRow(_ title: String, fromTop: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        // Only rows of the list: the tab bar has a button "Erfassen" as well.
        let row = app.cells.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        if fromTop { for _ in 0..<4 { app.swipeDown() } }
        var steps = 0
        while !(row.exists && row.isHittable), steps < 20 {
            let list = app.collectionViews.firstMatch
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
            steps += 1
        }
        XCTAssertTrue(row.exists && row.isHittable, "Settings row \(title) is not reachable by scrolling", file: file, line: line)
        row.tap()
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
