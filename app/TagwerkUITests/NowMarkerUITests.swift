import XCTest

/// The "now" marker and the running entry of the day view, with the clock pinned inside the demo seminar (10:00–12:30).
final class NowMarkerUITests: UITestCase {
    override var extraLaunchArguments: [String] { ["-TagwerkUITestNow", "10:30"] }

    func testRunningEntryShowsTheTimeLeftAndTheNowCapsule() {
        waitFor("Sprechstunde")
        // The time capsule of the marker: the label is "Jetzt, 10:30".
        waitFor("Jetzt, 10:30")
        // The seminar runs from 10:00 to 12:30: two hours left. Its label says so instead of the time range.
        let running = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "läuft, noch 120 Minuten")).firstMatch
        XCTAssertTrue(running.waitForExistence(timeout: Self.timeout), "The running seminar does not say how long it runs")
    }

    /// "Heute" aligns the grid to "now" again (PL4b): the grid is scrolled away from the current time, and a trip to
    /// tomorrow and back puts the capsule at the aligned height again.
    func testHeuteAlignsTheGridToNowAgain() {
        let capsule = waitFor("Jetzt, 10:30")
        XCTAssertTrue(capsule.isHittable, "The grid does not start at the current time")
        // Let the alignment of the opening settle, then remember the height it gives the capsule.
        var alignedY = capsule.frame.midY
        eventually("The alignment of the opening did not settle") {
            let y = capsule.frame.midY
            defer { alignedY = y }
            return abs(y - alignedY) < 1
        }
        // The page is dragged down to its top: the capsule moves down by the opening offset.
        for _ in 0..<3 { app.swipeDown(velocity: .fast) }
        eventually("The grid did not scroll away from the current time") { abs(capsule.frame.midY - alignedY) > 60 }
        tapButton("Nächster Tag")
        XCTAssertTrue(dayCaption("Morgen").waitForExistence(timeout: Self.timeout))
        tapButton("Heute")
        XCTAssertTrue(dayCaption("Heute").waitForExistence(timeout: Self.timeout))
        eventually("\"Heute\" did not align the grid to the current time") {
            capsule.exists && abs(capsule.frame.midY - alignedY) < 30
        }
    }

    private func dayCaption(_ caption: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH[c] %@", caption)).firstMatch
    }
}

