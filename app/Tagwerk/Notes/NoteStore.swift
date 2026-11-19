import Foundation
import Observation
import SwiftData
import TagwerkCore

/// The notes on this device. The only place that writes `NoteRecord`; the notes pages and, later, the
/// thought notes of the daily routines use it. Nothing here leaves the device.
@MainActor
@Observable
final class NoteStore {
    enum Filter: Equatable {
        /// Every note that is not in the trash.
        case all
        /// Morning and evening notes (the virtual folder "Gedanken").
        case thoughts
        /// The user's own notes in the default folder "Notizen".
        case own
        /// The notes lying directly in one folder.
        case folder(UUID)
        /// "Zuletzt gelöscht".
        case trash
    }

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let now: () -> Date
    /// Bumped by every write; views read it to follow changes.
    private(set) var revision = 0

    init(context: ModelContext, now: @escaping () -> Date = Date.init) {
        self.context = context
        self.now = now
    }

    // MARK: Reading

    /// The notes of a filter. Pinned notes first, then by `order`; the trash lists the newest deletion first.
    func notes(_ filter: Filter = .all, sortedBy order: NoteSortOrder = .modified) -> [NoteRecord] {
        let folderIDs = Set(folders().map(\.id))
        let matching = all().filter { note in
            if case .trash = filter { return note.deletedAt != nil }
            guard note.deletedAt == nil else { return false }
            switch filter {
            case .all: return true
            case .thoughts: return note.kind == .morning || note.kind == .evening
            // A note whose folder is gone reads as lying in the default folder.
            case .own: return note.kind == .free && (note.folderID.map { !folderIDs.contains($0) } ?? true)
            case .folder(let id): return note.folderID == id
            case .trash: return false
            }
        }
        if case .trash = filter {
            return matching.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
        }
        return matching.sorted { order.precedes(Self.sortKey($0), Self.sortKey($1)) }
    }

    private static func sortKey(_ note: NoteRecord) -> NoteSortKey {
        NoteSortKey(isPinned: note.isPinned, createdAt: note.createdAt, updatedAt: note.updatedAt, title: NoteText.title(note.text))
    }

    func note(id: UUID) -> NoteRecord? {
        all().first { $0.id == id }
    }

    /// The thought note of a kind and day, if there is one (a note in the trash does not count).
    func note(kind: NoteKind, dayKey: String) -> NoteRecord? {
        all().first { $0.deletedAt == nil && $0.kind == kind && $0.dayKey == dayKey }
    }

    var hasThoughts: Bool { all().contains { $0.deletedAt == nil && $0.kind != .free } }

    /// Notes that are not in the trash.
    var count: Int { all().filter { $0.deletedAt == nil }.count }

    /// How many notes are in "Zuletzt gelöscht".
    var trashedCount: Int { all().filter { $0.deletedAt != nil }.count }

    /// The note changed last.
    var latest: NoteRecord? { all().filter { $0.deletedAt == nil }.max { $0.updatedAt < $1.updatedAt } }

    // MARK: Writing

    /// Creates a note from trimmed text; empty text creates nothing. A morning or evening note exists once
    /// per day: a second one for the same kind and day replaces the text of the first.
    @discardableResult
    func create(text: String, kind: NoteKind = .free, dayKey: String? = nil, wasDictated: Bool = false,
                folderID: UUID? = nil) -> NoteRecord? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if kind != .free, let dayKey, let existing = note(kind: kind, dayKey: dayKey) {
            if existing.text != trimmed {
                existing.text = trimmed
                existing.updatedAt = now()
            }
            existing.wasDictated = wasDictated
            save()
            return existing
        }
        let record = NoteRecord(text: trimmed, kind: kind, dayKey: kind == .free ? nil : dayKey, wasDictated: wasDictated, now: now())
        // Thought notes live in the virtual folder "Gedanken", never in a real one.
        record.folderID = (kind == .morning || kind == .evening) ? nil : folderID
        context.insert(record)
        save()
        return record
    }

    /// Replaces the text; the change date moves only when the text differs.
    func updateText(_ id: UUID, text: String) {
        guard let record = note(id: id), record.text != text else { return }
        record.text = text
        record.updatedAt = now()
        save()
    }

    /// Pinning is not a change of the note: the change date stays.
    func setPinned(_ id: UUID, _ pinned: Bool) {
        guard let record = note(id: id), record.isPinned != pinned else { return }
        record.isPinned = pinned
        save()
    }

    func markProcessed(_ id: UUID, at date: Date) {
        guard let record = note(id: id) else { return }
        record.processedAt = date
        save()
    }

    /// Removes a note for good, without a trip through "Zuletzt gelöscht".
    func delete(_ id: UUID) {
        guard let record = note(id: id) else { return }
        context.delete(record)
        save()
    }

    /// Removes a note that holds only whitespace, e.g. when the editor closes.
    func deleteIfEmpty(_ id: UUID) {
        guard let record = note(id: id),
              record.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        context.delete(record)
        save()
    }

    // MARK: Trash

    /// Moves a note to "Zuletzt gelöscht". It stays there for `NoteFolderRules.retentionDays` days.
    func trash(_ id: UUID) {
        guard let record = note(id: id), record.deletedAt == nil else { return }
        record.deletedAt = now()
        record.isPinned = false
        save()
    }

    /// Puts a note back into its old folder, or into "Notizen" when that folder is gone.
    func restore(_ id: UUID) {
        guard let record = note(id: id), record.deletedAt != nil else { return }
        record.deletedAt = nil
        if let folderID = record.folderID, folder(id: folderID) == nil { record.folderID = nil }
        save()
    }

    /// Empties "Zuletzt gelöscht".
    func emptyTrash() {
        for record in all() where record.deletedAt != nil { context.delete(record) }
        save()
    }

    /// Removes the notes that are past the retention time of the trash; returns how many went.
    @discardableResult
    func purgeExpired(now: Date? = nil, calendar: Calendar = .current) -> Int {
        let reference = now ?? self.now()
        let expired = all().filter { record in
            record.deletedAt.map { NoteFolderRules.isExpired(deletedAt: $0, now: reference, calendar: calendar) } ?? false
        }
        guard !expired.isEmpty else { return 0 }
        for record in expired { context.delete(record) }
        save()
        return expired.count
    }

    // MARK: Folders

    func folders() -> [NoteFolderRecord] {
        _ = revision
        return (try? context.fetch(FetchDescriptor<NoteFolderRecord>())) ?? []
    }

    func folder(id: UUID) -> NoteFolderRecord? {
        folders().first { $0.id == id }
    }

    /// The system folder of a role, if it was created.
    func folder(role: NoteFolderRole) -> NoteFolderRecord? {
        folders().first { $0.role == role }
    }

    /// The folders as a tree, in display order.
    func folderTree() -> [NoteFolderNode] {
        NoteFolderRules.tree(folders().map(\.info))
    }

    /// Notes per folder including all subfolders (live notes only).
    func folderCounts() -> [UUID: Int] {
        NoteFolderRules.noteCounts(folders: folders().map(\.info),
                                   noteFolderIDs: all().filter { $0.deletedAt == nil }.map(\.folderID))
    }

    /// Creates a folder below `parentID` (`nil` is the top level) at the end of its level.
    /// Throws `NoteFolderRules.NameError` for a bad name and `MoveError.tooDeep` below the third level.
    @discardableResult
    func createFolder(name: String, parentID: UUID? = nil) throws -> NoteFolderRecord {
        let infos = folders().map(\.info)
        let trimmed = try NoteFolderRules.validatedName(name, parentID: parentID, in: infos)
        if !NoteFolderRules.canCreateFolder(under: parentID, in: infos) { throw NoteFolderRules.MoveError.tooDeep }
        let order = (infos.filter { $0.parentID == parentID }.map(\.order).max() ?? -1) + 1
        let record = NoteFolderRecord(name: trimmed, parentID: parentID, order: order, now: now())
        context.insert(record)
        save()
        return record
    }

    /// The system folder of a role; created with `name` on first use.
    @discardableResult
    func ensureSystemFolder(_ role: NoteFolderRole, name: String) -> NoteFolderRecord {
        if let existing = folder(role: role) { return existing }
        let order = (folders().filter { $0.parentID == nil }.map(\.order).max() ?? -1) + 1
        let record = NoteFolderRecord(name: name, parentID: nil, order: order, role: role, now: now())
        context.insert(record)
        save()
        return record
    }

    func renameFolder(_ id: UUID, to name: String) throws {
        guard let record = folder(id: id) else { return }
        let trimmed = try NoteFolderRules.validatedName(name, parentID: record.parentID, in: folders().map(\.info), excluding: id)
        guard record.name != trimmed else { return }
        record.name = trimmed
        save()
    }

    func moveFolder(_ id: UUID, to parentID: UUID?) throws {
        let infos = folders().map(\.info)
        try NoteFolderRules.validateMove(id, to: parentID, in: infos)
        guard let record = folder(id: id), record.parentID != parentID else { return }
        _ = try NoteFolderRules.validatedName(record.name, parentID: parentID, in: infos, excluding: id)
        record.parentID = parentID
        record.order = (infos.filter { $0.parentID == parentID }.map(\.order).max() ?? -1) + 1
        save()
    }

    /// Deletes a folder with its subfolders; their notes go to "Zuletzt gelöscht". A system folder cannot be deleted.
    func deleteFolder(_ id: UUID) throws {
        let infos = folders().map(\.info)
        guard let record = folder(id: id) else { return }
        guard record.role == nil else { throw NoteFolderRules.MoveError.systemFolder }
        let removed = NoteFolderRules.subtreeIDs(of: id, in: infos)
        let date = now()
        for note in all() where note.deletedAt == nil && note.folderID.map(removed.contains) == true {
            note.deletedAt = date
            note.isPinned = false
        }
        for folder in folders() where removed.contains(folder.id) { context.delete(folder) }
        save()
    }

    /// How many live notes a deletion of the folder would send to the trash (its subfolders included).
    func notesAffectedByDeleting(folder id: UUID) -> Int {
        let removed = NoteFolderRules.subtreeIDs(of: id, in: folders().map(\.info))
        return all().filter { $0.deletedAt == nil && $0.folderID.map(removed.contains) == true }.count
    }

    /// Moves the user's own notes into a folder (`nil` is "Notizen"). Thought notes stay where they are.
    func move(noteIDs: [UUID], to folderID: UUID?) {
        if let folderID, folder(id: folderID) == nil { return }
        let wanted = Set(noteIDs)
        var changed = false
        for record in all() where wanted.contains(record.id) && record.deletedAt == nil && record.kind == .free
            && record.folderID != folderID {
            record.folderID = folderID
            changed = true
        }
        if changed { save() }
    }

    private func all() -> [NoteRecord] {
        _ = revision
        return (try? context.fetch(FetchDescriptor<NoteRecord>())) ?? []
    }

    /// Saves and bumps `revision`; internal so the routines' extension can write through the same path.
    func save() {
        try? context.save()
        revision += 1
    }
}
