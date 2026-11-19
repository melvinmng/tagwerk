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
        case all
        /// Morning and evening notes.
        case thoughts
        /// The user's own notes.
        case own
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

    /// Pinned notes first, then by last change, newest first.
    func notes(_ filter: Filter = .all) -> [NoteRecord] {
        all().filter { note in
            switch filter {
            case .all: true
            case .thoughts: note.kind != .free
            case .own: note.kind == .free
            }
        }
        .sorted { first, second in
            if first.isPinned != second.isPinned { return first.isPinned }
            return first.updatedAt > second.updatedAt
        }
    }

    func note(id: UUID) -> NoteRecord? {
        all().first { $0.id == id }
    }

    /// The thought note of a kind and day, if there is one.
    func note(kind: NoteKind, dayKey: String) -> NoteRecord? {
        all().first { $0.kind == kind && $0.dayKey == dayKey }
    }

    var hasThoughts: Bool { all().contains { $0.kind != .free } }

    var count: Int { all().count }

    /// The note changed last.
    var latest: NoteRecord? { all().max { $0.updatedAt < $1.updatedAt } }

    // MARK: Writing

    /// Creates a note from trimmed text; empty text creates nothing. A morning or evening note exists once
    /// per day: a second one for the same kind and day replaces the text of the first.
    @discardableResult
    func create(text: String, kind: NoteKind = .free, dayKey: String? = nil, wasDictated: Bool = false) -> NoteRecord? {
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

    private func all() -> [NoteRecord] {
        _ = revision
        return (try? context.fetch(FetchDescriptor<NoteRecord>())) ?? []
    }

    private func save() {
        try? context.save()
        revision += 1
    }
}
