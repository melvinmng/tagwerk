import Foundation
import Observation
import OSLog
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
        /// The user's own notes in the default folder "Notizen".
        case own
        /// The notes lying directly in one folder.
        case folder(UUID)
        /// "Zuletzt gelöscht".
        case trash
    }

    /// Internal, so the extensions for journal and Bible Study in other files write through the same context.
    @ObservationIgnored let context: ModelContext
    @ObservationIgnored private let logger = Logger(subsystem: "local.tagwerk", category: "notes")
    @ObservationIgnored let now: () -> Date
    /// Bumped by every write; views read it to follow changes.
    private(set) var revision = 0
    /// Bumped by every write that can change what the habits read (a journal entry, a Bible Study session, a folder), but not by the
    /// autosave of a free note or of a Bible Study note: the habits do not read their text, and the refresh writes the widget snapshot.
    private(set) var habitRevision = 0

    /// What the last read of the store returned; invalidated by every save, also one of another writer on this context.
    @ObservationIgnored let notesCache = NoteFetchCache<NoteRecord>()
    @ObservationIgnored let foldersCache = NoteFetchCache<NoteFolderRecord>()
    @ObservationIgnored let sessionsCache = NoteFetchCache<BibleStudySessionRecord>()
    @ObservationIgnored nonisolated(unsafe) private var didSaveObserver: (any NSObjectProtocol)?

    /// Called after a Bible Study session was started or completed: the reminder names the next verse and drops the day of a
    /// completed session, so the app plans it again (BS7). Set by the app environment; the store knows nothing of notifications.
    @ObservationIgnored var onBibleStudyChanged: (() -> Void)?

    /// The pictures and files of the notes; `nil` where nothing needs them (most tests). A note that goes for good takes
    /// its attachments with it.
    @ObservationIgnored let attachments: NoteAttachmentStore?

    init(context: ModelContext, now: @escaping () -> Date = Date.init, attachments: NoteAttachmentStore? = nil) {
        self.context = context
        self.now = now
        self.attachments = attachments
        // Code that saves the context without the store (the backup restore) leaves the caches stale; its save invalidates them.
        didSaveObserver = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.invalidateCaches() }
            } else {
                Task { @MainActor in self?.invalidateCaches() }
            }
        }
    }

    deinit {
        if let didSaveObserver { NotificationCenter.default.removeObserver(didSaveObserver) }
    }

    /// The next read of notes, folders and sessions goes to the store.
    func invalidateCaches() {
        notesCache.invalidate()
        foldersCache.invalidate()
        sessionsCache.invalidate()
    }

    // MARK: Reading

    /// The notes of a filter. Pinned notes first, then by `order`; `ascending` turns the order inside the pinned and the
    /// unpinned notes around (oldest first, "Z bis A"). The trash lists the newest deletion first.
    func notes(_ filter: Filter = .all, sortedBy order: NoteSortOrder = .modified, ascending: Bool = false) -> [NoteRecord] {
        let folderIDs = Set(folders().map(\.id))
        let matching = all().filter { note in
            if case .trash = filter { return note.deletedAt != nil }
            guard note.deletedAt == nil else { return false }
            switch filter {
            case .all: return true
            // A note whose folder is gone reads as lying in the default folder.
            case .own: return note.kind == .free && (note.folderID.map { !folderIDs.contains($0) } ?? true)
            case .folder(let id): return note.folderID == id
            case .trash: return false
            }
        }
        if case .trash = filter {
            return matching.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
        }
        return matching.sorted { order.precedes(Self.sortKey($0), Self.sortKey($1), reversed: ascending) }
    }

    static func sortKey(_ note: NoteRecord) -> NoteSortKey {
        NoteSortKey(isPinned: note.isPinned, createdAt: note.createdAt, updatedAt: note.updatedAt, title: NoteText.title(note.text))
    }

    func note(id: UUID) -> NoteRecord? {
        all().first { $0.id == id }
    }

    /// What a lookup of one note found. `unreadable` is a failed read of the store, not a missing note: a page that follows its note
    /// must not treat it as deleted (#305).
    enum NoteState {
        case present(NoteRecord)
        case absent
        case unreadable(any Error)
    }

    /// Looks the note up in the store itself and tells a missing note from a read that failed. A note in the trash is present.
    func noteState(id: UUID) -> NoteState {
        _ = revision
        var descriptor = FetchDescriptor<NoteRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        do {
            if let record = try context.fetch(descriptor).first { return .present(record) }
            return .absent
        } catch {
            return .unreadable(error)
        }
    }

    /// True when the note must not reach ChatGPT right now: a private kind, a note in a private folder or below one (always), or
    /// a note the user locked while it is not unlocked (`lockHoldsBack`). A locked note that is unlocked in the current lock
    /// session is available to the assistant until the app goes to the background or the lock closes (decision of 2026-11-22,
    /// #188); closing the lock ends the assistant's note session (`onNoteLocked` and `NoteLock.onSessionClosed`). The only rule the
    /// assistant's note access, the suggestions, the translations and the recipe picker use (`NoteFolderRules.mayLeaveDevice`).
    func isPrivate(_ note: NoteRecord) -> Bool {
        !NoteFolderRules.mayLeaveDevice(kind: note.kind, folderID: note.folderID,
                                        privateFolderIDs: NoteFolderRules.privateFolderIDs(in: folders().map(\.info)),
                                        isLocked: lockHoldsBack(note.isLocked))
    }

    /// Whether the lock keeps a locked note away from the assistant right now; the argument is the lock mark of the note. The
    /// app wires it to the lock session (`NoteProtection.holdsBack`); a store without a lock keeps every locked note back.
    @ObservationIgnored var lockHoldsBack: @MainActor (_ isLocked: Bool) -> Bool = { $0 }

    /// How many notes carry the lock mark (notes in the trash included: they stay locked there).
    var lockedCount: Int { all().filter(\.isLocked).count }

    /// Called when notes get locked, so the assistant forgets what it read of them (`AssistantModel.endNoteSession`).
    @ObservationIgnored var onNoteLocked: (@MainActor () -> Void)?
    /// Called after any change of a lock mark, so an open search reads the notes again.
    @ObservationIgnored var onLockMarksChanged: (@MainActor () -> Void)?

    /// The thought note of a kind and day, if there is one (a note in the trash does not count).
    func note(kind: NoteKind, dayKey: String) -> NoteRecord? {
        all().first { $0.deletedAt == nil && $0.kind == kind && $0.dayKey == dayKey }
    }

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
        // Thought and dream notes live in the fixed folder of their kind, journal entries in their system folder.
        switch kind {
        case .morning, .evening, .dream:
            if let role = NoteFolderRole.role(for: kind) {
                record.folderID = ensureSystemFolder(role, name: Self.defaultFolderName(for: role)).id
            }
        case .journal: record.folderID = ensureJournalFolder().id
        case .free, .bibleStudy: record.folderID = folderID
        }
        context.insert(record)
        save()
        return record
    }

    /// A new empty free note in a folder (`nil` is "Notizen"), for the editor to fill. `deleteIfEmpty` removes it
    /// again when the editor closes without text.
    @discardableResult
    func createBlank(folderID: UUID? = nil) -> NoteRecord {
        let record = NoteRecord(text: "", kind: .free, now: now())
        record.folderID = folderID
        context.insert(record)
        save()
        return record
    }

    /// A copy of a note with `text` (trimmed; empty creates nothing): a new free note in the same folder, not pinned. The
    /// pictures and files the text refers to are copied for the new note and the references are rewritten, so the copy keeps
    /// them when the original is deleted for good. Without an attachment store the text stays as it is. A private, trashed or
    /// unknown note is not copied.
    @discardableResult
    func duplicate(_ id: UUID, text: String) -> NoteRecord? {
        guard let original = note(id: id), original.deletedAt == nil, original.kind == .free else { return nil }
        if let folderID = original.folderID, folder(id: folderID)?.role?.isPrivate == true { return nil }
        guard let copy = create(text: text, kind: .free, folderID: original.folderID) else { return nil }
        guard let attachments else { return copy }
        let referenced = MarkdownText.attachmentReferences(in: copy.text)
        let mapping = attachments.duplicate(ids: referenced, to: copy.id)
        guard !mapping.isEmpty else { return copy }
        copy.text = MarkdownText.replacingAttachmentIDs(in: copy.text, with: mapping)
        save()
        return copy
    }

    /// Replaces the text; the change date moves only when the text differs.
    func updateText(_ id: UUID, text: String) {
        guard let record = note(id: id), record.text != text else { return }
        record.text = text
        record.updatedAt = now()
        // The autosave of a free note or a Bible Study note changes nothing the habits read; a journal entry does (written or not).
        save(affectsHabits: record.kind != .free && record.kind != .bibleStudy)
    }

    /// Pinning is not a change of the note: the change date stays.
    func setPinned(_ id: UUID, _ pinned: Bool) {
        guard let record = note(id: id), record.isPinned != pinned else { return }
        record.isPinned = pinned
        save()
    }

    /// Sets or clears the lock mark. Locking and unlocking are not changes of the note: the change date stays. Locking ends the
    /// assistant's note session (`onNoteLocked`), so what it read of the note earlier is forgotten; unlocking does not.
    func setLocked(_ ids: [UUID], _ locked: Bool) {
        let wanted = Set(ids)
        var changed = false
        for record in all() where wanted.contains(record.id) && record.isLocked != locked {
            record.isLocked = locked
            changed = true
        }
        guard changed else { return }
        save()
        onLockMarksChanged?()
        if locked { onNoteLocked?() }
    }

    func markProcessed(_ id: UUID, at date: Date) {
        guard let record = note(id: id) else { return }
        record.processedAt = date
        save()
    }

    /// Removes a note for good, without a trip through "Zuletzt gelöscht".
    func delete(_ id: UUID) {
        guard let record = note(id: id) else { return }
        attachments?.deleteAll(of: id)
        context.delete(record)
        save()
    }

    /// Removes a note that holds only whitespace, e.g. when the editor closes. A journal entry that still holds only
    /// the unfilled template counts as empty too.
    func deleteIfEmpty(_ id: UUID) {
        guard let record = note(id: id) else { return }
        let isBlank = record.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // A journal entry or a recipe that is still the untouched template counts as empty.
        guard isBlank || (record.kind == .journal && JournalTemplate.isOnlyTemplate(record.text))
                || (record.kind == .free && RecipeNote.isOnlyTemplate(record.text)) else { return }
        attachments?.deleteAll(of: id)
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
        for record in all() where record.deletedAt != nil {
            attachments?.deleteAll(of: record.id)
            context.delete(record)
        }
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
        for record in expired {
            attachments?.deleteAll(of: record.id)
            context.delete(record)
        }
        save()
        return expired.count
    }

    // MARK: Folders

    func folders() -> [NoteFolderRecord] {
        _ = revision
        return foldersCache.fetch(in: context)
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

    /// Moves the user's own notes into a folder (`nil` is "Notizen"). Thought notes stay where they are. A folder that
    /// is filled by the routines only (Tagesstart, Tagesabschluss, Dream Log) refuses the move.
    func move(noteIDs: [UUID], to folderID: UUID?) {
        if let folderID {
            guard let target = folder(id: folderID), target.role?.acceptsOwnNotes ?? true else { return }
        }
        let wanted = Set(noteIDs)
        var changed = false
        for record in all() where wanted.contains(record.id) && record.deletedAt == nil && record.kind == .free
            && record.folderID != folderID {
            record.folderID = folderID
            changed = true
        }
        if changed { save() }
    }

    /// Every note including the trash; internal for the extensions of this store.
    func allNotes() -> [NoteRecord] { all() }

    private func all() -> [NoteRecord] {
        _ = revision
        return notesCache.fetch(in: context)
    }

    /// Saves and bumps `revision`; internal so the routines' extension can write through the same path. `affectsHabits: false` leaves
    /// `habitRevision` alone (see there).
    /// A failed write is logged and leaves both revisions alone: nothing was persisted, so views must not announce a change.
    func save(affectsHabits: Bool = true) {
        do {
            try context.save()
        } catch {
            logger.error("Saving notes failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        invalidateCaches()
        revision += 1
        if affectsHabits { habitRevision += 1 }
    }
}
