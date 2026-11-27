import XCTest

/// The project progress (#332): the overview in "Aufgaben" and the page of one project. The UI test mode serves fixed projects
/// (`ProjectProgressSources.demo`): "Beispiel-Projekt" (GitHub), "Privat & Haushalt" and "Studium" (reminder lists) and "Lokal";
/// "Studium" has had no movement for three weeks.
final class ProjectProgressUITests: UITestCase {
    private func openOverview(file: StaticString = #filePath, line: UInt = #line) {
        tab("Aufgaben", file: file, line: line)
        let entry = app.buttons[AccessibilityID.ProjectProgress.entryRow].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: Self.timeout), "The row Projektfortschritt is missing", file: file, line: line)
        entry.tap()
        XCTAssertTrue(app.navigationBars["Projektfortschritt"].waitForExistence(timeout: Self.timeout),
                      "The overview did not open", file: file, line: line)
    }

    private func row(_ title: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.ProjectProgress.row(title)].firstMatch
    }

    /// Waits for an element whose label or value contains the text (a sentence of the page is one element with more words).
    private func waitForText(containing text: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)
        let element = app.descendants(matching: .any).matching(predicate).firstMatch
        // The list creates rows near the screen only: scroll in small steps until the sentence is there.
        var swipes = 0
        while !element.waitForExistence(timeout: 2), swipes < 10 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.exists, "\(text) did not appear", file: file, line: line)
    }

    private func openProject(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let project = row(title)
        XCTAssertTrue(project.waitForExistence(timeout: Self.timeout), "The project \(title) is missing", file: file, line: line)
        project.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: Self.timeout), "The page of \(title) did not open",
                      file: file, line: line)
    }

    func testOverviewOpensFromTasksAndListsEverySource() {
        openOverview()
        for title in ["Beispiel-Projekt", "Privat & Haushalt", "Studium", "Lokal"] {
            XCTAssertTrue(row(title).waitForExistence(timeout: Self.timeout), "The project \(title) is not listed")
        }
    }

    func testSourceFilterNarrowsTheList() {
        openOverview()
        XCTAssertTrue(row("Beispiel-Projekt").waitForExistence(timeout: Self.timeout))
        selectSegment("Erinnerungen")
        XCTAssertTrue(row("Studium").waitForExistence(timeout: Self.timeout), "A reminder list vanished with the filter Erinnerungen")
        waitUntilGone(row("Beispiel-Projekt"))
        XCTAssertFalse(row("Lokal").exists, "The local tasks must not show under Erinnerungen")
        selectSegment("GitHub")
        XCTAssertTrue(row("Beispiel-Projekt").waitForExistence(timeout: Self.timeout))
        waitUntilGone(row("Studium"))
        selectSegment("Alle")
        XCTAssertTrue(row("Studium").waitForExistence(timeout: Self.timeout))
    }

    func testProjectWithoutMovementIsMarkedAsResting() {
        openOverview()
        let studies = row("Studium")
        XCTAssertTrue(studies.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(studies.label.contains("ruht seit"), "The resting project does not say so: \(studies.label)")
        XCTAssertFalse(row("Beispiel-Projekt").label.contains("ruht"), "An active project is marked as resting")
    }

    func testProjectPageShowsChartCountsAndOpenItems() {
        openOverview()
        openProject("Beispiel-Projekt")
        XCTAssertTrue(app.descendants(matching: .any)[AccessibilityID.ProjectProgress.chart].firstMatch.waitForExistence(timeout: Self.timeout),
                      "The weekly chart is missing")
        XCTAssertTrue(app.descendants(matching: .any)[AccessibilityID.ProjectProgress.figures].firstMatch.exists, "The figures are missing")
        // The blocked issue and the overdue one are open items of the demo project, below the time section: scroll to them.
        scrollTo(app.descendants(matching: .any)["App-Sperre im Fokus-Modus"].firstMatch, what: "App-Sperre im Fokus-Modus")
        XCTAssertTrue(app.staticTexts["Blockiert"].firstMatch.exists || app.staticTexts["BLOCKIERT"].firstMatch.exists,
                      "The group of blocked items is missing")
    }

    private func timeRow(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.ProjectProgress.timeRow(name)].firstMatch
    }

    /// Drags the page until the element is there: a lazy list creates no row below the fold, and a swipe can pass a short section.
    private func scrollTo(_ element: XCUIElement, what: String, file: StaticString = #filePath, line: UInt = #line) {
        dragUntilExistsAndHittable(element, what: what, file: file, line: line)
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
        // The picker lies above the section: scroll back to it first.
        dragUntilExistsAndHittable(app.buttons["3 Monate"].firstMatch, what: "The period picker")
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

    func testProjectPageOfAReminderListHasItsFootnote() {
        openOverview()
        openProject("Studium")
        waitForText(containing: "Gelöschte Erinnerungen fehlen im Verlauf")
    }
}

extension UITestCase {
    /// Drags the page until the element exists and can be hit: a lazy list creates no row below the fold, which happens at the
    /// largest text size.
    func dragUntilExistsAndHittable(_ element: XCUIElement, what: String, file: StaticString = #filePath, line: UInt = #line) {
        // A list that was scrolled before keeps its position, so the element can lie above: first towards the top, then down.
        var steps = 0
        while !(element.exists && element.isHittable), steps < 24 {
            dragPage(towardsTop: steps < 8)
            steps += 1
        }
        XCTAssertTrue(element.exists && element.isHittable, "\(what) is not reachable by scrolling", file: file, line: line)
    }

    /// Drags the page up in small steps until no text or row is covered by less than half by the navigation bar or the tab bar. The
    /// contrast check measures a line that straddles the edge of a bar partly against the glass of the bar and reports a real failure;
    /// only text that a bar covers by half or more is accepted (`SystemBarOverlap`). Where a list happens to stop after the drags depends
    /// on timing, so the part of the page the audit looks at is moved until the row at each edge is mostly under the bar or clear of it.
    func scrollPageClearOfBarEdges() {
        let screen = app.windows.firstMatch.frame
        let navigationBar = CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: app.navigationBars.firstMatch.frame.maxY)
        let tabBar = app.tabBars.firstMatch.frame
        for _ in 0..<12 {
            guard let snapshot = try? app.snapshot(),
                  Self.hasPartlyCoveredElement(in: snapshot, bars: [navigationBar, tabBar], screen: screen) else { return }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.66)))
        }
    }

    private static func hasPartlyCoveredElement(in snapshot: XCUIElementSnapshot, bars: [CGRect], screen: CGRect) -> Bool {
        for child in snapshot.children {
            let frame = child.frame
            // Containers (the list, the window) are as high as the screen; rows and texts are not.
            if frame.width > 0, frame.height > 0, frame.height < 120, [.staticText, .cell].contains(child.elementType),
               bars.contains(where: {
                   let share = SystemBarOverlap.coveredShare(of: frame, by: $0, within: screen)
                   return share > 0 && share < SystemBarOverlap.minimumCoveredShare
               }) { return true }
            if hasPartlyCoveredElement(in: child, bars: bars, screen: screen) { return true }
        }
        return false
    }

    /// The overview of the project progress and the page of its first project, in the two screens the audits cover.
    func auditProjectProgress(_ audit: (String) throws -> Void) throws {
        tab("Aufgaben")
        // An earlier part of the audit left a page open in this tab (the list of the notes): back to the list of the tasks.
        var pops = 0
        while !app.navigationBars["Aufgaben"].exists, pops < 4 {
            app.navigationBars.buttons.firstMatch.tap()
            pops += 1
        }
        let entry = app.buttons[AccessibilityID.ProjectProgress.entryRow].firstMatch
        dragUntilExistsAndHittable(entry, what: "The row Projektfortschritt")
        entry.tap()
        XCTAssertTrue(app.navigationBars["Projektfortschritt"].waitForExistence(timeout: Self.timeout), "The overview did not open")
        waitUntilScreenIsStable()
        try audit("Projektfortschritt")
        let project = app.descendants(matching: .any)[AccessibilityID.ProjectProgress.row("Beispiel-Projekt")].firstMatch
        dragUntilExistsAndHittable(project, what: "The demo project")
        project.tap()
        // The title of the page, not the chart: at the largest text size the chart lies below the fold of the lazy list.
        XCTAssertTrue(app.navigationBars["Beispiel-Projekt"].waitForExistence(timeout: Self.timeout), "The page of the project did not open")
        waitUntilScreenIsStable()
        try audit("Projektseite")
        // The time section lies below the chart: scroll to it and audit that part of the page as well.
        let planned = app.descendants(matching: .any)[AccessibilityID.ProjectProgress.timeRow("planned")].firstMatch
        dragUntilExistsAndHittable(planned, what: "The time section of the project page")
        scrollPageClearOfBarEdges()
        waitUntilScreenIsStable()
        try audit("Projektseite Zeit")
        // The status history follows the time section: the third part of the page the audits cover.
        let changes = app.descendants(matching: .any)[AccessibilityID.ProjectProgress.statusRow("changes")].firstMatch
        dragUntilExistsAndHittable(changes, what: "The status history of the project page")
        scrollPageClearOfBarEdges()
        waitUntilScreenIsStable()
        try audit("Projektseite Änderungen")
        // Back to "Aufgaben": the next audit starts from the list.
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
    }
}
