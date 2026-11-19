import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct ShoppingCategoryStoreTests {
    let container: ModelContainer
    let settings: AppSettings
    let store: ShoppingCategoryStore

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        store = ShoppingCategoryStore(context: container.mainContext, settings: settings)
    }

    private func id(_ builtin: ShoppingBuiltinCategory) throws -> UUID {
        try #require(store.categories().first { $0.builtinKey == builtin.rawValue }).id
    }

    @Test func seed_createsTenBuiltinsInOrder_once() {
        store.seedIfNeeded()
        #expect(store.categories().map(\.builtinKey) == ShoppingBuiltinCategory.allCases.map(\.rawValue))
        #expect(store.categories().map(\.sortIndex) == Array(0..<10))
        #expect(store.categories().first?.name == "Obst & Gemüse")
        #expect(settings.shoppingCategoriesSeeded)
        store.delete(store.categories()[0].id)
        store.seedIfNeeded()
        #expect(store.categories().count == 9)
    }

    @Test func add_appendsAndValidates() throws {
        store.seedIfNeeded()
        #expect(try store.add(name: " Tierbedarf ").sortIndex == 10)
        #expect(store.categories().last?.name == "Tierbedarf")
        #expect(throws: ShoppingCategoryRules.NameError.duplicate) { try store.add(name: "tierbedarf") }
        #expect(store.categories().count == 11)
    }

    @Test func add_stopsAtThirtyCategories() throws {
        for index in 1...30 { try store.add(name: "K\(index)") }
        #expect(throws: ShoppingCategoryRules.NameError.limitReached) { try store.add(name: "Zu viel") }
    }

    @Test func rename_keepsBuiltinKey_andAllowsOwnNameWithOtherCase() throws {
        store.seedIfNeeded()
        let chilled = try id(.chilled)
        try store.rename(chilled, to: "Milchprodukte")
        #expect(store.categories().first { $0.id == chilled }?.name == "Milchprodukte")
        #expect(store.categories().first { $0.id == chilled }?.builtinKey == "chilled")
        try store.rename(chilled, to: "MILCHPRODUKTE")
        #expect(store.categories().first { $0.id == chilled }?.name == "MILCHPRODUKTE")
        #expect(throws: ShoppingCategoryRules.NameError.duplicate) { try store.rename(chilled, to: "getränke") }
    }

    @Test func move_rewritesSortIndex() {
        store.seedIfNeeded()
        store.move(fromOffsets: IndexSet(integer: 9), toOffset: 0)
        #expect(store.categories().map(\.builtinKey).prefix(2) == ["care", "produce"])
        #expect(store.categories().map(\.sortIndex) == Array(0..<10))
        store.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(store.categories().map(\.builtinKey).prefix(3) == ["produce", "bakery", "care"])
    }

    @Test func delete_removesAssignmentsOfThatCategoryOnly() throws {
        store.seedIfNeeded()
        let chilled = try id(.chilled), drinks = try id(.drinks)
        store.assign(nameKey: "milch", to: chilled, manual: true)
        store.assign(nameKey: "saft", to: drinks, manual: true)
        store.assign(nameKey: "schrauben", to: nil, manual: true)
        store.delete(chilled)
        #expect(store.categories().count == 9)
        #expect(Set(store.assignments().keys) == ["saft", "schrauben"])
    }

    @Test func restoreBuiltins_appendsOnlyMissing_keepsRenamedAndCustom() throws {
        store.seedIfNeeded()
        store.delete(try id(.frozen))
        try store.rename(try id(.chilled), to: "Milchprodukte")
        try store.add(name: "Tierbedarf")
        let before = store.categories().count
        store.restoreBuiltins()
        #expect(store.categories().count == before + 1)
        #expect(store.categories().last?.builtinKey == "frozen")
        #expect(store.categories().contains { $0.name == "Milchprodukte" && $0.builtinKey == "chilled" })
        #expect(store.categories().contains { $0.name == "Tierbedarf" })
        store.restoreBuiltins()
        #expect(store.categories().count == before + 1)
    }

    @Test func assign_upsertsByNameKey_andAIDoesNotOverrideManual() throws {
        store.seedIfNeeded()
        let a = try id(.chilled), b = try id(.drinks)
        store.assign(nameKey: "milch", to: a, manual: true)
        store.assign(nameKey: "milch", to: b, manual: false)
        #expect(store.assignments()["milch"] == ShoppingAssignmentInfo(categoryID: a, isManual: true))
        store.assign(nameKey: "milch", to: b, manual: true)
        #expect(store.assignments().count == 1 && store.assignments()["milch"]?.categoryID == b)
        store.assign(nameKey: "reis", to: a, manual: false)
        store.assign(nameKey: "reis", to: b, manual: false)
        #expect(store.assignments()["reis"] == ShoppingAssignmentInfo(categoryID: b, isManual: false))
    }
}
