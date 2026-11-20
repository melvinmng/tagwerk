import XCTest

final class CaptureUITests: UITestCase {
    /// "95 / 2.300 kcal" or "~460 / 2.300 kcal": the calories of the day summary.
    private var kcalValue: XCUIElement { onScreen(.staticText, label: #"[~0-9.,]+ / [0-9.,]+ kcal"#, matching: true) }

    /// "0,0 l / 2,0 l": the water value of the day summary.
    private var waterValue: XCUIElement { onScreen(.staticText, label: #"[0-9.,]+ l / [0-9.,]+ l"#, matching: true) }

    func testLogMealAndWater() {
        tab("Erfassen")
        // The demo data adds meals depending on the time of day, so the checks compare with the value before.
        let kcalBefore = kcalValue.label
        onScreen(label: "Essen").tap()

        // Without a ChatGPT sign-in the sheet takes typed values: name, then kcal.
        typeIn("Was hast du gegessen?", text: "Apfel")
        tapButton("Weiter")
        let kcal = app.textFields["Kalorien"].firstMatch
        XCTAssertTrue(kcal.waitForExistence(timeout: Self.timeout), "The values form did not open")
        kcal.tap()
        kcal.typeText("95")
        tapButton("Sichern")
        // The summary counts the meal (the list of meals is further down and not built until scrolled to).
        eventually("The calories did not change from \(kcalBefore)") { kcalValue.label != kcalBefore }

        // Water: the quick button raises the value.
        let before = waterValue.label
        onScreen(label: "250 Milliliter Wasser erfassen").tap()
        eventually("The water value did not change from \(before)") { waterValue.label != before }
    }
}
