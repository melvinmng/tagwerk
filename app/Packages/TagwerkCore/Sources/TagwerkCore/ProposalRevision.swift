/// The rules for the items of one AI proposal that the user changes by hand and revises with follow-up messages
/// (plan ki-vorschlaege-anpassen, rules 1 to 5): the rows of a recipe, the articles of a sort proposal, the cards of a set.
/// Pure state, no network and no UI; each place that offers "Anpassen" keeps one revision and shows it.
///
/// - Every item carries a mark: `byUser` once the user edited it, `byAssistant` once an answer changed it, none otherwise.
/// - Items the user edited are pinned: an answer about one item leaves them alone, an answer about all items may change
///   them, but then reports it (`Outcome.overwritten`) so the screen can say so.
/// - What the AI proposed before the user edited an item is kept, so "Zurück zum Vorschlag der KI" is possible.
/// - One step of undo: the state before the last answer. A manual edit drops it (undoing the answer would undo the edit).
public struct ProposalRevision<Item: Identifiable & Equatable & Sendable>: Sendable where Item.ID: Sendable {
    /// What a follow-up message is about.
    public enum Scope: Equatable, Sendable {
        /// One item; nothing else changes, whatever the answer contains.
        case one(Item.ID)
        /// All items of the proposal.
        case all
    }

    /// The result of applying an answer.
    public struct Outcome: Equatable, Sendable {
        /// Items the answer changed, in item order.
        public var changed: [Item.ID] = []
        /// Pinned items among `changed`: the user had set them by hand and the message was not about them alone.
        public var overwritten: [Item.ID] = []
        /// Answer entries that were not applied: unknown items, items outside the scope, pinned items of a single-item answer.
        public var ignored: [Item.ID] = []
    }

    public private(set) var items: [Item]
    private var marks: [Item.ID: ProposalMark] = [:]
    /// The value the AI proposed for each item the user changed since.
    private var proposals: [Item.ID: Item] = [:]
    private var undoState: State?

    private struct State: Sendable {
        var items: [Item]
        var marks: [Item.ID: ProposalMark]
        var proposals: [Item.ID: Item]
    }

    public init(items: [Item]) {
        self.items = items
    }

    // MARK: Reading

    public func mark(of id: Item.ID) -> ProposalMark? { marks[id] }

    /// What the AI proposed for an item the user changed since; `nil` for an item that was not changed by hand.
    public func proposal(of id: Item.ID) -> Item? { proposals[id] }

    /// The items the user set by hand, in item order: the request names them, so the answer leaves them alone.
    public var pinnedIDs: [Item.ID] {
        items.filter { marks[$0.id] == .byUser }.map(\.id)
    }

    public var canUndo: Bool { undoState != nil }

    // MARK: Changing by hand

    /// Replaces the item with the same ID by the user's version and marks it `byUser`. Dropping back to what the AI
    /// proposed removes the mark again. Drops the undo step. Unknown IDs and unchanged values do nothing.
    public mutating func edit(_ item: Item) {
        guard let index = items.firstIndex(where: { $0.id == item.id }), items[index] != item else { return }
        let id = item.id
        let original = proposals[id] ?? items[index]
        items[index] = item
        if item == original {
            marks[id] = nil
            proposals[id] = nil
        } else {
            marks[id] = .byUser
            proposals[id] = original
        }
        undoState = nil
    }

    /// "Zurück zum Vorschlag der KI": the item as the AI last proposed it, without a mark.
    public mutating func resetToProposal(_ id: Item.ID) {
        guard let original = proposals[id], let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index] = original
        marks[id] = nil
        proposals[id] = nil
    }

    // MARK: Answers

    /// Applies the items of an answer. Items the answer repeats unchanged do nothing; items it changes get the mark
    /// `byAssistant` and count as the AI's latest proposal. Remembers the state before for one `undo`.
    @discardableResult
    public mutating func apply(answer: [Item], scope: Scope) -> Outcome {
        var outcome = Outcome()
        let before = State(items: items, marks: marks, proposals: proposals)
        var changedIDs = Set<Item.ID>()
        var overwrittenIDs = Set<Item.ID>()
        for entry in answer {
            guard let index = items.firstIndex(where: { $0.id == entry.id }) else {
                outcome.ignored.append(entry.id)
                continue
            }
            let id = entry.id
            switch scope {
            case .one(let target):
                // A single-item answer changes only that item, even when the user had set it by hand: they asked about it.
                guard id == target else {
                    outcome.ignored.append(id)
                    continue
                }
            case .all:
                break
            }
            guard items[index] != entry else { continue }
            if scope == .all, marks[id] == .byUser { overwrittenIDs.insert(id) }
            items[index] = entry
            marks[id] = .byAssistant
            proposals[id] = nil
            changedIDs.insert(id)
        }
        outcome.changed = items.map(\.id).filter { changedIDs.contains($0) }
        outcome.overwritten = items.map(\.id).filter { overwrittenIDs.contains($0) }
        undoState = changedIDs.isEmpty ? undoState : before
        return outcome
    }

    /// "Rückgängig": the state before the last answer. `false` when there is nothing to undo.
    @discardableResult
    public mutating func undo() -> Bool {
        guard let state = undoState else { return false }
        items = state.items
        marks = state.marks
        proposals = state.proposals
        undoState = nil
        return true
    }
}

/// Whether the follow-up bar of a proposal is shown and usable (plan ki-vorschlaege-anpassen, review focus 7).
public enum FollowUpAvailability: Equatable, Sendable {
    /// Without the consent of the function or without a ChatGPT sign-in there is no follow-up and no bar.
    case hidden
    /// Shown but not usable: no connection. Changing by hand does not depend on it.
    case offline
    case available

    public static func state(hasConsent: Bool, isSignedIn: Bool, isOffline: Bool) -> FollowUpAvailability {
        guard hasConsent, isSignedIn else { return .hidden }
        return isOffline ? .offline : .available
    }

    /// "Senden" works with an available bar, a message with text and no request running.
    public static func canSend(_ availability: FollowUpAvailability, text: String, isSending: Bool) -> Bool {
        availability == .available && !isSending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
