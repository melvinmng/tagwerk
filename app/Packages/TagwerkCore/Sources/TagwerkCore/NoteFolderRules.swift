import Foundation

/// A system folder of the notes: it has a fixed purpose, can be renamed but neither deleted nor moved.
public enum NoteFolderRole: String, Sendable, CaseIterable {
    case journal
    case bibleStudy
    /// Free-form thoughts; the user's own notes may be created in and moved into it.
    case brainDump
    /// Holds the morning thought notes of the daily routine.
    case morningRoutine
    /// Holds the evening thought notes of the daily routine.
    case eveningRoutine
    /// Holds the dream notes ("Dream Log"), one per day, written in the morning routine.
    case dreamLog

    /// The folder a kind of note belongs to; `nil` for kinds that have no fixed folder (free notes, journal, Bible Study).
    public static func role(for kind: NoteKind) -> NoteFolderRole? {
        allCases.first { $0.noteKind == kind }
    }

    /// Notes in a private folder never leave the device (see `NoteKind.isPrivate`).
    public var isPrivate: Bool {
        switch self {
        case .journal, .bibleStudy, .dreamLog: true
        case .brainDump, .morningRoutine, .eveningRoutine: false
        }
    }

    /// Whether a backup holds the folder without the switch "Tagebuch und Bible Study einschließen" (same rule as
    /// `NoteKind.isInDefaultBackup`).
    public var isInDefaultBackup: Bool {
        switch self {
        case .journal, .bibleStudy: false
        case .brainDump, .morningRoutine, .eveningRoutine, .dreamLog: true
        }
    }

    /// Whether the user's own (free) notes may be moved into this folder. The routine folders and the Dream Log are
    /// filled by the routines only. Journal and Bible Study keep the behaviour they always had: the folder picker offers them.
    public var acceptsOwnNotes: Bool {
        switch self {
        case .journal, .bibleStudy, .brainDump: true
        case .morningRoutine, .eveningRoutine, .dreamLog: false
        }
    }

    /// The kind of thought note that belongs into the folder; `nil` for folders without a fixed kind of note.
    public var noteKind: NoteKind? {
        switch self {
        case .morningRoutine: .morning
        case .eveningRoutine: .evening
        case .dreamLog: .dream
        case .journal, .bibleStudy, .brainDump: nil
        }
    }
}

/// A folder as the rules see it, independent of the storage model.
public struct NoteFolderInfo: Sendable, Hashable, Identifiable {
    public let id: UUID
    public var name: String
    public var parentID: UUID?
    public var order: Int
    public var role: NoteFolderRole?

    public init(id: UUID, name: String, parentID: UUID? = nil, order: Int = 0, role: NoteFolderRole? = nil) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.order = order
        self.role = role
    }
}

/// One node of the folder tree; `depth` is 1 for a top-level folder.
public struct NoteFolderNode: Sendable, Hashable, Identifiable {
    public var id: UUID { folder.id }
    public let folder: NoteFolderInfo
    public let depth: Int
    public let children: [NoteFolderNode]

    /// This node followed by all its descendants, depth first.
    public var flattened: [NoteFolderNode] { [self] + children.flatMap(\.flattened) }
}

/// Pure rules of the note folders: tree, depth, names, counts and the retention of deleted notes.
public enum NoteFolderRules {
    /// Folders nest at most this deep (a top-level folder has depth 1).
    public static let maximumDepth = 3
    public static let nameLimit = HabitRules.nameLimit
    /// Deleted notes are removed for good after this many days.
    public static let retentionDays = 30

    public enum NameError: Error, Sendable, Equatable {
        case empty, tooLong, duplicate
    }

    public enum MoveError: Error, Sendable, Equatable {
        case systemFolder, tooDeep, cycle, unknownFolder
    }

    // MARK: Tree

    /// Top-level folders and their children, each level by `order`, then by name. A folder whose parent is missing
    /// counts as a top-level folder, so no folder is lost to a broken reference. A reference cycle is cut at the
    /// first repeated folder.
    public static func tree(_ folders: [NoteFolderInfo]) -> [NoteFolderNode] {
        let ids = Set(folders.map(\.id))
        func children(of parent: UUID?, depth: Int, visited: Set<UUID>) -> [NoteFolderNode] {
            let level = folders.filter { folder in
                if let parent { return folder.parentID == parent }
                return folder.parentID == nil || !ids.contains(folder.parentID!)
            }
            return level.sorted(by: precedes).compactMap { folder in
                guard !visited.contains(folder.id) else { return nil }
                return NoteFolderNode(folder: folder, depth: depth,
                                      children: children(of: folder.id, depth: depth + 1, visited: visited.union([folder.id])))
            }
        }
        return children(of: nil, depth: 1, visited: [])
    }

    private static func precedes(_ first: NoteFolderInfo, _ second: NoteFolderInfo) -> Bool {
        if first.order != second.order { return first.order < second.order }
        return first.name.localizedStandardCompare(second.name) == .orderedAscending
    }

    /// Depth of a folder (top level is 1); `nil` for an unknown folder.
    public static func depth(of id: UUID, in folders: [NoteFolderInfo]) -> Int? {
        tree(folders).flatMap(\.flattened).first { $0.id == id }?.depth
    }

    /// The folder and everything below it.
    public static func subtreeIDs(of id: UUID, in folders: [NoteFolderInfo]) -> Set<UUID> {
        guard let node = tree(folders).flatMap(\.flattened).first(where: { $0.id == id }) else { return [] }
        return Set(node.flattened.map(\.id))
    }

    /// Levels of the folder's own subtree, counting the folder itself (a folder without children has height 1).
    static func height(of id: UUID, in folders: [NoteFolderInfo]) -> Int {
        guard let node = tree(folders).flatMap(\.flattened).first(where: { $0.id == id }) else { return 0 }
        func levels(_ node: NoteFolderNode) -> Int { 1 + (node.children.map(levels).max() ?? 0) }
        return levels(node)
    }

    /// Whether a new folder may be created below `parentID` (`nil` is the top level).
    public static func canCreateFolder(under parentID: UUID?, in folders: [NoteFolderInfo]) -> Bool {
        guard let parentID else { return true }
        guard let parent = folders.first(where: { $0.id == parentID }), parent.role == nil,
              let depth = depth(of: parentID, in: folders) else { return false }
        return depth < maximumDepth
    }

    /// Checks a move of `id` below `parentID`: no system folder, no move into itself or its own subtree, and the
    /// moved subtree must still fit into `maximumDepth`.
    public static func validateMove(_ id: UUID, to parentID: UUID?, in folders: [NoteFolderInfo]) throws {
        guard let folder = folders.first(where: { $0.id == id }) else { throw MoveError.unknownFolder }
        guard folder.role == nil else { throw MoveError.systemFolder }
        guard let parentID else { return }
        guard let parent = folders.first(where: { $0.id == parentID }),
              let parentDepth = depth(of: parentID, in: folders) else { throw MoveError.unknownFolder }
        guard parent.role == nil else { throw MoveError.systemFolder }
        if subtreeIDs(of: id, in: folders).contains(parentID) { throw MoveError.cycle }
        if parentDepth + height(of: id, in: folders) > maximumDepth { throw MoveError.tooDeep }
    }

    // MARK: Names

    /// The trimmed name, or the reason it is not allowed: not empty, at most `nameLimit` characters, and unique
    /// among the folders below the same parent (ignoring case and accents). `excluding` is the folder being renamed.
    public static func validatedName(_ name: String, parentID: UUID?, in folders: [NoteFolderInfo],
                                     excluding: UUID? = nil) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NameError.empty }
        guard trimmed.count <= nameLimit else { throw NameError.tooLong }
        let folded = SearchText.fold(trimmed)
        let clash = folders.contains { $0.id != excluding && $0.parentID == parentID && SearchText.fold($0.name) == folded }
        guard !clash else { throw NameError.duplicate }
        return trimmed
    }

    // MARK: Counts

    /// Notes per folder including the notes of all subfolders. `noteFolderIDs` holds the folder of each live note;
    /// `nil` stands for the default folder and is not counted here.
    public static func noteCounts(folders: [NoteFolderInfo], noteFolderIDs: [UUID?]) -> [UUID: Int] {
        var own: [UUID: Int] = [:]
        for case let id? in noteFolderIDs { own[id, default: 0] += 1 }
        var counts: [UUID: Int] = [:]
        for node in tree(folders).flatMap(\.flattened) {
            counts[node.id] = node.flattened.reduce(0) { $0 + own[$1.id, default: 0] }
        }
        return counts
    }

    // MARK: Retention

    /// Whether a note deleted at `deletedAt` is past the retention time at `now`.
    public static func isExpired(deletedAt: Date, now: Date, calendar: Calendar = .current) -> Bool {
        guard let limit = calendar.date(byAdding: .day, value: retentionDays, to: deletedAt) else { return false }
        return now >= limit
    }

    /// Days left before a deleted note is removed for good, at least 0.
    public static func daysLeft(deletedAt: Date, now: Date, calendar: Calendar = .current) -> Int {
        guard let limit = calendar.date(byAdding: .day, value: retentionDays, to: deletedAt) else { return 0 }
        let days = calendar.dateComponents([.day], from: now, to: limit).day ?? 0
        return max(0, days)
    }
}

/// What the order of a list of notes is based on.
public enum NoteSortOrder: String, Sendable, CaseIterable {
    case modified, created, title
}

/// The fields of a note that decide its place in a list.
public struct NoteSortKey: Sendable {
    public let isPinned: Bool
    public let createdAt: Date
    public let updatedAt: Date
    public let title: String

    public init(isPinned: Bool, createdAt: Date, updatedAt: Date, title: String) {
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
    }
}

extension NoteSortOrder {
    /// Pinned notes always come first. Dates sort newest first, titles alphabetically; ties fall back to the change date.
    public func precedes(_ first: NoteSortKey, _ second: NoteSortKey) -> Bool {
        if first.isPinned != second.isPinned { return first.isPinned }
        switch self {
        case .modified:
            return first.updatedAt > second.updatedAt
        case .created:
            if first.createdAt != second.createdAt { return first.createdAt > second.createdAt }
            return first.updatedAt > second.updatedAt
        case .title:
            let order = first.title.localizedStandardCompare(second.title)
            if order != .orderedSame { return order == .orderedAscending }
            return first.updatedAt > second.updatedAt
        }
    }
}
