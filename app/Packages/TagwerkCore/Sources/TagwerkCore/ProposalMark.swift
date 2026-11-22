/// Who last changed an AI proposal (a card, a row or a whole preview) before the user confirms it.
/// A proposal the model made and nobody touched has no mark.
public enum ProposalMark: String, Sendable, Equatable, Hashable, Codable {
    /// The user edited the proposal by hand.
    case byUser
    /// The model revised the proposal after the user asked for a change.
    case byAssistant
}
