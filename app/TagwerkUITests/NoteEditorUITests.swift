import XCTest

/// The note editor: the rendered page shows, a tap on its text writes at that line, "Fertig" shows the page again.
final class NoteEditorUITests: UITestCase {
    private static let demoText = "Ideen Hausarbeit\nGliederung überarbeiten\nZwei weitere Quellen suchen"

    /// Opens the demo note "Ideen Hausarbeit" (three lines) from the list of all standard notes; it opens as a page.
    private func openDemoNote(file: StaticString = #filePath, line: UInt = #line) {
        openNotes(file: file, line: line)
        let folder = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Notizen, ")).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: Self.timeout), "The folder \"Notizen\" is missing", file: file, line: line)
        folder.tap()
        let note = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Ideen Hausarbeit")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: Self.timeout), "The demo note is missing", file: file, line: line)
        note.tap()
        XCTAssertTrue(app.buttons["Mehr"].firstMatch.waitForExistence(timeout: Self.timeout), "The note did not open", file: file, line: line)
    }

    /// An element of the rendered page (a link of the web view) with this label.
    private func pageText(_ label: String) -> XCUIElement {
        app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private var editorText: String? { app.textViews.firstMatch.value as? String }

    func testTapOnLineOpensEditorThere() {
        openDemoNote()
        let second = pageText("Gliederung überarbeiten")
        XCTAssertTrue(second.waitForExistence(timeout: 3 * Self.timeout), "The page does not show the second line")
        XCTAssertFalse(app.buttons["Fertig"].exists, "The page is already in the writing mode")
        second.tap()
        XCTAssertTrue(app.buttons["Fertig"].waitForExistence(timeout: Self.timeout), "A tap on the text did not start writing")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: Self.timeout), "The keyboard did not come up")
        app.typeText("X")
        let expected = "Ideen Hausarbeit\nGliederung überarbeitenX\nZwei weitere Quellen suchen"
        eventually("The X is not at the end of the tapped line: \(editorText ?? "nil")") { editorText == expected }
    }

    func testTapOnCheckboxTogglesAndStaysInView() {
        openNotes()
        let folder = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Brain Dump")).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: Self.timeout))
        folder.tap()
        typeIn("Neue Notiz", text: "- [ ] Milch kaufen")
        tapButton("Notiz sichern")
        let note = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Milch kaufen")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: Self.timeout), "The note is not in the folder")
        note.tap()
        let box = app.webViews.descendants(matching: .any).matching(NSPredicate(format: "elementType == %d", XCUIElement.ElementType.switch.rawValue)).firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 3 * Self.timeout), "The page shows no checkbox")
        XCTAssertEqual(box.value as? String, "0")
        box.tap()
        eventually("The checkbox did not flip") {
            let flipped = self.app.webViews.descendants(matching: .any).matching(NSPredicate(format: "elementType == %d", XCUIElement.ElementType.switch.rawValue)).firstMatch
            return flipped.exists && flipped.value as? String == "1"
        }
        XCTAssertFalse(app.buttons["Fertig"].exists, "A tap on the checkbox started writing")
    }

    func testDoneReturnsToView() {
        openDemoNote()
        let second = pageText("Gliederung überarbeiten")
        XCTAssertTrue(second.waitForExistence(timeout: 3 * Self.timeout))
        second.tap()
        let done = app.buttons["Fertig"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout))
        done.tap()
        XCTAssertTrue(pageText("Gliederung überarbeiten").waitForExistence(timeout: 3 * Self.timeout), "The page is not back")
        XCTAssertFalse(app.buttons["Fertig"].exists)
        XCTAssertFalse(app.textViews.firstMatch.exists, "The text field is still there")
    }

    func testEmptyNoteOpensForWriting() {
        openNotes()
        let recipes = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Rezepte")).firstMatch
        XCTAssertTrue(recipes.waitForExistence(timeout: Self.timeout), "The folder \"Rezepte\" is missing")
        recipes.tap()
        // A new recipe is the untouched template: it opens for writing.
        tapButton("Neues Rezept")
        XCTAssertTrue(app.buttons["Fertig"].waitForExistence(timeout: Self.timeout), "The untouched note did not open for writing")
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: Self.timeout))
    }

    func testEditFromMenu() {
        openDemoNote()
        XCTAssertFalse(app.buttons["Fertig"].exists)
        app.buttons["Mehr"].firstMatch.tap()
        tapButton("Bearbeiten")
        XCTAssertTrue(app.buttons["Fertig"].waitForExistence(timeout: Self.timeout), "The menu entry did not start writing")
        XCTAssertEqual(editorText, Self.demoText, "The text field shows another text")
    }
}
