import Foundation
import Testing
@testable import TagwerkCore

struct ShoppingQuantityTests {
    private let german = Locale(identifier: "de_DE")
    private let english = Locale(identifier: "en_US")

    @Test func sum_plainNumbers() {
        #expect(ShoppingQuantity.sum("2", "1", locale: german) == "3")
        #expect(ShoppingQuantity.sum(" 2 ", "10", locale: german) == "12")
    }

    @Test func sum_sameUnit() {
        #expect(ShoppingQuantity.sum("200 g", "125 g", locale: german) == "325 g")
        #expect(ShoppingQuantity.sum("1 Dose", "2 Dosen", locale: german) == "3 Dosen")
        #expect(ShoppingQuantity.sum("1 EL", "1 EL", locale: german) == "2 EL")
        #expect(ShoppingQuantity.sum("1 Prise", "2 Prisen", locale: german) == "3 Prisen")
    }

    @Test func sum_unitFollowsTheTotal() {
        // A total of exactly one takes the singular form.
        #expect(ShoppingQuantity.sum("0,5 Dosen", "0,5 Dose", locale: german) == "1 Dose")
        #expect(ShoppingQuantity.sum("1 Dose", "1 Dose", locale: german) == "2 Dosen")
    }

    @Test func sum_differentUnits_isNil() {
        #expect(ShoppingQuantity.sum("1 kg", "200 g", locale: german) == nil)
        #expect(ShoppingQuantity.sum("1 Prise", "2", locale: german) == nil)
        #expect(ShoppingQuantity.sum("2", "1 Prise", locale: german) == nil)
    }

    @Test func sum_sameNameInsteadOfAUnit_adds() {
        #expect(ShoppingQuantity.sum("1 Beutel", "2 beutel", locale: german) == "3 Beutel")
        #expect(ShoppingQuantity.sum("1 Beutel", "2 Tüten", locale: german) == nil)
        #expect(ShoppingQuantity.sum("2 Zwiebeln", "1", locale: german) == nil, "a count with a name does not add to a bare number")
    }

    @Test func sum_decimalCommaLocale() {
        #expect(ShoppingQuantity.sum("1,5 l", "0,5 l", locale: german) == "2 l")
        #expect(ShoppingQuantity.sum("1,5 l", "0,25 l", locale: german) == "1,8 l")
        #expect(ShoppingQuantity.sum("1.5 l", "0.5 l", locale: english) == "2 l")
        #expect(ShoppingQuantity.sum("1,5 kg", "1 kg", locale: english) == "2.5 kg")
    }

    @Test func sum_missingExisting_takesTheRecipeQuantity() {
        #expect(ShoppingQuantity.sum(nil, "2", locale: german) == "2")
        #expect(ShoppingQuantity.sum("  ", "200 g", locale: german) == "200 g")
    }

    @Test func sum_missingExisting_takesAFreeTextAsItIs() {
        #expect(ShoppingQuantity.sum(nil, "nach Geschmack", locale: german) == "nach Geschmack")
    }

    @Test func sum_missingAdded_isNil() {
        #expect(ShoppingQuantity.sum("2", nil, locale: german) == nil)
        #expect(ShoppingQuantity.sum(nil, nil, locale: german) == nil)
    }

    @Test func sum_rangesAndFreeText_areNil() {
        #expect(ShoppingQuantity.sum("2–3", "1", locale: german) == nil)
        #expect(ShoppingQuantity.sum("2", "nach Geschmack", locale: german) == nil)
        #expect(ShoppingQuantity.sum("etwas", "2", locale: german) == nil)
        #expect(ShoppingQuantity.sum("2 EL Öl", "1 EL", locale: german) == nil, "a quantity with a name is no plain quantity")
    }

    @Test func merge_raisesWhenTheQuantitiesAdd() {
        #expect(ShoppingQuantity.merge(existing: "2", added: "1", locale: german) == .raise(to: "3"))
    }

    @Test func merge_makesASecondEntryWhenTheyDoNot() {
        #expect(ShoppingQuantity.merge(existing: "1 Prise", added: "2", locale: german) == .secondEntry)
    }

    @Test func merge_longNotes_neverRaise() {
        // Notes with more than the quantity line are never overwritten: the second entry takes the quantity.
        #expect(ShoppingQuantity.merge(existing: "2", added: "1", hasLongNotes: true, locale: german) == .secondEntry)
        #expect(ShoppingQuantity.merge(existing: "2", added: nil, hasLongNotes: true, locale: german) == .keep)
    }

    @Test func merge_keepsTheItemWhenTheRecipeNamesNoQuantity() {
        #expect(ShoppingQuantity.merge(existing: "2", added: nil, locale: german) == .keep)
        #expect(ShoppingQuantity.merge(existing: nil, added: "", locale: german) == .keep)
    }
}
