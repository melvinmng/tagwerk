import XCTest

/// Overlapping entries in the hour grid (BF1c): with large text the columns would be too narrow, so the entries become
/// one block. `-TagwerkDemoOverlap` adds three appointments at 13:30–14:30.
///
/// The decision by text size and width (collapse at the largest size, side by side at the standard size) is asked in
/// `GridCollapseLayoutTests` without an app launch. This is the one case that runs in the real grid, nightly only
/// (`nightly-only.txt`): the block, its VoiceOver label, the list behind it and the way from the list to an entry.
final class PlanOverlapUITests: UITestCase {
    override var extraLaunchArguments: [String] {
        ["-TagwerkDemoOverlap", "-TagwerkUITestTextSize", "accessibility5"] + Self.morningClockArguments
    }

    private let titles = ["Projektbesprechung", "Zahnarzt Kontrolle", "Anruf Steuerberater"]

    private func button(startingWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// Scrolls the page up until the element can be tapped. The drag starts in the hour label column at the left edge, where
    /// no entry can take the touch (a swipe from the middle of the screen can start on an entry and then does not scroll).
    private func reveal(_ element: XCUIElement, maxDrags: Int = 10, file: StaticString = #filePath, line: UInt = #line) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.72))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.25))
        var drags = 0
        while !(element.exists && element.isHittable), drags < maxDrags {
            start.press(forDuration: 0.05, thenDragTo: end)
            drags += 1
        }
        XCTAssertTrue(element.exists && element.isHittable, "\(element) is not reachable by scrolling", file: file, line: line)
    }

    func testOverlappingEntriesCollapseAtLargeText() {
        waitFor("Sprechstunde")
        // The demo seminar (twice) and the deadline overlap in the morning as well, so the block is found by its titles.
        let block = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "3 Termine", titles[0])).firstMatch
        reveal(block)
        // The block names the entries for VoiceOver as well.
        for title in titles { XCTAssertTrue(block.label.contains(title), "The block does not name \(title): \(block.label)") }
        // None of the three is a block of its own.
        XCTAssertFalse(button(startingWith: "Zahnarzt Kontrolle, ").exists)
        block.tap()
        XCTAssertTrue(app.staticTexts["Zum Verschieben den Eintrag öffnen."].waitForExistence(timeout: Self.timeout), "The list does not open")
        for title in titles {
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch.exists, "\(title) is not in the list")
        }
        // A row closes the list and opens the entry (after the sheet has gone).
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Zahnarzt Kontrolle")).firstMatch.tap()
        waitUntilGone(app.staticTexts["Zum Verschieben den Eintrag öffnen."])
        XCTAssertTrue(app.textFields["Zahnarzt Kontrolle"].waitForExistence(timeout: Self.timeout)
                      || app.staticTexts["Zahnarzt Kontrolle"].waitForExistence(timeout: Self.timeout), "The entry does not open")
    }
}
