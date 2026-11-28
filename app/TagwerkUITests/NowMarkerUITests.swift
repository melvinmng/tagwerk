import XCTest

/// The "now" marker of the day view, with the clock pinned inside the demo seminar (10:00–12:30). The texts of the running entry
/// ("läuft, noch 120 Minuten") and of the time capsule ("Jetzt, 10:30") are checked without an app launch in `PlanningModelTests`
/// (`runningRemaining_…`) and `NowLineTextTests`; what is left is the scrolling, which needs the real grid.
final class NowMarkerUITests: UITestCase {
    override var extraLaunchArguments: [String] { ["-TagwerkUITestNow", "10:30"] }

    /// "Heute" aligns the grid to "now" again (PL4b): the page is dragged down to its top, which moves the capsule into the
    /// lower half of the screen; a trip to tomorrow and back puts it at a third of the visible height again.
    /// The day view is paged: the neighbouring days stay beside the window in the tree, each with its own copy of the capsule and of the
    /// day caption, so the checks only look at the copy that is inside the window (frame) or that can be hit.
    func testHeuteAlignsTheGridToNowAgain() {
        waitFor("Jetzt, 10:30")
        let half = app.windows.firstMatch.frame.height / 2
        // The page is dragged down to its top (drags of a fixed length instead of fast swipes, which keep scrolling by inertia while
        // the frame is read): the capsule is below the middle then, or already below the lower edge of the screen.
        for _ in 0..<4 { dragPage(towardsTop: true) }
        waitUntilScreenIsStable()
        eventually("The grid did not scroll away from the current time") { (self.capsuleOfShownPage()?.frame.midY ?? 0) > half }
        tapButton("Nächster Tag")
        waitForDayCaption("Morgen")
        tapButton("Heute")
        waitForDayCaption("Heute")
        _ = onScreen(.any, label: "Jetzt, 10:30")
        eventually("\"Heute\" did not align the grid to the current time (capsule at \(capsuleOfShownPage()?.frame.midY ?? -1), middle \(half))") {
            guard let capsule = self.capsuleOfShownPage() else { return false }
            return capsule.isHittable && capsule.frame.midY < half
        }
    }

    /// The copy of the capsule on the page that is shown: its centre lies inside the window; the previews of the neighbouring days lie
    /// beside it. `nil` while the shown page has none.
    private func capsuleOfShownPage() -> XCUIElement? {
        let window = app.windows.firstMatch.frame
        return app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Jetzt, 10:30")).allElementsBoundByIndex
            .first { $0.exists && window.minX <= $0.frame.midX && $0.frame.midX <= window.maxX }
    }

    /// Waits until the caption of the shown day ("Heute", "Morgen") can be hit; the captions of the neighbouring days are not hittable.
    private func waitForDayCaption(_ caption: String, file: StaticString = #filePath, line: UInt = #line) {
        let captions = app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH[c] %@", caption))
        eventually("The caption \(caption) of the day is not on screen", file: file, line: line) {
            captions.allElementsBoundByIndex.contains { $0.exists && $0.isHittable }
        }
    }
}
