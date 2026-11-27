import XCTest

/// Einstellungen › KI › Spracheingabe und Vorlesen › Stimme Deutsch (#309). The UI test mode gives the page no voices, so the page
/// shows "Automatisch" only; the lists of real voices are covered by the unit tests and on the device.
final class VoiceChoiceUITests: UITestCase {
    override var extraLaunchArguments: [String] { ["-TagwerkDemoAI", "-TagwerkUITestScreen", "settings.ai.voice"] }

    func testVoicePageOpensFromItsRowAndKeepsAutomaticChosen() {
        XCTAssertTrue(app.navigationBars["Spracheingabe und Vorlesen"].waitForExistence(timeout: Self.timeout), "Voice settings did not open")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Stimme Deutsch")).firstMatch
        scrollTo(row)
        row.tap()
        XCTAssertTrue(app.navigationBars["Stimme Deutsch"].waitForExistence(timeout: Self.timeout), "The voice page did not open")
        let automatic = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Automatisch")).firstMatch
        XCTAssertTrue(automatic.waitForExistence(timeout: Self.timeout), "The row Automatisch is missing")
        XCTAssertTrue(app.buttons["Probe Automatisch"].exists, "The sample of Automatisch is missing")
        XCTAssertTrue(app.buttons["Weitere Stimmen laden"].exists, "The link to the iOS settings is missing")
        automatic.tap()
        // The back button leads to the settings page, which names the choice.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Spracheingabe und Vorlesen"].waitForExistence(timeout: Self.timeout), "The settings page did not come back")
        // The row "Stimme Deutsch" names the choice: its label (or value) carries "Automatisch".
        let chosenRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Stimme Deutsch")).firstMatch
        scrollTo(chosenRow)
        let shown = [chosenRow.label, chosenRow.value as? String ?? ""].joined(separator: " ")
        XCTAssertTrue(shown.contains("Automatisch"), "The settings page does not show Automatisch as the chosen voice: \(shown)")
    }
}
