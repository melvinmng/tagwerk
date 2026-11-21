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

    /// The focus sheet of a task offers "Erledigt" while the timer runs (FO1b). Ending within the first minute needs no
    /// question and leaves nothing behind, so the confirmation "Fokus beenden?" is covered by the model tests, not here.
    func testFocusSheetOffersDoneWhileRunning() {
        tab("Aufgaben")
        tapButton("Neue Aufgabe")
        onScreen(label: "Lokal").tap()
        typeIn("Titel", text: "UI-Test Fokus")
        tapButton("Hinzufügen")
        let created = app.descendants(matching: .any)[AccessibilityID.Tasks.row("UI-Test Fokus")]
        scrollTo(created)
        created.press(forDuration: 1.0)
        // The menu entry names the planned minutes; the start sheet follows.
        onScreen(label: "Fokus starten · 25 min").tap()
        onScreen(label: "Starten").tap()

        // The task list behind the sheet has its own "Erledigt" buttons, so the sheet's buttons are found by identifier.
        let done = app.buttons[AccessibilityID.Focus.done]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout), "Erledigt is offered while the timer runs")
        XCTAssertEqual(done.label, "Erledigt")
        XCTAssertTrue(app.buttons[AccessibilityID.Focus.pause].exists)
        XCTAssertTrue(app.buttons[AccessibilityID.Focus.stop].exists)
        XCTAssertTrue(onScreen(.staticText, label: "UI-Test Fokus").exists)

        // "Erledigt" completes the task during the phase and closes the sheet.
        done.tap()
        waitUntilGone(app.buttons[AccessibilityID.Focus.pause])
    }
}
