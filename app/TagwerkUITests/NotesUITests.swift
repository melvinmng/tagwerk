import XCTest

final class NotesUITests: UITestCase {
    func testCreateAndFindNote() {
        openNotes()
        let folder = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Brain Dump")).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: Self.timeout))
        folder.tap()
        typeIn("Neue Notiz", text: "UI-Test Notiz")
        tapButton("Notiz sichern")
        let note = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "UI-Test Notiz")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: Self.timeout), "The note is not in the folder")

        // Back to the folders: the count of the folder follows; then the search finds the note.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["Brain Dump, 1"].waitForExistence(timeout: Self.timeout), "The folder count did not change")
        tab("Planen")
        openSearch(typing: "UI-Test Notiz")
        let hit = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Notiz, UI-Test Notiz")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 20), "The search did not find the note")
    }
}
