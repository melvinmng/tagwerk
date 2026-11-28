import XCTest

/// The page of one project in the project progress (#332): planned and invested time, the status history with its note and the
/// period of the figures. Split off `ProjectProgressUITests` so the shards of the UI test job can balance the two halves; the steps
/// to reach a project are in `ProjectProgressUITestCase`. Same demo projects as there (`ProjectProgressSources.demo`).
@MainActor
final class ProjectProgressPageUITests: ProjectProgressUITestCase {
    private func timeRow(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.ProjectProgress.timeRow(name)].firstMatch
    }

    /// The demo project has planned blocks, focus sessions and a completion with a cut block (see `ProjectProgressSources.demo`):
    /// planned 7 h, invested 4 h, estimates of three open items 7 h 30 min.
    func testProjectPageShowsPlannedAndInvestedTime() {
        openOverview()
        openProject("Beispiel-Projekt")
        scrollTo(timeRow("planned"), what: "The planned time")
        XCTAssertEqual(timeRow("planned").value as? String, "7 h", "planned time")
        XCTAssertEqual(timeRow("invested").value as? String, "4 h", "invested time")
        XCTAssertTrue((timeRow("estimate").value as? String)?.contains("7 h 30 min") ?? false, "open estimates")
        XCTAssertTrue(app.descendants(matching: .any)[AccessibilityID.ProjectProgress.timeChart].firstMatch.exists, "The time chart is missing")
        // The demo records lie in the last three weeks: a longer period shows the same time.
        // The picker lies above the section: drag back to the top of the page, where it sits clear of the navigation bar.
        for _ in 0..<8 { dragPage(towardsTop: true) }
        selectSegment("3 Monate")
        scrollTo(timeRow("planned"), what: "The planned time after the change of the period")
        XCTAssertEqual(timeRow("planned").value as? String, "7 h")
    }

    private func statusRow(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.ProjectProgress.statusRow(name)].firstMatch
    }

    /// The demo log of "Beispiel-Projekt" (see `ProjectProgressSources.demo`): four status changes (two of them Ready to In progress),
    /// one reopening, one change of the due date and two moves of the planned day; "In progress" 4 days, "Review" 2 days.
    func testProjectPageShowsTheStatusHistoryWithItsNote() {
        openOverview()
        openProject("Beispiel-Projekt")
        scrollTo(statusRow("changes"), what: "The count of status changes")
        XCTAssertEqual(statusRow("changes").value as? String, "4")
        XCTAssertEqual(statusRow("transition.Ready>In progress").value as? String, "2×")
        scrollTo(statusRow("duration.In progress"), what: "The time in In progress")
        XCTAssertEqual(statusRow("duration.In progress").value as? String, "4 Tage")
        XCTAssertEqual(statusRow("duration.Review").value as? String, "2 Tage")
        scrollTo(statusRow("reopened"), what: "The reopen count")
        XCTAssertEqual(statusRow("reopened").value as? String, "1")
        XCTAssertEqual(statusRow("dueDates").value as? String, "1")
        XCTAssertEqual(statusRow("planDays").value as? String, "2")
        let note = app.descendants(matching: .any)[AccessibilityID.ProjectProgress.statusNote].firstMatch
        scrollTo(note, what: "The note about what the log covers")
        XCTAssertTrue(note.label.contains("in Tagwerk auf diesem Gerät"), "The note does not say what the log covers: \(note.label)")
    }

    func testProjectWithoutLogEntriesSaysSoAndStillShowsTheNote() {
        openOverview()
        openProject("Studium")
        scrollTo(app.descendants(matching: .any)[AccessibilityID.ProjectProgress.statusEmpty].firstMatch, what: "The note about missing log entries")
        let note = app.descendants(matching: .any)[AccessibilityID.ProjectProgress.statusNote].firstMatch
        scrollTo(note, what: "The note about what the log covers")
        XCTAssertFalse(statusRow("changes").exists, "A project without log entries shows no counts")
    }

    func testProjectWithoutRecordedTimeSaysSoInsteadOfZero() {
        openOverview()
        openProject("Studium")
        scrollTo(app.descendants(matching: .any)[AccessibilityID.ProjectProgress.timeEmpty].firstMatch, what: "The note about missing time data")
        XCTAssertEqual(timeRow("planned").value as? String, "–")
        XCTAssertEqual(timeRow("invested").value as? String, "–")
        XCTAssertFalse(app.descendants(matching: .any)[AccessibilityID.ProjectProgress.timeChart].firstMatch.exists,
                       "A chart of nothing is no information")
    }

    func testPeriodPickerChangesThePeriod() {
        openOverview()
        openProject("Beispiel-Projekt")
        waitForText(containing: "in den letzten 4 Wochen")
        selectSegment("3 Monate")
        waitForText(containing: "in den letzten 3 Monaten")
        selectSegment("1 Jahr")
        waitForText(containing: "im letzten Jahr")
    }

    func testFreePeriodOffersTwoDates() {
        openOverview()
        openProject("Beispiel-Projekt")
        selectSegment("Frei")
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: Self.timeout), "The free period has no date pickers")
        XCTAssertGreaterThanOrEqual(app.datePickers.count, 2)
    }
}
