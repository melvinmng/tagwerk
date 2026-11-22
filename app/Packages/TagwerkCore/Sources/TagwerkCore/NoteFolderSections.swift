import Foundation

/// The sections of the notes entry page in display order (design NO1b).
///
/// The first, unnamed block ("Alle Notizen", "Notizen", "Rezepte") is not part of the result: the view builds it
/// from `pinnedRoles`. The three named sections are always present, so the view can place its headings and
/// placeholders even when a section has no folder yet.
public enum NoteFolderSections {
    public enum Kind: Sendable, Equatable { case own, routines, personal }

    public struct Section: Sendable, Equatable {
        public let kind: Kind
        public let folders: [NoteFolderNode]

        public init(kind: Kind, folders: [NoteFolderNode]) {
            self.kind = kind
            self.folders = folders
        }
    }

    /// System folders shown in the first, unnamed section next to "Alle Notizen" and "Notizen".
    public static let pinnedRoles: [NoteFolderRole] = [.recipes]
    /// System folders of the section "Routinen" in display order.
    public static let routineRoles: [NoteFolderRole] = [.brainDump, .morningRoutine, .eveningRoutine, .dreamLog]
    /// System folders of the section "Persönlich" in display order.
    public static let personalRoles: [NoteFolderRole] = [.journal, .bibleStudy]

    /// "Meine Ordner" (the flattened tree of the user's own folders, possibly empty), "Routinen" and "Persönlich" in
    /// the fixed order of their roles. A missing system folder is left out; the view adds the placeholders.
    public static func sections(_ tree: [NoteFolderNode]) -> [Section] {
        let own = tree.filter { $0.folder.role == nil }.flatMap(\.flattened)
        return [
            Section(kind: .own, folders: own),
            Section(kind: .routines, folders: systemFolders(tree, roles: routineRoles)),
            Section(kind: .personal, folders: systemFolders(tree, roles: personalRoles))
        ]
    }

    /// The pinned system folders of the first block that exist, in the order of `pinnedRoles`.
    public static func pinned(_ tree: [NoteFolderNode]) -> [NoteFolderNode] {
        systemFolders(tree, roles: pinnedRoles)
    }

    private static func systemFolders(_ tree: [NoteFolderNode], roles: [NoteFolderRole]) -> [NoteFolderNode] {
        roles.flatMap { role in tree.filter { $0.folder.role == role }.flatMap(\.flattened) }
    }
}
