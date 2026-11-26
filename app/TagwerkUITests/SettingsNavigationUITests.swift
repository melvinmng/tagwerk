import XCTest

/// The way to a settings page through the list: the audits of the settings pages open them directly with
/// `-TagwerkUITestScreen` (see `AccessibilityAuditRecipesUITests.auditSettings`), so this test keeps the navigation covered.
final class SettingsNavigationUITests: UITestCase {
    func testSettingsPageOpensFromItsRow() {
        tab("Einstellungen")
        // "Einkaufsliste" is the page closest to the top of the list; the launch starts at the top.
        openSettingsRow("Einkaufsliste", fromTop: false)
        XCTAssertTrue(app.navigationBars["Einkaufsliste"].waitForExistence(timeout: Self.timeout), "Shopping settings did not open")
        // The back button leads to the list again.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Einstellungen"].waitForExistence(timeout: Self.timeout), "The settings list did not come back")
    }

    /// Types into the search field of the settings tab and returns the hit row that starts with `title`.
    private func searchSettings(for text: String, hit title: String) -> XCUIElement {
        tab("Einstellungen")
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: Self.timeout), "The settings have no search field")
        field.tap()
        field.typeText(text)
        return app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    func testSettingsSearch_opensNestedPage() {
        // "Stimme" is a keyword of "KI › Spracheingabe und Vorlesen", a page two levels down.
        let hit = searchSettings(for: "Stimme", hit: "Spracheingabe und Vorlesen")
        XCTAssertTrue(hit.waitForExistence(timeout: Self.timeout), "The page is not among the hits")
        hit.tap()
        XCTAssertTrue(app.navigationBars["Spracheingabe und Vorlesen"].waitForExistence(timeout: Self.timeout),
                      "The page did not open from the hit")
        // Back leads to the page "KI", the page above it.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["KI"].waitForExistence(timeout: Self.timeout), "The page above did not show")
    }

    func testSettingsSearch_rowWithoutPage_showsTheListAtTheRow() {
        // "Puffer" is a row of the main list: the hit opens the list and scrolls to the row.
        let hit = searchSettings(for: "Puffer", hit: "Puffer")
        XCTAssertTrue(hit.waitForExistence(timeout: Self.timeout), "The row is not among the hits")
        hit.tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Puffer")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout), "The list does not show the row")
        eventually("The row \"Puffer\" is not on the screen") { row.isHittable }
    }

    func testSettingsSearch_noHit_showsEmptyState() {
        _ = searchSettings(for: "xyzzy", hit: "xyzzy")
        let empty = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "xyzzy")).firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: Self.timeout), "No empty state for a search without hits")
    }
}
