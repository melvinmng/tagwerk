import Foundation
import OSLog

/// Log of the moments in which a page of the notes closes or the navigation of the "Aufgaben" tab is replaced (#305). The device is
/// the only place where "the note closes by itself" can be observed, so every such moment leaves a line. Filter in Console.app or
/// with `log stream --predicate 'subsystem == "local.tagwerk" AND category == "notes-navigation"'`. Note titles and texts are
/// never logged, only identifiers and counts.
enum NotesNavigationLog {
    private static let logger = Logger(subsystem: "local.tagwerk", category: "notes-navigation")

    /// The editor closes itself because its note is gone or in the trash.
    static func editorClosed(noteID: UUID, reason: String) {
        logger.notice("Editor closes: note \(noteID.uuidString, privacy: .public), reason: \(reason, privacy: .public)")
    }

    /// The editor could not read the note and stays open.
    static func noteUnreadable(noteID: UUID, error: String) {
        logger.error("Note not readable, editor stays open: note \(noteID.uuidString, privacy: .public), error: \(error, privacy: .public)")
    }

    /// The editor page went away; `pathHoldsNote` tells whether the navigation path still holds the note.
    static func editorDisappeared(noteID: UUID, pathHoldsNote: Bool) {
        logger.info("Editor disappeared: note \(noteID.uuidString, privacy: .public), still in path: \(pathHoldsNote, privacy: .public)")
    }

    /// A request to open the Bible Study start sheet arrived while a note is open: the path is left alone.
    static func startRequestKeptNote() {
        logger.notice("Bible Study start request ignored: a note is open, the path stays")
    }

    /// The path of the tab "Aufgaben" changed in a way that drops an open note: a pop (back button) or a replacement.
    static func pathDroppedNote(old: Int, new: Int, isPrefix: Bool) {
        logger.notice("Path dropped a note: \(old, privacy: .public) -> \(new, privacy: .public) pages, \(isPrefix ? "pop" : "replaced", privacy: .public)")
    }
}
