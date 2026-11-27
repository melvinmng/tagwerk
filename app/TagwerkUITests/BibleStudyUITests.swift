import XCTest

/// Bible Study (BS2b, BV1b, BV3a): the start sheet. The demo data holds a completed session of Römer that ended on the last verse
/// of chapter 3, so the suggestion is 4,1.
@MainActor
final class BibleStudyUITests: UITestCase {
    /// Aufgaben › Notizen › Bible Study. The folder sits in the section "Persönlich" below the fold of the overview.
    private func openBibleStudyFolder(file: StaticString = #filePath, line: UInt = #line) {
        openNotes(file: file, line: line)
        let folder = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Bible Study")).firstMatch
        scrollTo(folder, file: file, line: line)
        folder.tap()
    }

    /// Aufgaben › Notizen › Bible Study › "Bible Study starten".
    private func openStartSheet(file: StaticString = #filePath, line: UInt = #line) {
        openBibleStudyFolder(file: file, line: line)
        let start = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Bible Study starten")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: Self.timeout), "\"Bible Study starten\" is missing", file: file, line: line)
        start.tap()
        XCTAssertTrue(app.navigationBars["Bible Study starten"].waitForExistence(timeout: Self.timeout), "The start sheet did not open",
                      file: file, line: line)
    }

    /// BV3a: the sheet offers the verse after the last session and names where it comes from.
    func testStartSheetSuggestsNextVerse() {
        openStartSheet()
        let start = app.buttons["bibleStudy.start"]
        XCTAssertTrue(start.waitForExistence(timeout: Self.timeout), "The start button is missing")
        XCTAssertEqual(start.label, "Sitzung starten · Römer 4,1")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Kapitel 3 ist gelesen")).firstMatch.exists,
                      "The hint about the last session is missing")
    }

    /// BS2b: "Anderes …" opens the list of books; the search finds a book by its abbreviation, and one tap on the result chooses it
    /// while the keyboard is still open.
    func testOtherBookSearchFindsAlias() {
        openStartSheet()
        tapButton("Anderes …")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: Self.timeout), "The search field is missing")
        search.tap()
        search.typeText("Offb")
        let book = app.buttons["Offenbarung"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: Self.timeout), "The search did not find Offenbarung by its abbreviation")
        // One tap on the result while the keyboard is open has to choose the book (the keyboard closes with that tap, the sheet shrinks
        // to its medium detent afterwards): the keyboard dismissal of `KeyboardDismissal.swift` must not swallow the first tap.
        XCTAssertTrue(app.keyboards.firstMatch.exists, "The keyboard should still be open when the result is tapped")
        book.tap()
        let start = app.buttons["bibleStudy.start"]
        XCTAssertTrue(start.waitForExistence(timeout: Self.timeout), "The start sheet did not come back after choosing the book")
        XCTAssertEqual(start.label, "Sitzung starten · Offenbarung 1,1", "The start button does not name the chosen book")
        // #308: the chosen book is the first, selected chip; the book read last stays as the next one.
        let chips = app.buttons.matching(NSPredicate(format: "label IN %@", ["Offenbarung", "Römer"])).allElementsBoundByIndex
        XCTAssertEqual(chips.first?.label, "Offenbarung", "The chosen book is not the first chip")
        XCTAssertTrue(chips.first?.isSelected ?? false, "The chip of the chosen book is not selected")
        XCTAssertEqual(chips.dropFirst().first?.label, "Römer", "The book read last is missing from the chips")
    }

    /// #306: "Heute nicht" in the start sheet closes it (the reminder of today is dropped, as with the action of the notification).
    func testStartSheetOffersNotToday() {
        openStartSheet()
        tapButton("bibleStudy.skipToday")
        waitUntilGone(app.navigationBars["Bible Study starten"])
    }

    // MARK: Running session (BS1b, BV2b)

    /// Starts the suggested session of Römer; the note opens with the bar of the running session above its text.
    private func startSuggestedSession(file: StaticString = #filePath, line: UInt = #line) {
        openStartSheet(file: file, line: line)
        tapButton("bibleStudy.start", file: file, line: line)
        XCTAssertTrue(app.buttons["bibleSession.complete"].waitForExistence(timeout: Self.timeout), "The bar of the running session is missing",
                      file: file, line: line)
    }

    /// Back from the note to the list of the folder.
    private func leaveNote(file: StaticString = #filePath, line: UInt = #line) {
        let back = app.navigationBars.firstMatch.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: Self.timeout), "No way back from the note", file: file, line: line)
        back.tap()
    }

    /// BV2b: "Abschließen" opens the wheels; confirming completes the session, completes the heading and the bar goes.
    func testSessionBarCompletesWithChosenEnd() {
        startSuggestedSession()
        tapButton("bibleSession.complete")
        let confirm = app.buttons["bibleSession.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: Self.timeout), "The question \"Bis wohin gelesen?\" did not open")
        XCTAssertTrue(confirm.label.hasPrefix("Abschließen · 4,1–"), "The button names the offered end: \(confirm.label)")
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Sitzung abgeschlossen ✓"].waitForExistence(timeout: Self.timeout), "The bar did not confirm the end")
        waitUntilGone(app.buttons["bibleSession.complete"])
        let heading = app.textViews.firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: Self.timeout), "The note of the session has no text view")
        XCTAssertTrue((heading.value as? String)?.range(of: "· 4,1–[0-9]+", options: .regularExpression) != nil,
                      "The heading of the section was not completed")
    }

    /// #305: writing in a running session must never close the note. The note saves half a second after the last keystroke; every
    /// pause longer than that writes to the store, so the page has to stay when the stored text changes underneath it.
    func testRunningSessionStaysOpenWhileTyping() {
        startSuggestedSession()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: Self.timeout), "The note of the session has no text view")
        editor.tap()
        for round in 1...5 {
            editor.typeText("Gedanke \(round). ")
            // A real wait on purpose: the autosave is a timer, no element query can express it. Longer than its delay of 500 ms,
            // so the text is stored between the rounds.
            RunLoop.current.run(until: Date().addingTimeInterval(1.2))
            XCTAssertTrue(app.buttons["bibleSession.complete"].exists, "The note closed by itself after round \(round)")
            XCTAssertTrue(app.textViews.firstMatch.exists, "The text view is gone after round \(round)")
        }
        let text = app.textViews.firstMatch.value as? String ?? ""
        XCTAssertTrue(text.contains("Gedanke 5."), "The typed text is missing: \(text)")
    }

    /// Leaving the note keeps the session open: the folder list still offers to complete it.
    func testLeavingKeepsSessionOpen() {
        startSuggestedSession()
        leaveNote()
        XCTAssertTrue(app.staticTexts["Sitzung läuft"].waitForExistence(timeout: Self.timeout), "The open session is gone from the list")
    }

    /// "Abschließen" in the folder list asks the same question.
    func testCompleteFromFolderList() {
        startSuggestedSession()
        leaveNote()
        let complete = app.buttons["Abschließen"].firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: Self.timeout), "The list has no \"Abschließen\"")
        complete.tap()
        let confirm = app.buttons["bibleSession.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: Self.timeout), "The question \"Bis wohin gelesen?\" did not open")
        confirm.tap()
        waitUntilGone(app.staticTexts["Sitzung läuft"])
    }

    // MARK: Task from a checkbox (BS5b, #307)

    /// A running session whose note holds one checkbox line, shown as a page ("Fertig" closes the keyboard and the text field).
    private func startSessionWithCheckbox(file: StaticString = #filePath, line: UInt = #line) {
        startSuggestedSession(file: file, line: line)
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: Self.timeout), "The note of the session has no text view", file: file, line: line)
        editor.tap()
        // Typing before the text view has the focus loses keystrokes, and "Fertig" then closes an editor without the checkbox line.
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: Self.timeout), "The text view did not take the focus", file: file, line: line)
        // The tap puts the cursor where it lands, so the checkbox starts on a line of its own whatever came before.
        editor.typeText("\n- [ ] nochmal lesen")
        eventually("The checkbox line did not reach the text view", file: file, line: line) {
            (editor.value as? String)?.contains("- [ ] nochmal lesen") == true
        }
        tapButton("Fertig", file: file, line: line)
    }

    private func pageText(_ text: String) -> XCUIElement {
        app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// A long press on the box of the first checkbox offers "Als Aufgabe anlegen"; the hint comes before the sheet.
    private func askForTaskOnFirstCheckbox(file: StaticString = #filePath, line: UInt = #line) {
        let box = app.webViews.descendants(matching: .any).matching(NSPredicate(format: "elementType == %d", XCUIElement.ElementType.switch.rawValue)).firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: Self.timeout), "The checkbox is missing", file: file, line: line)
        box.press(forDuration: 1.0)
        let action = app.buttons["Als Aufgabe anlegen"].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: Self.timeout), "The long press did not open the menu of the checkbox", file: file, line: line)
        action.tap()
        XCTAssertTrue(app.staticTexts["Der Titel wird eine normale Aufgabe und ist dann nicht mehr privat (Erinnerungen, Assistent)."]
            .waitForExistence(timeout: Self.timeout), "The hint about the private title is missing", file: file, line: line)
        tapButton("Weiter", file: file, line: line)
    }

    /// #307: the long press on a checkbox of the page creates a task; the line gets the marker "→ Aufgabe" once the task exists.
    func testLongPressOnCheckboxCreatesTask() {
        startSessionWithCheckbox()
        XCTAssertFalse(pageText("→ Aufgabe").exists)
        askForTaskOnFirstCheckbox()
        tapButton("Hinzufügen")
        XCTAssertTrue(pageText("→ Aufgabe").waitForExistence(timeout: Self.timeout), "The line was not marked")
    }

    /// Cancelling the sheet creates nothing and leaves the line without the marker.
    func testCancelLeavesLineUnmarked() {
        startSessionWithCheckbox()
        askForTaskOnFirstCheckbox()
        tapButton("Abbrechen")
        XCTAssertTrue(pageText("nochmal lesen").waitForExistence(timeout: Self.timeout))
        XCTAssertFalse(pageText("→ Aufgabe").exists, "The line was marked although no task was created")
    }

    /// #307 (2A): "Als Aufgabe" in the bar above the keyboard turns the checkbox line at the cursor into a task, and only that line.
    func testBarButtonCreatesTaskFromCheckboxLineAtCursor() {
        startSuggestedSession()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: Self.timeout), "The note of the session has no text view")
        editor.tap()
        editor.typeText("\nnur Text")
        let button = app.buttons[AccessibilityID.NoteEditor.checkboxTaskButton]
        XCTAssertTrue(button.waitForExistence(timeout: Self.timeout), "The bar has no \"Als Aufgabe\"")
        XCTAssertFalse(button.isEnabled, "\"Als Aufgabe\" must be disabled in a line without a checkbox")
        editor.typeText("\n- [ ] nochmal lesen")
        eventually("\"Als Aufgabe\" did not get enabled in the checkbox line") { button.isEnabled }
        button.tap()
        XCTAssertTrue(app.staticTexts["Der Titel wird eine normale Aufgabe und ist dann nicht mehr privat (Erinnerungen, Assistent)."]
            .waitForExistence(timeout: Self.timeout), "The hint about the private title is missing")
        tapButton("Weiter")
        tapButton("Hinzufügen")
        eventually("The line was not marked") { (app.textViews.firstMatch.value as? String)?.contains("nochmal lesen → Aufgabe") == true }
    }

    // MARK: Capsule above the tab bar (2B) and row in "Aufgaben" (1B, #306)

    private var capsule: XCUIElement { app.descendants(matching: .any)["bibleSession.capsule"].firstMatch }

    /// 2B: while a session is open, every tab shows the capsule; a tap leads back into the note, where the bar of the session says
    /// the same, so the capsule is not shown there.
    func testSessionCapsuleLeadsBackIntoTheNote() {
        startSuggestedSession()
        XCTAssertFalse(capsule.exists, "The note shows the bar of the session itself; the capsule must not repeat it")
        tab("Planen")
        XCTAssertTrue(capsule.waitForExistence(timeout: Self.timeout), "The capsule of the running session is missing in another tab")
        capsule.tap()
        XCTAssertTrue(app.buttons["bibleSession.complete"].waitForExistence(timeout: Self.timeout), "The capsule did not lead back into the note")
        waitUntilGone(capsule)
    }

    /// 2B: without a running session there is no capsule.
    func testNoCapsuleWithoutSession() {
        tab("Planen")
        XCTAssertFalse(capsule.waitForExistence(timeout: 3), "The capsule shows although no session is open")
    }

    /// 1B: the plain row "Bible Study" in "Aufgaben" opens the start sheet while no session runs.
    func testTasksRowOpensTheStartSheet() {
        tab("Aufgaben")
        let row = app.buttons["tasks.bibleStudy"]
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout), "The row \"Bible Study\" is missing in Aufgaben")
        row.tap()
        XCTAssertTrue(app.navigationBars["Bible Study starten"].waitForExistence(timeout: Self.timeout), "The start sheet did not open")
    }

    /// 1B: with a session running the row leads into its note.
    func testTasksRowLeadsIntoTheRunningSession() {
        startSuggestedSession()
        // Back to the root of "Aufgaben": note, folder, notes overview.
        for _ in 0..<3 { leaveNote() }
        tapButton("tasks.bibleStudy")
        XCTAssertTrue(app.buttons["bibleSession.complete"].waitForExistence(timeout: Self.timeout), "The row did not lead into the note")
    }
}
