import XCTest

/// The window-wide tap that closes the keyboard (`KeyboardDismissal.swift`) must not swallow the tap on a control: with the keyboard
/// open, one tap on a button, a segment or a row performs its action (and still closes the keyboard).
final class KeyboardDismissalUITests: UITestCase {
    /// The meal sheet puts the focus into its text field on its own. The first tap on the segment "Meine Lebensmittel" has to select
    /// it; before the fix it only closed the keyboard, the sheet re-laid out and the touch-up landed outside the segment.
    func testSegmentTap_withKeyboardOpen_selectsSegmentInOneTap() {
        tab("Erfassen")
        onScreen(label: "Essen").tap()
        let segment = app.buttons["Meine Lebensmittel"].firstMatch
        XCTAssertTrue(segment.waitForExistence(timeout: Self.timeout), "The segment is missing")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: Self.timeout), "The text field did not take the focus")

        segment.tap()

        eventually("The first tap on the segment did not select it") { segment.isSelected }
    }

    /// A tap on empty space of the sheet still closes the keyboard (#184): the sheet title is not an input.
    func testTapOnSheetTitle_closesKeyboard() {
        tab("Erfassen")
        onScreen(label: "Essen").tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: Self.timeout), "The text field did not take the focus")

        app.navigationBars["Essen"].staticTexts["Essen"].firstMatch.tap()

        waitUntilGone(app.keyboards.firstMatch)
    }
}
