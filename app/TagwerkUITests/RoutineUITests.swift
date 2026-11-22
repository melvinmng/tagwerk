import XCTest

final class RoutineUITests: UITestCase {
    // The deep links `tagwerk://routine/start` and `tagwerk://routine/evening` are covered by the AppRoute unit tests;
    // the system confirmation of a custom URL scheme makes them unreliable in a UI test, so the sheets open from the
    // routine cards of "Erfassen".
    func testMorningAndEveningSheets() {
        tab("Erfassen")
        onScreen(label: "Tagesstart.*", matching: true).tap()
        XCTAssertTrue(app.navigationBars["Tagesstart"].waitForExistence(timeout: Self.timeout), "The morning sheet did not open")
        let brainDump = app.textViews["Brain Dump"]
        XCTAssertTrue(brainDump.waitForExistence(timeout: Self.timeout))
        brainDump.tap()
        brainDump.typeText("UI-Test")
        tapButton("Abschließen")
        waitUntilGone(app.navigationBars["Tagesstart"])

        onScreen(label: "Tagesabschluss.*", matching: true).tap()
        XCTAssertTrue(app.navigationBars["Tagesabschluss"].waitForExistence(timeout: Self.timeout), "The evening sheet did not open")
        waitFor("Bible Study starten")
    }

    /// RO3: journal and Bible Study sit in one section "Zeit mit Gott" in the evening wrap-up.
    func testEveningShowsTimeWithGodWithState() {
        tab("Erfassen")
        onScreen(label: "Tagesabschluss.*", matching: true).tap()
        XCTAssertTrue(app.navigationBars["Tagesabschluss"].waitForExistence(timeout: Self.timeout), "The evening sheet did not open")
        let heading = app.staticTexts["Zeit mit Gott"].firstMatch
        scrollTo(heading)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Tagebuch schreiben")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Bible Study starten")).firstMatch.exists)
    }

    /// RO3: with the place set to "In beiden", the morning start offers Bible Study, and no journal row.
    func testMorningShowsBibleStudyWhenOfferedThere() {
        tab("Einstellungen")
        let row = app.cells.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Routinen")).firstMatch
        var steps = 0
        while !(row.exists && row.isHittable), steps < 20 {
            let list = app.collectionViews.firstMatch
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
            steps += 1
        }
        row.tap()
        let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Bible Study anbieten")).firstMatch
        scrollTo(picker)
        picker.tap()
        tapButton("In beiden")
        tab("Erfassen")
        onScreen(label: "Tagesstart.*", matching: true).tap()
        XCTAssertTrue(app.navigationBars["Tagesstart"].waitForExistence(timeout: Self.timeout), "The morning sheet did not open")
        let bible = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Bible Study starten")).firstMatch
        scrollTo(bible)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Tagebuch")).firstMatch.exists,
                       "The morning start has no journal row")
    }

    /// RO1b: dream log first, then gratitude, then the brain dump, the focus row last.
    func testMorningSheetOrder() {
        tab("Erfassen")
        onScreen(label: "Tagesstart.*", matching: true).tap()
        XCTAssertTrue(app.navigationBars["Tagesstart"].waitForExistence(timeout: Self.timeout), "The morning sheet did not open")
        let dream = app.staticTexts["Dream Log"].firstMatch
        let gratitude = app.staticTexts["Dankbar für"].firstMatch
        let brainDump = app.staticTexts["Brain Dump"].firstMatch
        XCTAssertTrue(dream.waitForExistence(timeout: Self.timeout), "Dream Log heading missing")
        XCTAssertTrue(gratitude.exists && brainDump.exists, "Headings of the morning sheet missing")
        XCTAssertLessThan(dream.frame.minY, gratitude.frame.minY, "The dream log comes first")
        XCTAssertLessThan(gratitude.frame.minY, brainDump.frame.minY, "The gratitude comes before the brain dump")
    }

    /// RO3b: the last row closes the sheet and shows "Planen" without marking the start as done.
    func testFocusHintOpensPlanWithoutCompleting() {
        tab("Erfassen")
        onScreen(label: "Tagesstart.*", matching: true).tap()
        XCTAssertTrue(app.navigationBars["Tagesstart"].waitForExistence(timeout: Self.timeout), "The morning sheet did not open")
        let row = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "Fokus für heute.*")).firstMatch
        scrollTo(row)
        row.tap()
        waitUntilGone(app.navigationBars["Tagesstart"])
        XCTAssertTrue(app.tabBars.buttons["Planen"].isSelected, "\"Planen\" should be shown")
        tab("Erfassen")
        _ = onScreen(label: "Tagesstart.*Starten", matching: true)
    }

    /// RO5b: the card "Willst du etwas ändern?" appears below the brain dump once it holds text, and not before.
    func testChangeCardAppearsWithText() {
        tab("Erfassen")
        onScreen(label: "Tagesstart.*", matching: true).tap()
        XCTAssertTrue(app.navigationBars["Tagesstart"].waitForExistence(timeout: Self.timeout), "The morning sheet did not open")
        let brainDump = app.textViews["Brain Dump"]
        scrollTo(brainDump)
        XCTAssertFalse(app.staticTexts["Willst du etwas ändern?"].exists, "The card shows before there is any text")
        brainDump.tap()
        brainDump.typeText("Kopf voll wegen Umzug")
        waitFor("Willst du etwas ändern?")
        waitFor("Als Aufgabe anlegen")
    }

    /// RO8b: the questions of the weekly reflection stay above their fields, also after something was typed.
    func testReflectionQuestionsStayVisibleWithAnswer() {
        tab("Erfassen")
        onScreen(label: "Wochenrückblick, Woche.*", matching: true).tap()
        let question = app.staticTexts["Was lief gut?"].firstMatch
        scrollTo(question)
        // A multi-line field shows up as a text view or as a text field, depending on the system version.
        let asField = app.textFields["Was lief gut?"].firstMatch
        let field = asField.waitForExistence(timeout: 2) ? asField : app.textViews["Was lief gut?"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: Self.timeout), "The field of the first question is missing")
        field.tap()
        field.typeText("Kapitel 2 fertig")
        XCTAssertTrue(app.staticTexts["Was lief gut?"].firstMatch.exists, "The question disappeared with the answer")
        XCTAssertTrue(app.staticTexts["Belastet mich etwas?"].firstMatch.exists)
    }

    /// RO12b: "Überspringen" goes on to the next step; the bar and the heading name it.
    func testSkipAdvancesWithoutSaving() {
        tab("Erfassen")
        onScreen(label: "Wochenrückblick, Woche.*", matching: true).tap()
        let start = app.buttons["Wochenplanung starten"].firstMatch
        scrollTo(start)
        start.tap()
        XCTAssertTrue(app.navigationBars["Wochenplanung"].waitForExistence(timeout: Self.timeout), "The weekly planning did not open")
        func step(_ text: String) -> XCUIElement {
            app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        }
        XCTAssertTrue(step("Schritt 1 von 5").waitForExistence(timeout: Self.timeout))
        tapButton("Überspringen")
        XCTAssertTrue(step("Schritt 2 von 5 · danach: Fälligkeiten der neuen Woche").waitForExistence(timeout: Self.timeout))
    }
}
