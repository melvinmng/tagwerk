import XCTest

/// Audit in the largest text size (AX5) and in dark mode, on the four core screens only (the audit is slow).
/// Checked: clipped text and contrast. The Dynamic Type check is left to the default-size audit: it switches the system text
/// size itself, so with the size forced inside the app it would report every text as unsupported.
final class AccessibilityAuditLargeTextUITests: UITestCase {
    // Forced inside the app (UI test mode): the simulator-wide settings of XCUIDevice and the launch argument
    // `-UIPreferredContentSizeCategoryName` had no effect on the SwiftUI app in the simulator of this Xcode version.
    override var extraLaunchArguments: [String] { ["-TagwerkUITestTextSize", "accessibility5", "-TagwerkUITestDark", "-TagwerkDemoFoodLookup"] + AuditAllowlist.fixedClockArguments }

    private func audit(_ screen: String) throws {
        try AuditAllowlist.audit(app, screen: "AX5/dark " + screen, for: [.textClipped, .contrast])
    }

    func testAuditLargestTextAndDark() throws {
        waitFor("Sprechstunde")
        try audit("Planen")

        tab("Aufgaben")
        waitFor("Neue Aufgabe")
        try audit("Aufgaben")

        tab("Erfassen")
        waitFor("Wochenrückblick, Woche")
        try audit("Erfassen")

        // In the largest text size the row lies below the screen: scroll until a copy the user can tap is on screen (the page
        // previews of the neighbouring days keep copies in the tree).
        let reviewEntries = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "Wochenrückblick, Woche.*"))
        var reviewEntry: XCUIElement?
        for _ in 0..<8 where reviewEntry == nil {
            reviewEntry = reviewEntries.allElementsBoundByIndex.first { $0.isHittable }
            if reviewEntry == nil { app.swipeUp() }
        }
        XCTAssertNotNil(reviewEntry, "The row of the weekly review is not reachable by scrolling")
        reviewEntry?.tap()
        XCTAssertTrue(app.navigationBars["Wochenrückblick"].waitForExistence(timeout: Self.timeout))
        try audit("Wochenrückblick")
        dragUpUntilHittable(app.descendants(matching: .any).matching(identifier: AccessibilityID.WeekReview.trendLink).firstMatch)
        waitUntilScreenIsStable()
        // Only clipping: at this scroll position a row lies half behind the navigation bar, and the audit measures its contrast
        // against the glass of the bar (first run 2026-11-25: weekday mark "Di" at y = −14 pt), not against the list background.
        try AuditAllowlist.audit(app, screen: "AX5/dark Wochenrückblick (weiter unten)", for: [.textClipped])
        app.navigationBars.buttons.firstMatch.tap()

        openShoppingList()
        try audit("Einkaufsliste")

        try auditBarcodeScan(audit)
    }
}
