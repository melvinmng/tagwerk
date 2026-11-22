import Foundation
import TagwerkCore

/// The rules of the input sheet of a recipe (EK3b): which buttons end it, when they can be tapped, what a read sends for each
/// purpose, and whether the source is chosen on the sheet or set already.
enum RecipeInputRules {
    /// One button that ends the input with a purpose.
    struct PurposeButton: Equatable, Identifiable {
        let purpose: RecipePurpose
        let isEnabled: Bool
        var id: RecipePurpose { purpose }
    }

    /// "Zutaten auf die Einkaufsliste" first, then "Nur als Rezept speichern" when the sheet offers it. A recipe note as the
    /// source has no second button: it is a recipe note already, a copy would only duplicate it. A button can be tapped when
    /// there is an input and no read is running.
    static func purposeButtons(offersSaveOnly: Bool, sourceIsNote: Bool, hasInput: Bool, isReading: Bool) -> [PurposeButton] {
        let enabled = hasInput && !isReading
        var buttons = [PurposeButton(purpose: .shopping, isEnabled: enabled)]
        if offersSaveOnly, !sourceIsNote { buttons.append(PurposeButton(purpose: .saveOnly, isEnabled: enabled)) }
        return buttons
    }

    /// Whether the sheet shows the choice of the source and its input. Not when the source is set already (shared item, recipe
    /// note) and the sheet ends in the purpose buttons: then a line names the source and only the buttons follow.
    static func showsSourceInput(hasStart: Bool, hasChoice: Bool) -> Bool { !(hasStart && hasChoice) }

    /// What a read sends along with the recipe: only a recipe for the shopping list knows the categories and the open items of
    /// the list and the language of the list; a recipe that is only saved sends none of them.
    static func requestContext(for purpose: RecipePurpose, openItemKeys: Set<String>, categoryNames: [String],
                               shoppingLanguage: VoiceLanguage?) -> (openItemKeys: Set<String>, categoryNames: [String], shoppingLanguage: VoiceLanguage?) {
        switch purpose {
        case .shopping: (openItemKeys, categoryNames, shoppingLanguage)
        case .saveOnly: ([], [], nil)
        }
    }
}
