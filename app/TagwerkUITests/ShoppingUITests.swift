import XCTest

final class ShoppingUITests: UITestCase {
    func testAddSortAndCheckOffItem() {
        openShoppingList()
        let field = app.textFields["Artikel hinzufügen"]
        field.tap()
        field.typeText("Milch\n")

        // The offline dictionary files the item under its category (the built-in category of milk is "Kühlregal").
        let row = app.descendants(matching: .any)["Milch, nicht erledigt"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout), "Milch was not added")
        let header = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Kühlregal")).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: Self.timeout), "Milch is not in the category Kühlregal")
        XCTAssertLessThan(header.frame.minY, row.frame.minY, "The category header must be above the item")

        // The check circle sits at the leading edge of the row.
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.5)).tap()
        waitUntilGone(row)
        let completed = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Erledigt")).firstMatch
        XCTAssertTrue(completed.waitForExistence(timeout: Self.timeout), "The section Erledigt is missing")
        completed.tap()
        XCTAssertTrue(app.descendants(matching: .any)["Milch, erledigt"].firstMatch.waitForExistence(timeout: Self.timeout),
                      "Milch is not in the completed section")
    }
}
