import Foundation
import Testing
@testable import TagwerkCore

struct ShoppingTranslationPlanTests {
    private func item(_ id: String, _ name: String, quantity: String? = nil) -> ShoppingItem {
        ShoppingItem(id: id, name: name, quantity: quantity)
    }

    private func plan(_ names: [String]) -> ShoppingTranslationPlan {
        ShoppingTranslationPlan(openItems: names.enumerated().map { item("r\($0.offset)", $0.element) })
    }

    private func answer(_ texts: [String]) -> [(index: Int, text: String)] {
        texts.enumerated().map { (index: $0.offset, text: $0.element) }
    }

    // MARK: Offer

    @Test func offer_firstRun_adoptsTheCurrentLanguage() {
        #expect(ShoppingTranslationOffer.step(current: .english, settled: nil, openItemCount: 7) == .adopt(.english))
    }

    @Test func offer_sameLanguage_isNone() {
        #expect(ShoppingTranslationOffer.step(current: .german, settled: "de-DE", openItemCount: 7) == .none)
    }

    @Test func offer_changedLanguageWithItems_offers() {
        #expect(ShoppingTranslationOffer.step(current: .english, settled: "de-DE", openItemCount: 3) == .offer(.english))
    }

    @Test func offer_changedLanguageEmptyList_adopts() {
        #expect(ShoppingTranslationOffer.step(current: .english, settled: "de-DE", openItemCount: 0) == .adopt(.english))
    }

    @Test func offer_switchedBack_isNone() {
        // The card was shown for English; switching back to German, the settled language, hides it without a write.
        #expect(ShoppingTranslationOffer.step(current: .german, settled: "de-DE", openItemCount: 3) == .none)
    }

    @Test func offer_unknownStoredValue_offers() {
        #expect(ShoppingTranslationOffer.step(current: .german, settled: "xx-XX", openItemCount: 2) == .offer(.german))
    }

    // MARK: Request

    @Test func request_listsOpenNamesInListOrder() {
        let plan = plan(["Äpfel", "Karotten", "Milch"])
        #expect(plan.request.map(\.text) == ["Äpfel", "Karotten", "Milch"])
        #expect(plan.request.map(\.index) == [0, 1, 2])
        #expect(plan.leftOut == 0)
    }

    @Test func request_sameKeyGoesOutOnce() {
        let plan = ShoppingTranslationPlan(openItems: [item("a", "Milch"), item("b", "Eier"), item("c", "milch ")])
        #expect(plan.request.map(\.text) == ["Milch", "Eier"])
        #expect(plan.entries[0].itemIDs == ["a", "c"])
    }

    @Test func request_neverContainsQuantities() {
        let plan = ShoppingTranslationPlan(openItems: [item("a", "Milch", quantity: "2 Liter")])
        #expect(plan.request.map(\.text) == ["Milch"])
        #expect(!plan.request.contains { $0.text.contains("Liter") })
    }

    @Test func request_cutsAt100Names_andReportsTheRest() {
        let names = (1...123).map { "Artikel \($0)" }
        let plan = plan(names)
        #expect(plan.request.count == 100 && plan.request.last?.text == "Artikel 100")
        #expect(plan.leftOut == 23)
    }

    @Test func request_cutsAtCharacterLimit() {
        let names = (1...60).map { _ in String(repeating: "x", count: 70) }.enumerated().map { "\($0.offset)" + $0.element }
        let plan = plan(names)
        let characters = plan.request.reduce(0) { $0 + $1.text.count }
        #expect(characters <= ShoppingTranslationPlan.maximumCharacters)
        #expect(plan.request.count < 60 && plan.leftOut == 60 - plan.request.count)
    }

    // MARK: Whole answer

    @Test func changes_missingIndex_throws() {
        let plan = plan(["Äpfel", "Karotten"])
        #expect(throws: ShoppingTranslationPlan.Failure.indexMismatch) { try plan.changes(translations: [(0, "Apples")]) }
    }

    @Test func changes_extraIndex_throws() {
        let plan = plan(["Äpfel"])
        #expect(throws: ShoppingTranslationPlan.Failure.indexMismatch) { try plan.changes(translations: [(0, "Apples"), (1, "Carrots")]) }
        #expect(throws: ShoppingTranslationPlan.Failure.indexMismatch) { try plan.changes(translations: [(5, "Apples")]) }
    }

    @Test func changes_duplicateIndex_throws() {
        let plan = plan(["Äpfel", "Karotten"])
        #expect(throws: ShoppingTranslationPlan.Failure.indexMismatch) { try plan.changes(translations: [(0, "Apples"), (0, "Carrots")]) }
    }

    // MARK: Single entries

    @Test func changes_emptyText_keepsTheItem() throws {
        #expect(try plan(["Äpfel", "Milch"]).changes(translations: answer(["  ", "Milk"])).map(\.newName) == ["Milk"])
    }

    @Test func changes_lineBreak_keepsTheItem() throws {
        #expect(try plan(["Äpfel", "Milch"]).changes(translations: answer(["Apples\nand pears", "Milk"])).map(\.newName) == ["Milk"])
    }

    @Test func changes_tooLong_keepsTheItem() throws {
        let long = String(repeating: "a", count: ShoppingInputParser.maxNameLength + 1)
        #expect(try plan(["Äpfel", "Milch"]).changes(translations: answer([long, "Milk"])).map(\.newName) == ["Milk"])
        let exact = String(repeating: "a", count: ShoppingInputParser.maxNameLength)
        #expect(try plan(["Äpfel"]).changes(translations: answer([exact])).map(\.newName) == [exact])
    }

    @Test func changes_changedNumber_keepsTheItem() throws {
        let plan = plan(["Cola 0,5 l", "Milch 1 l"])
        let changes = try plan.changes(translations: answer(["Cola 0.33 l", "Milk 1 l"]))
        #expect(changes.map(\.oldName) == ["Milch 1 l"])
        #expect(try plan.changes(translations: answer(["Cola 0,5 l", "Milk 1 l"])).count == 1, "unchanged text is no change either")
    }

    @Test func changes_sameKey_isDropped() throws {
        #expect(try plan(["Äpfel"]).changes(translations: answer(["apfel"])).isEmpty)
    }

    @Test func changes_brandNameReturnedUnchanged_isDropped() throws {
        #expect(try plan(["Nutella", "Milch"]).changes(translations: answer(["Nutella", "Milk"])).map(\.oldName) == ["Milch"])
    }

    // MARK: Duplicates

    @Test func changes_translationAlreadyOnList_isBlocked() throws {
        let plan = plan(["Milch", "milk"])
        let changes = try plan.changes(translations: answer(["milk", "milk"]))
        #expect(changes.count == 1)
        #expect(changes[0].oldName == "Milch" && changes[0].blocked == .alreadyOnList)
    }

    @Test func changes_itemsLeftOutAreStillCheckedForDuplicates() throws {
        let names = ["Milch"] + (1...100).map { "Artikel \($0)" } + ["Milk"]
        let plan = ShoppingTranslationPlan(openItems: names.enumerated().map { item("r\($0.offset)", $0.element) })
        #expect(plan.leftOut == 2, "\"Artikel 100\" and \"Milk\" do not fit")
        let texts = plan.request.map { $0.text == "Milch" ? "Milk" : $0.text }
        let changes = try plan.changes(translations: answer(texts))
        #expect(changes.map(\.blocked) == [.alreadyOnList])
    }

    @Test func changes_twoItemsSameTranslation_secondIsBlocked() throws {
        let plan = plan(["Karotten", "Möhren"])
        let changes = try plan.changes(translations: answer(["Carrots", "Carrots"]))
        #expect(changes.map(\.blocked) == [nil, .sameTranslationTwice])
        #expect(changes.map(\.oldName) == ["Karotten", "Möhren"])
    }

    @Test func changes_twoRemindersSameName_renameTogether() throws {
        let plan = ShoppingTranslationPlan(openItems: [item("a", "Milch", quantity: "1 l"), item("b", "milch")])
        let changes = try plan.changes(translations: answer(["Milk"]))
        #expect(changes.map(\.itemID) == ["a", "b"] && changes.allSatisfy { $0.newName == "Milk" && $0.blocked == nil })
        #expect(changes.map(\.oldName) == ["Milch", "milch"])
    }

    // MARK: Display

    @Test func changes_carryTheQuantityForDisplay() throws {
        let plan = ShoppingTranslationPlan(openItems: [item("a", "Äpfel", quantity: "6 Stück"), item("b", "Milch")])
        let changes = try plan.changes(translations: answer(["Apples", "Milk"]))
        #expect(changes.map(\.quantity) == ["6 Stück", nil])
    }

    @Test func changes_trimTheNewName() throws {
        #expect(try plan(["Äpfel"]).changes(translations: answer(["  Apples \n"])).map(\.newName) == ["Apples"])
    }
}
