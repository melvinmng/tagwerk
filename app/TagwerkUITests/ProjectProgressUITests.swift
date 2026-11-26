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
        // The blocked issue and the overdue one are open items of the demo project.
        waitFor("App-Sperre im Fokus-Modus")
        XCTAssertTrue(app.staticTexts["Blockiert"].firstMatch.exists || app.staticTexts["BLOCKIERT"].firstMatch.exists,
                      "The group of blocked items is missing")
    }

    private func timeRow(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.ProjectProgress.timeRow(name)].firstMatch
    }

    /// Scrolls the lazy list until the element exists; the time section lies below the chart.
    private func scrollTo(_ element: XCUIElement, what: String, file: StaticString = #filePath, line: UInt = #line) {
        var swipes = 0
        while !element.waitForExistence(timeout: 2), swipes < 10 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.exists, "\(what) did not appear", file: file, line: line)
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
        selectSegment("3 Monate")
        scrollTo(timeRow("planned"), what: "The planned time after the change of the period")
        XCTAssertEqual(timeRow("planned").value as? String, "7 h")
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
        // Back to "Aufgaben": the next audit starts from the list.
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
    }
}
