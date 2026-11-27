import XCTest

/// Repositories and projects of the GitHub account as hits of the global search. UI tests have no GitHub account, so the app answers
/// with invented repositories and projects (`-TagwerkUITestGitHubCatalog`): the repositories "beispiel/app" and "beispiel/studium",
/// the projects "App" and "Studium und Klausuren". A tap opens the page of that project in the tab "Aufgaben". The section moves to the
/// top of the list when the query names a repository or project (#348), and "Issue anlegen" (context menu of a hit, "+" of the project
/// page) opens "Neue Aufgabe" with the repository and the project filled in.
final class GitHubSearchUITests: UITestCase {
    override var extraLaunchArguments: [String] { ["-TagwerkUITestGitHubCatalog"] }

    func testSearchOpensTheProgressOfARepositoryHit() {
        openSearch(typing: "studium")
        let hit = app.descendants(matching: .any)[AccessibilityID.Search.repositoryHit("beispiel/studium")].firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: Self.timeout), "The repository is not among the hits")
        // The header is read out with the count ("Repositories und Projekte, 2"), so VoiceOver and the test find it by that label.
        XCTAssertTrue(app.staticTexts["Repositories und Projekte, 2"].firstMatch.exists, "The section of the hits has no header with the count")
        hit.tap()
        // The search sheet closes and the page of the repository opens on top of the project overview.
        XCTAssertTrue(app.navigationBars["beispiel/studium"].waitForExistence(timeout: Self.timeout), "The page of the repository did not open")
        XCTAssertFalse(app.textFields["Suchen"].exists, "The search sheet is still open")
    }

    func testSearchOpensTheProgressOfAProjectHit() {
        openSearch(typing: "klausuren")
        let hit = app.descendants(matching: .any)[AccessibilityID.Search.projectHit("Studium und Klausuren")].firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: Self.timeout), "The project is not among the hits")
        hit.tap()
        XCTAssertTrue(app.navigationBars["Studium und Klausuren"].waitForExistence(timeout: Self.timeout), "The page of the project did not open")
        XCTAssertFalse(app.textFields["Suchen"].exists, "The search sheet is still open")
    }

    func testSearchWithoutAMatchShowsNoGitHubSection() {
        openSearch(typing: "zzzxqj")
        XCTAssertFalse(app.descendants(matching: .any)[AccessibilityID.Search.repositoryHit("beispiel/studium")].firstMatch
            .waitForExistence(timeout: 3), "A repository was found for a text it does not contain")
    }

    // MARK: Order of the section (#348)

    private func hit(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// The row of the appointment "Klausur Statistik" (the demo data of the UI test mode).
    private var examEvent: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Klausur Statistik")).firstMatch
    }

    func testANameHitMovesTheSectionAboveTheAppointments() {
        // "klausur" starts the word "Klausuren" of a project and the title of an appointment.
        openSearch(typing: "klausur")
        let project = hit(AccessibilityID.Search.projectHit("Studium und Klausuren"))
        XCTAssertTrue(project.waitForExistence(timeout: Self.timeout), "The project is not among the hits")
        XCTAssertTrue(examEvent.waitForExistence(timeout: Self.timeout), "The appointment is not among the hits")
        XCTAssertLessThan(project.frame.minY, examEvent.frame.minY, "The section of the project stayed below the appointments")
    }

    func testAHitInsideAWordKeepsTheSectionBelowTheAppointments() {
        // "ausur" occurs inside "Klausuren" and "Klausur": no start of a word, so the section keeps its place.
        openSearch(typing: "ausur")
        let project = hit(AccessibilityID.Search.projectHit("Studium und Klausuren"))
        XCTAssertTrue(project.waitForExistence(timeout: Self.timeout), "The project is not among the hits")
        XCTAssertTrue(examEvent.waitForExistence(timeout: Self.timeout), "The appointment is not among the hits")
        XCTAssertGreaterThan(project.frame.minY, examEvent.frame.minY, "The section of the project moved up without a name hit")
    }

    // MARK: Issue anlegen (#348)

    /// The value of a row of "Neue Aufgabe" ("Repository", "Projekte"): the selection that is read out.
    private func rowValue(_ title: String) -> String? {
        app.buttons[title].firstMatch.value as? String
    }

    private func expectFilledSheet(repository: String, projects: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.navigationBars["Neue Aufgabe"].waitForExistence(timeout: Self.timeout), "\"Neue Aufgabe\" did not open",
                      file: file, line: line)
        XCTAssertTrue(app.buttons["Repository"].firstMatch.waitForExistence(timeout: Self.timeout), "The row Repository is missing",
                      file: file, line: line)
        eventually("The repository is not filled in", file: file, line: line) { rowValue("Repository") == repository }
        eventually("The project is not filled in", file: file, line: line) { rowValue("Projekte") == projects }
    }

    func testContextMenuOfARepositoryHitCreatesAnIssueForIt() {
        openSearch(typing: "studium")
        let repository = hit(AccessibilityID.Search.repositoryHit("beispiel/studium"))
        XCTAssertTrue(repository.waitForExistence(timeout: Self.timeout), "The repository is not among the hits")
        repository.press(forDuration: 1.2)
        let entry = app.buttons["Issue anlegen"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: Self.timeout), "The context menu has no entry \"Issue anlegen\"")
        entry.tap()
        // The projects linked to the repository come with it.
        expectFilledSheet(repository: "beispiel/studium", projects: "Studium und Klausuren")
        app.buttons["Abbrechen"].firstMatch.tap()
        // The search stays open beneath the sheet.
        XCTAssertTrue(app.textFields["Suchen"].waitForExistence(timeout: Self.timeout), "The search closed with the sheet")
        XCTAssertTrue(repository.exists, "The hits are gone after the sheet")
    }

    func testContextMenuOfAProjectHitFillsTheProjectAndItsOnlyRepository() {
        openSearch(typing: "klausuren")
        let project = hit(AccessibilityID.Search.projectHit("Studium und Klausuren"))
        XCTAssertTrue(project.waitForExistence(timeout: Self.timeout), "The project is not among the hits")
        project.press(forDuration: 1.2)
        let entry = app.buttons["Issue anlegen"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: Self.timeout), "The context menu has no entry \"Issue anlegen\"")
        entry.tap()
        expectFilledSheet(repository: "beispiel/studium", projects: "Studium und Klausuren")
    }

    func testThePlusOnTheProjectPageOfARepositoryCreatesAnIssueForIt() {
        openSearch(typing: "studium")
        let repository = hit(AccessibilityID.Search.repositoryHit("beispiel/studium"))
        XCTAssertTrue(repository.waitForExistence(timeout: Self.timeout), "The repository is not among the hits")
        repository.tap()
        XCTAssertTrue(app.navigationBars["beispiel/studium"].waitForExistence(timeout: Self.timeout), "The page of the repository did not open")
        let plus = app.buttons[AccessibilityID.ProjectProgress.newTask].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: Self.timeout), "The page has no \"+\"")
        XCTAssertEqual(plus.label, "Issue anlegen")
        plus.tap()
        expectFilledSheet(repository: "beispiel/studium", projects: "Studium und Klausuren")
    }

    func testThePlusOnTheProjectPageOfAProjectFillsTheProjectAndItsOnlyRepository() {
        openSearch(typing: "klausuren")
        let project = hit(AccessibilityID.Search.projectHit("Studium und Klausuren"))
        XCTAssertTrue(project.waitForExistence(timeout: Self.timeout), "The project is not among the hits")
        project.tap()
        XCTAssertTrue(app.navigationBars["Studium und Klausuren"].waitForExistence(timeout: Self.timeout), "The page of the project did not open")
        let plus = app.buttons[AccessibilityID.ProjectProgress.newTask].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: Self.timeout), "The page has no \"+\"")
        plus.tap()
        expectFilledSheet(repository: "beispiel/studium", projects: "Studium und Klausuren")
    }
}
