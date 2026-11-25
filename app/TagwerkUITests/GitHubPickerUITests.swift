import XCTest

/// The picker sheets of a GitHub issue ("Repository wählen", "Projekte"). UI tests have no GitHub catalog, so the app shows the
/// sheets with invented repositories and projects (`-TagwerkUITestScreen github.repositoryPicker` / `github.projectPicker`).
final class GitHubRepositoryPickerUITests: UITestCase {
    override var extraLaunchArguments: [String] { ["-TagwerkUITestScreen", "github.repositoryPicker"] }

    func testRepositoryPicker_findsRepositoryBySearch() {
        XCTAssertTrue(app.navigationBars["Repository wählen"].waitForExistence(timeout: Self.timeout), "The picker did not open")
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: Self.timeout), "The picker has no search field")
        field.tap()
        field.typeText("klausuren")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "klausuren")).firstMatch
            .waitForExistence(timeout: Self.timeout), "A search without hits shows no empty state")
        replaceText(of: field, with: "repository-17")
        let hit = app.buttons["beispiel/repository-17"].firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: Self.timeout), "The repository is not among the hits")
        hit.tap()
        XCTAssertTrue(app.navigationBars["Repository wählen"].waitForNonExistence(timeout: Self.timeout), "The sheet stayed open after the choice")
    }

    func testRepositoryPicker_listsRecentRepositoriesFirstAndTheCountOfAll() {
        XCTAssertTrue(app.navigationBars["Repository wählen"].waitForExistence(timeout: Self.timeout), "The picker did not open")
        XCTAssertTrue(app.staticTexts["Zuletzt verwendet"].firstMatch.waitForExistence(timeout: Self.timeout), "No section of recent repositories")
        XCTAssertTrue(app.staticTexts["Alle Repositories (28)"].firstMatch.waitForExistence(timeout: Self.timeout), "The count of all repositories is wrong")
    }
}

final class GitHubProjectPickerUITests: UITestCase {
    override var extraLaunchArguments: [String] { ["-TagwerkUITestScreen", "github.projectPicker"] }

    func testProjectPicker_choosesSeveralProjectsAndCloses() {
        XCTAssertTrue(app.navigationBars["Projekte (1)"].waitForExistence(timeout: Self.timeout), "The picker did not open")
        app.buttons["Studium und Klausuren"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Projekte (2)"].waitForExistence(timeout: Self.timeout), "The second project was not counted")
        app.buttons["Fertig"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Projekte (2)"].waitForNonExistence(timeout: Self.timeout), "The sheet stayed open after \"Fertig\"")
    }

    func testProjectPicker_noProjectClearsTheChoice() {
        XCTAssertTrue(app.navigationBars["Projekte (1)"].waitForExistence(timeout: Self.timeout), "The picker did not open")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Kein Projekt")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Projekte"].waitForExistence(timeout: Self.timeout), "\"Kein Projekt\" did not clear the choice")
    }
}
