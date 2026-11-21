import XCTest

final class TaskFlowUITests: UITestCase {
    func testCreateEditCompleteUndo() {
        tab("Aufgaben")
        tapButton("Neue Aufgabe")

        // A local task: no calendar or reminder write, so the list of the demo data stays as it is.
        onScreen(label: "Lokal").tap()
        typeIn("Titel", text: "UI-Test Aufgabe")
        tapButton("Hinzufügen")
        let created = app.descendants(matching: .any)[AccessibilityID.Tasks.row("UI-Test Aufgabe")]
        // A task without a due date sits at the end of the list, which builds its rows only when scrolled to.
        scrollTo(created)

        // Edit: change the title in the editor.
        created.tap()
        replaceText(of: app.textFields[AccessibilityID.Tasks.editorTitle].firstMatch, with: "UI-Test Aufgabe geändert")
        tapButton("Sichern")
        let edited = app.descendants(matching: .any)[AccessibilityID.Tasks.row("UI-Test Aufgabe geändert")]
        scrollTo(edited)
        waitUntilGone(created)

        // Complete with the swipe action; the capsule offers "Rückgängig".
        edited.swipeRight()
        tapButton("Erledigt")
        waitUntilGone(edited)
        tapButton("Rückgängig")
        scrollTo(edited)
    }

    /// The button above the keyboard is a symbol ("Tastatur ausblenden"), there is no second "Fertig", and the sheet stays open.
    func testKeyboardButtonHidesKeyboard() {
        tab("Aufgaben")
        tapButton("Neue Aufgabe")
        onScreen(label: "Lokal").tap()
        typeIn("Notiz", text: "UI-Test")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: Self.timeout), "The keyboard did not appear")
        XCTAssertFalse(app.buttons["Fertig"].exists, "The keyboard button must not be labelled \"Fertig\" any more")
        tapButton("Tastatur ausblenden")
        waitUntilGone(app.keyboards.firstMatch)
        XCTAssertTrue(app.textFields["Titel"].exists, "The sheet closed with the keyboard")
    }

    /// The root view sets the Return key of single-line fields to "Fertig", also inside sheets; a multi-line field keeps "return".
    func testReturnKeyReadsFertigInSingleLineFields() {
        tab("Aufgaben")
        tapButton("Neue Aufgabe")
        onScreen(label: "Lokal").tap()
        typeIn("Titel", text: "UI-Test")
        XCTAssertTrue(app.keyboards.buttons["Fertig"].waitForExistence(timeout: Self.timeout),
                      "The Return key of the title field does not read \"Fertig\"")
        typeIn("Notiz", text: "UI-Test")
        XCTAssertTrue(app.keyboards.buttons["Fertig"].waitForNonExistence(timeout: Self.timeout),
                      "The Return key of the multi-line field must not read \"Fertig\"")
    }
}
