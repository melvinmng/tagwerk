import XCTest

final class PlanUITests: UITestCase {
    // A new time block starts at the next full hour of "now", and the hour grid scrolls to "now". A fixed morning time keeps the
    // test independent of the hour of the run; the late-evening rounding is covered by `BlockStartTests`.
    override var extraLaunchArguments: [String] { Self.morningClockArguments + (name.contains("TravelMenu") ? ["-TagwerkDemoTravel"] : []) }

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

    /// The travel block opens a menu with three actions (PL11b); "Fahrzeit ändern …" opens the page of the event as a sheet.
    func testTravelMenuOffersThreeActions() {
        let travel = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Fahrzeit ")).firstMatch
        XCTAssertTrue(travel.waitForExistence(timeout: Self.timeout), "No travel block on screen")
        travel.tap()
        for action in ["Route in Karten", "Fahrzeit ändern …", "Keine Fahrzeit für diesen Termin"] {
            XCTAssertTrue(app.buttons[action].firstMatch.waitForExistence(timeout: Self.timeout), "\(action) is not in the menu")
        }
        app.buttons["Fahrzeit ändern …"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Fahrzeit"].waitForExistence(timeout: Self.timeout), "The page \"Fahrzeit\" does not open")
        app.buttons["Abbrechen"].firstMatch.tap()
        waitUntilGone(app.navigationBars["Fahrzeit"])
    }

    /// The next time block of today (the clock stands at 09:30, the new block starts at 10:00) carries "▶ Fokus"; a tap starts
    /// the timer at once and does not open the block's sheet (FO4b).
    func testFocusButtonOnTheRunningBlockStartsFocus() {
        waitFor("Sprechstunde")
        tab("Aufgaben")
        let task = app.descendants(matching: .any)[AccessibilityID.Tasks.row("Literatur sichten")]
        XCTAssertTrue(task.waitForExistence(timeout: Self.timeout))
        task.tap()
        let addBlock = app.buttons["Zeitblock hinzufügen"].firstMatch
        scrollTo(addBlock)
        addBlock.tap()
        tapButton("Sichern")
        tab("Planen")
        let block = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Literatur sichten, ")).firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: Self.timeout), "The time block is not in the day")
        let button = app.buttons[AccessibilityID.Focus.planButton].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: Self.timeout), "The block carries no focus button")
        XCTAssertGreaterThanOrEqual(button.frame.width, 44, "The focus button is narrower than 44 pt")
        XCTAssertGreaterThanOrEqual(button.frame.height, 28, "The focus button is lower than 28 pt")
        button.tap()
        // The timer runs at once, with the sheet of the timer and not the sheet of the block.
        XCTAssertTrue(app.buttons[AccessibilityID.Focus.pause].waitForExistence(timeout: Self.timeout), "The timer did not start")
        XCTAssertFalse(app.buttons["Zeitblock löschen"].exists, "The sheet of the block opened as well")
    }
}
