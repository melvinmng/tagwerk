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
}
