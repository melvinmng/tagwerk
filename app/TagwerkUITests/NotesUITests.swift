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

    /// NO3b: the plus button in the row "Brain Dump" opens an empty note for writing; leaving it without text creates no note.
    func testBrainDumpPlusOpensEmptyNoteForWriting() {
        openNotes()
        let plus = app.buttons["Neue Notiz in Brain Dump"].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: Self.timeout), "The row Brain Dump has no plus button")
        XCTAssertTrue(app.buttons["Brain Dump, 0"].exists, "The demo data already has a Brain Dump note")
        plus.tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: Self.timeout), "The empty note did not open for writing")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["Brain Dump, 0"].waitForExistence(timeout: Self.timeout), "The empty note was kept")
    }

    func testShowNoteInFolderFromSearchHit() {
        openNotes()
        let folder = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Brain Dump")).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: Self.timeout))
        folder.tap()
        typeIn("Neue Notiz", text: "Ordner-Sprung Notiz")
        tapButton("Notiz sichern")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Ordner-Sprung Notiz")).firstMatch
            .waitForExistence(timeout: Self.timeout), "The note is not in the folder")
        app.navigationBars.buttons.firstMatch.tap()
        tab("Planen")
        openSearch(typing: "Ordner-Sprung Notiz")
        let hit = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Notiz, Ordner-Sprung Notiz")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 20), "The search did not find the note")
        hit.press(forDuration: 1.0)
        let show = app.buttons["Im Ordner zeigen"].firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: Self.timeout), "The menu has no entry \"Im Ordner zeigen\"")
        show.tap()
        // The search closes and "Aufgaben" shows the list of the folder with the note.
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Ordner-Sprung Notiz")).firstMatch
            .waitForExistence(timeout: Self.timeout), "The folder list with the note did not open")
        XCTAssertFalse(app.textFields["Suchen"].exists, "The search sheet is still open")
    }

    /// The assistant button of the notes: without the consent it shows the sheet first, "Einverstanden" opens the chat with its
    /// context line (#233; the chat runs on the demo transport, nothing is sent).
    func testNotesAssistantConsentThenChat() {
        openNotes()
        let assistant = app.buttons["Assistent"].firstMatch
        XCTAssertTrue(assistant.waitForExistence(timeout: Self.timeout), "The notes overview has no assistant button")
        assistant.tap()
        XCTAssertTrue(app.staticTexts["Notizen mit ChatGPT"].waitForExistence(timeout: Self.timeout), "The consent sheet did not show")
        tapButton("Einverstanden")
        let context = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Notizen · ohne")).firstMatch
        XCTAssertTrue(context.waitForExistence(timeout: Self.timeout), "The notes chat did not open with its context line")
        XCTAssertTrue(context.label.contains("Tagebuch mit Gott"), "The context line does not name the private folders: \(context.label)")
    }
}
