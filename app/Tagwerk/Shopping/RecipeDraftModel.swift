import Foundation
import Observation
import TagwerkCore

/// Asks ChatGPT about the recipe on the sheet again (the source is held by the closure of the sheet that read it): the current
/// result with the names of the ingredients the user set by hand, the ingredient the message is about, and the message.
typealias RecipeReviser = @MainActor (_ current: RecipeImporter.Result, _ pinned: [String], _ focus: String?, _ comment: String) async throws
    -> RecipeImporter.Result

/// One ingredient of the proposal with an identity that survives renaming, so marks, the choice of the checkmark and an answer
/// that renames the ingredient stay attached to the right row (the name of a candidate is its identity otherwise).
struct RecipeRow: Identifiable, Equatable, Sendable {
    var id = UUID()
    var candidate: RecipeImporter.Candidate

    /// The row with the values of the small sheet "Zutat": a name (the name of the list when the recipe has a second one) and a
    /// category. The amount is not part of it: it is changed with the amount button of the row only, which keeps it apart from
    /// the scaling by servings.
    @MainActor func edited(name: String, category: String) -> RecipeRow {
        var row = self
        let newName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(ShoppingInputParser.maxNameLength))
        if !newName.isEmpty {
            if row.candidate.shoppingName != nil { row.candidate.shoppingName = newName } else { row.candidate.name = newName }
        }
        row.candidate.category = category
        return row
    }
}

/// The state of the ingredients on the result sheet and on the confirmation of "Rezept speichern" (plan ki-vorschlaege-anpassen,
/// task D2): the rows with their marks, the checkmarks, the follow-up and "Rückgängig". Both views show the same model, so the
/// note that is saved is the revised recipe the user saw.
@MainActor
@Observable
final class RecipeDraftModel {
    /// The recipe as read, or as the last answer changed it: title, servings, steps; its candidates are `rows`.
    private(set) var result: RecipeImporter.Result
    let followUp: PreviewFollowUpModel<RecipeRow>
    /// Rows the user unchecked.
    private(set) var deselected: Set<UUID>
    /// `nil` for a recipe read on the device and for a recipe that has no source any more: no follow-up then.
    @ObservationIgnored private let reviser: RecipeReviser?
    @ObservationIgnored private var metaBeforeAnswer: RecipeImporter.Result?

    init(result: RecipeImporter.Result, reviser: RecipeReviser?) {
        self.result = result
        self.reviser = result.readLocally ? nil : reviser
        let rows = result.candidates.map { RecipeRow(candidate: $0) }
        followUp = PreviewFollowUpModel(items: rows)
        deselected = Set(rows.filter(\.candidate.alreadyOnList).map(\.id))
    }

    var hasFollowUp: Bool { reviser != nil }
    var rows: [RecipeRow] { followUp.items }
    var candidates: [RecipeImporter.Candidate] { rows.map(\.candidate) }

    /// The recipe as it is now: the title, servings and steps of the last answer with the candidates of the rows.
    var current: RecipeImporter.Result {
        var copy = result
        copy.candidates = candidates
        return copy
    }

    // MARK: Choosing

    func isSelected(_ id: UUID) -> Bool { !deselected.contains(id) }

    func toggle(_ id: UUID) {
        if deselected.contains(id) { deselected.remove(id) } else { deselected.insert(id) }
    }

    /// The candidates "hinzufügen" puts on the list.
    var selectedCandidates: [RecipeImporter.Candidate] {
        rows.filter { !deselected.contains($0.id) }.map(\.candidate)
    }

    // MARK: Changing by hand

    func edit(_ row: RecipeRow) {
        followUp.edit(row)
        metaBeforeAnswer = nil
    }

    // MARK: Follow-up

    func send(_ comment: String) async {
        guard let reviser else { return }
        let before = Set(rows.map(\.id))
        let metaBefore = result
        var answered: RecipeImporter.Result?
        var wasAll = true
        await followUp.send(comment, using: { [weak self] request in
            guard let self else { throw CancellationError() }
            var focusID: UUID?
            var focusName: String?
            if case .one(let id) = request.scope {
                focusID = id
                focusName = request.items.first { $0.id == id }?.candidate.listName
                wasAll = false
            }
            var current = self.result
            current.candidates = request.items.map(\.candidate)
            let names = request.items.filter { request.pinned.contains($0.id) }.map(\.candidate.listName)
            let answer = try await reviser(current, names, focusName, request.comment)
            answered = answer
            let aligned = Self.align(answer.candidates, with: request.items, focus: focusID)
            return .init(items: aligned, message: aligned == request.items ? String(localized: "Keine Änderung.")
                                                                           : String(localized: "Rezept überarbeitet."))
        }, failure: { ($0 as? RecipeImporter.Failure ?? .failed).message })
        guard followUp.canUndo, let answered else { return }
        // New rows follow the rule of the first reading: an ingredient that is on the list already starts unchecked.
        for row in rows where !before.contains(row.id) && row.candidate.alreadyOnList { deselected.insert(row.id) }
        if wasAll {
            metaBeforeAnswer = metaBefore
            result.title = answered.title
            result.steps = answered.steps
            if result.servings == nil { result.servings = answered.servings }
        }
    }

    func undo() {
        followUp.undo()
        if let metaBeforeAnswer {
            result.title = metaBeforeAnswer.title
            result.steps = metaBeforeAnswer.steps
            result.servings = metaBeforeAnswer.servings
        }
        metaBeforeAnswer = nil
    }

    // MARK: Putting an answer onto the rows

    /// An answer candidate with the name of a row is that row (same identity; the very same row when nothing changed); every
    /// other answer candidate is a new row. With a `focus` that has no namesake, a single unmatched candidate stands for it
    /// (the message renamed the ingredient).
    static func align(_ answer: [RecipeImporter.Candidate], with current: [RecipeRow], focus: UUID? = nil) -> [RecipeRow] {
        var unused = current
        var matches: [UUID?] = answer.map { candidate in
            guard let index = unused.firstIndex(where: { ShoppingName.key($0.candidate.listName) == ShoppingName.key(candidate.listName) }) else { return nil }
            return unused.remove(at: index).id
        }
        if let focus, unused.contains(where: { $0.id == focus }) {
            let open = matches.indices.filter { matches[$0] == nil }
            if open.count == 1 { matches[open[0]] = focus }
        }
        return zip(answer, matches).map { candidate, id in
            guard let id, let old = current.first(where: { $0.id == id }) else { return RecipeRow(candidate: candidate) }
            var same = candidate
            same.alreadyOnList = old.candidate.alreadyOnList
            if same == old.candidate { return old }
            return RecipeRow(id: old.id, candidate: candidate)
        }
    }
}
