import Foundation
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// EK4b: items of a recipe that are on the shopping list already stand in their own section; checking one raises its quantity
/// when the two can be added, otherwise a second entry is made. A quantity can be typed instead of the scaled one.
@MainActor
struct RecipeListedItemsTests {
    private let german = Locale(identifier: "de_DE")
    private let now = testNow()
    let container: ModelContainer
    let settings: AppSettings
    let store: InMemoryReminderStore
    let categories: ShoppingCategoryStore
    let model: ShoppingModel

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        settings.shoppingListID = "shop"
        let now = self.now
        func item(_ id: String, _ title: String, notes: String?) -> ReminderRecord {
            ReminderRecord(id: id, title: title, notes: notes, due: nil, ekPriority: 0, isCompleted: false, listID: "shop",
                           lastModified: nil, createdAt: now, completedAt: nil)
        }
        store = InMemoryReminderStore(
            lists: [ListInfo(id: "shop", title: "Einkauf", colorHex: nil, kind: .calDAV)],
            records: [item("onions", "Zwiebeln", notes: "2"), item("pinch", "Salz", notes: "1 Prise"),
                      item("long", "Mehl", notes: "500 g\nBio, Type 405"), item("plain", "Ingwer", notes: nil)],
            now: { now })
        categories = ShoppingCategoryStore(context: container.mainContext, settings: settings, now: { now })
        categories.seedIfNeeded()
        model = ShoppingModel(store: store, settings: settings, categories: categories, now: { now })
    }

    private func candidate(_ name: String, _ quantity: String?, onList: Bool = true) -> RecipeImporter.Candidate {
        RecipeImporter.Candidate(name: name, quantity: quantity, category: "Sonstiges", alreadyOnList: onList)
    }

    private func records(titled title: String) -> [ReminderRecord] { store.records.values.filter { $0.title == title } }

    // MARK: Applying

    @Test func apply_checkedExistingItem_raisesQuantity() async {
        let report = await RecipeImporter.apply([candidate("Zwiebeln", "1")], model: model, categories: categories, locale: german)
        #expect(report.raised == ["Zwiebeln"])
        #expect(report.added.isEmpty && report.failed.isEmpty)
        #expect(records(titled: "Zwiebeln").map(\.notes) == ["3"], "one entry, quantity raised from 2 to 3")
    }

    @Test func apply_checkedExistingItem_withoutSum_addsSecondEntry() async {
        let report = await RecipeImporter.apply([candidate("Salz", "2")], model: model, categories: categories, locale: german)
        #expect(report.added == ["Salz"] && report.raised.isEmpty)
        #expect(Set(records(titled: "Salz").map(\.notes)) == ["1 Prise", "2"], "the old entry stays, a second one is made")
    }

    @Test func apply_existingItemWithLongNotes_isNeverOverwritten() async {
        let report = await RecipeImporter.apply([candidate("Mehl", "250 g")], model: model, categories: categories, locale: german)
        #expect(report.added == ["Mehl"])
        #expect(Set(records(titled: "Mehl").map(\.notes)) == ["500 g\nBio, Type 405", "250 g"])
    }

    @Test func apply_existingItemWithoutQuantity_takesTheRecipeQuantity() async {
        let report = await RecipeImporter.apply([candidate("Ingwer", "10 g")], model: model, categories: categories, locale: german)
        #expect(report.raised == ["Ingwer"])
        #expect(records(titled: "Ingwer").map(\.notes) == ["10 g"])
    }

    @Test func apply_recipeWithoutQuantity_leavesTheItemAlone() async {
        let report = await RecipeImporter.apply([candidate("Zwiebeln", nil)], model: model, categories: categories, locale: german)
        #expect(report.alreadyOnList == ["Zwiebeln"] && report.added.isEmpty && report.raised.isEmpty)
        #expect(records(titled: "Zwiebeln").map(\.notes) == ["2"])
    }

    @Test func apply_newItem_isAddedAsBefore() async {
        let report = await RecipeImporter.apply([candidate("Kokosmilch", "1 Dose", onList: false)], model: model, categories: categories,
                                                locale: german)
        #expect(report.added == ["Kokosmilch"])
        #expect(records(titled: "Kokosmilch").map(\.notes) == ["1 Dose"])
    }

    @Test func apply_secondEntry_isFoundByTheInputBarAsTheFirst() async {
        // The input bar still dedups by name: it changes the first entry, never a third one.
        _ = await RecipeImporter.apply([candidate("Salz", "2")], model: model, categories: categories, locale: german)
        let report = await model.add([ParsedItem(name: "Salz", quantity: "3")])
        #expect(report.alreadyOnList == ["Salz"])
        #expect(records(titled: "Salz").count == 2)
    }

    // MARK: Lines and headers

    @Test func existingLine_raise() {
        let listed = ShoppingItem(id: "onions", name: "Zwiebeln", quantity: "2")
        #expect(RecipeResultView.existingLine(listed: listed, added: "1", locale: german) == "auf der Liste: 2 · anhaken erhöht auf 3")
    }

    @Test func existingLine_secondEntry() {
        let listed = ShoppingItem(id: "pinch", name: "Salz", quantity: "1 Prise")
        #expect(RecipeResultView.existingLine(listed: listed, added: "2", locale: german)
                == "auf der Liste: 1 Prise · anhaken legt einen zweiten Eintrag an")
        let long = ShoppingItem(id: "long", name: "Mehl", quantity: "500 g", hasLongNotes: true)
        #expect(RecipeResultView.existingLine(listed: long, added: "250 g", locale: german)
                == "auf der Liste: 500 g · anhaken legt einen zweiten Eintrag an")
    }

    @Test func existingLine_withoutQuantityOnTheList_andWithoutQuantityInTheRecipe() {
        let plain = ShoppingItem(id: "plain", name: "Ingwer")
        #expect(RecipeResultView.existingLine(listed: plain, added: "10 g", locale: german) == "auf der Liste: ohne Menge · anhaken setzt 10 g")
        #expect(RecipeResultView.existingLine(listed: plain, added: nil, locale: german) == "schon auf der Liste · bleibt unverändert")
        let onions = ShoppingItem(id: "onions", name: "Zwiebeln", quantity: "2")
        #expect(RecipeResultView.existingLine(listed: onions, added: nil, locale: german) == "auf der Liste: 2 · bleibt unverändert")
        #expect(RecipeResultView.existingLine(listed: nil, added: "1", locale: german) == "schon auf der Liste")
    }

    @Test func headers_carryTheCount() {
        #expect(RecipeResultView.newHeader(count: 3) == "Neu · 3")
        #expect(RecipeResultView.listedHeader(count: 1) == "Schon auf der Liste · 1")
        #expect(RecipeResultView.servingsHeader(recipeServings: 4) == "Portionen · 4 im Rezept")
        #expect(RecipeResultView.servingsHeader(recipeServings: nil) == "Portionen")
    }

    // MARK: Selection

    @Test func result_existingItemsStartDeselected() {
        let items = [candidate("Zwiebeln", "1"), candidate("Kokosmilch", "1 Dose", onList: false)]
        #expect(RecipeResultView.initiallyDeselected(items) == [ShoppingName.key("Zwiebeln")])
    }

    @Test func buttonTitle_countsSelected() {
        let items = [candidate("Zwiebeln", "1"), candidate("Kokosmilch", "1 Dose", onList: false), candidate("Ingwer", "10 g", onList: false)]
        let selected = RecipeResultView.selection(items, deselected: RecipeResultView.initiallyDeselected(items))
        #expect(RecipeResultView.addTitle(count: selected.count) == "2 Artikel hinzufügen")
    }

    // MARK: Typed quantities

    @Test func effective_typedQuantity_replacesTheScaledOne() {
        let line = IngredientLine.parse("125 g rote Linsen")
        let lentils = RecipeImporter.Candidate(name: "rote Linsen", quantity: "125 g", line: line, category: "Sonstiges", alreadyOnList: false)
        let scaled = RecipeResultView.effective([lentils], base: 4, target: 8, locale: german, overrides: [:])
        #expect(scaled[0].quantity == "250 g")
        let typed = RecipeResultView.effective([lentils], base: 4, target: 8, locale: german, overrides: [lentils.id: "1 Packung"])
        #expect(typed[0].quantity == "1 Packung")
        #expect(typed[0].line == nil, "a typed quantity is free text")
        #expect(RecipeImporter.listItem(for: typed[0], locale: german).quantity == "1 Packung")
    }

    @Test func effective_emptyTypedQuantity_clearsIt() {
        let lentils = RecipeImporter.Candidate(name: "rote Linsen", quantity: "125 g", category: "Sonstiges", alreadyOnList: false)
        let cleared = RecipeResultView.effective([lentils], base: nil, target: nil, locale: german, overrides: [lentils.id: "  "])
        #expect(cleared[0].quantity == nil)
    }
}
