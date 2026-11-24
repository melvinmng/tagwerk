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
        return sessionsCache.fetch(in: context)
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

    /// The latest session of a book by the time it started, open ones included (BV3a).
    func lastSession(bookKey: String) -> BibleStudySessionRecord? {
        sessions().filter { $0.book == bookKey }.max { $0.startedAt < $1.startedAt }
    }

    /// The books of the latest sessions, each once, newest first, for the chips "Zuletzt" (BS2b).
    func recentBookKeys(limit: Int = 3) -> [String] {
        var keys: [String] = []
        for session in sessions().sorted(by: { $0.startedAt > $1.startedAt }) where !keys.contains(session.book) {
            keys.append(session.book)
            if keys.count == limit { break }
        }
        return keys
    }

    /// Where a new session in the book should begin (BS2b, BV3a): after the end of its latest session, at the start of that
    /// session while it is open, or at 1,1 without one. Notes imported from Notion have no sessions and give 1,1.
    func suggestion(for book: BibleBook) -> BibleProgress.Next {
        let last = lastSession(bookKey: book.key)
        return BibleProgress.suggestion(lastStart: last?.resolvedStart, lastEnd: last?.resolvedEnd, book: book.number)
    }

    /// Starts a session with the passage typed as free text. The text is kept as it is.
    @discardableResult
    func startSession(book: BibleBook, passage: String, dayKey: String, dateText: String, locale: Locale = .current)
        -> (note: NoteRecord, session: BibleStudySessionRecord) {
        startSession(book: book, passage: nil, freeText: passage, dayKey: dayKey, dateText: dateText, locale: locale)
    }

    /// Starts a session: opens the note of the book, appends a dated section ("19.11.2026 · 3,21–") and records the
    /// session. A passage that lies inside the verse table is stored as numbers and written as `passage.text()`; a passage
    /// outside it, or none, falls back to `freeText`, which stays free text. `dateText` is the day as shown in the title.
    @discardableResult
    func startSession(book: BibleBook, passage: BiblePassage?, freeText: String? = nil, dayKey: String, dateText: String,
                      locale: Locale = .current) -> (note: NoteRecord, session: BibleStudySessionRecord) {
        let numbers = passage.flatMap { $0.isValid(in: book.number) ? $0 : nil }
        let passageText = numbers?.text() ?? (freeText ?? passage?.text() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let note = openBibleNote(book: book, locale: locale)
        note.text = BibleStudyTemplate.appendingSession(to: note.text, dateText: dateText, passage: passageText)
        note.updatedAt = now()
        let session = BibleStudySessionRecord(dayKey: dayKey, book: book.key, passage: passageText, noteID: note.id, startedAt: now())
        if let numbers {
            session.startChapter = numbers.start.chapter
            session.startVerse = numbers.start.verse
            session.endChapter = numbers.end?.chapter ?? 0
            session.endVerse = numbers.end?.verse ?? 0
        }
        context.insert(session)
        save()
        onBibleStudyChanged?()
        return (note, session)
    }

    /// Marks the session as completed; a second call changes nothing. With `end` (BV2b) the end is stored when it is a verse
    /// of the book and not before the start, and the heading of the session section is completed ("3,21–" becomes
    /// "3,21–26") if that line is still exactly the one written at the start; a heading the reader changed stays as it is.
    /// Without `end` the session keeps the end it has.
    func completeSession(_ id: UUID, end: BibleReference? = nil) {
        guard let session = sessions().first(where: { $0.id == id }), session.completedAt == nil else { return }
        session.completedAt = now()
        if let end, let bookNumber = Int(session.book),
           BibleVerseCounts.isValid(book: bookNumber, chapter: end.chapter, verse: end.verse) {
            let start = session.resolvedStart
            if start.map({ end >= $0 }) ?? true {
                let oldPassage = session.passage
                session.endChapter = end.chapter
                session.endVerse = end.verse
                if let start { completeHeading(of: session, oldPassage: oldPassage, passage: BiblePassage(start: start, end: end)) }
            }
        }
        save()
        onBibleStudyChanged?()
    }

    private func completeHeading(of session: BibleStudySessionRecord, oldPassage: String, passage: BiblePassage) {
        let newPassage = passage.text()
        guard newPassage != oldPassage else { return }
        session.passage = newPassage
        guard let day = PlanDay(dayKey: session.dayKey), let note = notes(.all).first(where: { $0.id == session.noteID }) else { return }
        let updated = BibleStudyTemplate.replacingSessionHeading(in: note.text, dateText: BibleStudyTemplate.dateText(day),
                                                                 oldPassage: oldPassage, newPassage: newPassage)
        guard updated != note.text else { return }
        note.text = updated
        note.updatedAt = now()
    }

    /// The moments the completed sessions began, for the learned reminder time (BS8).
    func completedSessionStartTimes() -> [Date] {
        sessions().filter { $0.completedAt != nil }.map(\.startedAt)
    }

    /// What the reminder says about where to go on: the book of the latest session and the verse that follows in it. `nil`
    /// without a session and for a session typed as free text, which has no verse to continue at (BS7).
    func reminderContinuation() -> (book: BibleBook, next: BibleProgress.Next)? {
        guard let last = lastSession, let book = BibleBooks.book(key: last.book), last.resolvedStart != nil else { return nil }
        return (book, suggestion(for: book))
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
