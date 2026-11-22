import XCTest

/// Scanning, drawing and tables in the note editor. The document camera does not exist in the simulator, so the app is
/// started with `-TagwerkUITestScan 2`: "Dokument scannen" then delivers two test pages instead of opening the camera.
final class NoteInsertUITests: UITestCase {
    override var extraLaunchArguments: [String] { ["-TagwerkUITestScan", "2"] }

    /// Opens the demo note "Ideen Hausarbeit" and starts writing at its second line, so the bar above the keyboard shows.
    private func openDemoNoteForWriting(file: StaticString = #filePath, line: UInt = #line) {
        openNotes(file: file, line: line)
        let folder = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Notizen, ")).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: Self.timeout), "The folder \"Notizen\" is missing", file: file, line: line)
        folder.tap()
        let note = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Ideen Hausarbeit")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: Self.timeout), "The demo note is missing", file: file, line: line)
        note.tap()
        let second = pageText("Gliederung überarbeiten")
        XCTAssertTrue(second.waitForExistence(timeout: 3 * Self.timeout), "The page does not show the second line", file: file, line: line)
        second.tap()
        XCTAssertTrue(app.buttons[AccessibilityID.NoteEditor.insertMenu].waitForExistence(timeout: Self.timeout), "The bar above the keyboard did not show",
                      file: file, line: line)
    }

    /// An element of the rendered page (a link of the web view) whose label contains the text.
    private func pageElement(containing text: String) -> XCUIElement {
        app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func pageText(_ label: String) -> XCUIElement {
        app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private var editorText: String? { app.textViews.firstMatch.value as? String }

    func testScanInsertsPdfCardWithPreview() {
        openDemoNoteForWriting()
        app.buttons[AccessibilityID.NoteEditor.insertMenu].tap()
        tapButton("Dokument scannen")
        eventually("The reference of the scan is not in the text: \(editorText ?? "nil")") { editorText?.contains("](attachment:") == true }
        // The reference stands in its own line, below the line of the cursor.
        XCTAssertTrue(editorText?.contains("Gliederung überarbeiten\n[Scan ") == true, "The scan is not in its own line: \(editorText ?? "nil")")
        tapButton("Fertig")
        let card = pageElement(containing: "2 Seiten")
        XCTAssertTrue(card.waitForExistence(timeout: 3 * Self.timeout), "The page shows no card for the scan")
        XCTAssertTrue(card.label.contains("Scan "), "The card does not show the name of the scan: \(card.label)")
        XCTAssertTrue(card.label.contains("PDF"), "The card does not name the file type: \(card.label)")
    }

    // MARK: Drawing

    /// A stroke across the middle of the screen, on the canvas.
    private func drawStroke() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.45))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.6))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    private func occurrences(of text: String, in string: String?) -> Int {
        (string ?? "").components(separatedBy: text).count - 1
    }

    /// Draws a stroke on a new canvas and puts the drawing into the note.
    private func insertDrawing() {
        app.buttons[AccessibilityID.NoteEditor.insertMenu].tap()
        tapButton("Zeichnung")
        let done = app.buttons[AccessibilityID.NoteEditor.drawingDone]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout), "The canvas did not open")
        drawStroke()
        done.tap()
        eventually("The reference of the drawing is not in the text: \(editorText ?? "nil")") { editorText?.contains("![Zeichnung](attachment:") == true }
    }

    func testDrawAndSeeDrawingInNote() {
        openDemoNoteForWriting()
        insertDrawing()
        XCTAssertTrue(editorText?.contains("Gliederung überarbeiten\n![Zeichnung](") == true, "The drawing is not in its own line: \(editorText ?? "nil")")
        tapButton("Fertig")
        XCTAssertTrue(app.webViews.images.firstMatch.waitForExistence(timeout: 3 * Self.timeout), "The page shows no picture for the drawing")
    }

    func testEmptyDrawingInsertsNothing() {
        openDemoNoteForWriting()
        let before = editorText
        app.buttons[AccessibilityID.NoteEditor.insertMenu].tap()
        tapButton("Zeichnung")
        let done = app.buttons[AccessibilityID.NoteEditor.drawingDone]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout), "The canvas did not open")
        done.tap()
        eventually("The canvas did not close") { !done.exists }
        XCTAssertEqual(editorText, before, "An empty drawing changed the text")
    }

    func testEditDrawingKeepsSingleReference() {
        openDemoNoteForWriting()
        insertDrawing()
        tapButton("Fertig")
        let picture = app.webViews.images.firstMatch
        XCTAssertTrue(picture.waitForExistence(timeout: 3 * Self.timeout), "The page shows no picture for the drawing")
        picture.tap()
        let edit = app.buttons[AccessibilityID.NoteEditor.drawingEdit]
        XCTAssertTrue(edit.waitForExistence(timeout: Self.timeout), "A tap on the drawing did not open the viewer")
        edit.tap()
        let done = app.buttons[AccessibilityID.NoteEditor.drawingDone]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout), "\"Bearbeiten\" did not open the canvas")
        drawStroke()
        done.tap()
        eventually("The canvas did not close") { !done.exists }
        // Back in the viewer; "Fertig" closes it.
        tapButton("Fertig")
        app.buttons["Mehr"].firstMatch.tap()
        tapButton("Bearbeiten")
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: Self.timeout))
        XCTAssertEqual(occurrences(of: "attachment:", in: editorText), 1, "Editing the drawing changed the number of references: \(editorText ?? "nil")")
    }
}
