import Foundation
import Observation
import TagwerkCore

/// The state of the sheet "Vorschlag von ChatGPT" after "Mit ChatGPT sortieren" (plan ki-vorschlaege-anpassen, task D4): the
/// changes with their marks, the categories the user picked by hand, the checkmarks, the follow-up and "Rückgängig". The
/// request and the state of the list it was made for stay with the model, so a follow-up sends the same item and category names
/// again (AN7b) and every answer is checked against them like the first one.
@MainActor
@Observable
final class ShoppingSortDraft {
    let request: ShoppingSorter.Request
    /// Item key → the category the item is in now.
    let current: [String: String]
    let followUp: PreviewFollowUpModel<ShoppingSorter.Change>
    /// Categories that do not exist yet: the ones ChatGPT proposed. Only those a change still moves an item into are created.
    private(set) var proposedNew: [String]
    private(set) var deselectedCategories: Set<String> = []
    private(set) var deselectedItems: Set<String> = []
    @ObservationIgnored private let reviser: Reviser?

    typealias Reviser = @MainActor (_ request: ShoppingSorter.Request, _ current: [String: String], _ proposal: ShoppingSorter.Proposal,
                                    _ pinned: Set<String>, _ focus: String?, _ comment: String) async throws -> ShoppingSorter.Proposal

    init(proposal: ShoppingSorter.Proposal, request: ShoppingSorter.Request, current: [String: String], reviser: Reviser?) {
        self.request = request
        self.current = current
        self.reviser = reviser
        proposedNew = proposal.newCategories
        followUp = PreviewFollowUpModel(items: proposal.changes)
    }

    var hasFollowUp: Bool { reviser != nil }
    var changes: [ShoppingSorter.Change] { followUp.items }

    /// The new categories the changes still use, in the order of the proposal.
    var newCategories: [String] {
        let used = Set(changes.map { $0.toCategory.lowercased() })
        return proposedNew.filter { used.contains($0.lowercased()) }
    }

    /// The categories a row can be moved to: those of the list, the fixed section and the proposed new ones.
    var categoryChoices: [String] {
        let existing = request.categoryNames
        return existing + proposedNew.filter { name in !existing.contains { $0.lowercased() == name.lowercased() } }
    }

    // MARK: Choosing

    func toggleItem(_ id: String) {
        if deselectedItems.contains(id) { deselectedItems.remove(id) } else { deselectedItems.insert(id) }
    }

    func toggleCategory(_ name: String) {
        if deselectedCategories.contains(name) { deselectedCategories.remove(name) } else { deselectedCategories.insert(name) }
    }

    /// What "Vorschlag übernehmen" stores: the checked changes, with the new categories they still need.
    var selection: ShoppingSorter.Proposal {
        var chosen = ShoppingSortResultSheet.selection(proposal: ShoppingSorter.Proposal(newCategories: newCategories, changes: changes),
                                                       deselectedCategories: deselectedCategories, deselectedItems: deselectedItems)
        // A category nothing checked moves into is not created.
        let used = Set(chosen.changes.map { $0.toCategory.lowercased() })
        chosen.newCategories = chosen.newCategories.filter { used.contains($0.lowercased()) }
        return chosen
    }

    // MARK: Changing by hand

    /// The user picked a category for an item. Only the categories of `categoryChoices` can be chosen.
    func pick(_ category: String, for id: String) {
        guard categoryChoices.contains(category), var change = changes.first(where: { $0.id == id }) else { return }
        change.toCategory = category
        followUp.edit(change)
    }

    // MARK: Follow-up

    func send(_ comment: String) async {
        guard let reviser else { return }
        var answered: ShoppingSorter.Proposal?
        await followUp.send(comment, using: { [weak self] request in
            guard let self else { throw CancellationError() }
            var focus: String?
            if case .one(let id) = request.scope { focus = id }
            let proposal = ShoppingSorter.Proposal(newCategories: self.proposedNew, changes: request.items)
            let answer = try await reviser(self.request, self.current, proposal, Set(request.pinned), focus, request.comment)
            answered = answer
            return .init(items: answer.changes, message: answer.changes == request.items ? String(localized: "Keine Änderung.")
                                                                                        : String(localized: "Einteilung überarbeitet."))
        }, failure: { ($0 as? ShoppingSorter.Failure ?? .failed).message })
        if let answered {
            for name in answered.newCategories where !proposedNew.contains(where: { $0.lowercased() == name.lowercased() }) { proposedNew.append(name) }
        }
    }
}
