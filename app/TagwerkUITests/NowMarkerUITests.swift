import XCTest

/// The "now" marker and the running entry of the day view, with the clock pinned inside the demo seminar (10:00–12:30).
final class NowMarkerUITests: UITestCase {
    override var extraLaunchArguments: [String] { ["-TagwerkUITestNow", "10:30"] }

    func testRunningEntryShowsTheTimeLeftAndTheNowCapsule() throws {
        waitFor("Sprechstunde")
        // The time capsule of the marker: the label is "Jetzt, 10:30".
        waitFor("Jetzt, 10:30")
        // The seminar runs from 10:00 to 12:30: two hours left. Its label says so instead of the time range.
        let running = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "läuft, noch 120 Minuten")).firstMatch
        XCTAssertTrue(running.waitForExistence(timeout: Self.timeout), "The running seminar does not say how long it runs")
        // The audit covers the running entry as well (frame and time line in the grid).
        try AuditAllowlist.audit(app, screen: "Planen (Tag)", for: .all)
    }
}
