import XCTest

final class TaskFlowUITests: UITestCase {
    /// Pinned to the morning (09:30), so the morning card, the hour grid and the wrap-up give the same result at every hour of the day,
    /// also shortly before midnight.
    override var extraLaunchArguments: [String] { Self.morningClockArguments }

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

    /// The running session stays visible above the tabs; a tap on the bar brings the sheet back (FO5b).
    func testFocusBarReturnsToTheSheet() {
        tab("Aufgaben")
        tapButton("Neue Aufgabe")
        onScreen(label: "Lokal").tap()
        typeIn("Titel", text: "UI-Test Leiste")
        tapButton("Hinzufügen")
        let created = app.descendants(matching: .any)[AccessibilityID.Tasks.row("UI-Test Leiste")]
        scrollTo(created)
        created.press(forDuration: 1.0)
        onScreen(label: "Fokus starten · 25 min").tap()
        onScreen(label: "Starten").tap()
        XCTAssertTrue(app.buttons[AccessibilityID.Focus.pause].waitForExistence(timeout: Self.timeout))
        onScreen(label: "Schließen").tap()

        // The bar is there in another tab, too, and opens the sheet again.
        tab("Planen")
        let bar = app.descendants(matching: .any)[AccessibilityID.Focus.bar]
        XCTAssertTrue(bar.waitForExistence(timeout: Self.timeout), "The focus bar is shown above the tabs")
        tab("Aufgaben")
        XCTAssertTrue(bar.waitForExistence(timeout: Self.timeout))
        bar.tap()
        XCTAssertTrue(app.buttons[AccessibilityID.Focus.pause].waitForExistence(timeout: Self.timeout))
        // "Erledigt" ends the session at once, however long the test took. "Beenden" asks for confirmation after the first
        // minute, so using it here would make the test depend on the speed of the run.
        app.buttons[AccessibilityID.Focus.done].tap()
        waitUntilGone(bar)
    }

    /// The keyboard of the task sheet, in one launch: the Return key of single-line fields reads "Fertig" (the root view sets it, also
    /// inside sheets, #188 TA1a), a multi-line field keeps "return", the button above the keyboard is a symbol ("Tastatur ausblenden"),
    /// there is no second "Fertig", and the sheet stays open when the keyboard closes.
    func testKeyboardReturnKeyAndHideButton() {
        tab("Aufgaben")
        tapButton("Neue Aufgabe")
        onScreen(label: "Lokal").tap()
        typeIn("Titel", text: "UI-Test")
        XCTAssertTrue(app.keyboards.buttons["Fertig"].waitForExistence(timeout: Self.timeout),
                      "The Return key of the title field does not read \"Fertig\"")
        typeIn("Notiz", text: "UI-Test")
        // Neither the Return key of the multi-line field nor the button above the keyboard may read "Fertig".
        XCTAssertTrue(app.buttons["Fertig"].waitForNonExistence(timeout: Self.timeout),
                      "The Return key of the multi-line field or the keyboard button reads \"Fertig\"")
        XCTAssertTrue(app.keyboards.firstMatch.exists, "The keyboard did not stay up for the note")
        tapButton("Tastatur ausblenden")
        waitUntilGone(app.keyboards.firstMatch)
        XCTAssertTrue(app.textFields["Titel"].exists, "The sheet closed with the keyboard")
    }
}
