import AIKit
import Foundation

/// Strict JSON schemas of the note tools (same rules as `AppTools+Definitions`: every property required, optional values nullable).
extension NoteChatTools {
    static var listNotesDefinition: ToolDefinition {
        AppTools.tool("list_notes", "Lists the user's notes with id, title, folder and date of the last change, newest first; never the text. Private notes (journal, Bible Study, dream log) are not included. Use folder_id to list one folder (with the folders below it) and query to find notes whose title or text contains every word. Read the text of a note with read_note, only when the request needs it. Also returns the folders you can use.", [
            "folder_id": AppTools.string("Folder id of the form folder:<uuid> from the folders of an earlier list_notes; null for all notes", nullable: true),
            "query": AppTools.string("Words that all have to occur in the title or text, at least 2 characters; null for no filter", nullable: true),
        ])
    }

    static var changeDefinitions: [ToolDefinition] {
        [
            AppTools.tool("create_note", "Creates a new note. The first line of text is the title; the text is Markdown. Without folder_id it goes to the folder this chat was opened from, otherwise to Notizen. Cannot attach files or pictures. Needs confirmation.", [
                "text": AppTools.string("The complete text of the new note; the first line is the title"),
                "folder_id": AppTools.string("Folder id from list_notes; null for the default", nullable: true),
            ]),
            AppTools.tool("update_note", "Replaces the text of a note you have read with read_note in this conversation and that has not changed since. text is the complete new text; the first line is the title; keep every reference of the form (attachment:<uuid>) unchanged. Only one change per note and answer. A note that was cut when read cannot be revised. Needs confirmation.", [
                "note_id": AppTools.string("Note id of the form note:<uuid>"),
                "text": AppTools.string("The complete new text of the note"),
            ]),
            AppTools.tool("delete_note", "Moves a note to Zuletzt gelöscht, where the user can restore it for 30 days. It cannot empty that folder or delete for good. Needs confirmation.", [
                "note_id": AppTools.string("Note id of the form note:<uuid>"),
                "reason": AppTools.string("Short reason, shown on the card; null for none", nullable: true),
            ]),
        ]
    }
}
