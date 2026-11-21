import AIKit
import Foundation
import TagwerkCore

/// `read_note`: the full text of a note the assistant found with `search` (issue #173, decision D4).
extension AppTools {
    /// Longest text of one note; a longer note is cut and flagged `truncated`.
    static let maxNoteTextLength = 12_000
    /// Budget of one `read_note` answer in UTF-8 bytes, below the 16 KB limit of `Conversation.clipped`.
    static let maxReadOutputLength = 14_000
    /// How many notes one call may read.
    static let maxNotesPerRead = 5
    /// A note that would fit with less text than this is reported as `not_read` instead of being cut that far.
    private static let minimumUsefulTextLength = 300

    /// Answer for private, trashed and unknown ids alike: the existence of a private note is not readable.
    static var noteNotFoundMessage: String { String(localized: "Notiz nicht gefunden.") }

    /// What the stored chat keeps of a `read_note` result: the titles and a notice, never the text.
    static let noteTextGoneNotice = "Der Text ist nicht mehr verfügbar. Lies die Notiz erneut, wenn du ihn brauchst."

    /// Whether the consent "Notizen mit ChatGPT" is on and the context has notes.
    var offersNotes: Bool { noteAccess != nil && notesAllowed }

    func readNote(_ args: Arguments) throws -> String {
        guard notesAllowed, let noteAccess else {
            throw ToolError(String(localized: "Die Einwilligung „Notizen mit ChatGPT“ fehlt."))
        }
        var ids: [String] = []
        for id in args.strings("note_ids") where !ids.contains(id) { ids.append(id) }
        guard !ids.isEmpty else { throw ToolError(String(localized: "Das Argument note_ids fehlt.")) }
        guard ids.count <= Self.maxNotesPerRead else { throw ToolError(String(localized: "Höchstens fünf Notizen auf einmal.")) }

        var entries: [[String: Any]] = []
        var notFound: [String] = []
        var notRead: [String] = []
        var remaining = Self.maxReadOutputLength - 400   // room for the keys around the entries
        for id in ids {
            guard let note = noteAccess.visibleNote(key: id) else {
                notFound.append(id)
                continue
            }
            let title = Self.truncated(Self.noteTitle(note), to: Self.maxNoteTitleLength)
            var text = String(note.text.prefix(Self.maxNoteTextLength))
            var isTruncated = note.text.count > Self.maxNoteTextLength
            func entry() -> [String: Any] { ["id": id, "title": title, "text": text, "truncated": isTruncated] }
            if Self.jsonSize(entry()) > remaining {
                // Cut the text to what is left of the budget (binary search on the character count).
                var low = 0, high = text.count
                let full = text
                while low < high {
                    let middle = (low + high + 1) / 2
                    text = String(full.prefix(middle))
                    isTruncated = true
                    if Self.jsonSize(entry()) <= remaining { low = middle } else { high = middle - 1 }
                }
                text = String(full.prefix(low))
                isTruncated = true
                guard low >= min(Self.minimumUsefulTextLength, full.count) else {
                    notRead.append(id)
                    continue
                }
            }
            remaining -= Self.jsonSize(entry())
            entries.append(entry())
            noteSession.remember(note.id, text: text, truncated: isTruncated)
        }
        if entries.isEmpty && notRead.isEmpty {
            throw ToolError(Self.noteNotFoundMessage)
        }
        var answer: [String: Any] = ["notes": entries]
        if !notFound.isEmpty { answer["notFound"] = notFound }
        if !notRead.isEmpty { answer["not_read"] = notRead }
        return Self.json(answer)
    }

    /// First line of the note as plain text, "Ohne Titel" for a note without one.
    private static func noteTitle(_ note: NoteRecord) -> String {
        let title = SearchDocument(noteText: MarkdownText.plainText(note.text), kindLabel: "").title
        return title.isEmpty ? String(localized: "Ohne Titel") : title
    }

    private static func jsonSize(_ entry: [String: Any]) -> Int {
        (try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys, .withoutEscapingSlashes]).count) ?? 0
    }

    /// Titles of a `read_note` output, from the full form (`notes[].title`) and from the stored form (`read`).
    static func readNoteTitles(in output: String) -> [String] {
        guard let data = output.data(using: .utf8), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return []
        }
        if let notes = object["notes"] as? [[String: Any]] { return notes.compactMap { $0["title"] as? String } }
        return object["read"] as? [String] ?? []
    }

    /// Stored form of a `read_note` output: titles and a notice. An output that cannot be parsed holds no titles.
    static func storedReadNoteOutput(_ output: String) -> String {
        if let data = output.data(using: .utf8), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           object["notes"] == nil {
            return output   // an error or an already stored form: no note text in it
        }
        return json(["ok": true, "read": readNoteTitles(in: output), "note": noteTextGoneNotice])
    }
}
