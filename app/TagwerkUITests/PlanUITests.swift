import XCTest

final class PlanUITests: UITestCase {
    // A new time block starts at the next full hour of "now", and the hour grid scrolls to "now". A fixed morning time keeps the
    // test independent of the hour of the run; the late-evening rounding is covered by `BlockStartTests`.
    override var extraLaunchArguments: [String] { Self.morningClockArguments }

    /// The day title element carries the relative day ("Heute", "Morgen") as its value and the date as its label.
    private func dayTitle(startingWith caption: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH[c] %@", caption)).firstMatch
    }

    func testDayViewBlockAndPaging() {
        // The day view shows the demo appointment.
        waitFor("Sprechstunde")

        // A time block through the task editor, "Geplant" › "Zeitblock hinzufügen".
        tab("Aufgaben")
        let task = app.descendants(matching: .any)[AccessibilityID.Tasks.row("Literatur sichten")]
        XCTAssertTrue(task.waitForExistence(timeout: Self.timeout))
        task.tap()
        // The editor is a long form; "Geplant" is further down.
        let addBlock = app.buttons["Zeitblock hinzufügen"].firstMatch
        scrollTo(addBlock)
        addBlock.tap()
        tapButton("Sichern")
        tab("Planen")
        let block = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Literatur sichten, ")).firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: Self.timeout), "The time block is not in the day")

        // Paging: the arrow goes to tomorrow, a swipe to the right returns to today.
        let today = dayTitle(startingWith: "Heute")
        XCTAssertTrue(today.waitForExistence(timeout: Self.timeout))
        let todayTitle = today.label
        tapButton("Nächster Tag")
        let tomorrow = dayTitle(startingWith: "Morgen")
        XCTAssertTrue(tomorrow.waitForExistence(timeout: Self.timeout), "The title did not change to tomorrow")
        XCTAssertNotEqual(tomorrow.label, todayTitle)
        app.windows.firstMatch.swipeRight()
        XCTAssertTrue(dayTitle(startingWith: "Heute").waitForExistence(timeout: Self.timeout), "The swipe did not return to today")
    }

    /// The month pages by dragging sideways over the grid (PL7b): the title moves on to the next month.
    func testMonthPagesBySwiping() {
        waitFor("Sprechstunde")
        tapButton("Monat")
        let current = dayTitle(startingWith: "Dieser Monat")
        XCTAssertTrue(current.waitForExistence(timeout: Self.timeout), "The month view does not show the current month")
        let month = current.label
        app.swipeLeft()
        // A month that is not the current one carries only the year as its caption.
        let other = app.staticTexts.matching(NSPredicate(format: "value MATCHES %@", "\\d{4}")).firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: Self.timeout), "The swipe did not page to the next month")
        XCTAssertNotEqual(other.label, month)
        // Swiping back returns to the current month.
        app.swipeRight()
        XCTAssertTrue(dayTitle(startingWith: "Dieser Monat").waitForExistence(timeout: Self.timeout), "The swipe did not return")
        // A tap on a day still works inside the container, and scrolling up and down starts no page change.
        let cell = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", " 15. ")).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: Self.timeout), "The 15th is not in the month grid")
        cell.tap()
        app.swipeUp()
        app.swipeDown()
        XCTAssertTrue(dayTitle(startingWith: "Dieser Monat").exists, "A vertical drag changed the month")
    }
}

