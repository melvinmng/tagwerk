import XCTest

/// The capsule "zu früh" of a tight trip (PL10b, plan g1 task V2) in the hour grid. `-TagwerkDemoTravel` adds the "Team-Call"
/// (08:30–09:40) before the seminar (10:00), whose trip of 30 minutes then starts ten minutes before the call ends.
///
/// This class used to hold proofs 3 and 4 of the capsule, the contrast audit on the day view in light and dark appearance, in the grid and
/// in the list. They are gone: grid and list draw the same view (`TravelWarningCapsule`, a solid fill with its own text colour, nothing
/// of the surroundings shines through), so the contrast of the rendered capsule in `MarkerRenderContrastTests` (light and dark) and the
/// colour values in `MarkerColorsTests` decide it without an app launch. What stays is the placement, which needs the real grid layout.
/// Nightly only (`nightly-only.txt`).
final class TravelContrastUITests: UITestCase {
    override var extraLaunchArguments: [String] { ["-TagwerkDemoTravel"] + Self.morningClockArguments }

    private var capsules: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "travel.warningCapsule")
    }

    /// The attachment sits flush above its event (beside the call it overlaps in time): the capsule lies right above one of the seminar
    /// buttons and over its column. Once the screen has settled the grid has narrow columns (the seminar and its copy, the call, the deadline,
    /// the break: 78 pt each), and the capsule is wider than one column, so it may reach into the next one; before the settle wait of the
    /// UI test mode the seminar had a column of its own and the capsule fitted into it.
    func testAttachmentSitsAboveItsEventInTheGrid() {
        let capsule = capsules.firstMatch
        XCTAssertTrue(capsule.waitForExistence(timeout: Self.timeout), "No capsule on screen")
        let seminars = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Seminar")).allElementsBoundByIndex
        XCTAssertFalse(seminars.isEmpty, "The seminar is not on screen")
        let frame = capsule.frame
        let below = seminars.filter { frame.maxY <= $0.frame.minY + 2 && $0.frame.minY - frame.maxY < 30
            && frame.minX < $0.frame.maxX && frame.maxX > $0.frame.minX }
        XCTAssertFalse(below.isEmpty, "No seminar sits right below the capsule \(frame): \(seminars.map(\.frame))")
    }
}
