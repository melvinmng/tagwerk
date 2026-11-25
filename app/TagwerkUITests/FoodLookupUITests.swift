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
}
