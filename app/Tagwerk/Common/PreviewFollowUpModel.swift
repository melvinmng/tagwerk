import Foundation
import Observation
import TagwerkCore

/// The state of a preview sheet that offers "Anpassen" (plan ki-vorschlaege-anpassen, strand D): the items of the proposal
/// with their marks, what the follow-up is about, the request that is running and the exchange so far. The rules for what an
/// answer may change live in `ProposalRevision`; this model adds the request around them: only one request at a time, an
/// answer that arrives after `discard()` (the sheet closed, the input was replaced) is dropped, and nothing is stored.
///
/// Each sheet gives `send` a closure that makes its own request and returns the items of the answer, in the format of its
/// first request. The model decides what is applied: an answer about one item changes only that item, an answer about all
/// items may add, change and remove items, and reports the items the user had set by hand that it overwrote.
@MainActor
@Observable
final class PreviewFollowUpModel<Item: Identifiable & Equatable & Sendable> where Item.ID: Sendable {
    typealias Scope = ProposalRevision<Item>.Scope

    /// What a sheet's request needs: the scope, the items as they are now, the ones the user set by hand and the message.
    struct Request {
        var scope: Scope
        var items: [Item]
        var pinned: [Item.ID]
        var comment: String
    }

    struct Reply {
        var items: [Item]
        var message: String
        init(items: [Item], message: String) {
            self.items = items
            self.message = message
        }
    }

    private(set) var revision: ProposalRevision<Item>
    private(set) var state: FollowUpState = .ready
    /// The sentence of the last answer.
    private(set) var reply = ""
    /// Items of the last answer the user had set by hand: the sheet says so and "Rückgängig" brings them back.
    private(set) var overwritten: [Item.ID] = []
    /// The item the next message is about; `nil` stands for all items.
    var focus: Item.ID?
    private(set) var lastMessage = ""

    @ObservationIgnored private var generation = 0

    init(items: [Item]) {
        revision = ProposalRevision(items: items)
    }

    var items: [Item] { revision.items }
    var canUndo: Bool { revision.canUndo }
    var isSending: Bool { state == .sending }

    var scope: Scope {
        if let focus, items.contains(where: { $0.id == focus }) { return .one(focus) }
        return .all
    }

    func mark(of id: Item.ID) -> ProposalMark? { revision.mark(of: id) }

    // MARK: Changing by hand

    /// The user changed an item: it carries the mark `byUser` and the answer to a later message leaves it alone.
    /// Dropping the undo step also clears the sentence of the answer that step belonged to.
    func edit(_ item: Item) {
        let hadUndo = revision.canUndo
        revision.edit(item)
        if hadUndo { reply = ""; overwritten = [] }
    }

    func resetToProposal(_ id: Item.ID) { revision.resetToProposal(id) }

    /// The screen's own copy of the list changed by hand (steppers, swipe, "hinzufügen"): the model follows it, so marks and
    /// the next request see what the user sees. A change drops the undo step and the sentence that belonged to it.
    func syncByHand(_ screenItems: [Item]) {
        guard screenItems != revision.items else { return }
        let hadUndo = revision.canUndo
        revision.syncByHand(screenItems)
        if hadUndo { reply = ""; overwritten = [] }
    }

    /// The first result of a request, or a new one ("Neu schätzen"): marks, undo and exchange start over.
    func replaceItems(_ items: [Item]) {
        discard()
        revision = ProposalRevision(items: items)
        reply = ""
        overwritten = []
        focus = nil
        state = .ready
    }

    /// The sheet closed or its input changed: an answer that is still on its way is dropped.
    func discard() {
        generation += 1
        if state == .sending { state = .ready }
    }

    // MARK: Follow-up

    /// Sends `comment` about the focused item or about all items. Without a request in flight and with a message only.
    func send(_ comment: String, using reviser: @escaping @MainActor (Request) async throws -> Reply,
              failure: @escaping (Error) -> String) async {
        let comment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSending, !comment.isEmpty else { return }
        lastMessage = comment
        state = .sending
        generation += 1
        let mine = generation
        let scope = self.scope
        let request = Request(scope: scope, items: items, pinned: revision.pinnedIDs, comment: comment)
        do {
            let answer = try await reviser(request)
            guard mine == generation else { return }
            apply(answer, scope: scope)
            state = .ready
        } catch is CancellationError {
            if mine == generation { state = .ready }
        } catch {
            guard mine == generation else { return }
            state = .failed(failure(error))
        }
    }

    private func apply(_ answer: Reply, scope: Scope) {
        reply = answer.message
        let outcome: ProposalRevision<Item>.Outcome
        switch scope {
        case .one: outcome = revision.apply(answer: answer.items, scope: scope)
        case .all: outcome = revision.replaceAll(with: answer.items)
        }
        overwritten = outcome.overwritten
    }

    /// "Rückgängig": the items as they were before the last answer.
    func undo() {
        guard revision.undo() else { return }
        reply = ""
        overwritten = []
    }
}
