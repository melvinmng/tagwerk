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
}
