import XCTest

/// Automatic accessibility audit (`performAccessibilityAudit`) of the core screens in the default text size.
/// One launch covers all screens, to keep the run short. Findings must be fixed or sit on `AuditAllowlist` with a reason.
final class AccessibilityAuditUITests: UITestCase {
    // A fixed time of day: the hour grid of "Planen" scrolls to the current time, so without it the audited part of the
    // grid (and with it the findings) would depend on the hour of the run.
    override var extraLaunchArguments: [String] { AuditAllowlist.fixedClockArguments }

    /// Runs the audit on the screen that is open now; findings that are not on the allowlist fail the test.
    private func audit(_ screen: String) throws {
        AuditAllowlist.currentScreen = screen
        try app.performAccessibilityAudit(for: .all) { issue in MainActor.assumeIsolated { AuditAllowlist.isAccepted(issue) } }
    }

    func testAuditDefaultSize() throws {
        waitFor("Sprechstunde")
        try audit("Planen (Tag)")

        tab("Aufgaben")
        waitFor("Pflanzen gießen")
        try audit("Aufgaben")

        tab("Erfassen")
        onScreen(label: "Tagesabschluss.*", matching: true).tap()
        XCTAssertTrue(app.navigationBars["Tagesabschluss"].waitForExistence(timeout: Self.timeout))
        try audit("Tagesabschluss")
        tapButton("Fertig")
        waitUntilGone(app.navigationBars["Tagesabschluss"])

        openShoppingList()
        for item in ["Milch", "Brot"] {
            app.textFields["Artikel hinzufügen"].tap()
            app.textFields["Artikel hinzufügen"].typeText(item + "\n")
            waitFor(item)
        }
        try audit("Einkaufsliste")
        app.navigationBars.buttons.firstMatch.tap()

        openNotes()
        let allNotes = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alle Notizen")).firstMatch
        XCTAssertTrue(allNotes.waitForExistence(timeout: Self.timeout))
        allNotes.tap()
        XCTAssertTrue(app.navigationBars["Alle Notizen"].waitForExistence(timeout: Self.timeout))
        try audit("Notizenliste")


        tab("Planen")
        // The return key closes the keyboard, so its suggestion bar is not part of the audit.
        openSearch(typing: "Pretest\n")
        waitFor("Pretest vorbereiten", timeout: 20)
        try audit("Suche")
    }
}
