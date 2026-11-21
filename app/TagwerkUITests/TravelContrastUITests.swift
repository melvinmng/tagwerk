import XCTest

/// Proofs 3 and 4 of the capsule "zu früh" (PL10b, plan g1 task V2): the contrast audit on the day view with a tight trip, in
/// the grid and in the list, in light and dark appearance, WITHOUT `AuditAllowlist`. A finding on the capsule fails the test.
/// `-TagwerkDemoTravel` adds the "Team-Call" (08:30–09:40) before the seminar (10:00), whose trip of 30 minutes then starts
/// ten minutes before the call ends. Only findings on the capsule count here; the other elements are covered by the audits of
/// the screens.
final class TravelContrastUITests: UITestCase {
    override var extraLaunchArguments: [String] {
        ["-TagwerkDemoTravel"] + Self.morningClockArguments + (name.contains("InDark") ? ["-TagwerkUITestDark"] : [])
    }

    private var capsules: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "travel.warningCapsule")
    }

    /// Fails for every contrast finding on a capsule; findings on other elements are not this test's subject.
    private func auditCapsules(_ screen: String, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(capsules.firstMatch.waitForExistence(timeout: Self.timeout),
                      "\(screen): no capsule on screen, the audit would prove nothing", file: file, line: line)
        // The audit has no time setting and runs out of time on a loaded machine; such a run says nothing, so it is repeated
        // (like `AuditAllowlist`), up to three attempts. The issues of an aborted attempt are dropped.
        for attempt in 1...3 {
            var onCapsule: [XCUIAccessibilityAuditIssue] = []
            do {
                try app.performAccessibilityAudit(for: .contrast) { issue in
                    if issue.element?.identifier == "travel.warningCapsule" { onCapsule.append(issue) }
                    return true
                }
            } catch let error as NSError where error.code == -56 && attempt < 3 {
                print("Accessibility audit timed out (attempt \(attempt) of 3), running it again")
                continue
            }
            for issue in onCapsule {
                XCTFail("\(screen): contrast finding on the capsule: \(issue.compactDescription) | \(issue.detailedDescription)",
                        file: file, line: line)
            }
            return
        }
    }

    private func checkGridAndList() throws {
        try auditCapsules("grid")
        // The list shows the same capsule behind "Losfahren".
        let toggle = app.buttons["Als Liste zeigen"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: Self.timeout), "The switch to the list is missing")
        toggle.tap()
        try auditCapsules("list")
    }

    func testTightTripInLight() throws {
        try checkGridAndList()
    }

    func testTightTripInDark() throws {
        try checkGridAndList()
    }

    /// The attachment sits flush above its event, in the column of the event (beside the call it overlaps in time): the
    /// capsule lies above one of the seminar buttons and within its column.
    func testAttachmentSitsAboveItsEventInTheGrid() {
        let capsule = capsules.firstMatch
        XCTAssertTrue(capsule.waitForExistence(timeout: Self.timeout), "No capsule on screen")
        let seminars = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Seminar")).allElementsBoundByIndex
        XCTAssertFalse(seminars.isEmpty, "The seminar is not on screen")
        let frame = capsule.frame
        let below = seminars.filter { frame.maxY <= $0.frame.minY + 2 && $0.frame.minY - frame.maxY < 30
            && frame.minX >= $0.frame.minX - 2 && frame.maxX <= $0.frame.maxX + 2 }
        XCTAssertFalse(below.isEmpty, "No seminar sits right below the capsule \(frame): \(seminars.map(\.frame))")
    }
}
