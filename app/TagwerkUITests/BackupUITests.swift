import XCTest

/// The pages of the data backup (DS1, DS3, DS4): the status card, the explanation page, the password page with its warning and
/// the list of safety copies. Each page runs through the accessibility audit; findings must be fixed or sit on `AuditAllowlist`.
final class BackupUITests: UITestCase {
    override var extraLaunchArguments: [String] { AuditAllowlist.fixedClockArguments }

    private func audit(_ screen: String) throws {
        try AuditAllowlist.audit(app, screen: screen, for: .all)
    }

    /// Only rows of the list: the tab bar has buttons with the same words.
    private func openSettingsRow(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let row = app.cells.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        for _ in 0..<4 { app.swipeDown() }
        var steps = 0
        while !(row.exists && row.isHittable), steps < 20 {
            let list = app.collectionViews.firstMatch
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
            steps += 1
        }
        XCTAssertTrue(row.exists && row.isHittable, "Settings row \(title) is not reachable by scrolling", file: file, line: line)
        row.tap()
    }

    private func openRow(_ title: String, in page: String, file: StaticString = #filePath, line: UInt = #line) {
        let row = app.cells.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        var steps = 0
        while !(row.exists && row.isHittable), steps < 10 {
            app.swipeUp()
            steps += 1
        }
        XCTAssertTrue(row.exists && row.isHittable, "Row \(title) of \(page) is not reachable", file: file, line: line)
        row.tap()
    }

    func testBackupPagesAudit() throws {
        tab("Einstellungen")
        openSettingsRow("Datensicherung")
        XCTAssertTrue(app.navigationBars["Datensicherung"].waitForExistence(timeout: Self.timeout), "The backup page did not open")
        // Without a backup folder the automatic backup is off: the card says so and the page names the actions.
        XCTAssertTrue(app.descendants(matching: .any)["backup.statusCard"].waitForExistence(timeout: Self.timeout), "The status card is missing")
        XCTAssertTrue(app.buttons["Jetzt sichern"].exists)
        try audit("Einstellungen › Datensicherung")

        openRow("Was wird gesichert?", in: "Datensicherung")
        XCTAssertTrue(app.navigationBars["Was wird gesichert?"].waitForExistence(timeout: Self.timeout))
        try audit("Einstellungen › Datensicherung › Was wird gesichert?")
        app.navigationBars.buttons.firstMatch.tap()

        openRow("Mit Passwort verschlüsseln", in: "Datensicherung")
        XCTAssertTrue(app.navigationBars["Verschlüsselung"].waitForExistence(timeout: Self.timeout))
        // The warning stands on the page before the switch can be turned on.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Ohne Passwort lässt sich eine verschlüsselte Sicherung nicht öffnen")).firstMatch
            .waitForExistence(timeout: Self.timeout), "The warning is missing")
        try audit("Einstellungen › Datensicherung › Verschlüsselung")
        app.navigationBars.buttons.firstMatch.tap()

        openRow("Sicherheitskopien", in: "Datensicherung")
        XCTAssertTrue(app.navigationBars["Sicherheitskopien"].waitForExistence(timeout: Self.timeout))
        try audit("Einstellungen › Datensicherung › Sicherheitskopien")
    }
}
