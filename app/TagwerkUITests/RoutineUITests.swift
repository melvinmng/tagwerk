import XCTest

final class RoutineUITests: UITestCase {
    // The deep links `tagwerk://routine/start` and `tagwerk://routine/evening` are covered by the AppRoute unit tests;
    // the system confirmation of a custom URL scheme makes them unreliable in a UI test, so the sheets open from the
    // routine cards of "Erfassen".
    func testMorningAndEveningSheets() {
        tab("Erfassen")
        onScreen(label: "Tagesstart.*", matching: true).tap()
        XCTAssertTrue(app.navigationBars["Tagesstart"].waitForExistence(timeout: Self.timeout), "The morning sheet did not open")
        let brainDump = app.textViews["Brain Dump"]
        XCTAssertTrue(brainDump.waitForExistence(timeout: Self.timeout))
        brainDump.tap()
        brainDump.typeText("UI-Test")
        tapButton("Abschließen")
        waitUntilGone(app.navigationBars["Tagesstart"])

        onScreen(label: "Tagesabschluss.*", matching: true).tap()
        XCTAssertTrue(app.navigationBars["Tagesabschluss"].waitForExistence(timeout: Self.timeout), "The evening sheet did not open")
        waitFor("Bible Study starten")
    }

    /// RO1b: dream log first, then gratitude, then the brain dump, the focus row last.
    func testMorningSheetOrder() {
        tab("Erfassen")
        onScreen(label: "Tagesstart.*", matching: true).tap()
        XCTAssertTrue(app.navigationBars["Tagesstart"].waitForExistence(timeout: Self.timeout), "The morning sheet did not open")
        let dream = app.staticTexts["Dream Log"].firstMatch
        let gratitude = app.staticTexts["Dankbar für"].firstMatch
        let brainDump = app.staticTexts["Brain Dump"].firstMatch
        XCTAssertTrue(dream.waitForExistence(timeout: Self.timeout), "Dream Log heading missing")
        XCTAssertTrue(gratitude.exists && brainDump.exists, "Headings of the morning sheet missing")
        XCTAssertLessThan(dream.frame.minY, gratitude.frame.minY, "The dream log comes first")
        XCTAssertLessThan(gratitude.frame.minY, brainDump.frame.minY, "The gratitude comes before the brain dump")
    }

    /// RO3b: the last row closes the sheet and shows "Planen" without marking the start as done.
    func testFocusHintOpensPlanWithoutCompleting() {
        tab("Erfassen")
        onScreen(label: "Tagesstart.*", matching: true).tap()
        XCTAssertTrue(app.navigationBars["Tagesstart"].waitForExistence(timeout: Self.timeout), "The morning sheet did not open")
        let row = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "Fokus für heute.*")).firstMatch
        scrollTo(row)
        row.tap()
        waitUntilGone(app.navigationBars["Tagesstart"])
        XCTAssertTrue(app.tabBars.buttons["Planen"].isSelected, "\"Planen\" should be shown")
        tab("Erfassen")
        _ = onScreen(label: "Tagesstart.*Starten", matching: true)
    }

    /// RO5b: the card "Willst du etwas ändern?" appears below the brain dump once it holds text, and not before.
    func testChangeCardAppearsWithText() {
        tab("Erfassen")
        onScreen(label: "Tagesstart.*", matching: true).tap()
        XCTAssertTrue(app.navigationBars["Tagesstart"].waitForExistence(timeout: Self.timeout), "The morning sheet did not open")
        let brainDump = app.textViews["Brain Dump"]
        scrollTo(brainDump)
        XCTAssertFalse(app.staticTexts["Willst du etwas ändern?"].exists, "The card shows before there is any text")
        brainDump.tap()
        brainDump.typeText("Kopf voll wegen Umzug")
        waitFor("Willst du etwas ändern?")
        waitFor("Als Aufgabe anlegen")
    }
}
