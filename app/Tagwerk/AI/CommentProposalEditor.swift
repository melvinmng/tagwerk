import AIKit
import Observation
import SwiftUI

/// Editor for `add_comment` (plan ki-vorschlaege-anpassen, task B3): the text of the comment.
@MainActor
@Observable
final class CommentProposalEditor: ProposalEditor {
    nonisolated static let toolNames: Set<String> = ["add_comment"]

    let call: ToolCall
    var body = ""

    @ObservationIgnored private let base: [String: Any]
    @ObservationIgnored private let initialBody: String

    required init?(call: ToolCall, context: ProposalEditorContext) {
        guard Self.toolNames.contains(call.name), let base = ProposalArguments.decode(call.arguments) else { return nil }
        self.call = call
        self.base = base
        initialBody = base["body"] as? String ?? ""
        body = initialBody
    }

    var isValid: Bool { !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func arguments() -> Data {
        var result = base
        if body != initialBody { result["body"] = body.trimmingCharacters(in: .whitespacesAndNewlines) }
        return ProposalArguments.encode(result)
    }

    var fields: AnyView { AnyView(CommentProposalFields(editor: self)) }

    func load() async {}
}

private struct CommentProposalFields: View {
    @Bindable var editor: CommentProposalEditor

    var body: some View {
        Section {
            TextField("Kommentar", text: $editor.body, axis: .vertical).lineLimit(3...12).keyboardDoneButton()
        }
    }
}
