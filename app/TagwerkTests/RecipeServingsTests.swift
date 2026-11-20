import Foundation
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct RecipeServingsTests {
    private let german = Locale(identifier: "de_DE")

    private func candidate(_ name: String, _ text: String?, category: String = "Sonstiges") -> RecipeImporter.Candidate {
        guard let text else { return RecipeImporter.Candidate(name: name, quantity: nil, category: category, alreadyOnList: false) }
        let line = IngredientLine.parse(text + " " + name)
        return RecipeImporter.Candidate(name: name, quantity: RecipeImporter.quantityText(of: line, locale: german),
                                        line: line.amount == nil ? nil : line, category: category, alreadyOnList: false)
    }

    @Test func servings_defaultTargetIsBase() {
        #expect(RecipeResultView.targetServings(base: 4, cooking: nil) == 4)
        #expect(RecipeResultView.targetServings(base: 4, cooking: 6) == 6)
        #expect(RecipeResultView.targetServings(base: nil, cooking: nil) == nil)
        // Changing "Rezept für" afterwards does not undo a choice of "Ich koche für".
        #expect(RecipeResultView.targetServings(base: 2, cooking: 6) == 6)
    }

    @Test func servings_missingBase_blocksAdd() {
        #expect(!RecipeResultView.canAdd(base: nil, selectedCount: 5))
        #expect(!RecipeResultView.canAdd(base: 4, selectedCount: 0))
        #expect(RecipeResultView.canAdd(base: 4, selectedCount: 1))
    }

    @Test func stepper_startsAtFour_andStaysInRange() {
        #expect(RecipeResultView.stepped(nil, by: 1) == 4 && RecipeResultView.stepped(nil, by: -1) == 4)
        #expect(RecipeResultView.stepped(4, by: 1) == 5 && RecipeResultView.stepped(4, by: -1) == 3)
        #expect(RecipeResultView.stepped(1, by: -1) == 1 && RecipeResultView.stepped(50, by: 1) == 50)
    }

    @Test func scaled_scalesStructuredAndFreeQuantities_namesStay() {
        let candidates = [candidate("rote Linsen", "250 g"), candidate("Kokosmilch", "1 Dose"), candidate("Ei", "1"),
                          candidate("Salz", nil), candidate("Prise Zimt", nil)]
        var free = candidate("Tomaten", nil)
        free.quantity = "2 Dosen"
        var text = candidate("Pfeffer", nil)
        text.quantity = "nach Geschmack"
        let scaled = RecipeResultView.scaled(candidates: candidates + [free, text], base: 4, target: 6, locale: german)
        #expect(scaled.map(\.quantity) == ["375 g", "1,5 Dosen", "2", nil, nil, "3 Dosen", "nach Geschmack"])
        // Names and ids stay, so the selection survives and the list gets the singular name.
        #expect(scaled.map(\.name) == (candidates + [free, text]).map(\.name) && scaled.map(\.id) == (candidates + [free, text]).map(\.id))
    }

    @Test func scaled_withoutBaseOrWithEqualServings_changesNothing() {
        let candidates = [candidate("rote Linsen", "250 g")]
        #expect(RecipeResultView.scaled(candidates: candidates, base: nil, target: 6, locale: german) == candidates)
        #expect(RecipeResultView.scaled(candidates: candidates, base: 4, target: 4, locale: german) == candidates)
        #expect(RecipeResultView.scaled(candidates: candidates, base: 4, target: nil, locale: german) == candidates)
    }

    @Test func scaled_keepsTheDecimalSeparatorOfTheRecipeLanguage() {
        let line = IngredientLine.parse("1 can coconut milk")
        let item = RecipeImporter.Candidate(name: "coconut milk", quantity: "1 can", line: line, category: "Sonstiges", alreadyOnList: false)
        let english = RecipeResultView.scaled(candidates: [item], base: 4, target: 6, locale: Locale(identifier: "en_US"))
        #expect(english[0].quantity == "1.5 cans")
    }

    @Test func servings_scaledQuantitiesGoOnTheList() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let settings = try AppSettings.current(in: container.mainContext)
        settings.shoppingListID = "shop"
        let now = testNow()
        let store = InMemoryReminderStore(lists: [ListInfo(id: "shop", title: "Einkauf", colorHex: nil, kind: .calDAV)], records: [], now: { now })
        let categories = ShoppingCategoryStore(context: container.mainContext, settings: settings, now: { now })
        categories.seedIfNeeded()
        let model = ShoppingModel(store: store, settings: settings, categories: categories, now: { now })
        let items = [candidate("rote Linsen", "250 g"), candidate("Kokosmilch", "1 Dose")]
        let chosen = RecipeResultView.scaled(candidates: items, base: 4, target: 6, locale: german)
        let report = await RecipeImporter.apply(chosen, model: model, categories: categories)
        #expect(Set(report.added) == ["rote Linsen", "Kokosmilch"])
        #expect(store.records.values.first { $0.title == "rote Linsen" }?.notes == "375 g")
        #expect(store.records.values.first { $0.title == "Kokosmilch" }?.notes == "1,5 Dosen")
    }
}
