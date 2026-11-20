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
}
