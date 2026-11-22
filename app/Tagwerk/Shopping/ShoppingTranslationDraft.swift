import Foundation
import Observation
import TagwerkCore

/// The state of the sheet "Übersetzung" for "Artikel übersetzen" (plan ki-vorschlaege-anpassen, task D5): the changes with their
/// marks, the names the user typed over, the checkmarks, the follow-up and "Rückgängig". The plan of the request stays with the
/// model, so a follow-up sends the same names again (AN7b) and every answer is checked against them like the first one.
@MainActor
@Observable
final class ShoppingTranslationDraft {
    typealias Change = ShoppingTranslationPlan.Change
    typealias Reviser = @MainActor (_ plan: ShoppingTranslationPlan, _ language: VoiceLanguage, _ current: [Change], _ pinned: Set<String>,
                                    _ focus: String?, _ comment: String) async throws -> [Change]

    let plan: ShoppingTranslationPlan
    let language: VoiceLanguage
    let followUp: PreviewFollowUpModel<Change>
    /// Rows the user unchecked.
    private(set) var deselected: Set<String> = []
    /// The name keys of every open item; a name that lands on one of them is blocked, like in the first answer.
    @ObservationIgnored private let openKeys: Set<String>
    @ObservationIgnored private let reviser: Reviser?

    init(changes: [Change], plan: ShoppingTranslationPlan, language: VoiceLanguage, openKeys: Set<String>, reviser: Reviser?) {
        self.plan = plan
        self.language = language
        self.openKeys = openKeys
        self.reviser = reviser
        followUp = PreviewFollowUpModel(items: changes)
    }

    var hasFollowUp: Bool { reviser != nil }
    var changes: [Change] { followUp.items }

    /// What "Übernehmen" writes: the checked rows that are not blocked, with the names as they are now.
    var selected: [Change] { ShoppingTranslationModel.selection(changes, deselected: deselected) }

    func toggle(_ id: String) {
        if deselected.contains(id) { deselected.remove(id) } else { deselected.insert(id) }
    }

    // MARK: Changing by hand

    /// The user typed another name for an item. The name is trimmed, must not be empty, must not break the line, must not be longer
    /// than a name may be and must not be the old name; a name that is the name of another open item blocks the row, as in the
    /// first answer. A row ChatGPT blocked cannot be edited. Returns whether the name was taken.
    @discardableResult
    func rename(_ id: String, to text: String) -> Bool {
        guard var change = changes.first(where: { $0.id == id }), change.blocked == nil || followUp.mark(of: id) == .byUser else { return false }
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains(where: \.isNewline), name.count <= ShoppingInputParser.maxNameLength else { return false }
        let key = ShoppingName.key(name)
        guard !key.isEmpty, key != ShoppingName.key(change.oldName) else { return false }
        change.newName = name
        if openKeys.contains(key) {
            change.blocked = .alreadyOnList
        } else if changes.contains(where: { $0.id != id && $0.blocked == nil && ShoppingName.key($0.newName) == key }) {
            change.blocked = .sameTranslationTwice
        } else {
            change.blocked = nil
        }
        followUp.edit(change)
        return true
    }

    // MARK: Follow-up

    func send(_ comment: String) async {
        guard let reviser else { return }
        await followUp.send(comment, using: { [weak self] request in
            guard let self else { throw CancellationError() }
            var focus: String?
            if case .one(let id) = request.scope { focus = id }
            let answer = try await reviser(self.plan, self.language, request.items, Set(request.pinned), focus, request.comment)
            return .init(items: answer, message: answer == request.items ? String(localized: "Keine Änderung.") : String(localized: "Übersetzung überarbeitet."))
        }, failure: { ($0 as? ShoppingTranslator.Failure ?? .failed).message })
    }
}
