import XCTest

/// Repositories and projects of the GitHub account as hits of the global search. UI tests have no GitHub account, so the app answers
/// with invented repositories and projects (`-TagwerkUITestGitHubCatalog`): the repositories "beispiel/app" and "beispiel/studium",
/// the projects "App" and "Studium und Klausuren". A tap opens the page of that project in the tab "Aufgaben".
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
}
