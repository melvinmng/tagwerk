import XCTest

final class SearchUITests: UITestCase {
    func testSearchFindsTaskAndOpensIt() {
        // The magnifier of "Planen"; "Karteikarten" is a task of the demo data.
        openSearch(typing: "Karteikarten")
        let hit = app.descendants(matching: .any)[AccessibilityID.Tasks.row("Karteikarten")].firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 20), "The task is not among the hits")
        hit.tap()
        // The editor sheet opens with the title of the task.
        let title = app.textFields[AccessibilityID.Tasks.editorTitle].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: Self.timeout), "The task sheet did not open")
        XCTAssertEqual(title.value as? String, "Karteikarten")
    }

    func testPlanFromSearchHit() {
        openSearch(typing: "Karteikarten")
        let hit = app.descendants(matching: .any)[AccessibilityID.Tasks.row("Karteikarten")].firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 20), "The task is not among the hits")
        hit.press(forDuration: 1.0)
        let tomorrow = app.buttons["Morgen"].firstMatch
        XCTAssertTrue(tomorrow.waitForExistence(timeout: Self.timeout), "The menu has no entry \"Morgen\"")
        tomorrow.tap()
        // The sheet stays open; the menu now offers to show the planned task in the plan.
        XCTAssertTrue(hit.waitForExistence(timeout: Self.timeout), "The search sheet closed after planning")
        hit.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Im Plan zeigen"].firstMatch.waitForExistence(timeout: Self.timeout),
                      "The menu does not offer \"Im Plan zeigen\" after planning")
    }

    func testStartFocusFromSearchHit() {
        openSearch(typing: "Karteikarten")
        let hit = app.descendants(matching: .any)[AccessibilityID.Tasks.row("Karteikarten")].firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 20), "The task is not among the hits")
        hit.press(forDuration: 1.0)
        // The menu entry names the planned minutes (FO3b); the start sheet follows it.
        onScreen(label: "Fokus starten · 25 min").tap()
        // The search sheet closes, the start sheet opens after it and starts the focus timer.
        onScreen(label: "Starten").tap()
        XCTAssertTrue(app.navigationBars["Fokus-Timer"].waitForExistence(timeout: Self.timeout), "The focus timer did not open")
        XCTAssertFalse(app.textFields["Suchen"].exists, "The search sheet is still open")
    }

    func testSearchOpensSettingsPage() {
        // "Pomodoro" is the setting "Pomodoro (Runden mit Pausen)" on the page "Fokus-Timer".
        openSearch(typing: "Pomodoro")
        let hit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pomodoro (Runden")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: Self.timeout), "The setting is not among the hits")
        hit.tap()
        // The search sheet closes and the tab "Einstellungen" shows the page.
        XCTAssertTrue(app.navigationBars["Fokus-Timer"].waitForExistence(timeout: Self.timeout), "The settings page did not open")
        XCTAssertFalse(app.textFields["Suchen"].exists, "The search sheet is still open")
    }
}
