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

    /// EK1b: the tidying entries of the menu "Mehr" sit in the third group; without completed items "Erledigte entfernen" is greyed out.
    func testRemoveCompletedDisabledWithoutCompletedItems() {
        openShoppingList()
        app.buttons["Mehr"].firstMatch.tap()
        let removeCompleted = menuEntry("Erledigte entfernen")
        XCTAssertTrue(removeCompleted.waitForExistence(timeout: Self.timeout), "\"Erledigte entfernen\" is missing in the menu")
        XCTAssertFalse(removeCompleted.isEnabled, "\"Erledigte entfernen\" must be disabled without completed items")
        XCTAssertEqual(removeCompleted.label, "Erledigte entfernen", "Without completed items the entry carries no number")
        // The list is empty, so "Liste leeren" is greyed out too.
        XCTAssertFalse(menuEntry("Liste leeren").isEnabled, "\"Liste leeren\" must be disabled on an empty list")
    }

    /// EK1b, EK2a: the entry names the number of completed items; the question uses the same word and the button "Entfernen".
    func testRemoveCompleted_namesCountAndConfirms() {
        openShoppingList()
        let field = app.textFields["Artikel hinzufügen"]
        field.tap()
        field.typeText("Milch\n")
        let row = app.descendants(matching: .any)["Milch, nicht erledigt"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout), "Milch was not added")
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.5)).tap()
        waitUntilGone(row)

        app.buttons["Mehr"].firstMatch.tap()
        let removeCompleted = menuEntry("Erledigte entfernen")
        XCTAssertTrue(removeCompleted.waitForExistence(timeout: Self.timeout), "\"Erledigte entfernen\" is missing in the menu")
        eventually("The entry does not name the one completed item") { removeCompleted.label == "Erledigte entfernen (1)" }
        XCTAssertTrue(removeCompleted.isEnabled, "\"Erledigte entfernen\" must be enabled with a completed item")
        removeCompleted.tap()

        waitFor("1 erledigte Artikel entfernen?")
        waitFor("Sie verschwinden auch aus Apple Erinnerungen.")
        tapButton("Entfernen")
        let completedSection = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Erledigt")).firstMatch
        waitUntilGone(completedSection)
    }

    /// An entry of the menu "Mehr". The entries carry their number in the label ("Erledigte entfernen (1)"), and a menu item does not
    /// reliably expose the accessibility identifier of its button, so the query uses the label prefix, like the other menu tests.
    private func menuEntry(_ prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }
}
