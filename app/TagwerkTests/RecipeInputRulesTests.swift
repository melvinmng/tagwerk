import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

/// EK3b: the recipe sheet puts the source first and ends in two buttons; the tapped button decides the purpose.
@MainActor
struct RecipeInputRulesTests {
    // MARK: The purpose is chosen by the button

    @Test func purpose_isChosenByButton() {
        let keys: Set<String> = ["milch"]
        let names = ["Kühlregal", "Sonstiges"]
        // "Zutaten auf die Einkaufsliste" sends the categories and the open items of the list ...
        let shopping = RecipeInputRules.requestContext(for: .shopping, openItemKeys: keys, categoryNames: names, shoppingLanguage: .english)
        #expect(shopping.openItemKeys == keys)
        #expect(shopping.categoryNames == names)
        #expect(shopping.shoppingLanguage == .english)
        // ... "Nur als Rezept speichern" sends none of them, however the sheet got there (also after the consent sheet).
        let saveOnly = RecipeInputRules.requestContext(for: .saveOnly, openItemKeys: keys, categoryNames: names, shoppingLanguage: .english)
        #expect(saveOnly.openItemKeys.isEmpty)
        #expect(saveOnly.categoryNames.isEmpty)
        #expect(saveOnly.shoppingLanguage == nil)
    }

    @Test func purpose_ofTheTappedButton_decidesWhetherTheResultIsOnlySaved() {
        #expect(RecipeSheet.savesOnly(offersSaveOnly: true, purpose: .saveOnly))
        #expect(!RecipeSheet.savesOnly(offersSaveOnly: true, purpose: .shopping))
        #expect(!RecipeSheet.savesOnly(offersSaveOnly: false, purpose: .saveOnly))
    }

    // MARK: Buttons

    @Test func buttons_shoppingFirst_thenSaveOnly() {
        let buttons = RecipeInputRules.purposeButtons(offersSaveOnly: true, sourceIsNote: false, hasInput: true, isReading: false)
        #expect(buttons.map(\.purpose) == [.shopping, .saveOnly])
        #expect(buttons.allSatisfy { $0.isEnabled })
    }

    @Test func buttons_disabledWithoutInput() {
        let buttons = RecipeInputRules.purposeButtons(offersSaveOnly: true, sourceIsNote: false, hasInput: false, isReading: false)
        #expect(buttons.count == 2)
        #expect(buttons.allSatisfy { !$0.isEnabled })
    }

    @Test func buttons_disabledWhileReading() {
        let buttons = RecipeInputRules.purposeButtons(offersSaveOnly: true, sourceIsNote: false, hasInput: true, isReading: true)
        #expect(buttons.allSatisfy { !$0.isEnabled })
    }

    @Test func buttons_withoutSaveOnlyOffer_haveOnlyTheShoppingButton() {
        let buttons = RecipeInputRules.purposeButtons(offersSaveOnly: false, sourceIsNote: false, hasInput: true, isReading: false)
        #expect(buttons.map(\.purpose) == [.shopping])
    }

    @Test func buttons_recipeNoteAsSource_hasNoSaveOnlyButton() {
        // A recipe note is a recipe note already; saving it again would duplicate it.
        let buttons = RecipeInputRules.purposeButtons(offersSaveOnly: true, sourceIsNote: true, hasInput: true, isReading: false)
        #expect(buttons.map(\.purpose) == [.shopping])
    }

    // MARK: Preset source

    @Test func presetSource_showsOnlyButtons() {
        // Shared item or recipe note: the source is set, the sheet shows a line and the buttons.
        #expect(!RecipeInputRules.showsSourceInput(hasStart: true, hasChoice: true))
        // Without a preset the source is chosen on the sheet.
        #expect(RecipeInputRules.showsSourceInput(hasStart: false, hasChoice: true))
        // "Rezept mit ChatGPT anlegen" has no buttons of this kind and always shows its input.
        #expect(RecipeInputRules.showsSourceInput(hasStart: false, hasChoice: false))
        #expect(RecipeInputRules.showsSourceInput(hasStart: true, hasChoice: false))
    }
}
