import AIKit
import Observation
import SwiftUI
import TagwerkCore

/// Editor for `assign_task` (plan ki-vorschlaege-anpassen, task B3): who the issue is assigned to afterwards.
///
/// The call holds `add` and `remove`; the editor shows the people after the change and writes the difference to the
/// people who are assigned now. The card stays a single confirmation, and its warning (a hand-over) is described again
/// for the new people. People who cannot be assigned in the repository are not offered; the function checks them again.
@MainActor
@Observable
final class AssignProposalEditor: ProposalEditor {
    nonisolated static let toolNames: Set<String> = ["assign_task"]

    let call: ToolCall
    let context: ProposalEditorContext
    let assignment: ProposalAssignment
    private(set) var selection: Set<String>
    private(set) var assigneeLoad: AssigneeLoad = .idle

    @ObservationIgnored private let base: [String: Any]
    @ObservationIgnored private let initialSelection: Set<String>

    required init?(call: ToolCall, context: ProposalEditorContext) {
        guard Self.toolNames.contains(call.name), let base = ProposalArguments.decode(call.arguments),
              let key = base["id"] as? String, let assignment = context.assignment(key) else { return nil }
        self.call = call
        self.context = context
        self.base = base
        self.assignment = assignment
        let change = AssigneeChange(add: base["add"] as? [String] ?? [], remove: base["remove"] as? [String] ?? [])
        let after = AssigneeRules.applying(change, to: assignment.current)
        selection = Set(after)
        initialSelection = Set(after.map { $0.lowercased() })
    }

    var me: String? { context.gitHubDirectory()?.login }

    /// Everyone the user can pick: the assignable people of the repository and everyone assigned now (so they can be
    /// taken off), the user first.
    var candidates: [String] {
        var logins = assigneeLoad.logins(for: assignment.repository)
        for login in assignment.current where !AssigneeRules.contains(logins, login) { logins.append(login) }
        for login in selection where !AssigneeRules.contains(logins, login) { logins.append(login) }
        return AssigneeSelection.ordered(candidates: logins, me: me)
    }

    func choose(_ people: Set<String>) {
        guard people.count <= AssigneeRules.maximum else { return }
        selection = people
    }

    // MARK: ProposalEditor

    var isValid: Bool { selection.count <= AssigneeRules.maximum }

    func arguments() -> Data {
        var result = base
        if Set(selection.map { $0.lowercased() }) != initialSelection {
            let ordered = candidates.filter(selection.contains)
            let change = AssigneeRules.change(original: assignment.current, edited: ordered) ?? AssigneeChange(add: [], remove: [])
            result["add"] = change.add
            result["remove"] = change.remove
        }
        return ProposalArguments.encode(result)
    }

    var fields: AnyView { AnyView(AssignProposalFields(editor: self)) }

    func load() async {
        guard let directory = context.gitHubDirectory() else { return }
        let repository = assignment.repository
        assigneeLoad = .loading(repository: repository)
        let logins = await directory.assignableUsers(in: repository, maxAge: AppEnvironment.catalogMaxAge)
        assigneeLoad = assigneeLoad.adopting(logins, for: repository, selected: repository)
    }
}

private struct AssignProposalFields: View {
    @Bindable var editor: AssignProposalEditor

    var body: some View {
        Section {
            AssigneeSelectionRow(candidates: editor.candidates, me: editor.me, load: editor.assigneeLoad,
                                 selection: Binding(get: { editor.selection }, set: { editor.choose($0) }))
        } footer: {
            Text("Wer nach der Änderung zugewiesen ist. Nur Personen, die in diesem Repository zuweisbar sind, stehen zur Auswahl.")
        }
    }
}
