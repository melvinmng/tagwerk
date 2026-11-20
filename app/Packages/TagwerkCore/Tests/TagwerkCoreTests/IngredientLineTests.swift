import Foundation
import Testing
@testable import TagwerkCore

struct IngredientLineTests {
    private let german = Locale(identifier: "de_DE")
    private let english = Locale(identifier: "en_US")

    @Test func parse_gramsAndName() {
        let line = IngredientLine.parse("250 g rote Linsen")
        #expect(line.amount == 250 && line.amountUpper == nil && line.unit == "g" && line.name == "rote Linsen")
        #expect(line.note == nil && !line.isToTaste)
        // The unit may be glued to the number.
        let glued = IngredientLine.parse("500g Mehl")
        #expect(glued.amount == 500 && glued.unit == "g" && glued.name == "Mehl")
    }

    @Test func parse_decimalComma() {
        let comma = IngredientLine.parse("1,5 l Milch")
        #expect(comma.amount == Decimal(string: "1.5") && comma.unit == "l" && comma.name == "Milch")
        let point = IngredientLine.parse("0.25 kg Butter")
        #expect(point.amount == Decimal(string: "0.25") && point.unit == "kg")
    }

    @Test func parse_unicodeFraction() {
        #expect(IngredientLine.parse("½ TL Salz").amount == Decimal(string: "0.5"))
        #expect(IngredientLine.parse("¾ Tasse Zucker").amount == Decimal(string: "0.75"))
        #expect(IngredientLine.parse("⅓ Bund Petersilie").unit == "Bund")
        let third = IngredientLine.parse("⅓ Tasse Reis")
        #expect(third.amount.map { IngredientLine.format($0, locale: german) } == "0,3")
    }

    @Test func parse_mixedFraction() {
        let spaced = IngredientLine.parse("1 1/2 EL Öl")
        #expect(spaced.amount == Decimal(string: "1.5") && spaced.unit == "EL" && spaced.name == "Öl")
        #expect(IngredientLine.parse("1/2 Zitrone").amount == Decimal(string: "0.5"))
        #expect(IngredientLine.parse("1½ Tassen Mehl").amount == Decimal(string: "1.5"))
        #expect(IngredientLine.parse("2 ¼ Tassen Mehl").amount == Decimal(string: "2.25"))
        // Two plain numbers are no mixed fraction.
        #expect(IngredientLine.parse("2 3 Eier").amount == 2)
    }

    @Test func parse_range() {
        for text in ["2-3 Zwiebeln", "2–3 Zwiebeln", "2 - 3 Zwiebeln"] {
            let line = IngredientLine.parse(text)
            #expect(line.amount == 2 && line.amountUpper == 3 && line.name == "Zwiebeln", "\(text)")
        }
        #expect(IngredientLine.parse("2-3 EL Öl").unit == "EL")
        // A descending pair is no range.
        #expect(IngredientLine.parse("3-1 Eier").amountUpper == nil)
    }

    @Test func parse_unitPlural_dosen() {
        let line = IngredientLine.parse("2 Dosen Tomaten")
        #expect(line.amount == 2 && line.unit == "Dosen" && line.name == "Tomaten" && line.unitKind == .container)
        let abbreviated = IngredientLine.parse("1 Pck. Hefe")
        #expect(abbreviated.unit == "Pck." && abbreviated.name == "Hefe")
        #expect(IngredientLine.parse("2 cups of flour").name == "flour")
    }

    @Test func parse_noAmount_wholeLineIsName() {
        let line = IngredientLine.parse("  frischer Basilikum (zum Garnieren) ")
        #expect(line.amount == nil && line.unit == nil && line.note == nil && !line.isToTaste)
        #expect(line.name == "frischer Basilikum (zum Garnieren)")
        // Letters glued to a number that are no unit: not an amount.
        #expect(IngredientLine.parse("3D-Brille").amount == nil)
        // Countable names without a unit keep the whole name.
        let eggs = IngredientLine.parse("2 große Eier")
        #expect(eggs.amount == 2 && eggs.unit == nil && eggs.name == "große Eier")
    }

    @Test func parse_toTaste_german() {
        for text in ["Salz nach Geschmack", "etwas Öl", "Pfeffer n. B.", "Muskat n.B."] {
            let line = IngredientLine.parse(text)
            #expect(line.isToTaste && line.amount == nil && line.name == text, "\(text)")
        }
        // With an amount the marker does not turn the line into a "to taste" line.
        #expect(!IngredientLine.parse("1 TL Salz, nach Geschmack mehr").isToTaste)
    }

    @Test func parse_toTaste_english() {
        for text in ["Salt to taste", "some olive oil"] {
            #expect(IngredientLine.parse(text).isToTaste, "\(text)")
        }
        // "some" is matched as a word only.
        #expect(!IngredientLine.parse("Awesome sauce").isToTaste)
    }

    @Test func parse_parenthesisKeptAsNote() {
        let line = IngredientLine.parse("1 Dose Kokosmilch (400 ml)")
        #expect(line.amount == 1 && line.unit == "Dose" && line.name == "Kokosmilch" && line.note == "400 ml")
        let middle = IngredientLine.parse("2 Zwiebeln (rot), gewürfelt")
        #expect(middle.name == "Zwiebeln, gewürfelt" && middle.note == "rot")
    }

    @Test func formatted_roundTrip_german() {
        for text in ["250 g rote Linsen", "1 Dose Kokosmilch (400 ml)", "1,5 EL Öl", "2–3 Zwiebeln", "2 große Eier", "Salz nach Geschmack"] {
            #expect(IngredientLine.parse(text).formatted(locale: german) == text, "\(text)")
        }
        // "1,0" reads "1", an en dash replaces the hyphen of a range.
        #expect(IngredientLine(amount: Decimal(string: "1.0"), unit: "EL", name: "Öl").formatted(locale: german) == "1 EL Öl")
        #expect(IngredientLine.parse("2-3 EL Öl").formatted(locale: german) == "2–3 EL Öl")
        #expect(IngredientLine.parse("1/3 Tasse Reis").formatted(locale: german) == "0,3 Tasse Reis")
    }

    @Test func formatted_englishDecimalPoint() {
        #expect(IngredientLine.parse("1,5 l Milch").formatted(locale: english) == "1.5 l Milch")
        #expect(IngredientLine.parse("1 1/2 cups flour").formatted(locale: english) == "1.5 cups flour")
    }
}
