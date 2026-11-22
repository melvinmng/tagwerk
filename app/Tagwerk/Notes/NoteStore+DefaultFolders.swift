import Foundation
import TagwerkCore

/// The fixed folders "Brain Dump", "Tagesstart", "Tagesabschluss", "Dream Log" and "Rezepte" on top of the notes store.
/// Writing still goes only through `NoteStore`.
extension NoteStore {
    /// The fixed folders in display order.
    static let defaultFolderRoles: [NoteFolderRole] = [.brainDump, .morningRoutine, .eveningRoutine, .dreamLog, .recipes]

    /// The name a fixed folder gets when it is created. The user may rename it afterwards; a rename is kept.
    static func defaultFolderName(for role: NoteFolderRole) -> String {
        switch role {
        case .journal: String(localized: "Tagebuch mit Gott")
        case .bibleStudy: String(localized: "Bible Study")
        case .brainDump: String(localized: "Brain Dump")
        case .morningRoutine: String(localized: "Tagesstart")
        case .eveningRoutine: String(localized: "Tagesabschluss")
        case .dreamLog: String(localized: "Dream Log")
        case .recipes: String(localized: "Rezepte")
        }
    }

    enum FolderResetError: Error, Equatable {
        /// The folder is the user's own; only a system folder has a fixed name to go back to.
        case notASystemFolder
    }

    /// Whether a system folder carries another name than the one it was created with.
    static func isRenamed(_ folder: NoteFolderRecord) -> Bool {
        guard let role = folder.role else { return false }
        return folder.name != defaultFolderName(for: role)
    }

    /// Puts the fixed name back; only offered while the name differs from `defaultFolderName(for:)`. Throws
    /// `FolderResetError.notASystemFolder` for the user's own folders and `NoteFolderRules.NameError.duplicate` when
    /// another folder on the same level has taken the fixed name meanwhile.
    func resetFolderName(_ id: UUID) throws {
        guard let record = folder(id: id) else { return }
        guard let role = record.role else { throw FolderResetError.notASystemFolder }
        try renameFolder(id, to: Self.defaultFolderName(for: role))
    }

    /// Creates the fixed folders that are missing and files the routine and dream notes into their folders.
    /// Safe to call again at any time: it creates nothing twice, keeps renamed folders and saves only after a change.
    func ensureDefaultFolders() {
        for role in Self.defaultFolderRoles {
            ensureSystemFolder(role, name: Self.defaultFolderName(for: role))
        }
        sortRoutineNotes()
    }

    /// Puts every morning, evening and dream note into the folder of its kind, notes in the trash included, so a
    /// restored note finds its folder again. Free notes, journal entries and Bible Study notes stay where they are.
    func sortRoutineNotes() {
        var changed = false
        for record in allNotes() {
            guard let role = NoteFolderRole.role(for: record.kind), let folder = folder(role: role),
                  record.folderID != folder.id else { continue }
            record.folderID = folder.id
            changed = true
        }
        if changed { save() }
    }
}
