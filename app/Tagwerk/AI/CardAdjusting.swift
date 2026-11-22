import AIKit
import Foundation
import TagwerkCore

/// What the sheet "Vorschlag anpassen" needs from the place that holds the open cards: the chat of the assistant and the
/// suggestions of a thoughts note (plan ki-vorschlaege-anpassen, tasks B1 and C1). Both keep the call of an open card,
/// remember what the model proposed and carry the mark; neither runs anything when a card is adjusted.
@MainActor
protocol CardAdjusting: AnyObject {
    /// The consent a follow-up about one card needs; without it the sheet shows no input line.
    var cardFollowUpHasConsent: Bool { get }

    /// True while the open call differs from what the model proposed.
    func isAdjusted(_ call: ToolCall) -> Bool

    /// The editor for an open card; `nil` for a function without one and for a call that is not open any more.
    func proposalEditor(for call: ToolCall) -> (any ProposalEditor)?

    /// An editor that starts from other arguments than the call holds, e.g. the answer of ChatGPT to a follow-up.
    func proposalEditor(for call: ToolCall, arguments: Data) -> (any ProposalEditor)?

    /// Writes the values into the open card by the user (`.byUser`) or from an answer of ChatGPT (`.byAssistant`).
    @discardableResult
    func adjust(_ call: ToolCall, arguments: Data, mark: ProposalMark) -> ToolCall?

    /// Puts the proposal of the model back; `nil` when the card was not adjusted.
    @discardableResult
    func resetAdjustment(_ call: ToolCall) -> ToolCall?

    /// One request about one open card (`CardReviser`).
    func reviseCard(_ call: ToolCall, current: Data, comment: String) async throws -> CardReviser.Answer
}

extension AssistantModel: CardAdjusting {}
