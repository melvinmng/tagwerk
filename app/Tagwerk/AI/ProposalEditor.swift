import AIKit
import Foundation
import SwiftUI
import TagwerkCore

/// What an editor of a proposal needs from the app: the calendar of the dates it shows and the GitHub catalog the
/// issue fields offer (plan ki-vorschlaege-anpassen, task B1).
struct ProposalEditorContext {
    var calendar: Calendar
    var now: () -> Date = { Date() }
    var gitHubDirectory: () -> (any GitHubDirectory)?
}

/// The fields of one function's proposal, for the sheet "Vorschlag anpassen". An editor reads the arguments of a call,
/// shows the fields that exist for the thing anyway (the fields of "Neue Aufgabe", the event sheet, ...) and writes the
/// arguments back. It never runs anything: the card stays a proposal and is carried out by "Bestätigen" only.
///
/// Contract of `arguments()`: arguments the user did not touch keep exactly the value the call had (`null` stays `null`),
/// and arguments the editor does not know are kept as they are.
@MainActor
protocol ProposalEditor: AnyObject {
    /// The functions this editor handles; `ProposalEditors` derives the adjustable functions from them.
    static var toolNames: Set<String> { get }

    init?(call: ToolCall, context: ProposalEditorContext)

    /// False while a value the function needs is missing; "Fertig" is then disabled.
    var isValid: Bool { get }

    /// The arguments of the call with the user's values.
    func arguments() -> Data

    /// The fields, to be placed in a `Form`.
    var fields: AnyView { get }

    /// Loads what the fields need from the network, e.g. the people of a repository.
    func load() async
}

/// The registry that maps functions to editors. A function without an editor has no "Anpassen" (AN11a).
@MainActor
enum ProposalEditors {
    /// One entry per editor type; later strands add theirs here.
    static let editorTypes: [any ProposalEditor.Type] = [TaskProposalEditor.self]

    /// The functions whose cards offer "Anpassen".
    static var toolNames: Set<String> { editorTypes.reduce(into: Set<String>()) { $0.formUnion($1.toolNames) } }

    static func make(for call: ToolCall, context: ProposalEditorContext) -> (any ProposalEditor)? {
        editorTypes.first { $0.toolNames.contains(call.name) }.flatMap { $0.init(call: call, context: context) }
    }
}

/// Reading and writing the arguments of a call as JSON; shared by the editors.
enum ProposalArguments {
    /// The arguments as an object; `nil` when they are not one.
    static func decode(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Stable output (sorted keys, no escaped slashes), like the other places that write arguments.
    static func encode(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
    }

    /// "YYYY-MM-DD" or "YYYY-MM-DDTHH:mm" as day and minutes of the day; `nil` for anything else.
    static func dayAndTime(_ text: String?) -> (day: PlanDay, minutes: Int?)? {
        guard let text, !text.isEmpty else { return nil }
        let parts = text.split(separator: "T")
        guard let first = parts.first, let day = AIPlanner.planDay(String(first)) else { return nil }
        if parts.count == 2, let minutes = AIPlanner.minutes(String(parts[1])) { return (day, minutes) }
        return (day, nil)
    }

    /// The inverse of `dayAndTime`.
    static func dueString(day: PlanDay, minutes: Int?) -> String {
        let text = AIPlanner.dayString(day)
        guard let minutes else { return text }
        return text + "T" + AIPlanner.time(minutes)
    }
}
