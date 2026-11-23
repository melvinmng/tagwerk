import XCTest

/// The habits of "Erfassen" (GW3): a habit that its source fulfilled keeps its check when it is tapped and explains itself.
final class HabitUITests: UITestCase {
    /// The button with a label that starts with `prefix` and can be hit now; the page of "Erfassen" scrolls up until it is there.
    /// "Erfassen" keeps the neighbouring days as page previews in the tree, so only a hittable match counts.
    private func hittableButton(_ prefix: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let query = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
        var steps = 0
        while steps < 8 {
            if let found = query.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) { return found }
            app.swipeUp()
            steps += 1
        }
        XCTFail("\(prefix) is not reachable by scrolling", file: file, line: line)
        return query.firstMatch
    }

    private func stateValue(of row: XCUIElement) -> String { (row.value as? String) ?? "" }

    /// A habit fulfilled by the wrap-up of the day: it is created in the sheet, the wrap-up is closed, then the check is tapped.
    func testTapOnAutomaticHabitShowsHintAndKeepsCheck() {
        tab("Erfassen")
        hittableButton("Gewohnheit anlegen").tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: Self.timeout), "The habit sheet did not open")
        name.tap()
        // The return key closes the keyboard, so it does not cover the rows below.
        name.typeText("Tag abschließen\n")
        let source = app.buttons["Tagesabschluss erledigt"]
        scrollTo(source)
        // The swipe has to come to rest, and the keyboard of the name field has to be gone, before the row is hit.
        waitUntilScreenIsStable()
        source.tap()
        eventually("The source was not selected") { source.isSelected }
        tapButton("Fertig")
        waitUntilGone(app.navigationBars["Neue Gewohnheit"])

        // Before the wrap-up the source is open and ticks the habit by itself.
        let open = hittableButton("Tag abschließen")
        XCTAssertTrue(stateValue(of: open).hasPrefix("offen, hakt sich selbst ab"), "The open automatic row names its state: \(stateValue(of: open))")

        hittableButton("Tagesabschluss").tap()
        XCTAssertTrue(app.navigationBars["Tagesabschluss"].waitForExistence(timeout: Self.timeout), "The evening sheet did not open")
        tapButton("Abschließen")
        waitUntilGone(app.navigationBars["Tagesabschluss"])

        eventually("The row is fulfilled automatically") { self.stateValue(of: self.hittableButton("Tag abschließen")).hasPrefix("automatisch erfüllt") }
        // The hint appears under the list: scroll the row up first, so that there is room below it on the screen.
        app.swipeUp()
        waitUntilScreenIsStable()
        // The check mark is the button of the row, at its left edge; the middle of the row opens nothing.
        hittableButton("Tag abschließen").coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        let hint = app.staticTexts["Automatisch erfüllt durch den Tagesabschluss. Lässt sich nicht abwählen."]
        XCTAssertTrue(hint.waitForExistence(timeout: Self.timeout), "The hint did not show")
        XCTAssertTrue(stateValue(of: hittableButton("Tag abschließen")).hasPrefix("automatisch erfüllt"), "The check must stay")
    }
}
