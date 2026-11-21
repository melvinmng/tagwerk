import Foundation
import Testing
@testable import TagwerkCore

struct RecipeTranslationPlanTests {
    private let photoID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    private var english: String {
        """
        # Red Lentil Curry

        Servings: 4

        ## Ingredients
        - 250 g red lentils
        - 2 tbsp curry paste
        - [ ] 1 can coconut milk (400 ml)

        ## Instructions
        1. Chop the onions.
        2. Simmer for 20 minutes.

        My note: tastes better the next day.
        ![Dish](attachment:\(photoID.uuidString))

        Source: [chefkoch.de](https://www.chefkoch.de/rezepte/123)
        """
    }

    /// The translation a well-behaved model would return for `english`, keyed by the plan's request indices.
    private func germanTranslations(for plan: RecipeTranslationPlan) -> [Int: String] {
        let table: [String: String] = [
            "Red Lentil Curry": "Rotes Linsencurry",
            "250 g red lentils": "250 g rote Linsen",
            "2 tbsp curry paste": "2 EL Currypaste",
            "1 can coconut milk (400 ml)": "1 Dose Kokosmilch (400 ml)",
            "Chop the onions.": "Zwiebeln würfeln.",
            "Simmer for 20 minutes.": "20 Minuten köcheln lassen.",
            "My note: tastes better the next day.": "Meine Notiz: schmeckt am nächsten Tag besser."
        ]
        return Dictionary(uniqueKeysWithValues: plan.request.map { ($0.index, table[$0.text] ?? $0.text) })
    }

    // MARK: Segments

    @Test func segments_headingsAndLabelsStayLocal() {
        let plan = RecipeTranslationPlan(markdown: english)
        #expect(plan.segments.contains(.ingredientsHeading(prefix: "## ")))
        #expect(plan.segments.contains(.stepsHeading(prefix: "## ")))
        #expect(plan.segments.contains(.servings(value: "4")))
        #expect(plan.segments.contains(.source(value: "[chefkoch.de](https://www.chefkoch.de/rezepte/123)")))
        let sent = plan.request.map(\.text)
        #expect(!sent.contains("Ingredients") && !sent.contains("Instructions"))
        #expect(!sent.contains { $0.contains("Servings") || $0.contains("Source") })
    }

    @Test func segments_listMarkerAndCheckboxArePrefix() {
        let plan = RecipeTranslationPlan(markdown: english)
        #expect(plan.segments.contains(.text(prefix: "- ", body: "250 g red lentils", isIngredient: true)))
        #expect(plan.segments.contains(.text(prefix: "- [ ] ", body: "1 can coconut milk (400 ml)", isIngredient: true)))
        #expect(plan.segments.contains(.text(prefix: "# ", body: "Red Lentil Curry", isIngredient: false)))
    }

    @Test func segments_numberedStepKeepsItsNumber() {
        let plan = RecipeTranslationPlan(markdown: english)
        #expect(plan.segments.contains(.text(prefix: "1. ", body: "Chop the onions.", isIngredient: false)))
        #expect(plan.segments.contains(.text(prefix: "2. ", body: "Simmer for 20 minutes.", isIngredient: false)))
    }

    @Test func segments_attachmentOnlyLineIsFixed() {
        let reference = "![Dish](attachment:\(photoID.uuidString))"
        let plan = RecipeTranslationPlan(markdown: english)
        #expect(plan.segments.contains(.fixed(reference)))
        #expect(!plan.request.contains { $0.text.contains("attachment:") })
        let withBullet = RecipeTranslationPlan(markdown: "- \(reference)\n")
        #expect(withBullet.segments.first == .fixed("- \(reference)"))
    }

    @Test func segments_addressOnlyLineIsFixed() {
        let plan = RecipeTranslationPlan(markdown: "## Ingredients\n- flour\nhttps://example.com/recipe\n")
        #expect(plan.segments.contains(.fixed("https://example.com/recipe")))
    }

    @Test func segments_textOutsideSectionsIsTranslatable() {
        let plan = RecipeTranslationPlan(markdown: english)
        #expect(plan.request.map(\.text).contains("My note: tastes better the next day."))
    }

    @Test func segments_lineWithoutLettersIsFixed() {
        let plan = RecipeTranslationPlan(markdown: "## Ingredients\n- flour\n---\n-\n1.\n")
        #expect(plan.request.map(\.text) == ["flour"])
    }

    @Test func request_skipsBlankAndFixedLines() {
        let plan = RecipeTranslationPlan(markdown: english)
        let requested = plan.request
        #expect(requested.map(\.text) == [
            "Red Lentil Curry", "250 g red lentils", "2 tbsp curry paste", "1 can coconut milk (400 ml)",
            "Chop the onions.", "Simmer for 20 minutes.", "My note: tastes better the next day."
        ])
        #expect(Set(requested.map(\.index)).count == requested.count)
        for entry in requested {
            guard case .text(_, let body, _) = plan.segments[entry.index] else {
                Issue.record("Index \(entry.index) does not point at a text segment")
                continue
            }
            #expect(body == entry.text)
        }
    }

    // MARK: Assembling

    @Test func assembled_englishToGerman_keepsStructure() throws {
        let plan = RecipeTranslationPlan(markdown: english)
        let result = try plan.assembled(translations: germanTranslations(for: plan), language: .german)
        let expected = """
        # Rotes Linsencurry

        Portionen: 4

        ## Zutaten
        - 250 g rote Linsen
        - 2 EL Currypaste
        - [ ] 1 Dose Kokosmilch (400 ml)

        ## Zubereitung
        1. Zwiebeln würfeln.
        2. 20 Minuten köcheln lassen.

        Meine Notiz: schmeckt am nächsten Tag besser.
        ![Dish](attachment:\(photoID.uuidString))

        Quelle: [chefkoch.de](https://www.chefkoch.de/rezepte/123)
        """
        #expect(result == expected)
        let note = try #require(RecipeNote.parse(result))
        #expect(note.title == "Rotes Linsencurry" && note.servings == 4)
        let original = try #require(RecipeNote.parse(english))
        #expect(note.ingredients.count == 3 && note.ingredients.count == original.ingredients.count)
        #expect(note.steps.count == original.steps.count && note.sourceURL == original.sourceURL)
    }

    @Test func assembled_germanToEnglish_usesEnglishHeadings() throws {
        let german = "# Linsencurry\n\nPortionen: 4\n\n## Zutaten\n- 250 g rote Linsen\n\n## Zubereitung\n1. Zwiebeln würfeln.\n"
        let plan = RecipeTranslationPlan(markdown: german)
        let translations = Dictionary(uniqueKeysWithValues: plan.request.map { entry in
            (entry.index, ["Linsencurry": "Lentil curry", "250 g rote Linsen": "250 g red lentils", "Zwiebeln würfeln.": "Chop the onions."][entry.text]!)
        })
        let result = try plan.assembled(translations: translations, language: .english)
        #expect(result == "# Lentil curry\n\nServings: 4\n\n## Ingredients\n- 250 g red lentils\n\n## Instructions\n1. Chop the onions.\n")
    }

    @Test func assembled_germanAnleitung_becomesZubereitungOrInstructions() throws {
        let markdown = "## Zutaten\n- Mehl\n\n## Anleitung\n1. Mischen.\n"
        let plan = RecipeTranslationPlan(markdown: markdown)
        let translations = Dictionary(uniqueKeysWithValues: plan.request.map { ($0.index, $0.text) })
        #expect(try plan.assembled(translations: translations, language: .german).contains("## Zubereitung"))
        #expect(try plan.assembled(translations: translations, language: .english).contains("## Instructions"))
    }

    @Test func assembled_keepsInlineAttachmentReference() throws {
        let markdown = "## Ingredients\n- 1 cup flour\n\nSee the ![photo](attachment:\(photoID.uuidString)) for the dough.\n"
        let plan = RecipeTranslationPlan(markdown: markdown)
        let translations = Dictionary(uniqueKeysWithValues: plan.request.map { entry in
            (entry.index, entry.text.hasPrefix("See") ? "Siehe das ![photo](attachment:\(photoID.uuidString)) für den Teig." : "1 Tasse Mehl")
        })
        let result = try plan.assembled(translations: translations, language: .german)
        #expect(MarkdownText.attachmentIDs(in: result) == [photoID])
        #expect(result.contains("Siehe das ![photo](attachment:\(photoID.uuidString)) für den Teig."))
    }

    @Test func assembled_keepsTrailingNewline() throws {
        for markdown in ["## Ingredients\n- flour", "## Ingredients\n- flour\n", "## Ingredients\n- flour\n\n"] {
            let plan = RecipeTranslationPlan(markdown: markdown)
            let translations = Dictionary(uniqueKeysWithValues: plan.request.map { ($0.index, "Mehl") })
            let result = try plan.assembled(translations: translations, language: .german)
            #expect(result == markdown.replacingOccurrences(of: "Ingredients", with: "Zutaten").replacingOccurrences(of: "flour", with: "Mehl"))
        }
    }

    @Test func assembled_keepsWindowsLineEndings() throws {
        let markdown = "## Ingredients\r\n- flour\r\n"
        let plan = RecipeTranslationPlan(markdown: markdown)
        let translations = Dictionary(uniqueKeysWithValues: plan.request.map { ($0.index, "Mehl") })
        #expect(try plan.assembled(translations: translations, language: .german) == "## Zutaten\r\n- Mehl\r\n")
    }

    @Test func assembled_missingIndex_throwsIndexMismatch() {
        let plan = RecipeTranslationPlan(markdown: english)
        var translations = germanTranslations(for: plan)
        translations.removeValue(forKey: plan.request[2].index)
        #expect(throws: RecipeTranslationPlan.Failure.indexMismatch) { try plan.assembled(translations: translations, language: .german) }
    }

    @Test func assembled_extraIndex_throwsIndexMismatch() {
        let plan = RecipeTranslationPlan(markdown: english)
        var translations = germanTranslations(for: plan)
        translations[999] = "Zusatz"
        #expect(throws: RecipeTranslationPlan.Failure.indexMismatch) { try plan.assembled(translations: translations, language: .german) }
    }

    @Test func assembled_emptyOrMultilineText_throws() {
        let plan = RecipeTranslationPlan(markdown: english)
        var empty = germanTranslations(for: plan)
        empty[plan.request[1].index] = "   "
        #expect(throws: RecipeTranslationPlan.Failure.emptyLine) { try plan.assembled(translations: empty, language: .german) }
        var multiline = germanTranslations(for: plan)
        multiline[plan.request[1].index] = "250 g rote Linsen\n- 1 Zwiebel"
        #expect(throws: RecipeTranslationPlan.Failure.lineBreak) { try plan.assembled(translations: multiline, language: .german) }
    }

    @Test func assembled_droppedAttachment_throws() {
        let markdown = "## Ingredients\n- flour\n\nSee ![photo](attachment:\(photoID.uuidString)) here.\n"
        let plan = RecipeTranslationPlan(markdown: markdown)
        let translations = Dictionary(uniqueKeysWithValues: plan.request.map { ($0.index, $0.text.hasPrefix("See") ? "Siehe hier." : "Mehl") })
        #expect(throws: RecipeTranslationPlan.Failure.attachmentsChanged) { try plan.assembled(translations: translations, language: .german) }
    }

    @Test func assembled_changedLink_throws() {
        let markdown = "## Ingredients\n- flour\n\nSee [the video](https://example.com/watch) here.\n"
        let plan = RecipeTranslationPlan(markdown: markdown)
        let translations = Dictionary(uniqueKeysWithValues: plan.request.map {
            ($0.index, $0.text.hasPrefix("See") ? "Siehe [das Video](https://example.com/other) hier." : "Mehl")
        })
        #expect(throws: RecipeTranslationPlan.Failure.linksChanged) { try plan.assembled(translations: translations, language: .german) }
    }

    @Test func assembled_changedAmountInIngredient_throws() {
        let plan = RecipeTranslationPlan(markdown: english)
        var translations = germanTranslations(for: plan)
        translations[plan.request[1].index] = "255 g rote Linsen"
        #expect(throws: RecipeTranslationPlan.Failure.amountsChanged) { try plan.assembled(translations: translations, language: .german) }
    }

    @Test func assembled_changedFractionInIngredient_throws() {
        let plan = RecipeTranslationPlan(markdown: "## Ingredients\n- ½ cup sugar\n")
        let entry = plan.request[0]
        #expect(throws: RecipeTranslationPlan.Failure.amountsChanged) {
            try plan.assembled(translations: [entry.index: "1/2 Tasse Zucker"], language: .german)
        }
        #expect(throws: RecipeTranslationPlan.Failure.amountsChanged) {
            try plan.assembled(translations: [entry.index: "¼ Tasse Zucker"], language: .german)
        }
    }

    @Test func assembled_changedDecimalSeparator_isAccepted() throws {
        let plan = RecipeTranslationPlan(markdown: "## Ingredients\n- 1.5 cups milk\n- 2,5 l water\n- 1.000 g flour\n")
        let entries = plan.request
        let translations = [entries[0].index: "1,5 Tassen Milch", entries[1].index: "2.5 l Wasser", entries[2].index: "1,000 g Mehl"]
        let result = try plan.assembled(translations: translations, language: .german)
        #expect(result == "## Zutaten\n- 1,5 Tassen Milch\n- 2.5 l Wasser\n- 1,000 g Mehl\n")
    }

    @Test func assembled_changedDigits_throws() throws {
        let plan = RecipeTranslationPlan(markdown: "## Ingredients\n- 1.5 cups milk\n")
        let entry = plan.request[0]
        // A removed separator, a fraction instead of a decimal, a different number and a separator turned into a space.
        for answer in ["15 Tassen Milch", "1 1/2 Tassen Milch", "2 Tassen Milch", "1 5 Tassen Milch", "1,6 Tassen Milch"] {
            #expect(throws: RecipeTranslationPlan.Failure.amountsChanged) {
                try plan.assembled(translations: [entry.index: answer], language: .german)
            }
        }
        // The same notation passes.
        #expect(try plan.assembled(translations: [entry.index: "1.5 Tassen Milch"], language: .german) == "## Zutaten\n- 1.5 Tassen Milch\n")
    }

    @Test func comparableNumberTokens_ignoreTheDecimalSeparatorOnly() {
        #expect(RecipeTranslationPlan.comparableNumberTokens(in: "1.5 cups") == RecipeTranslationPlan.comparableNumberTokens(in: "1,5 Tassen"))
        #expect(RecipeTranslationPlan.comparableNumberTokens(in: "1.000 g") == RecipeTranslationPlan.comparableNumberTokens(in: "1,000 g"))
        #expect(RecipeTranslationPlan.comparableNumberTokens(in: "1.5 cups") != RecipeTranslationPlan.comparableNumberTokens(in: "15 Tassen"))
        #expect(RecipeTranslationPlan.comparableNumberTokens(in: "1.5 cups") != RecipeTranslationPlan.comparableNumberTokens(in: "1 5 Tassen"))
        #expect(RecipeTranslationPlan.comparableNumberTokens(in: "1.5 cups") != RecipeTranslationPlan.comparableNumberTokens(in: "1 1/2 Tassen"))
    }

    @Test func numberTokens_keepSeparatorsBetweenDigits() {
        #expect(RecipeTranslationPlan.numberTokens(in: "1.5 cups, 2,5 l and 1.000 g") == ["1.5", "2,5", "1.000"])
        #expect(RecipeTranslationPlan.numberTokens(in: "1½ EL, 20. Mai, 3, 4") == ["1", "½", "20", "3", "4"])
        #expect(RecipeTranslationPlan.numberTokens(in: "1/2 TL") == ["1", "2"])
        #expect(RecipeTranslationPlan.numberTokens(in: "keine Zahl") == [])
    }

    @Test func assembled_translatedUnit_isAccepted() throws {
        let plan = RecipeTranslationPlan(markdown: "## Ingredients\n- 2 tbsp curry paste\n- 1½ cups milk\n")
        let translations = Dictionary(uniqueKeysWithValues: plan.request.map {
            ($0.index, $0.text.hasPrefix("2") ? "2 EL Currypaste" : "1½ Tassen Milch")
        })
        let result = try plan.assembled(translations: translations, language: .german)
        #expect(result == "## Zutaten\n- 2 EL Currypaste\n- 1½ Tassen Milch\n")
    }

    @Test func assembled_amountsOutsideIngredientsAreNotCompared() throws {
        let plan = RecipeTranslationPlan(markdown: "## Ingredients\n- flour\n\n## Instructions\n1. Bake for 20 minutes.\n")
        let translations = Dictionary(uniqueKeysWithValues: plan.request.map { ($0.index, $0.text.hasPrefix("Bake") ? "Eine Viertelstunde backen." : "Mehl") })
        #expect(try plan.assembled(translations: translations, language: .german).contains("Eine Viertelstunde backen."))
    }

    @Test func assembled_otherHeadingTranslatedToZutaten_throwsStructureChanged() {
        let markdown = "# Curry\n\n## Ingredients\n- rice\n\n## For the sauce\n- tomatoes\n"
        let plan = RecipeTranslationPlan(markdown: markdown)
        let translations = Dictionary(uniqueKeysWithValues: plan.request.map {
            ($0.index, ["Curry": "Curry", "rice": "Reis", "For the sauce": "Zutaten", "tomatoes": "Tomaten"][$0.text]!)
        })
        #expect(throws: RecipeTranslationPlan.Failure.structureChanged) { try plan.assembled(translations: translations, language: .german) }
    }

    @Test func assembled_titleTranslatedToZutaten_throwsStructureChanged() {
        let plan = RecipeTranslationPlan(markdown: "# Curry\n\n## Ingredients\n- rice\n")
        let translations = Dictionary(uniqueKeysWithValues: plan.request.map { ($0.index, $0.text == "Curry" ? "Zutaten" : "Reis") })
        #expect(throws: RecipeTranslationPlan.Failure.structureChanged) { try plan.assembled(translations: translations, language: .german) }
    }

    @Test func assembled_noteWithoutIngredients_throwsNotARecipe() {
        let plan = RecipeTranslationPlan(markdown: "# Shopping ideas\n\nBuy flour.\n")
        let translations = Dictionary(uniqueKeysWithValues: plan.request.map { ($0.index, "Text") })
        #expect(throws: RecipeTranslationPlan.Failure.notARecipe) { try plan.assembled(translations: translations, language: .german) }
    }

    // MARK: Limits

    @Test func isWithinLimits_falseAbove300Lines() {
        let within = "## Ingredients\n" + (1..<RecipeTranslationPlan.maximumLines).map { "- item \($0)" }.joined(separator: "\n")
        #expect(RecipeTranslationPlan(markdown: within).isWithinLimits)
        let above = within + "\n- one more\n- and another"
        #expect(!RecipeTranslationPlan(markdown: above).isWithinLimits)
    }

    @Test func isWithinLimits_falseAbove12000Characters() {
        let longLine = String(repeating: "a", count: 4_000)
        let markdown = "## Ingredients\n- flour\n" + (0..<3).map { _ in "- \(longLine)" }.joined(separator: "\n")
        #expect(!RecipeTranslationPlan(markdown: markdown).isWithinLimits)
    }

    // MARK: RecipeNote additions

    @Test func outline_matchesParseClassification() {
        let markdown = "# Title\n\n## Ingredients:\n- a\n\n### Notes\nx\n\n## Directions\n1. b\n"
        #expect(RecipeNote.outline(markdown) == [.ingredients, .other, .steps])
        #expect(RecipeNote.outline("# Zutaten\n- a\n## Anleitung\n1. b") == [.ingredients, .steps])
        #expect(RecipeNote.outline("no headings at all") == [])
    }

    @Test func headingLanguage_germanEnglishUnknown() {
        #expect(RecipeNote.headingLanguage("## Zutaten\n- a") == .german)
        #expect(RecipeNote.headingLanguage("## Ingredients\n- a") == .english)
        #expect(RecipeNote.headingLanguage("## Ingredienti\n- a") == nil)
        #expect(RecipeNote.headingLanguage("- a") == nil)
    }
}
