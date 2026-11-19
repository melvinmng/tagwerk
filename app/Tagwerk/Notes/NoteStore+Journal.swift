import Foundation
import TagwerkCore

/// The journal "Tagebuch mit Gott" (#182) on top of the notes store. Writing still goes only through `NoteStore`.
extension NoteStore {
    /// The system folder of the journal, created on first use.
    @discardableResult
    func ensureJournalFolder() -> NoteFolderRecord {
        ensureSystemFolder(.journal, name: String(localized: "Tagebuch mit Gott"))
    }

    /// The live journal entry of a day, if there is one.
    func journalEntry(dayKey: String) -> NoteRecord? {
        note(kind: .journal, dayKey: dayKey)
    }

    /// The entry of a day, created from the template when there is none yet. An entry that stays untouched is removed
    /// again when the editor closes (`deleteIfEmpty`).
    @discardableResult
    func openJournalEntry(dayKey: String, locale: Locale = .current) -> NoteRecord {
        if let existing = journalEntry(dayKey: dayKey) { return existing }
        let folder = ensureJournalFolder()
        let record = NoteRecord(text: JournalTemplate.text(locale: locale), kind: .journal, dayKey: dayKey, now: now())
        record.folderID = folder.id
        context.insert(record)
        save()
        return record
    }

    /// The days that have a live journal entry.
    var journalDayKeys: Set<String> {
        Set(notes(.all).filter { $0.kind == .journal }.compactMap(\.dayKey))
    }

    /// Notion page ids of everything imported so far, including notes in the trash (a deleted import is not brought back).
    var importedSourceIDs: Set<String> {
        (notes(.all) + notes(.trash)).reduce(into: Set<String>()) { $0.formUnion(NotionImportPlanner.markerIDs($1.importSourceID)) }
    }

    struct ImportResult: Equatable {
        var created = 0
        var appended = 0
        var skipped = 0
    }

    /// Stores imported journal entries. A page that was imported before is skipped. A day without an entry gets a new one
    /// (dated like the Notion page); a day with an entry gets the text appended below a separator, nothing is overwritten,
    /// except that an entry holding only the unfilled template is replaced.
    @discardableResult
    func importJournal(_ entries: [NotionJournalEntry], locale: Locale = Locale(identifier: "de_DE")) -> ImportResult {
        var result = ImportResult()
        guard !entries.isEmpty else { return result }
        let folder = ensureJournalFolder()
        var known = importedSourceIDs
        for entry in entries {
            guard !known.contains(entry.id) else { result.skipped += 1; continue }
            if let existing = journalEntry(dayKey: entry.dayKey) {
                existing.text = JournalTemplate.isOnlyTemplate(existing.text)
                    ? entry.text : NotionImportPlanner.appending(entry.text, to: existing.text, locale: locale)
                existing.updatedAt = now()
                existing.importSourceID = Self.marker(adding: entry.id, to: existing.importSourceID)
                result.appended += 1
            } else {
                let stamp = entry.createdAt ?? now()
                let record = NoteRecord(text: entry.text, kind: .journal, dayKey: entry.dayKey, now: stamp)
                record.folderID = folder.id
                record.importSourceID = entry.id
                context.insert(record)
                result.created += 1
            }
            known.insert(entry.id)
        }
        save()
        return result
    }

    static func marker(adding id: String, to marker: String?) -> String {
        let existing = marker.map { $0.split(separator: " ").map(String.init) } ?? []
        return (existing + [id]).joined(separator: " ")
    }
}
