import AIKit
import Foundation
import TagwerkCore

/// The tool set of the notes chat (issue #233): everything `AppTools` offers (including `search` and `read_note`), plus
/// `list_notes` and the tools that create, revise and trash notes. The note tools exist only while the consent
/// "Notizen mit ChatGPT" is on, and every one of them goes through `NoteToolAccess`, which leaves out private and trashed
/// notes. The note texts the assistant read live in `base.noteSession`, one instance for all chats.
@MainActor
final class NoteChatTools: ToolHandler {
    static let noteReadTools: Set<String> = ["list_notes"]
    static let noteWriteTools: Set<String> = ["create_note", "update_note", "delete_note"]
    /// Most notes one `list_notes` answer names.
    static let maxListedNotes = 200
    /// Budget of one `list_notes` answer in UTF-8 bytes, below the 16 KB limit of `Conversation.clipped` (the answer must stay valid JSON).
    static let maxListOutputLength = 14_000

    let base: AppTools
    let access: NoteToolAccess
    private let hasConsent: () -> Bool
    /// The note a chat about one note is about; `nil` in the chat about all notes. With a scope `list_notes` is not offered.
    var scope: UUID?
    /// The folder a new note goes to when the model names none (the folder the chat was opened from); `nil` is "Notizen".
    var defaultFolderID: UUID?

    init(base: AppTools, access: NoteToolAccess, hasConsent: @escaping () -> Bool) {
        self.base = base
        self.access = access
        self.hasConsent = hasConsent
    }

    // MARK: ToolHandler

    var definitions: [ToolDefinition] {
        guard hasConsent() else { return base.definitions }
        return base.definitions + (scope == nil ? [Self.listNotesDefinition] : [])
    }

    func kind(of name: String) -> ToolKind {
        if Self.noteReadTools.contains(name) { return .read }
        if Self.noteWriteTools.contains(name) { return .write }
        return base.kind(of: name)
    }

    /// `list_notes` keeps only the number of titles it delivered; the other tools follow the base.
    func storedForm(of call: ToolCall, output: String?) -> (arguments: String, output: String?) {
        guard call.name == "list_notes" else { return base.storedForm(of: call, output: output) }
        let arguments = String(decoding: call.arguments, as: UTF8.self)
        guard let output else { return (arguments, nil) }
        return (arguments, Self.storedListOutput(output))
    }

    /// `list_notes` and `read_note` are shown as lines in the chat. This does not depend on the consent: the lines of the
    /// stored history stay visible after the consent was withdrawn.
    func showsActivity(_ name: String) -> Bool { Self.noteReadTools.contains(name) || base.showsActivity(name) }

    func run(_ call: ToolCall) async -> String {
        guard Self.noteReadTools.contains(call.name) || Self.noteWriteTools.contains(call.name) else { return await base.run(call) }
        guard hasConsent() else { return AppTools.error(String(localized: "Die Einwilligung „Notizen mit ChatGPT“ fehlt.")) }
        guard let arguments = try? JSONSerialization.jsonObject(with: call.arguments) as? [String: Any] else {
            return AppTools.error(String(localized: "Die Argumente sind kein gültiges JSON."))
        }
        do {
            switch call.name {
            case "list_notes": return try listNotes(AppTools.Arguments(arguments))
            default: throw AppTools.ToolError(String(localized: "Unbekannte Funktion \(call.name)."))
            }
        } catch let error as AppTools.ToolError {
            return AppTools.error(error.message)
        } catch {
            return AppTools.error(TaskListModel.message(for: error))
        }
    }

    // MARK: list_notes

    static var folderNotFoundMessage: String { String(localized: "Ordner nicht gefunden.") }

    private func listNotes(_ args: AppTools.Arguments) throws -> String {
        guard scope == nil else { throw AppTools.ToolError(String(localized: "Dieses Gespräch betrifft nur eine Notiz.")) }
        var folderID: UUID?
        if let key = args.string("folder_id") {
            guard let folder = access.visibleFolder(key: key) else { throw AppTools.ToolError(Self.folderNotFoundMessage) }
            folderID = folder.id
        }
        var query: String?
        if let text = args.string("query")?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            guard text.count >= 2 else { throw AppTools.ToolError(String(localized: "Die Suche braucht mindestens 2 Zeichen.")) }
            query = text
        }
        let entries = access.entries(folderID: folderID, query: query)
        let folders = access.visibleFolders().map { ["id": NoteToolAccess.folderKey(for: $0.id), "name": $0.name] }
        func json(_ entry: NoteToolAccess.Entry) -> [String: Any] {
            var item: [String: Any] = ["id": NoteToolAccess.key(for: entry.id), "title": entry.title, "folder": entry.folderName,
                                       "updated": dayText(entry.updatedAt)]
            if let matchedIn = entry.matchedIn { item["matched_in"] = matchedIn.rawValue }
            return item
        }
        var listed = entries.prefix(Self.maxListedNotes).map(json)
        func answer(truncated: Bool) -> [String: Any] {
            var result: [String: Any] = ["notes": listed, "folders": folders, "total": entries.count]
            if truncated { result["truncated"] = true }
            return result
        }
        var truncated = listed.count < entries.count
        while AppTools.json(answer(truncated: truncated)).utf8.count > Self.maxListOutputLength, !listed.isEmpty {
            listed.removeLast()
            truncated = true
        }
        return AppTools.json(answer(truncated: truncated))
    }

    /// "YYYY-MM-DD" in the calendar of the planning.
    private func dayText(_ date: Date) -> String {
        AIPlanner.dayString(PlanDay(date: date, calendar: base.planning.calendar))
    }

    /// Stored form of a `list_notes` output: the number of titles delivered, no titles. An error or an already stored form stays as it is.
    static func storedListOutput(_ output: String) -> String {
        guard let data = output.data(using: .utf8), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let notes = object["notes"] as? [Any] else { return output }
        return AppTools.json(["ok": true, "listed": notes.count])
    }

    /// The number of titles in a `list_notes` output, from the full form (`notes`) and from the stored form (`listed`).
    static func listedCount(in output: String) -> Int? {
        guard let data = output.data(using: .utf8), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        if let notes = object["notes"] as? [Any] { return notes.count }
        return object["listed"] as? Int
    }
}
