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
}
