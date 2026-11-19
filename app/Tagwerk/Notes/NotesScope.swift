import Foundation

/// What a notes list shows: the entries of the folder overview, or one real folder.
enum NotesScope: Hashable {
    /// Every note outside the trash.
    case all
    /// The default folder "Notizen".
    case standard
    /// "Zuletzt gelöscht".
    case trash
    case folder(UUID)

    var filter: NoteStore.Filter {
        switch self {
        case .all: .all
        case .standard: .own
        case .trash: .trash
        case .folder(let id): .folder(id)
        }
    }

    /// Whether the quick capture bar is offered: a new note needs a place to land.
    var allowsCapture: Bool {
        switch self {
        case .all, .standard, .folder: true
        case .trash: false
        }
    }

    /// The folder a new note is created in; `nil` is the default folder.
    var captureFolderID: UUID? {
        if case .folder(let id) = self { return id }
        return nil
    }
}
