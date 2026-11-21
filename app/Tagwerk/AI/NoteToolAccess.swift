import Foundation
import TagwerkCore

/// The only place that selects notes for ChatGPT: `search`, `read_note` and the note tools of the notes chat all go
/// through it. A note is visible when it is neither in the trash nor private (`NoteStore.isPrivate`).
@MainActor
struct NoteToolAccess {
    let store: NoteStore

    /// Prefix of the id the assistant sees: "note:<UUID>".
    static let keyPrefix = "note:"

    /// Notes that are neither trashed nor private.
    func visibleNotes() -> [NoteRecord] {
        let privateFolders = NoteFolderRules.privateFolderIDs(in: store.folders().map(\.info))
        return store.notes(.all).filter {
            NoteFolderRules.mayLeaveDevice(kind: $0.kind, folderID: $0.folderID, privateFolderIDs: privateFolders)
        }
    }

    /// The visible note for a key of the form "note:<UUID>"; `nil` for private, trashed and unknown notes alike,
    /// so the answer does not reveal that a private note exists.
    func visibleNote(key: String) -> NoteRecord? {
        guard key.hasPrefix(Self.keyPrefix), let id = UUID(uuidString: String(key.dropFirst(Self.keyPrefix.count))) else { return nil }
        return visibleNotes().first { $0.id == id }
    }

    static func key(for id: UUID) -> String { keyPrefix + id.uuidString }
}
