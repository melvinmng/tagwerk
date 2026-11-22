import Foundation
import SwiftData
import TagwerkCore

/// Bible Study (#186) on top of the notes store: one note per book in a system folder, and the sessions. Writing notes still
/// goes only through `NoteStore`.
extension NoteStore {
    /// The system folder of Bible Study, created on first use.
    @discardableResult
    func ensureBibleStudyFolder() -> NoteFolderRecord {
        ensureSystemFolder(.bibleStudy, name: String(localized: "Bible Study"))
    }

    /// The live note of a book, if there is one.
    func bibleNote(bookKey: String) -> NoteRecord? {
        notes(.all).first { $0.kind == .bibleStudy && $0.bookKey == bookKey }
    }

    /// The note of a book, created from the template when there is none yet.
    @discardableResult
    func openBibleNote(book: BibleBook, locale: Locale = .current) -> NoteRecord {
        if let existing = bibleNote(bookKey: book.key) { return existing }
        let folder = ensureBibleStudyFolder()
        let record = NoteRecord(text: BibleStudyTemplate.text(book: book, locale: locale), kind: .bibleStudy, now: now())
        record.folderID = folder.id
        record.bookKey = book.key
        context.insert(record)
        save()
        return record
    }

    // MARK: Sessions

    func sessions() -> [BibleStudySessionRecord] {
        _ = revision
        return (try? context.fetch(FetchDescriptor<BibleStudySessionRecord>())) ?? []
    }

    /// The open session of a note, if there is one.
    func openSession(noteID: UUID) -> BibleStudySessionRecord? {
        sessions().filter { $0.noteID == noteID && $0.completedAt == nil }.max { $0.startedAt < $1.startedAt }
    }

    /// The latest session, open or completed.
    var lastSession: BibleStudySessionRecord? {
        sessions().max { $0.startedAt < $1.startedAt }
    }

    /// The book of the latest session, to suggest it for the next one.
    var lastBookKey: String? {
        sessions().max { $0.startedAt < $1.startedAt }?.book
    }

    /// Starts a session: opens the note of the book, appends a dated section ("19.11.2026 · 3,21-31") and records the
    /// session. `dateText` is the day as shown in the section title.
    @discardableResult
    func startSession(book: BibleBook, passage: String, dayKey: String, dateText: String, locale: Locale = .current)
        -> (note: NoteRecord, session: BibleStudySessionRecord) {
        let note = openBibleNote(book: book, locale: locale)
        note.text = BibleStudyTemplate.appendingSession(to: note.text, dateText: dateText, passage: passage)
        note.updatedAt = now()
        let session = BibleStudySessionRecord(dayKey: dayKey, book: book.key,
                                              passage: passage.trimmingCharacters(in: .whitespacesAndNewlines),
                                              noteID: note.id, startedAt: now())
        context.insert(session)
        save()
        return (note, session)
    }

    /// Marks the session as completed; a second call changes nothing.
    func completeSession(_ id: UUID) {
        guard let session = sessions().first(where: { $0.id == id }), session.completedAt == nil else { return }
        session.completedAt = now()
        save()
    }

    /// The days with at least one completed session inside `range` (by the day the session started).
    func completedSessionDays(in range: ClosedRange<PlanDay>) -> Set<PlanDay> {
        Set(sessions().filter { $0.completedAt != nil }.compactMap { PlanDay(dayKey: $0.dayKey) }.filter { range.contains($0) })
    }

    // MARK: Import

    /// Stores the Bible Study notes of a Notion export: one note per book. A page already imported is skipped; a book that
    /// has a note gets the text appended below a separator, a new book gets a note starting with the book's name. Pages
    /// whose title is not a book are counted as unmatched and left out. No sessions are created.
    @discardableResult
    func importBibleNotes(_ pages: [NotionBibleNote], locale: Locale = Locale(identifier: "de_DE")) -> BibleImportResult {
        var result = BibleImportResult()
        guard !pages.isEmpty else { return result }
        var known = importedSourceIDs
        for page in pages {
            guard !known.contains(page.id) else { result.skipped += 1; continue }
            guard let book = BibleBooks.book(matching: page.title) else { result.unmatched.append(page.title); continue }
            if let existing = bibleNote(bookKey: book.key) {
                existing.text = NotionImportPlanner.appending(page.text, to: existing.text, locale: locale)
                existing.updatedAt = now()
                existing.importSourceID = Self.marker(adding: page.id, to: existing.importSourceID)
                result.appended += 1
            } else {
                let folder = ensureBibleStudyFolder()
                let record = NoteRecord(text: book.name(locale: locale) + "\n\n" + page.text, kind: .bibleStudy, now: now())
                record.folderID = folder.id
                record.bookKey = book.key
                record.importSourceID = page.id
                context.insert(record)
                result.created += 1
            }
            known.insert(page.id)
        }
        save()
        return result
    }

    struct BibleImportResult: Equatable {
        var created = 0
        var appended = 0
        var skipped = 0
        /// Titles that are not a book of the Bible.
        var unmatched: [String] = []
    }
}
