import AIKit
import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

/// Loads a fixed page; records the addresses.
final class RecipeLinkFetcher: PageFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var requested: [URL] = []
    var page = ""
    var urls: [URL] { lock.withLock { requested } }

    func fetch(_ url: URL) async throws -> Data {
        lock.withLock { requested.append(url) }
        return Data(page.utf8)
    }
}

/// Shared helpers of the tests that read a recipe: the answer of ChatGPT in the new schema and the importer.
@MainActor
final class RecipeReadingFixture {
    let responder = FakePlanResponder()
    let fetcher = RecipeLinkFetcher()
    final class Counter { var models = 0 }
    let modelCalls = Counter()
    let categories = ["Obst & Gemüse", "Kühlregal", "Vorrat & Konserven"]

    func importer(consent: Bool = true) -> RecipeImporter {
        let calls = modelCalls
        return RecipeImporter(responder: responder, model: { calls.models += 1; return "gpt-test" }, hasConsent: { consent },
                              fetcher: fetcher, timeout: .seconds(30))
    }

    /// The answer in the schema of the recipe import: title, servings, steps, items with amount and unit.
    func answer(title: String? = "Linsencurry", servings: Int? = 4, steps: [String] = ["Zwiebeln andünsten.", "Linsen garen."],
                items: [(name: String, amount: Double?, unit: String?, quantity: String?, category: String)]) -> String {
        let object: [String: Any] = [
            "title": title as Any? ?? NSNull(), "servings": servings as Any? ?? NSNull(), "steps": steps,
            "items": items.map { ["name": $0.name, "amount": $0.amount as Any? ?? NSNull(), "unit": $0.unit as Any? ?? NSNull(),
                                   "quantity": $0.quantity as Any? ?? NSNull(), "category": $0.category] }
        ]
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    var curry: String {
        answer(items: [("rote Linsen", 250, "g", nil, "Vorrat & Konserven"), ("Kokosmilch", 1, "Dose", nil, "Vorrat & Konserven"),
                       ("Ei", 2, nil, nil, "Kühlregal"), ("Salz", nil, nil, "nach Geschmack", "Vorrat & Konserven")])
    }

    func sentText(_ index: Int = 0) -> String {
        responder.calls[index].input.map { item -> String in
            switch item {
            case .user(let text): text
            case .userImage(let text, _), .userImages(let text, _): text
            default: ""
            }
        }.joined(separator: "\n")
    }
}

@MainActor
struct RecipeReadingTests {
    let fixture = RecipeReadingFixture()

    // MARK: Schema and prompt

    @Test func schema_hasServingsTitleStepsAmountUnit() throws {
        let schema = try #require(try JSONSerialization.jsonObject(with: RecipeImporter.schema) as? [String: Any])
        let properties = try #require(schema["properties"] as? [String: Any])
        #expect(Set(properties.keys) == ["title", "servings", "steps", "items"])
        #expect(Set(try #require(schema["required"] as? [String])) == ["title", "servings", "steps", "items"])
        #expect(schema["additionalProperties"] as? Bool == false)
        let items = try #require((properties["items"] as? [String: Any])?["items"] as? [String: Any])
        let entry = try #require(items["properties"] as? [String: Any])
        let itemKeys: Set<String> = ["name", "amount", "unit", "quantity", "category", "shopping_name", "shopping_unit"]
        #expect(Set(entry.keys) == itemKeys)
        #expect(Set(try #require(items["required"] as? [String])) == itemKeys)
        #expect(items["additionalProperties"] as? Bool == false)
    }

    @Test func inputText_namesTheRecipeLanguage() {
        let german = RecipeImporter.inputText(recipe: "500 g Mehl", categories: ["Kühlregal"], language: .german)
        let english = RecipeImporter.inputText(recipe: nil, categories: ["Kühlregal"], language: .english)
        #expect(german.contains(#""language":"Deutsch""#) && german.contains("500 g Mehl"))
        #expect(english.contains(#""language":"English""#) && english.contains("photo"))
    }

    @Test func instructions_askForTheRecipeLanguage_notTheLanguageOfTheRecipe() {
        let text = RecipeImporter.instructions
        #expect(text.contains(#"in der Sprache aus "language""#) && text.contains("Übersetze, wenn das Rezept eine andere"))
        #expect(text.contains("Übersetze keine Eigennamen"))
        #expect(!text.contains("Behalte die Sprache des Rezepts bei"))
    }

    @Test func englishRecipeLanguage_withAGermanRecipe_asksForEnglish() async throws {
        fixture.responder.enqueue(fixture.answer(title: "Lentil curry", items: [("red lentils", 250, "g", nil, "Vorrat & Konserven")]))
        let result = try await fixture.importer().read(.text("250 g rote Linsen"), language: .english,
                                                       categoryNames: fixture.categories, openItemKeys: [])
        #expect(fixture.sentText().contains(#""language":"English""#) && fixture.sentText().contains("250 g rote Linsen"))
        #expect(result.language == .english && result.title == "Lentil curry")
        // The amounts are written with the decimal separator of that language.
        fixture.responder.enqueue(fixture.answer(items: [("flour", 1.5, "cups", nil, "Sonstiges")]))
        let english = try await fixture.importer().read(.text("x"), language: .english, categoryNames: [], openItemKeys: [])
        let german = try RecipeImporter.validate(Data(fixture.answer(items: [("Mehl", 1.5, "Tassen", nil, "Sonstiges")]).utf8),
                                                 categoryNames: ["Sonstiges"], openItemKeys: [], language: .german)
        #expect(english.candidates[0].quantity == "1.5 cups" && german.candidates[0].quantity == "1,5 Tassen")
    }

    // MARK: Validation

    @Test func validate_keepsServingsAndSteps() throws {
        let result = try RecipeImporter.validate(Data(fixture.curry.utf8), categoryNames: fixture.categories + ["Sonstiges"], openItemKeys: [])
        #expect(result.title == "Linsencurry" && result.servings == 4)
        #expect(result.steps == ["Zwiebeln andünsten.", "Linsen garen."] && result.sourceURL == nil)
        #expect(result.candidates.map(\.name) == ["rote Linsen", "Kokosmilch", "Ei", "Salz"])
    }

    @Test func validate_servingsOutsideOneToFifty_areNil() throws {
        for servings in [0, 51, 400, -2] {
            let result = try RecipeImporter.validate(Data(fixture.answer(servings: servings, items: [("Mehl", nil, nil, nil, "Sonstiges")]).utf8),
                                                     categoryNames: ["Sonstiges"], openItemKeys: [])
            #expect(result.servings == nil, "\(servings)")
        }
        let none = try RecipeImporter.validate(Data(fixture.answer(title: nil, servings: nil, items: [("Mehl", nil, nil, nil, "Sonstiges")]).utf8),
                                               categoryNames: ["Sonstiges"], openItemKeys: [])
        #expect(none.servings == nil && none.title.isEmpty)
    }

    @Test func validate_capsSteps() throws {
        let many = (1...30).map { "Schritt \($0)" } + ["  ", String(repeating: "x", count: 500)]
        let result = try RecipeImporter.validate(Data(fixture.answer(steps: many, items: [("Mehl", nil, nil, nil, "Sonstiges")]).utf8),
                                                 categoryNames: ["Sonstiges"], openItemKeys: [])
        #expect(result.steps.count == RecipeImporter.maxSteps && result.steps.first == "Schritt 1" && result.steps.last == "Schritt 20")
        let long = try RecipeImporter.validate(Data(fixture.answer(steps: ["", String(repeating: "x", count: 500)], items: [("Mehl", nil, nil, nil, "Sonstiges")]).utf8),
                                               categoryNames: ["Sonstiges"], openItemKeys: [])
        #expect(long.steps.count == 1 && long.steps[0].count == RecipeImporter.maxStepLength)
    }

    @Test func validate_amountAndUnitBecomeIngredientLine() throws {
        let result = try RecipeImporter.validate(Data(fixture.curry.utf8), categoryNames: fixture.categories + ["Sonstiges"], openItemKeys: [])
        let lentils = result.candidates[0]
        #expect(lentils.line?.amount == 250 && lentils.line?.unit == "g" && lentils.quantity == "250 g")
        #expect(result.candidates[1].line?.unit == "Dose" && result.candidates[1].quantity == "1 Dose")
        // A count has an amount but no unit; free text stays a quantity without a line.
        #expect(result.candidates[2].line?.amount == 2 && result.candidates[2].line?.unit == nil && result.candidates[2].quantity == "2")
        #expect(result.candidates[3].line == nil && result.candidates[3].quantity == "nach Geschmack")
        // A nonsense amount is dropped; the free quantity is used then.
        let odd = try RecipeImporter.validate(Data(fixture.answer(items: [("Mehl", -3, "g", "etwas", "Sonstiges"), ("Zucker", 0, nil, nil, "Sonstiges")]).utf8),
                                              categoryNames: ["Sonstiges"], openItemKeys: [])
        #expect(odd.candidates[0].line == nil && odd.candidates[0].quantity == "etwas" && odd.candidates[1].line == nil)
    }

    // MARK: Links

    @Test func link_resultCarriesSourceURL() async throws {
        fixture.fetcher.page = #"<html><script type="application/ld+json">{"@type":"Recipe","recipeIngredient":["200 g Linsen"]}</script></html>"#
        fixture.responder.enqueue(fixture.curry)
        let url = URL(string: "https://www.example.com/rezepte/linsencurry")!
        let result = try await fixture.importer().read(.link(url), language: .german, categoryNames: fixture.categories, openItemKeys: [])
        #expect(result.sourceURL == url)
        // Text and photo have no address.
        fixture.responder.enqueue(fixture.curry)
        let text = try await fixture.importer().read(.text("200 g Linsen"), language: .german, categoryNames: fixture.categories, openItemKeys: [])
        #expect(text.sourceURL == nil)
        #expect(!fixture.sentText().contains("example.com"))
    }

    // MARK: Notes

    private let structuredNote = """
    # Linsencurry

    Portionen: 4

    ## Zutaten
    - 250 g rote Linsen
    - 1 Dose Kokosmilch (400 ml)
    - 2 Eier
    - Salz nach Geschmack

    ## Zubereitung
    1. Zwiebeln andünsten.
    2. Linsen garen.

    Quelle: [chefkoch.de](https://www.chefkoch.de/rezepte/1)
    """

    @Test func structuredNote_neverCallsTheResponder() async throws {
        let classified = ClassifierLog()
        let result = try await fixture.importer().read(.note(UUID(), text: structuredNote), language: .german, categoryNames: fixture.categories,
                                                       openItemKeys: ["eier"]) { key in
            classified.keys.append(key)
            return key == "eier" ? "Kühlregal" : nil
        }
        #expect(fixture.responder.calls.isEmpty && fixture.modelCalls.models == 0 && fixture.fetcher.urls.isEmpty)
        #expect(result.title == "Linsencurry" && result.servings == 4 && result.readLocally)
        #expect(result.steps == ["Zwiebeln andünsten.", "Linsen garen."] && result.sourceURL?.host() == "www.chefkoch.de")
        #expect(result.candidates.map(\.name) == ["rote Linsen", "Kokosmilch", "Eier", "Salz nach Geschmack"])
        #expect(result.candidates.map(\.quantity) == ["250 g", "1 Dose (400 ml)", "2", nil])
        // The categories come from the classifier of the list; what it does not know is "Sonstiges".
        #expect(result.candidates.map(\.category) == ["Sonstiges", "Sonstiges", "Kühlregal", "Sonstiges"])
        #expect(result.candidates.map(\.alreadyOnList) == [false, false, true, false])
        #expect(classified.keys.contains("rote linsen"))
    }

    @Test func structuredNote_withoutConsent_works() async throws {
        let result = try await fixture.importer(consent: false).read(.note(UUID(), text: structuredNote), language: .german,
                                                                     categoryNames: fixture.categories, openItemKeys: [])
        #expect(result.candidates.count == 4 && fixture.responder.calls.isEmpty)
    }

    @Test func structuredNote_keepsAmountsAsNumbers() async throws {
        let result = try await fixture.importer().read(.note(UUID(), text: structuredNote), language: .german,
                                                       categoryNames: fixture.categories, openItemKeys: [])
        #expect(result.candidates[0].line?.amount == 250 && result.candidates[1].line?.unit == "Dose" && result.candidates[3].line == nil)
    }

    @Test func unstructuredNote_needsConsent() async {
        await #expect(throws: RecipeImporter.Failure.consentMissing) {
            try await fixture.importer(consent: false).read(.note(UUID(), text: "Linsen kaufen und kochen"), language: .german,
                                                            categoryNames: fixture.categories, openItemKeys: [])
        }
        #expect(fixture.responder.calls.isEmpty && fixture.modelCalls.models == 0)
    }

    @Test func unstructuredNote_sendsTheText() async throws {
        fixture.responder.enqueue(fixture.curry)
        let result = try await fixture.importer().read(.note(UUID(), text: "  Linsencurry: 250 g Linsen, 1 Dose Kokosmilch  "),
                                                       language: .german, categoryNames: fixture.categories, openItemKeys: [])
        #expect(fixture.responder.calls.count == 1 && fixture.sentText().contains("Linsencurry: 250 g Linsen, 1 Dose Kokosmilch"))
        #expect(!result.readLocally && result.sourceURL == nil)
    }

    @Test func classifier_usesAssignmentsThenDictionary() {
        let dairy = ShoppingCategoryInfo(id: UUID(), name: "Kühlregal", sortIndex: 0, builtinKey: ShoppingBuiltinCategory.chilled.rawValue)
        let produce = ShoppingCategoryInfo(id: UUID(), name: "Obst & Gemüse", sortIndex: 1, builtinKey: ShoppingBuiltinCategory.produce.rawValue)
        let assignments = ["kerzen": ShoppingAssignmentInfo(categoryID: produce.id, isManual: true)]
        let classify = RecipeImporter.localClassifier(assignments: assignments, categories: [dairy, produce])
        #expect(classify("kerzen") == "Obst & Gemüse")
        #expect(classify("milch") == "Kühlregal")
        #expect(classify("unbekanntes ding") == nil)
    }
}

private final class ClassifierLog { var keys: [String] = [] }
