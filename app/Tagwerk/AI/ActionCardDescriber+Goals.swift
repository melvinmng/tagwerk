import AIKit
import Foundation
import TagwerkCore

extension ActionCardDescriber {
    /// The card of `propose_nutrition_goals` and `propose_activity_goals`: the old and new values and the cross-check of Tagwerk. A warning
    /// of the cross-check makes "Übernehmen" ask a second time; a proposal that cannot be adopted blocks the button.
    func describeGoals(_ call: ToolCall, language: VoiceLanguage, spoken: Bool) -> AssistantModel.ActionCard {
        func text(_ key: String.LocalizationValue) -> String { Localized.string(key, in: language, bundle: .main) }
        guard let content = goalCard(call) else { return AssistantModel.ActionCard(title: text("Ziele"), change: call.name) }
        var change = content.change
        // Spoken, the arrow becomes a word.
        if spoken { change = change.replacingOccurrences(of: " → ", with: " " + text("wird zu") + " ") }
        var card = AssistantModel.ActionCard(title: content.title, change: change, warning: content.warning, confirmTitle: text("Übernehmen"))
        card.blocksConfirmation = content.isBlocked
        card.asksTwice = content.warning != nil && !content.isBlocked
        return card
    }
}
