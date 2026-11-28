import XCTest

/// Shared steps of the project progress UI tests. The tests are split over two classes (`ProjectProgressUITests`: overview, project
/// page contents and the "+"; `ProjectProgressPageUITests`: time, status history and period of the project page) so the shards of
/// the UI test job can balance them (`ui-test-durations.txt`).
@MainActor
class ProjectProgressUITestCase: UITestCase {
    func openOverview(file: StaticString = #filePath, line: UInt = #line) {
        tab("Aufgaben", file: file, line: line)
        let entry = app.buttons[AccessibilityID.ProjectProgress.entryRow].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: Self.timeout), "The row Projektfortschritt is missing", file: file, line: line)
        entry.tap()
        XCTAssertTrue(app.navigationBars["Projektfortschritt"].waitForExistence(timeout: Self.timeout),
                      "The overview did not open", file: file, line: line)
    }

    func row(_ title: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.ProjectProgress.row(title)].firstMatch
    }

    /// Waits for an element whose label or value contains the text (a sentence of the page is one element with more words).
    func waitForText(containing text: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)
        let element = app.descendants(matching: .any).matching(predicate).firstMatch
        // The list creates rows near the screen only: scroll in small steps until the sentence is there.
        var swipes = 0
        while !element.waitForExistence(timeout: 2), swipes < 10 {
            dragPage(towardsTop: false)
            swipes += 1
        }
        XCTAssertTrue(element.exists, "\(text) did not appear", file: file, line: line)
    }

    func openProject(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let project = row(title)
        XCTAssertTrue(project.waitForExistence(timeout: Self.timeout), "The project \(title) is missing", file: file, line: line)
        project.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: Self.timeout), "The page of \(title) did not open",
                      file: file, line: line)
    }

    /// Drags the page until the element is there: a lazy list creates no row below the fold, and a swipe can pass a short section.
    func scrollTo(_ element: XCUIElement, what: String, file: StaticString = #filePath, line: UInt = #line) {
        dragUntilExistsAndHittable(element, what: what, file: file, line: line)
    }
}

/// The project progress (#332): the overview in "Aufgaben", the contents of the page of one project and the "+" on it. The UI test mode serves fixed projects
/// (`ProjectProgressSources.demo`): "Beispiel-Projekt" (GitHub), "Privat & Haushalt" and "Studium" (reminder lists) and "Lokal";
/// "Studium" has had no movement for three weeks.
final class ProjectProgressUITests: ProjectProgressUITestCase {
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

    func testProjectPageOfAReminderListHasItsFootnote() {
        openOverview()
        openProject("Studium")
        waitForText(containing: "Gelöschte Erinnerungen fehlen im Verlauf")
    }

    // MARK: "+" on the project page (#348)

    private var newTaskButton: XCUIElement { app.buttons[AccessibilityID.ProjectProgress.newTask].firstMatch }

    func testProjectPageOfTheLocalTasksCreatesALocalTask() {
        openOverview()
        openProject("Lokal")
        XCTAssertTrue(newTaskButton.waitForExistence(timeout: Self.timeout), "The page has no \"+\"")
        XCTAssertEqual(newTaskButton.label, "Aufgabe anlegen")
        newTaskButton.tap()
        XCTAssertTrue(app.navigationBars["Neue Aufgabe"].waitForExistence(timeout: Self.timeout), "\"Neue Aufgabe\" did not open")
        XCTAssertTrue(app.buttons["Lokal"].firstMatch.isSelected, "The sheet does not start with the source \"Lokal\"")
    }

    func testProjectPageOfAReminderListCreatesAReminder() {
        openOverview()
        openProject("Studium")
        XCTAssertTrue(newTaskButton.waitForExistence(timeout: Self.timeout), "The page has no \"+\"")
        XCTAssertEqual(newTaskButton.label, "Aufgabe anlegen")
        newTaskButton.tap()
        XCTAssertTrue(app.navigationBars["Neue Aufgabe"].waitForExistence(timeout: Self.timeout), "\"Neue Aufgabe\" did not open")
        XCTAssertTrue(app.buttons["Erinnerung"].firstMatch.isSelected, "The sheet does not start with the source \"Erinnerung\"")
    }

    func testProjectPageOfAGitHubProjectHasNoPlusWithoutAGitHubAccount() {
        // The UI test mode has no GitHub account, so no issue can be created: the page offers no "+" at all.
        openOverview()
        openProject("Beispiel-Projekt")
        XCTAssertTrue(app.descendants(matching: .any)[AccessibilityID.ProjectProgress.figures].firstMatch.waitForExistence(timeout: Self.timeout),
                      "The page did not load")
        XCTAssertFalse(newTaskButton.exists, "A page that cannot create an issue shows a \"+\"")
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
        // Back to the overview, then the page of the local tasks: its toolbar shows the "+" (a GitHub project has none without an account).
        app.navigationBars.buttons.firstMatch.tap()
        let local = app.descendants(matching: .any)[AccessibilityID.ProjectProgress.row("Lokal")].firstMatch
        dragUntilExistsAndHittable(local, what: "The local tasks")
        local.tap()
        XCTAssertTrue(app.buttons[AccessibilityID.ProjectProgress.newTask].firstMatch.waitForExistence(timeout: Self.timeout),
                      "The page of the local tasks has no \"+\"")
        waitUntilScreenIsStable()
        // Only what the "+" can get wrong: its name, its hit area and whether it is found at all. Contrast and Dynamic Type of this page are
        // those of "Projektseite" (the chart legend and its notes, covered by the entries of that screen).
        try AuditAllowlist.audit(app, screen: "Projektseite Lokal (Knopf)",
                                 for: [.sufficientElementDescription, .hitRegion, .elementDetection, .trait, .textClipped])
        // Back to "Aufgaben": the next audit starts from the list.
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
    }
}
