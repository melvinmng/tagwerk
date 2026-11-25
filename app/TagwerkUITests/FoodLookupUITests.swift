import XCTest

/// The online search in Open Food Facts (decision LM1d), against scripted answers: the app runs with `-TagwerkDemoFoodLookup`, so no
/// request leaves the simulator. The address is invented.
final class FoodLookupUITests: UITestCase {
    override var extraLaunchArguments: [String] { ["-TagwerkDemoFoodLookup"] }

    /// Typing does not search; the tap asks for the consent and the contact address first; after "Einverstanden und suchen" the hits
    /// show, and a hit is taken over as an own food.
    func testOnlineSearch_consentFirst_thenResults() {
        tab("Erfassen")
        onScreen(label: "Essen").tap()
        selectSegment("Meine Lebensmittel")
        typeIn("Was hast du gegessen?", text: "Skyr")
        let hideKeyboard = app.buttons[AccessibilityID.Common.hideKeyboard].firstMatch
        XCTAssertTrue(hideKeyboard.waitForExistence(timeout: Self.timeout), "The button above the keyboard is missing")
        hideKeyboard.tap()

        // The row is there, nothing was searched while typing.
        let row = app.buttons[AccessibilityID.FoodLookup.searchRow].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout), "The row for the online search is missing")
        XCTAssertFalse(app.descendants(matching: .any)[AccessibilityID.FoodLookup.results].exists, "A search started while typing")
        row.tap()

        // The consent comes first; the contact address is optional, so "Einverstanden" works without one.
        let contact = app.textFields[AccessibilityID.FoodLookup.contactField].firstMatch
        XCTAssertTrue(contact.waitForExistence(timeout: Self.timeout), "The consent sheet did not open")
        // An empty field reports no value (older systems reported the placeholder as the value); the placeholder is a separate property.
        let typed = (contact.value as? String) ?? ""
        XCTAssertTrue(typed.isEmpty || typed == "E-Mail-Adresse", "The field must start empty (only the placeholder shows): \(typed)")
        XCTAssertEqual(contact.placeholderValue, "E-Mail-Adresse", "The placeholder of the field is missing")
        let agree = app.buttons[AccessibilityID.FoodLookup.agreeButton].firstMatch
        XCTAssertTrue(agree.isEnabled, "Agreeing must not need an address")
        XCTAssertFalse(app.descendants(matching: .any)[AccessibilityID.FoodLookup.results].exists, "Results appeared before the consent")
        contact.tap()
        contact.typeText("ui-test@example.org\n")
        XCTAssertTrue(agree.isEnabled, "A valid address should allow agreeing")
        agree.tap()

        // The scripted answer lists two hits; the first one is complete.
        let hit = app.descendants(matching: .any).matching(identifier: AccessibilityID.FoodLookup.results)
            .matching(NSPredicate(format: "label CONTAINS 'Demo Skyr natur'")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: Self.timeout), "The hits did not show")
        hit.tap()
        tapButton(AccessibilityID.FoodLookup.saveFood)
        // The edit sheet holds the product with its values; saving makes it an own food.
        XCTAssertTrue(app.textFields["Kalorien"].firstMatch.waitForExistence(timeout: Self.timeout), "The food form did not open")
        tapButton(AccessibilityID.Food.saveButton)

        let food = app.buttons.matching(identifier: AccessibilityID.Food.row)
            .matching(NSPredicate(format: "label CONTAINS 'Demo Skyr natur'")).firstMatch
        XCTAssertTrue(food.waitForExistence(timeout: Self.timeout), "The taken-over product is not in the list of own foods")

        // Saved without a change, the product keeps its source note. The values have two decimal places (the scripted answer gives
        // 11,37 g protein, 0,15 g salt and the energy in kilojoules): a number field that rounded them would count as a change.
        food.swipeLeft()
        tapButton("Bearbeiten")
        let note = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Open Food Facts, abgerufen am'")).firstMatch
        // The note is the last section of the form, below the further nutrients, and the form builds its rows lazily.
        scrollTo(note)
        XCTAssertTrue(note.exists, "The source note of the product is missing or says that the values were changed")
    }

    // MARK: Barcode scan

    /// A code with a valid check digit that the scripted answer knows as a complete product ("Demo Skyr natur").
    private static let knownBarcode = "4000000000006"
    /// A valid code that the scripted answer does not know.
    private static let unknownBarcode = "4012345678901"

    /// Erfassen › Essen › Meine Lebensmittel › "Strichcode scannen". The simulator has no scanner, so the sheet starts with the field for
    /// the digits.
    private func openBarcodeSheet(file: StaticString = #filePath, line: UInt = #line) {
        tab("Erfassen")
        onScreen(label: "Essen").tap()
        selectSegment("Meine Lebensmittel")
        let row = app.buttons[AccessibilityID.FoodLookup.scanRow].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout), "The row Strichcode scannen is missing", file: file, line: line)
        scrollTo(row, file: file, line: line)
        row.tap()
        XCTAssertTrue(app.textFields[AccessibilityID.FoodLookup.manualField].firstMatch.waitForExistence(timeout: Self.timeout),
                      "The scan sheet did not open with the field for the digits", file: file, line: line)
    }

    private func submitBarcode(_ code: String, file: StaticString = #filePath, line: UInt = #line) {
        typeIn(AccessibilityID.FoodLookup.manualField, text: code, file: file, line: line)
        tapButton(AccessibilityID.FoodLookup.manualSubmit, file: file, line: line)
    }

    /// A known code: the consent comes first (the code is not among the own foods), then the preview; taking the product over makes it an own
    /// food.
    func testBarcode_manualEntry_knownProduct_showsPreviewAndSaves() {
        openBarcodeSheet()
        submitBarcode(Self.knownBarcode)

        // Nothing was sent before the consent.
        let agree = app.buttons[AccessibilityID.FoodLookup.agreeButton].firstMatch
        XCTAssertTrue(agree.waitForExistence(timeout: Self.timeout), "The consent did not show for an unknown code")
        agree.tap()

        tapButton(AccessibilityID.FoodLookup.saveFood)
        XCTAssertTrue(app.textFields["Kalorien"].firstMatch.waitForExistence(timeout: Self.timeout), "The food form did not open")
        tapButton(AccessibilityID.Food.saveButton)

        let food = app.buttons.matching(identifier: AccessibilityID.Food.row)
            .matching(NSPredicate(format: "label CONTAINS 'Demo Skyr natur'")).firstMatch
        XCTAssertTrue(food.waitForExistence(timeout: Self.timeout), "The scanned product is not in the list of own foods")
    }

    /// A code that Open Food Facts does not know: the way on is "Selbst anlegen", and the food form carries the code.
    func testBarcode_manualEntry_unknownProduct_offersOwnFood() {
        openBarcodeSheet()
        submitBarcode(Self.unknownBarcode)
        tapButton(AccessibilityID.FoodLookup.agreeButton)

        XCTAssertTrue(app.staticTexts["Open Food Facts kennt diesen Strichcode nicht."].firstMatch.waitForExistence(timeout: Self.timeout),
                      "The answer for an unknown code is missing")
        // The label and the code are one element for VoiceOver ("Strichcode, 4012345678901").
        let shownCode = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", Self.unknownBarcode)).firstMatch
        XCTAssertTrue(shownCode.exists, "The code is not shown")
        tapButton(AccessibilityID.FoodLookup.scanCreateFood)
        XCTAssertTrue(app.textFields[AccessibilityID.Food.nameField].firstMatch.waitForExistence(timeout: Self.timeout), "The food form did not open")
    }

    /// A number that is no barcode is refused on the spot, with the hint, and nothing is asked.
    func testBarcode_manualEntry_invalidCode_showsHint() {
        openBarcodeSheet()
        submitBarcode("12345678")
        XCTAssertTrue(app.staticTexts["Das ist kein gültiger Strichcode."].firstMatch.waitForExistence(timeout: Self.timeout),
                      "The hint for a wrong number is missing")
        XCTAssertFalse(app.buttons[AccessibilityID.FoodLookup.agreeButton].firstMatch.exists, "The consent showed for an invalid code")
    }

    /// A food that carries the code is found without the consent and without a connection: the amount sheet opens straight away.
    func testBarcode_ownFood_opensAmountSheetWithoutConsent() {
        openBarcodeSheet()
        // Create the food through the declined consent, so the consent stays off for the rest of the test.
        submitBarcode(Self.unknownBarcode)
        tapButton("Nicht jetzt")
        tapButton(AccessibilityID.FoodLookup.scanCreateFood)
        typeIn(AccessibilityID.Food.nameField, text: "Eigener Skyr")
        let kcal = app.textFields["Kalorien"].firstMatch
        XCTAssertTrue(kcal.waitForExistence(timeout: Self.timeout), "The food form did not open")
        kcal.tap()
        kcal.typeText("62")
        let hideKeyboard = app.buttons[AccessibilityID.Common.hideKeyboard].firstMatch
        XCTAssertTrue(hideKeyboard.waitForExistence(timeout: Self.timeout), "The button above the keyboard is missing")
        hideKeyboard.tap()
        tapButton(AccessibilityID.Food.saveButton)
        let food = app.buttons.matching(identifier: AccessibilityID.Food.row)
            .matching(NSPredicate(format: "label CONTAINS 'Eigener Skyr'")).firstMatch
        XCTAssertTrue(food.waitForExistence(timeout: Self.timeout), "The food is not in the list")

        // The same code again: the own food answers.
        let row = app.buttons[AccessibilityID.FoodLookup.scanRow].firstMatch
        scrollTo(row)
        row.tap()
        submitBarcode(Self.unknownBarcode)
        XCTAssertTrue(app.textFields[AccessibilityID.Food.amountField].firstMatch.waitForExistence(timeout: Self.timeout),
                      "The amount sheet of the own food did not open")
        XCTAssertFalse(app.buttons[AccessibilityID.FoodLookup.agreeButton].firstMatch.exists, "The consent showed for an own food")
    }
}
