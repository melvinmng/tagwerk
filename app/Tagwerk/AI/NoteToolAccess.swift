import Foundation
import TagwerkCore

/// The only place that selects notes for ChatGPT: `search`, `read_note` and the note tools of the notes chat all go
/// through it. A note is visible when it is neither in the trash nor private (`NoteStore.isPrivate`: a private kind or
/// folder, or a locked note, also while the lock is open).
@MainActor
struct NoteToolAccess {
    let store: NoteStore

    /// Prefix of the id the assistant sees: "note:<UUID>".
    static let keyPrefix = "note:"

    /// Notes that are neither trashed nor private nor locked.
    func visibleNotes() -> [NoteRecord] {
        let privateFolders = NoteFolderRules.privateFolderIDs(in: store.folders().map(\.info))
        return store.notes(.all).filter {
            NoteFolderRules.mayLeaveDevice(kind: $0.kind, folderID: $0.folderID, privateFolderIDs: privateFolders, isLocked: $0.isLocked)
        }
    }

    /// The visible note for a key of the form "note:<UUID>"; `nil` for private, trashed and unknown notes alike,
    /// so the answer does not reveal that a private note exists.
    func visibleNote(key: String) -> NoteRecord? {
        guard key.hasPrefix(Self.keyPrefix), let id = UUID(uuidString: String(key.dropFirst(Self.keyPrefix.count))) else { return nil }
        return visibleNotes().first { $0.id == id }
    }

    static func key(for id: UUID) -> String { keyPrefix + id.uuidString }

    /// The names of the folders that never leave the device, as the user sees them (a renamed folder keeps its new name);
    /// a folder that does not exist yet shows its default name. Journal, Bible Study and Dream Log, in this order.
    func privateFolderNames() -> [String] {
        let roles: [NoteFolderRole] = [.journal, .bibleStudy, .dreamLog]
        return roles.map { role in store.folder(role: role)?.name ?? NoteStore.defaultFolderName(for: role) }
    }

    /// "A, B und C" in the language of the user (or of `locale`); used by the consent sheet, the context line and the
    /// sentence about private notes.
    static func listText(_ names: [String], locale: Locale = .autoupdatingCurrent) -> String {
        names.formatted(.list(type: .and).locale(locale))
    }
}
