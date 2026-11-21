import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct ShoppingInputTests {
    @Test func preview_onlyForSeveralOrDictated() {
        let one = [ParsedItem(name: "Kaffee", quantity: nil)]
        #expect(!ShoppingInput.needsPreview(items: one, wasDictated: false))
        #expect(ShoppingInput.needsPreview(items: one, wasDictated: true))
        #expect(ShoppingInput.needsPreview(items: one + one, wasDictated: false))
        #expect(!ShoppingInput.needsPreview(items: [], wasDictated: true))
    }

    @Test func feedback_texts() {
        #expect(ShoppingInput.feedback(.init(added: ["Kaffee", "Reis", "Zwiebeln"]), droppedCount: 0) == "3 hinzugefügt")
        #expect(ShoppingInput.feedback(.init(alreadyOnList: ["Eier"]), droppedCount: 0) == "Eier steht schon drauf")
        #expect(ShoppingInput.feedback(.init(alreadyOnList: ["Eier", "Milch"]), droppedCount: 0) == "Eier, Milch stehen schon drauf")
        #expect(ShoppingInput.feedback(.init(reopened: ["Kaffee"]), droppedCount: 0) == "Kaffee wieder geöffnet")
        #expect(ShoppingInput.feedback(.init(added: ["Reis"], alreadyOnList: ["Eier"]), droppedCount: 3)
                == "1 hinzugefügt · Eier steht schon drauf · Höchstens 20 Artikel auf einmal")
    }

    @Test func feedback_failureAppendsTheErrorText() {
        let report = ShoppingModel.AddReport(added: ["Reis"], failed: ["Eier"], errorMessage: "Kein Zugriff auf diese Quelle.")
        #expect(ShoppingInput.feedback(report, droppedCount: 0) == "1 hinzugefügt · Kein Zugriff auf diese Quelle.")
        #expect(ShoppingInput.feedback(.init(), droppedCount: 0) == "")
    }

    @Test func chipTitle_showsQuantityBeforeName() {
        #expect(ShoppingInput.chipTitle(ParsedItem(name: "Zwiebeln", quantity: "2")) == "＋ 2 Zwiebeln")
        #expect(ShoppingInput.chipTitle(ParsedItem(name: "Kaffee", quantity: nil)) == "＋ Kaffee")
    }

    @Test func rowLabel_namesQuantityAndState() {
        let item = ShoppingItem(id: "1", name: "Hafermilch", quantity: "2 Packungen")
        #expect(ShoppingInput.accessibilityLabel(item) == "Hafermilch, 2 Packungen, nicht erledigt")
        #expect(ShoppingInput.accessibilityLabel(ShoppingItem(id: "2", name: "Eier", isCompleted: true)) == "Eier, erledigt")
    }
}

@MainActor
struct ShoppingLanguageChipTests {
    private let germanApp = Locale(identifier: "de_DE")

    @Test func chip_togglesBetweenTheTwoLanguages_andStoresAFixedValue() {
        let settings = AppSettings()
        settings.shoppingLanguage = "de-DE"
        settings.toggleShoppingLanguage()
        #expect(settings.shoppingLanguage == "en-US")
        settings.toggleShoppingLanguage()
        #expect(settings.shoppingLanguage == "de-DE")
    }

    @Test func chip_fromLikeRecipes_switchesToTheOtherLanguage() {
        let settings = AppSettings()
        settings.recipeLanguage = "en-US"
        #expect(settings.shoppingLanguage == "recipes" && settings.contentLanguages.shoppingLanguage(locale: germanApp) == .english)
        settings.toggleShoppingLanguage()
        #expect(settings.shoppingLanguage == "de-DE", "a fixed value, so changing the recipe language later does not switch the list")
        settings.recipeLanguage = "de-DE"
        #expect(settings.contentLanguages.shoppingLanguage(locale: germanApp) == .german)
        settings.recipeLanguage = "en-US"
        #expect(settings.contentLanguages.shoppingLanguage(locale: germanApp) == .german)
    }

    @Test func chip_fromLikeTheApp_switchesToTheOtherLanguage() {
        let settings = AppSettings()
        settings.shoppingLanguage = "auto"
        // The tests run in German: the list follows the app in German, so a tap makes it English.
        settings.toggleShoppingLanguage()
        #expect(settings.shoppingLanguage == (VoiceLanguage.from(locale: .current) == .german ? "en-US" : "de-DE"))
    }

    @Test func dictationAtShopping_usesTheShoppingLanguage() {
        let settings = AppSettings()
        settings.voiceRecognitionLanguage = "de-DE"
        settings.shoppingLanguage = "en-US"
        #expect(settings.dictationLanguage(at: .shopping) == .english)
        #expect(settings.dictationLanguage(at: .notes) == .german)
        settings.toggleShoppingLanguage()
        #expect(settings.dictationLanguage(at: .shopping) == .german)
    }
}
