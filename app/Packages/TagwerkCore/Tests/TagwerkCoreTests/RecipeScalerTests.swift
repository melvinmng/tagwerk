import Foundation
import Testing
@testable import TagwerkCore

struct RecipeScalerTests {
    private let german = Locale(identifier: "de_DE")
    private let english = Locale(identifier: "en_US")

    private func scaled(_ text: String, from base: Int, to target: Int, locale: Locale? = nil) -> String {
        RecipeScaler.scale(IngredientLine.parse(text), from: base, to: target).formatted(locale: locale ?? german)
    }

    @Test func fourToSix_grams() {
        #expect(scaled("250 g rote Linsen", from: 4, to: 6) == "375 g rote Linsen")
        #expect(scaled("200 ml Brühe", from: 4, to: 6) == "300 ml Brühe")
        // Between 10 and 1000 steps of 5, from 1000 steps of 10.
        #expect(scaled("333 g Mehl", from: 4, to: 6) == "500 g Mehl")
        #expect(scaled("1300 g Kartoffeln", from: 4, to: 6) == "1950 g Kartoffeln")
        #expect(scaled("750 g Kartoffeln", from: 4, to: 8) == "1500 g Kartoffeln")
        #expect(scaled("1 kg Kartoffeln", from: 4, to: 6) == "1,5 kg Kartoffeln")
        #expect(scaled("1 EL Öl", from: 4, to: 6) == "1,5 EL Öl")
    }

    @Test func fourToSix_cansBecomeOneAndAHalf() {
        #expect(scaled("1 Dose Kokosmilch", from: 4, to: 6) == "1,5 Dosen Kokosmilch")
        #expect(scaled("1 Dose Kokosmilch (400 ml)", from: 4, to: 6) == "1,5 Dosen Kokosmilch (400 ml)")
        #expect(scaled("1 can coconut milk", from: 4, to: 6, locale: english) == "1.5 cans coconut milk")
        #expect(scaled("2 Dosen Tomaten", from: 4, to: 2) == "1 Dose Tomaten")
    }

    @Test func fourToSix_eggsRoundUp() {
        #expect(scaled("1 Ei", from: 4, to: 6) == "2 Eier")
        #expect(scaled("2 Zwiebeln", from: 4, to: 6) == "3 Zwiebeln")
        #expect(scaled("1 Zwiebel", from: 4, to: 6) == "2 Zwiebeln")
        #expect(scaled("1 große Zwiebel", from: 4, to: 1) == "1 große Zwiebel")
        #expect(scaled("3 Eier", from: 6, to: 2) == "1 Ei")
        #expect(scaled("1 egg", from: 4, to: 6, locale: english) == "2 eggs")
        #expect(scaled("1 Zehe Knoblauch", from: 4, to: 6) == "2 Zehen Knoblauch")
        // Names outside the list stay as written.
        #expect(scaled("1 Karotte", from: 4, to: 6) == "2 Karotte")
    }

    @Test func twoToOne_smallGramsWhole() {
        #expect(scaled("5 g Hefe", from: 2, to: 1) == "3 g Hefe")
        #expect(scaled("1 g Safran", from: 4, to: 1) == "1 g Safran")
    }

    @Test func toTaste_unchanged() {
        for text in ["Salz nach Geschmack", "etwas Öl", "Pfeffer n. B.", "Salt to taste"] {
            #expect(scaled(text, from: 4, to: 6) == text, "\(text)")
        }
    }

    @Test func pinch_unchanged() {
        #expect(scaled("1 Prise Zimt", from: 4, to: 6) == "1 Prise Zimt")
        #expect(scaled("1 pinch salt", from: 4, to: 6, locale: english) == "1 pinch salt")
    }

    @Test func range_scalesBothEnds() {
        #expect(scaled("2–3 EL Öl", from: 4, to: 8) == "4–6 EL Öl")
        #expect(scaled("2-3 Zwiebeln", from: 4, to: 6) == "3–5 Zwiebeln")
    }

    @Test func sameServings_identity() {
        let line = IngredientLine.parse("250 g rote Linsen")
        #expect(RecipeScaler.scale(line, from: 4, to: 4) == line)
        #expect(RecipeScaler.scale("500 g", from: 4, to: 4, locale: german) == "500 g")
    }

    @Test func baseZero_unchanged() {
        let line = IngredientLine.parse("250 g rote Linsen")
        #expect(RecipeScaler.scale(line, from: 0, to: 6) == line)
        #expect(RecipeScaler.scale(line, from: 4, to: 0) == line)
        #expect(RecipeScaler.scale("250 g", from: 0, to: 6, locale: german) == "250 g")
    }

    @Test func quantityText_scalesFreeQuantities() {
        #expect(RecipeScaler.scale("500 g", from: 4, to: 6, locale: german) == "750 g")
        #expect(RecipeScaler.scale("2 Dosen", from: 4, to: 6, locale: german) == "3 Dosen")
        #expect(RecipeScaler.scale("1 Dose", from: 4, to: 6, locale: german) == "1,5 Dosen")
        #expect(RecipeScaler.scale("1 große Dose", from: 4, to: 6, locale: german) == "1,5 große Dosen")
        #expect(RecipeScaler.scale("nach Geschmack", from: 4, to: 6, locale: german) == "nach Geschmack")
        #expect(RecipeScaler.scale("1 Prise", from: 4, to: 6, locale: german) == "1 Prise")
        #expect(RecipeScaler.scale(nil, from: 4, to: 6, locale: german) == nil)
    }
}
