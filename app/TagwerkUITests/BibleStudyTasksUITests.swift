import XCTest

/// Bible Study: tasks from the checkboxes of a session note (BS5b, #307), the capsule above the tab bar (2B) and the row in
/// "Aufgaben" (1B, #306). Split off `BibleStudyUITests` so the shards of the UI test job can balance the two halves; the steps to
/// reach the session are in `BibleStudyUITestCase`.
@MainActor
final class BibleStudyTasksUITests: BibleStudyUITestCase {
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
