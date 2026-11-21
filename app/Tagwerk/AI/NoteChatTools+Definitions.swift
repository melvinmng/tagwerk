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
}
