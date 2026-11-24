import AIKit
import Foundation
import TagwerkCore

/// `create_note`, `update_note` and `delete_note`. They run only after the user confirmed the card. Every check answers
/// with a German sentence the model can act on; for private and trashed notes the answer is the one for an unknown id.
extension NoteChatTools {
    /// Longest text of a note the assistant writes, the same limit as for reading.
    static var maxWrittenTextLength: Int { AppTools.maxNoteTextLength }
    /// Longest title kept in the stored form of `create_note` and `update_note`.
    static let maxStoredTitleLength = 80

    // MARK: create_note

    func createNote(_ args: AppTools.Arguments) throws -> String {
        let text = try checkedNewText(try args.require("text"))
        guard MarkdownText.attachmentReferences(in: text).isEmpty else {
            throw AppTools.ToolError(String(localized: "Anhänge kann der Assistent nicht anlegen. Nimm den Verweis auf den Anhang nicht in den Text auf."))
        }
        let folderID: UUID?
        do {
            folderID = try access.newNoteFolder(key: args.string("folder_id"), defaultFolderID: defaultFolderID)
        } catch NoteToolAccess.FolderChoiceError.unknown {
            throw AppTools.ToolError(Self.folderNotFoundMessage)
        } catch {
            throw AppTools.ToolError(String(localized: "In diesen Ordner kann der Assistent keine Notiz anlegen."))
        }
        guard let note = access.store.create(text: text, kind: .free, folderID: folderID) else {
            throw AppTools.ToolError(String(localized: "Der Text der Notiz fehlt."))
        }
        // What the assistant wrote counts as read: it may revise the note in the same session. The stored text is the
        // reference (the store trims), not the argument.
        base.noteSession.remember(note.id, text: note.text, truncated: false)
        return AppTools.json(["ok": true, "id": NoteToolAccess.key(for: note.id), "title": NoteToolAccess.displayTitle(note)])
    }

    // MARK: update_note

    func updateNote(_ args: AppTools.Arguments) throws -> String {
        let key = try args.require("note_id")
        try checkScope(key)
        guard let note = access.visibleNote(key: key) else { throw AppTools.ToolError(AppTools.noteNotFoundMessage) }
        guard let read = base.noteSession.readTexts[note.id] else {
            throw AppTools.ToolError(String(localized: "Lies die Notiz zuerst mit read_note, bevor du sie überarbeitest."))
        }
        guard !base.noteSession.truncated.contains(note.id) else {
            throw AppTools.ToolError(String(localized: "Die Notiz ist zu lang und wurde beim Lesen gekürzt. Sie lässt sich nicht überarbeiten."))
        }
        guard note.text == read else {
            throw AppTools.ToolError(String(localized: "Die Notiz wurde inzwischen geändert. Lies sie erneut."))
        }
        let text = try checkedNewText(try args.require("text"))
        guard text != note.text.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw AppTools.ToolError(String(localized: "Der neue Text ist gleich dem alten."))
        }
        guard MarkdownText.attachmentIDs(in: text) == MarkdownText.attachmentIDs(in: note.text) else {
            throw AppTools.ToolError(String(localized: "Die Anhänge der Notiz müssen im Text bleiben. Übernimm die Verweise auf Anhänge unverändert."))
        }
        access.store.updateText(note.id, text: text)
        base.noteSession.remember(note.id, text: text, truncated: false)
        return AppTools.json(["ok": true, "title": NoteToolAccess.displayTitle(note)])
    }

    // MARK: delete_note

    func deleteNote(_ args: AppTools.Arguments) throws -> String {
        let key = try args.require("note_id")
        try checkScope(key)
        guard let note = access.visibleNote(key: key) else { throw AppTools.ToolError(AppTools.noteNotFoundMessage) }
        let title = NoteToolAccess.displayTitle(note)
        access.store.trash(note.id)
        return AppTools.json(["ok": true, "title": title, "trash_days": NoteFolderRules.retentionDays])
    }

    // MARK: Checks

    /// In a chat about one note only that note may be changed or deleted.
    private func checkScope(_ key: String) throws {
        guard let scope, key != NoteToolAccess.key(for: scope) else { return }
        throw AppTools.ToolError(String(localized: "Dieses Gespräch betrifft nur eine andere Notiz."))
    }

    /// The trimmed text when it is neither empty nor longer than `maxWrittenTextLength`.
    private func checkedNewText(_ raw: String) throws -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AppTools.ToolError(String(localized: "Der Text der Notiz fehlt.")) }
        guard text.count <= Self.maxWrittenTextLength else {
            throw AppTools.ToolError(String(localized: "Die Notiz ist zu lang (höchstens 12 000 Zeichen)."))
        }
        return text
    }

    // MARK: Stored form

    /// The arguments of `create_note` and `update_note` without the text, plus its title: the stored chat holds no note text.
    static func storedChangeArguments(_ arguments: String) -> String {
        guard let data = arguments.data(using: .utf8), var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return arguments
        }
        if let text = object.removeValue(forKey: "text") as? String {
            object["title"] = Self.firstLine(of: text)
        }
        return AppTools.json(object)
    }

    /// The first non-empty line, at most `maxStoredTitleLength` characters.
    static func firstLine(of text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        return String(line.trimmingCharacters(in: .whitespaces).prefix(maxStoredTitleLength))
    }
}
