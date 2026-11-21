import XCTest

/// Accessibility audits of the screens added for recipes (G1) and for the shortcuts and settings rows (G2): the folder
/// "Rezepte", a recipe note, the recipe sheets ("Rezept hinzufügen", "Rezept mit ChatGPT anlegen" with consent and
/// confirmation), the entry in the shopping list, and the settings "KI › Sprache", "Erfassen" and "Einkaufsliste".
///
/// The flows run offline: `-TagwerkDemoAI` gives a signed-in demo session with scripted answers (see `DemoAITransport`), so
/// no network and no account are used. The recipe note comes from the demo data (invented dish). Each test launches the app
/// once and walks through its screens, to keep the run short. Findings must be fixed or sit on `AuditAllowlist` with a reason.
@MainActor
class RecipeScreensAuditCase: UITestCase {
    override var extraLaunchArguments: [String] { ["-TagwerkDemoAI"] + AuditAllowlist.fixedClockArguments }

    typealias Audit = (String) throws -> Void

    /// Notes › Rezepte: the folder with the demo recipe, the recipe note itself, and the ingredient result of
    /// "Zutaten auf die Einkaufsliste" (the note is read on the device: no consent, no network).
    func auditRecipeFolderAndNote(_ audit: Audit) throws {
        openNotes()
        openRecipesFolder()
        let note = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Demo Linsensuppe")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: Self.timeout), "Demo recipe missing in the folder")
        try audit("Rezepte")

        // In the large text size the card can lie behind the capture bar at the bottom.
        if note.frame.minY > app.frame.height * 0.6 {
            let list = app.collectionViews.firstMatch
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
        }
        note.tap()
        XCTAssertTrue(app.buttons["Mehr"].firstMatch.waitForExistence(timeout: Self.timeout), "Recipe note did not open")
        // The note view loads its content after the page opened; the audit must not run on the empty page.
        let content = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "rote Linsen", "rote Linsen")).firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: Self.timeout), "The recipe note shows no content")
        try audit("Rezept-Notiz")

        app.buttons["Mehr"].firstMatch.tap()
        tapButton("Zutaten auf die Einkaufsliste")
        tapScrolling("Zutaten übernehmen")
        XCTAssertTrue(app.navigationBars["Zutaten"].waitForExistence(timeout: Self.timeout), "Ingredient result did not open")
        try audit("Zutaten (Rezept)")
    }

    /// "Rezept mit ChatGPT anlegen": input, consent (asked once at the first read) and the confirmation with the servings.
    func auditCreateRecipe(_ audit: Audit) throws {
        openNotes()
        openRecipesFolder()
        tapButton("Rezept mit ChatGPT anlegen")
        XCTAssertTrue(app.navigationBars["Rezept mit ChatGPT anlegen"].waitForExistence(timeout: Self.timeout))
        try audit("Rezept anlegen (Eingabe)")
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: Self.timeout), "Recipe text field missing")
        editor.tap()
        editor.typeText("Gemüsepfanne für 2: 2 Paprika, 150 g Reis, Salz")
        // The keyboard is a process of its own, and animations of the app cannot be turned off there: wait for its "Fertig" button
        // (it exists as soon as the keyboard is up), close it, and wait until it is really gone before the next step.
        tapButton("Fertig")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: Self.timeout), "The keyboard did not close")
        tapScrolling("Rezept holen")
        waitFor("Einverstanden")
        // The decline button is the lowest control of the sheet (below the fold in the large text size): audit only when it exists.
        waitFor("Nicht jetzt")
        try audit("Rezept anlegen (Einwilligung)")
        tapScrolling("Einverstanden")
        XCTAssertTrue(app.navigationBars["Rezept speichern"].waitForExistence(timeout: 20), "Confirmation did not open")
        try audit("Rezept anlegen (Bestätigung)")
    }

    /// Shopping list › menu › "Rezept hinzufügen …": the input with its sources, and the source "Notiz".
    func auditShoppingRecipeEntry(_ audit: Audit) throws {
        openShoppingList()
        app.buttons["Mehr"].firstMatch.tap()
        tapButton("Rezept hinzufügen …")
        XCTAssertTrue(app.navigationBars["Rezept hinzufügen"].waitForExistence(timeout: Self.timeout))
        try audit("Einkauf › Rezept hinzufügen")
        app.buttons["Notiz"].firstMatch.tap()
        waitFor("Demo Linsensuppe")
        try audit("Einkauf › Rezept hinzufügen (Notiz)")
    }

    /// Einstellungen › KI › Sprache (recipe language), › Erfassen (goal water, shortcut phrases of G2) and › Einkaufsliste (consent).
    func auditSettings(_ audit: Audit) throws {
        tab("Einstellungen")
        openSettingsRow("KI")
        openSettingsRow("Sprache")
        XCTAssertTrue(app.navigationBars["Sprache"].waitForExistence(timeout: Self.timeout), "Language settings did not open")
        // The rows "Sprachpaket …" show "…" until the state of the language packs is known and then a longer text (more lines in
        // the large text size). The audit must not run in between.
        waitUntilGone(app.staticTexts["…"].firstMatch)
        try audit("Einstellungen › KI › Sprache")
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()

        openSettingsRow("Erfassen")
        XCTAssertTrue(app.navigationBars["Erfassen"].waitForExistence(timeout: Self.timeout))
        try audit("Einstellungen › Erfassen")
        app.navigationBars.buttons.firstMatch.tap()

        openSettingsRow("Einkaufsliste")
        XCTAssertTrue(app.navigationBars["Einkaufsliste"].waitForExistence(timeout: Self.timeout), "Shopping settings did not open")
        try audit("Einstellungen › Einkaufsliste")
    }

    /// Taps a button that can lie below the fold in the large text size: scrolls to it first.
    private func tapScrolling(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        // A form is a lazy list: the button does not exist before it is scrolled into view.
        let button = app.buttons[title].firstMatch
        scrollTo(button, file: file, line: line)
        button.tap()
    }

    private func openRecipesFolder() {
        let folder = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Rezepte")).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: Self.timeout), "Folder Rezepte missing")
        folder.tap()
        XCTAssertTrue(app.navigationBars["Rezepte"].waitForExistence(timeout: Self.timeout))
    }

    /// Scrolls the settings list in small steps (a lazy list only creates the rows near the screen, and a full-page swipe can jump
    /// over a row) to the row that starts with this title and opens it. The scroll position stays when a page is left, so
    /// the search goes to the top first.
    private func openSettingsRow(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        // Only rows of the list: the tab bar has a button "Erfassen" as well.
        let row = app.cells.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        for _ in 0..<4 { app.swipeDown() }
        var steps = 0
        while !(row.exists && row.isHittable), steps < 20 {
            let list = app.collectionViews.firstMatch
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
            steps += 1
        }
        XCTAssertTrue(row.exists && row.isHittable, "Settings row \(title) is not reachable by scrolling", file: file, line: line)
        row.tap()
    }
}

/// The recipe screens in the default text size, all audit types.
final class AccessibilityAuditRecipesUITests: RecipeScreensAuditCase {
    private func audit(_ screen: String) throws {
        try AuditAllowlist.audit(app, screen: screen, for: .all)
    }

    func testAuditRecipeFolderAndNote() throws { try auditRecipeFolderAndNote(audit) }
    func testAuditCreateRecipe() throws { try auditCreateRecipe(audit) }
    func testAuditShoppingRecipeEntry() throws { try auditShoppingRecipeEntry(audit) }
    func testAuditSettings() throws { try auditSettings(audit) }
}

/// The recipe screens in the largest text size (AX5) and dark mode: clipped text and contrast (see
/// `AccessibilityAuditLargeTextUITests` for why the Dynamic Type check is left out).
final class AccessibilityAuditRecipesLargeTextUITests: RecipeScreensAuditCase {
    override var extraLaunchArguments: [String] { super.extraLaunchArguments + ["-TagwerkUITestTextSize", "accessibility5", "-TagwerkUITestDark"] }

    private func audit(_ screen: String) throws {
        try AuditAllowlist.audit(app, screen: "AX5/dark " + screen, for: [.textClipped, .contrast])
    }

    func testAuditRecipeFolderAndNote() throws { try auditRecipeFolderAndNote(audit) }
    func testAuditCreateRecipe() throws { try auditCreateRecipe(audit) }
    func testAuditShoppingRecipeEntry() throws { try auditShoppingRecipeEntry(audit) }
    func testAuditSettings() throws { try auditSettings(audit) }
}
