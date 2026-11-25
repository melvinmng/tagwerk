import XCTest

/// Audit in the largest text size (AX5) and in dark mode, on the four core screens only (the audit is slow).
/// Checked: clipped text and contrast. The Dynamic Type check is left to the default-size audit: it switches the system text
/// size itself, so with the size forced inside the app it would report every text as unsupported.
final class AccessibilityAuditLargeTextUITests: UITestCase {
    // Forced inside the app (UI test mode): the simulator-wide settings of XCUIDevice and the launch argument
    // `-UIPreferredContentSizeCategoryName` had no effect on the SwiftUI app in the simulator of this Xcode version.
    override var extraLaunchArguments: [String] { ["-TagwerkUITestTextSize", "accessibility5", "-TagwerkUITestDark"] + AuditAllowlist.fixedClockArguments }

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

        onScreen(label: "Wochenrückblick, Woche.*", matching: true).tap()
        XCTAssertTrue(app.navigationBars["Wochenrückblick"].waitForExistence(timeout: Self.timeout))
        try audit("Wochenrückblick")
        app.swipeUp()
        waitUntilScreenIsStable()
        try audit("Wochenrückblick (weiter unten)")
        app.navigationBars.buttons.firstMatch.tap()

        openShoppingList()
        try audit("Einkaufsliste")
    }
}
