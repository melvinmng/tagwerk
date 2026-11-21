import XCTest

final class RoutineUITests: UITestCase {
    // The deep links `tagwerk://routine/start` and `tagwerk://routine/evening` are covered by the AppRoute unit tests;
    // the system confirmation of a custom URL scheme makes them unreliable in a UI test, so the sheets open from the
    // routine cards of "Erfassen".
    func testMorningAndEveningSheets() {
        tab("Erfassen")
        onScreen(label: "Tagesstart.*", matching: true).tap()
        XCTAssertTrue(app.navigationBars["Tagesstart"].waitForExistence(timeout: Self.timeout), "The morning sheet did not open")
        let brainDump = app.textViews.firstMatch
        XCTAssertTrue(brainDump.waitForExistence(timeout: Self.timeout))
        brainDump.tap()
        brainDump.typeText("UI-Test")
        tapButton("Abschließen")
        waitUntilGone(app.navigationBars["Tagesstart"])

        onScreen(label: "Tagesabschluss.*", matching: true).tap()
        XCTAssertTrue(app.navigationBars["Tagesabschluss"].waitForExistence(timeout: Self.timeout), "The evening sheet did not open")
        waitFor("Bible Study starten")
    }
}
