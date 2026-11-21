import XCTest

/// SPC1a–SPC3a and SPC8b: switching the language of the shopping list offers to translate the open items with ChatGPT; preview,
/// apply and undo. The flows run offline with the demo session (`-TagwerkDemoAI`), whose scripted answer translates a few
/// names (see `DemoAITransport.shoppingTranslationAnswer`).
final class ShoppingTranslateUITests: UITestCase {
    override var extraLaunchArguments: [String] { ["-TagwerkDemoAI"] }

    private func addItem(_ name: String) {
        let field = app.textFields["Artikel hinzufügen"]
        field.tap()
        field.typeText(name + "\n")
        waitFor("\(name), nicht erledigt")
    }

    func testTranslateOffer_previewApplyUndo() {
        openShoppingList()
        addItem("Milch")
        addItem("Brot")

        // The language mark switches the list to English; the card offers to translate the two open items.
        tapButton("Sprache der Einkaufsliste Deutsch, auf Englisch wechseln")
        waitFor("Einkaufsliste jetzt auf Englisch")
        tapButton("Mit ChatGPT übersetzen")
        // The consent of sorting did not cover translating yet: its sheet names translating.
        XCTAssertTrue(app.navigationBars["Mit ChatGPT übersetzen"].waitForExistence(timeout: Self.timeout), "The consent sheet did not open")
        tapButton("Einverstanden und übersetzen")

        XCTAssertTrue(app.navigationBars["Übersetzung"].waitForExistence(timeout: Self.timeout), "The preview did not open")
        waitFor("Milch wird Milk, ausgewählt")
        tapButton("Übernehmen")

        waitFor("Milk, nicht erledigt")
        waitFor("Bread, nicht erledigt")
        tapButton("Rückgängig")
        waitFor("Milch, nicht erledigt")
        waitFor("Brot, nicht erledigt")
        // The old language is the settled one again: the card is back.
        waitFor("Einkaufsliste jetzt auf Englisch")
    }

    func testTranslateOffer_keepAsIs_hidesTheCard() {
        openShoppingList()
        addItem("Milch")

        tapButton("Sprache der Einkaufsliste Deutsch, auf Englisch wechseln")
        let title = waitFor("Einkaufsliste jetzt auf Englisch")
        tapButton("So lassen")
        waitUntilGone(title)
        XCTAssertTrue(app.descendants(matching: .any)["Milch, nicht erledigt"].firstMatch.exists, "\"So lassen\" must not rename anything")

        // English is the settled language now: the card returns only with the next switch.
        tapButton("Sprache der Einkaufsliste Englisch, auf Deutsch wechseln")
        waitFor("Einkaufsliste jetzt auf Deutsch")
    }
}
