import AIKit
import Foundation
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// SP2b: the shopping list has its own language; a recipe import then returns a second name and unit per ingredient.
@MainActor
struct RecipeShoppingLanguageTests {
    let fixture = RecipeReadingFixture()
    private let names = ["Obst & Gemüse", "Kühlregal", "Vorrat & Konserven", "Sonstiges"]

    private typealias Entry = (name: String, amount: Double?, unit: String?, quantity: String?, category: String, shoppingName: String?, shoppingUnit: String?)

    private func answer(_ items: [Entry]) -> Data {
        let object: [String: Any] = [
            "title": "Lentil soup", "servings": 4, "steps": [],
            "items": items.map { ["name": $0.name, "amount": $0.amount as Any? ?? NSNull(), "unit": $0.unit as Any? ?? NSNull(),
                                   "quantity": $0.quantity as Any? ?? NSNull(), "category": $0.category,
                                   "shopping_name": $0.shoppingName as Any? ?? NSNull(), "shopping_unit": $0.shoppingUnit as Any? ?? NSNull()] }
        ]
        return try! JSONSerialization.data(withJSONObject: object)
    }

    private func validate(_ items: [Entry], shopping: VoiceLanguage? = .german, open: Set<String> = []) throws -> RecipeImporter.Result {
        try RecipeImporter.validate(answer(items), categoryNames: names, openItemKeys: open, language: .english, shoppingLanguage: shopping)
    }

    // MARK: Request

    @Test func inputText_sameLanguage_sendsNullShoppingLanguage() {
        let text = RecipeImporter.inputText(recipe: "500 g flour", categories: names, language: .german)
        #expect(text == "Recipe:\n500 g flour\n\nCategories and language as JSON:\n"
            + #"{"categories":["Obst & Gemüse","Kühlregal","Vorrat & Konserven","Sonstiges"],"language":"Deutsch","shopping_language":null}"#)
    }

    @Test func inputText_differentLanguage_namesBoth() {
        let text = RecipeImporter.inputText(recipe: "500 g flour", categories: ["Sonstiges"], language: .english, shoppingLanguage: .german)
        #expect(text.contains(#""language":"English""#) && text.contains(#""shopping_language":"Deutsch""#))
    }

    @Test func schema_requiresBothShoppingFields() throws {
        let schema = try #require(JSONSerialization.jsonObject(with: RecipeImporter.schema) as? [String: Any])
        let item = try #require(((schema["properties"] as? [String: Any])?["items"] as? [String: Any])?["items"] as? [String: Any])
        let required = try #require(item["required"] as? [String])
        #expect(required.contains("shopping_name") && required.contains("shopping_unit"))
    }

    @Test func read_sendsTheShoppingLanguageOnlyWhenGiven() async throws {
        fixture.responder.enqueue(fixture.curry)
        _ = try await fixture.importer().read(.text("250 g Linsen"), language: .german, shoppingLanguage: .english,
                                              categoryNames: fixture.categories, openItemKeys: [])
        #expect(fixture.sentText().contains(#""shopping_language":"English""#))
    }

    @Test func saveOnly_neverSendsAShoppingLanguage() async throws {
        // A recipe that is only saved passes no shopping language (RecipeSheet), so the request names none.
        fixture.responder.enqueue(fixture.curry)
        let result = try await fixture.importer().read(.text("250 g Linsen"), language: .german, categoryNames: [], openItemKeys: [])
        #expect(fixture.sentText().contains(#""shopping_language":null"#))
        #expect(result.shoppingLanguage == nil && result.candidates.allSatisfy { $0.shoppingName == nil && $0.shoppingUnit == nil })
    }

    // MARK: Validation

    @Test func validate_shoppingName_becomesTheListName() throws {
        let result = try validate([("red lentils", 250, "g", nil, "Vorrat & Konserven", "rote Linsen", "g")])
        let candidate = try #require(result.candidates.first)
        #expect(candidate.name == "red lentils" && candidate.shoppingName == "rote Linsen" && candidate.listName == "rote Linsen")
        #expect(candidate.id == ShoppingName.key("rote Linsen"))
        #expect(result.shoppingLanguage == .german)
    }

    @Test func validate_missingShoppingName_fallsBackToName() throws {
        let result = try validate([("lentils", 1, "kg", nil, "Sonstiges", nil, nil)])
        #expect(result.candidates.first?.listName == "lentils" && result.candidates.first?.shoppingName == nil)
    }

    @Test func validate_shoppingNameOnOpenList_isMarkedAlreadyOnList() throws {
        let result = try validate([("milk", 1, "l", nil, "Kühlregal", "Milch", "l")], open: [ShoppingName.key("Milch")])
        #expect(result.candidates.first?.alreadyOnList == true)
        // The recipe name alone would not have matched the German list.
        #expect(try validate([("milk", 1, "l", nil, "Kühlregal", nil, nil)], open: [ShoppingName.key("Milch")]).candidates.first?.alreadyOnList == false)
    }

    @Test func validate_twoIngredientsSameShoppingName_areMerged() throws {
        let result = try validate([("carrots", 2, nil, nil, "Obst & Gemüse", "Karotten", nil),
                                   ("baby carrots", 100, "g", nil, "Obst & Gemüse", "Karotten", "g")])
        #expect(result.candidates.count == 1)
        #expect(result.candidates.first?.name == "carrots")
    }

    @Test func validate_emptyShoppingName_isIgnored() throws {
        let result = try validate([("salt", nil, nil, "to taste", "Sonstiges", "  ", " ")])
        #expect(result.candidates.first?.shoppingName == nil && result.candidates.first?.shoppingUnit == nil)
    }

    @Test func validate_shoppingNameLongerThanLimit_isCut() throws {
        let long = String(repeating: "a", count: ShoppingInputParser.maxNameLength + 20)
        let result = try validate([("x", 1, nil, nil, "Sonstiges", long, nil)])
        #expect(result.candidates.first?.shoppingName?.count == ShoppingInputParser.maxNameLength)
    }

    @Test func validate_withoutShoppingLanguage_ignoresSecondNames() throws {
        let result = try validate([("milk", 1, "l", nil, "Kühlregal", "Milch", "l")], shopping: nil)
        #expect(result.candidates.first?.shoppingName == nil && result.shoppingLanguage == nil)
    }

    // MARK: List item and apply

    @Test func listItem_usesShoppingUnitAndLocale() {
        let cans = RecipeImporter.Candidate(name: "tomatoes", quantity: "2 cans", line: IngredientLine(amount: 2, unit: "cans", name: "tomatoes"),
                                            category: "Sonstiges", alreadyOnList: false, shoppingName: "Tomaten", shoppingUnit: "Dosen")
        #expect(RecipeImporter.listItem(for: cans, locale: Locale(identifier: "de_DE")) == ParsedItem(name: "Tomaten", quantity: "2 Dosen"))
        let liters = RecipeImporter.Candidate(name: "milk", quantity: "1.5 l", line: IngredientLine(amount: 1.5, unit: "l", name: "milk"),
                                              category: "Sonstiges", alreadyOnList: false, shoppingName: "Milch", shoppingUnit: "l")
        #expect(RecipeImporter.listItem(for: liters, locale: Locale(identifier: "de_DE")).quantity == "1,5 l")
    }

    @Test func listItem_freeTextAndPlainCandidates_keepTheirQuantity() {
        let salt = RecipeImporter.Candidate(name: "salt", quantity: "to taste", category: "Sonstiges", alreadyOnList: false, shoppingName: "Salz")
        #expect(RecipeImporter.listItem(for: salt, locale: Locale(identifier: "de_DE")) == ParsedItem(name: "Salz", quantity: "to taste"))
        let plain = RecipeImporter.Candidate(name: "Mehl", quantity: "500 g", line: IngredientLine(amount: 500, unit: "g", name: "Mehl"),
                                             category: "Sonstiges", alreadyOnList: false)
        #expect(RecipeImporter.listItem(for: plain, locale: Locale(identifier: "en_US")) == ParsedItem(name: "Mehl", quantity: "500 g"))
    }

    @Test func apply_putsShoppingNamesOnTheList_andRemembersTheirCategory() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let settings = try AppSettings.current(in: container.mainContext)
        settings.shoppingListID = "shop"
        let now = testNow()
        let store = InMemoryReminderStore(lists: [ListInfo(id: "shop", title: "Einkauf", colorHex: nil, kind: .calDAV)], records: [], now: { now })
        let categoryStore = ShoppingCategoryStore(context: container.mainContext, settings: settings, now: { now })
        categoryStore.seedIfNeeded()
        let model = ShoppingModel(store: store, settings: settings, categories: categoryStore, now: { now })
        let fridge = try #require(categoryStore.categories().first { $0.builtinKey == ShoppingBuiltinCategory.chilled.rawValue })
        let candidate = RecipeImporter.Candidate(name: "yoghurt", quantity: "2 cups", line: IngredientLine(amount: 2, unit: "cups", name: "yoghurt"),
                                                 category: fridge.name, alreadyOnList: false, shoppingName: "Joghurt", shoppingUnit: "Becher")
        let report = await RecipeImporter.apply([candidate], model: model, categories: categoryStore, locale: Locale(identifier: "de_DE"))
        #expect(report.added == ["Joghurt"] && report.failed.isEmpty)
        #expect(store.records.values.first?.title == "Joghurt" && store.records.values.first?.notes == "2 Becher")
        #expect(categoryStore.assignments()[ShoppingName.key("Joghurt")] == ShoppingAssignmentInfo(categoryID: fridge.id, isManual: false))
        #expect(categoryStore.assignments()[ShoppingName.key("yoghurt")] == nil)
    }

    // MARK: Note and scaling

    @Test func recipeNote_alwaysUsesRecipeLanguageNames() {
        let candidate = RecipeImporter.Candidate(name: "red lentils", quantity: "250 g", line: IngredientLine(amount: 250, unit: "g", name: "red lentils"),
                                                 category: "Sonstiges", alreadyOnList: false, shoppingName: "rote Linsen", shoppingUnit: "g")
        let result = RecipeImporter.Result(title: "Soup", servings: 4, candidates: [candidate], steps: [], sourceURL: nil, language: .english,
                                           shoppingLanguage: .german)
        let note = RecipeNoteWriter.recipeNote(from: result, title: "Soup", servings: 4)
        #expect(note.ingredients == ["250 g red lentils"])
        #expect(!note.markdown(language: .english).contains("rote Linsen"))
    }

    @Test func scaled_keepsShoppingNames() {
        let candidate = RecipeImporter.Candidate(name: "carrots", quantity: "2", line: IngredientLine(amount: 2, unit: nil, name: "carrots"),
                                                 category: "Sonstiges", alreadyOnList: false, shoppingName: "Karotten")
        let scaled = RecipeResultView.scaled(candidates: [candidate], base: 2, target: 4, locale: Locale(identifier: "en_US"))
        #expect(scaled.first?.shoppingName == "Karotten" && scaled.first?.listName == "Karotten" && scaled.first?.quantity == "4")
    }

    // MARK: Local read of a note

    private func noteText(headings: (String, String)) -> String {
        "# Soup\nPortionen: 4\n\n## \(headings.0)\n- 250 g red lentils\n- 2 carrots\n\n## \(headings.1)\n1. Cook.\n"
    }

    @Test func noteInput_differentShoppingLanguage_neverCallsTheResponder() async throws {
        let result = try await fixture.importer(consent: false).read(.note(UUID(), text: noteText(headings: ("Ingredients", "Instructions"))),
                                                                     language: .english, shoppingLanguage: .german,
                                                                     categoryNames: fixture.categories, openItemKeys: [])
        #expect(result.readLocally && fixture.responder.calls.isEmpty && fixture.modelCalls.models == 0 && fixture.fetcher.urls.isEmpty)
        #expect(result.candidates.allSatisfy { $0.shoppingName == nil && $0.shoppingUnit == nil })
    }

    @Test func noteInput_differentShoppingLanguage_marksKeepsNoteLanguage() async throws {
        let english = noteText(headings: ("Ingredients", "Instructions"))
        let marked = try await fixture.importer(consent: false).read(.note(UUID(), text: english), language: .english, shoppingLanguage: .german,
                                                                     categoryNames: fixture.categories, openItemKeys: [])
        #expect(marked.keepsNoteLanguage && marked.noteLanguage == .english)
        // The list has the language of the note, or the recipe and the list share one language: no hint.
        let same = try await fixture.importer(consent: false).read(.note(UUID(), text: english), language: .english, shoppingLanguage: .english,
                                                                   categoryNames: fixture.categories, openItemKeys: [])
        let none = try await fixture.importer(consent: false).read(.note(UUID(), text: english), language: .english,
                                                                   categoryNames: fixture.categories, openItemKeys: [])
        #expect(!same.keepsNoteLanguage && !none.keepsNoteLanguage)
    }

    @Test func noteInput_languageComesFromTheHeadings_notFromTheRecipeSetting() async throws {
        let german = noteText(headings: ("Zutaten", "Zubereitung"))
        let result = try await fixture.importer(consent: false).read(.note(UUID(), text: german), language: .english, shoppingLanguage: .german,
                                                                     categoryNames: fixture.categories, openItemKeys: [])
        #expect(result.noteLanguage == .german && !result.keepsNoteLanguage)
    }
    @Test func noteInput_listAndRecipeEnglish_germanNote_marksKeepsNoteLanguage() async throws {
        // The recipe language and the list share English (no second language), but the note is German: its names stay German.
        let german = noteText(headings: ("Zutaten", "Zubereitung"))
        let result = try await fixture.importer(consent: false).read(.note(UUID(), text: german), language: .english,
                                                                     categoryNames: fixture.categories, openItemKeys: [])
        #expect(result.keepsNoteLanguage && result.noteLanguage == .german)
    }
}
