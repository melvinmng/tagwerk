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

    /// The row "Erinnerungen" appears in the sheet once a due date is set, shows the default and opens the selection page.
    func testNewTaskOffersRemindersOnceDueIsSet() {
        tab("Aufgaben")
        tapButton("Neue Aufgabe")
        onScreen(label: "Lokal").tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Erinnerungen'"))
        // The tab behind a sheet stays in the tree, so only elements on screen count.
        XCTAssertTrue(row.allElementsBoundByIndex.filter(\.isHittable).isEmpty, "The reminders row must not show before a due date is set")

        let due = app.switches["Fällig"].firstMatch
        XCTAssertTrue(due.waitForExistence(timeout: Self.timeout), "The due switch is missing")
        // The switch sits at the right end of its row; a tap in the middle of the row does not reach it.
        due.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(due.value as? String, "1", "The due switch did not turn on")
        // The row says "Standard" while the default applies.
        let reminders = onScreen(.any, label: "Erinnerungen.*Standard.*", matching: true)
        reminders.tap()
        waitFor("Antippen setzt oder entfernt eine Erinnerung.")
        XCTAssertTrue(app.buttons["Eigene …"].firstMatch.exists, "The page does not offer an own reminder")
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
