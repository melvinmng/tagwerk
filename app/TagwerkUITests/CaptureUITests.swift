import XCTest

final class CaptureUITests: UITestCase {
    /// The budget line of the day head, one element: "Noch etwa 1.480 Kilokalorien: Ziel 2.300, plus 260 aktiv, minus etwa 1.340 gegessen".
    private var budgetLine: XCUIElement {
        let line = app.descendants(matching: .any).matching(identifier: AccessibilityID.Capture.budgetLine)
            .matching(NSPredicate(format: "label CONTAINS 'Ziel'")).allElementsBoundByIndex.first { $0.isHittable }
        return line ?? app.descendants(matching: .any)[AccessibilityID.Capture.budgetLine].firstMatch
    }

    /// "0,0 l / 2,0 l": the water value of the day summary.
    private var waterValue: XCUIElement { onScreen(.staticText, label: #"[0-9.,]+ l / [0-9.,]+ l"#, matching: true) }

    func testLogMealAndWater() {
        tab("Erfassen")
        // The demo data adds meals depending on the time of day, so the checks compare with the value before.
        XCTAssertTrue(budgetLine.waitForExistence(timeout: Self.timeout), "The budget line is missing")
        let kcalBefore = budgetLine.label
        onScreen(label: "Essen").tap()

        // Without a ChatGPT sign-in the sheet takes typed values: name, then kcal.
        typeIn("Was hast du gegessen?", text: "Apfel")
        tapButton("Weiter")
        let kcal = app.textFields["Kalorien"].firstMatch
        XCTAssertTrue(kcal.waitForExistence(timeout: Self.timeout), "The values form did not open")
        kcal.tap()
        kcal.typeText("95")
        tapButton("Sichern")
        // The budget line counts the meal (the list of meals is further down and not built until scrolled to).
        eventually("The budget did not change from \(kcalBefore)") { budgetLine.label != kcalBefore }

        // Water: the quick button raises the value.
        let before = waterValue.label
        onScreen(label: "250 Milliliter Wasser erfassen").tap()
        eventually("The water value did not change from \(before)") { waterValue.label != before }
    }

    /// Decision BU4b: the head reads "Ziel + Aktiv − Gegessen = Noch" as one element, and a tap on it opens the breakdown.
    func testCaptureHead_showsBudgetEquation() {
        tab("Erfassen")
        let line = budgetLine
        XCTAssertTrue(line.waitForExistence(timeout: Self.timeout), "The budget line is missing")
        let label = line.label
        XCTAssertTrue(label.contains("Ziel") && label.contains("gegessen"), "The spoken sentence lacks a term: \(label)")
        // The demo Health delivers 520 kcal of active energy today; half of it counts by default.
        XCTAssertTrue(label.contains("plus 260 aktiv"), "The credited activity is missing: \(label)")
        line.tap()
        XCTAssertTrue(app.navigationBars["Aktiv heute"].waitForExistence(timeout: Self.timeout), "The breakdown did not open")
        let credited = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Angerechnet'")).firstMatch
        // The sheet opens at half height and its list builds the rows lazily, so the last section is reached by scrolling.
        scrollTo(credited)
        XCTAssertTrue(credited.exists, "The credited row is missing")
    }

    /// Decision NU3b: calories and macros are visible, the further nutrients fold out; an empty field stays unknown.
    func testMealSheet_furtherNutrients_expandAndSave() {
        tab("Erfassen")
        XCTAssertTrue(budgetLine.waitForExistence(timeout: Self.timeout), "The budget line is missing")
        let before = budgetLine.label
        onScreen(label: "Essen").tap()
        typeIn("Was hast du gegessen?", text: "Haferbrei")
        tapButton("Weiter")
        let kcal = app.textFields["Kalorien"].firstMatch
        XCTAssertTrue(kcal.waitForExistence(timeout: Self.timeout), "The values form did not open")
        kcal.tap()
        kcal.typeText("320")
        // Folded out on a tap; two of the four nutrients are visible by default (fiber and sugar), none is known yet.
        // The label of the row reads "Weitere Nährwerte, 0 von 2": the name and the counter are one element.
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Weitere Nährwerte'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout), "The row for further nutrients is missing")
        XCTAssertTrue(row.label.contains("0 von 2"), "No nutrient is known yet: \(row.label)")
        // The decimal pad covers the lower part of the sheet, including this row: close it before the tap.
        let hideKeyboard = app.buttons[AccessibilityID.Common.hideKeyboard].firstMatch
        XCTAssertTrue(hideKeyboard.waitForExistence(timeout: Self.timeout), "The button above the keyboard is missing")
        hideKeyboard.tap()
        row.tap()
        let fiber = app.textFields["Ballaststoffe"].firstMatch
        // The new rows may lie below the fold of the half-height sheet.
        scrollTo(fiber)
        XCTAssertTrue(fiber.exists, "The fiber field did not appear")
        fiber.tap()
        fiber.typeText("6")
        eventually("The counter did not follow the typed value") { row.label.contains("1 von 2") }
        tapButton("Sichern")
        eventually("The meal was not saved: the budget did not change from \(before)") { budgetLine.label != before }
    }

    /// Decision KG1c: the fourth quick button opens the weight sheet; saving shows the confirmation with "Rückgängig", and undoing
    /// takes the entry away again.
    func testQuickEntry_weight_savesAndOffersUndo() {
        tab("Erfassen")
        let button = app.buttons[AccessibilityID.Capture.quickWeight].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: Self.timeout), "The quick button for the weight is missing")
        button.tap()
        // The sheet starts with a value (the demo data holds no weight yet), so saving needs no typing.
        XCTAssertTrue(app.navigationBars["Gewicht"].waitForExistence(timeout: Self.timeout), "The weight sheet did not open")
        app.buttons[AccessibilityID.Capture.weightSave].firstMatch.tap()
        let confirmation = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'kg erfasst'")).firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: Self.timeout), "The confirmation with the weight is missing")
        tapButton("Rückgängig")
        eventually("The confirmation did not disappear after undoing") { !confirmation.exists }
    }
}
