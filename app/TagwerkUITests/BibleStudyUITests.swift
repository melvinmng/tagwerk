import XCTest

/// Bible Study (BS2b, BV1b, BV3a): the start sheet. The demo data holds a completed session of Römer that ended on the last verse
/// of chapter 3, so the suggestion is 4,1.
@MainActor
final class BibleStudyUITests: UITestCase {
    /// Aufgaben › Notizen › Bible Study › "Bible Study starten".
    private func openStartSheet(file: StaticString = #filePath, line: UInt = #line) {
        openNotes(file: file, line: line)
        let folder = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Bible Study")).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: Self.timeout), "The folder \"Bible Study\" is missing", file: file, line: line)
        folder.tap()
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

    /// BS2b: "Anderes …" opens the list of books; the search finds a book by its abbreviation.
    func testOtherBookSearchFindsAlias() {
        openStartSheet()
        tapButton("Anderes …")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: Self.timeout), "The search field is missing")
        search.tap()
        search.typeText("Offb")
        let book = app.buttons["Offenbarung"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: Self.timeout), "The search did not find Offenbarung by its abbreviation")
        book.tap()
        let start = app.buttons["bibleStudy.start"]
        XCTAssertTrue(start.waitForExistence(timeout: Self.timeout))
        XCTAssertEqual(start.label, "Sitzung starten · Offenbarung 1,1")
    }
}
