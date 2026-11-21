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
        let start = app.buttons["Fokus starten"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: Self.timeout), "The menu has no entry \"Fokus starten\"")
        start.tap()
        // The search sheet closes and the focus timer opens after it.
        XCTAssertTrue(app.navigationBars["Fokus-Timer"].waitForExistence(timeout: Self.timeout), "The focus timer did not open")
        XCTAssertFalse(app.textFields["Suchen"].exists, "The search sheet is still open")
    }
}
