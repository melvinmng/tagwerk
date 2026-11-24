import XCTest

/// The way into the goal planning chat (decisions PV1b, PV2a, ZI1b): the trends page offers "Ziele planen", the consent sheet comes
/// first, then the sheet that shows the data package, then the chat. The chat runs on the demo transport (`-TagwerkDemoAI`); nothing is sent.
final class GoalPlanningUITests: UITestCase {
    override var extraLaunchArguments: [String] { ["-TagwerkDemoAI"] }

    /// The button with this identifier that is on the screen. The pages next to the shown day of "Erfassen" are laid out beside it and
    /// carry the same identifiers, so the first match is not always the one the user sees.
    private func visibleButton(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let window = app.windows.firstMatch
        for _ in 0..<8 {
            let matches = app.buttons.matching(identifier: identifier).allElementsBoundByIndex
            if let visible = matches.first(where: { $0.exists && $0.isHittable && window.frame.contains($0.frame) }) { return visible }
            app.swipeUp()
        }
        XCTFail("The button \(identifier) is not on the screen", file: file, line: line)
        return app.buttons[identifier].firstMatch
    }

    private func openTrendsPage() {
        tab("Erfassen")
        visibleButton(AccessibilityID.Trend.entry).tap()
        XCTAssertTrue(app.navigationBars["Verlauf und Ziele"].waitForExistence(timeout: Self.timeout), "The trends page did not open")
    }

    func testPlanGoals_consentThenDataSheetThenChat() {
        openTrendsPage()
        visibleButton(AccessibilityID.GoalPlanning.planEntry).tap()

        // The consent comes first, once.
        tapButton(AccessibilityID.GoalPlanning.consentAgree)
        // Then the sheet that shows exactly what would be sent; every group has a switch.
        let begin = app.buttons[AccessibilityID.GoalPlanning.begin].firstMatch
        XCTAssertTrue(begin.waitForExistence(timeout: Self.timeout), "The data sheet did not appear after the consent")
        XCTAssertTrue(app.switches[AccessibilityID.GoalPlanning.groupSwitch("nutrition")].firstMatch.exists, "The group Ernährung has no switch")
        begin.tap()

        // The chat opens when the sheet has left; the context chip names it.
        waitFor("Kontext: Ziele planen", timeout: 20)
    }

    func testPlanGoals_secondTime_skipsTheConsent() {
        openTrendsPage()
        visibleButton(AccessibilityID.GoalPlanning.planEntry).tap()
        tapButton(AccessibilityID.GoalPlanning.consentAgree)
        XCTAssertTrue(app.buttons[AccessibilityID.GoalPlanning.begin].firstMatch.waitForExistence(timeout: Self.timeout))
        // "Abbrechen" ends the way without a chat; the consent stays.
        let begin = app.buttons[AccessibilityID.GoalPlanning.begin].firstMatch
        app.buttons["Abbrechen"].firstMatch.tap()
        // The sheet has to be gone before the entry below it can be tapped.
        waitUntilGone(begin)
        let plan = visibleButton(AccessibilityID.GoalPlanning.planEntry)
        plan.tap()
        XCTAssertTrue(app.buttons[AccessibilityID.GoalPlanning.begin].firstMatch.waitForExistence(timeout: Self.timeout),
                      "The consent is asked once; the next entry goes straight to the data sheet")
        XCTAssertFalse(app.buttons[AccessibilityID.GoalPlanning.consentAgree].firstMatch.exists)
    }
}
