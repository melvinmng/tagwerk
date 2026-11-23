import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

/// Footer and entry texts of the notes list (phase 5 design §5.6).
@MainActor
struct NotesListTextTests {
    let calendar = testCalendar()
    /// Thursday, 2026-11-19 10:00.
    var now: Date { at(19, 10) }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func note(_ text: String = "Ideen Hausarbeit\nGliederung", kind: NoteKind = .free, dayKey: String? = nil,
                      dictated: Bool = false, updated: Date) -> NoteRecord {
        NoteRecord(text: text, kind: kind, dayKey: dayKey, wasDictated: dictated, now: updated)
    }

    private func footer(_ note: NoteRecord) -> String {
        NotesListView.footer(for: note, now: now, calendar: calendar)
    }

    @Test func footer_freeNote_relativeDates() {
        #expect(footer(note(updated: at(19, 8, 12))) == "heute 08:12")
        #expect(footer(note(updated: at(17, 15))) == "Dienstag")
        #expect(footer(note(updated: at(13, 9))) == "Freitag")
        #expect(footer(note(updated: at(12, 9))) == "12. Nov.")
    }

    @Test func footer_dictatedSuffix() {
        #expect(footer(note(dictated: true, updated: at(19, 8, 12))) == "heute 08:12 · diktiert")
    }

    @Test func footer_thoughts_nameOriginAndDay() {
        #expect(footer(note(kind: .evening, dayKey: "2026-11-18", updated: at(19, 7))) == "Tagesabschluss · 18.11.")
        #expect(footer(note(kind: .morning, dayKey: "2026-11-18", updated: at(19, 7))) == "Tagesstart · 18.11.")
        #expect(footer(note(kind: .morning, dayKey: nil, updated: at(17, 7))) == "Tagesstart · 17.11.")
    }

    @Test func lockedPreview_text() {
        #expect(NotesListView.lockedPreview() == "Gesperrt")
    }

    @Test func selection_lockSkipsNotesInPrivateFolders() {
        let privateFolder = UUID()
        let settings = NoteProtection.Settings(isEnabled: true, locksPrivateFolders: true, canAuthenticate: true)
        let own = note(updated: now)
        let inPrivateFolder = note(updated: now)
        inPrivateFolder.folderID = privateFolder
        let journal = note(kind: .journal, dayKey: "2026-11-18", updated: now)
        let alreadyLocked = note(updated: now)
        alreadyLocked.isLocked = true
        let ids = NotesListView.lockableIDs(of: [own, inPrivateFolder, journal, alreadyLocked], privateFolderIDs: [privateFolder], settings: settings)
        #expect(ids == [own.id])
        // With the folder switch off the note in the private folder can be locked as well.
        let relaxed = NoteProtection.Settings(isEnabled: true, locksPrivateFolders: false, canAuthenticate: true)
        #expect(Set(NotesListView.lockableIDs(of: [own, inPrivateFolder, journal], privateFolderIDs: [privateFolder], settings: relaxed))
                == [own.id, inPrivateFolder.id])
    }

    @Test func entrySubtitle_latestOrEmpty() {
        #expect(NotesListView.entrySubtitle(latest: note(updated: at(19, 8, 12)), now: now, calendar: calendar)
                == "zuletzt: „Ideen Hausarbeit“ · heute 08:12")
        #expect(NotesListView.entrySubtitle(latest: nil, now: now, calendar: calendar) == "Noch keine Notizen")
    }

    @Test func footer_thoughts_namesTheTasksDerivedFromThem() {
        let derived = note(kind: .evening, dayKey: "2026-11-18", updated: at(19, 7))
        derived.derivedActionCount = 2
        #expect(footer(derived) == "Tagesabschluss · 18.11. · 2 Aufgaben daraus")
        derived.derivedActionCount = 1
        #expect(footer(derived) == "Tagesabschluss · 18.11. · 1 Aufgabe daraus")
        derived.derivedActionCount = 0
        #expect(footer(derived) == "Tagesabschluss · 18.11.")
        let free = note(updated: at(19, 8, 12))
        free.derivedActionCount = 3
        #expect(footer(free) == "heute 08:12")
    }

    @Test func listFootnote_staysTrueOnceThoughtsCanBeSent() {
        #expect(NotesListView.listFootnote ==
                "Notizen liegen nur auf diesem iPhone. An ChatGPT geht eine Brain-Dump-Notiz nur, wenn du bei ihr auf „Vorschläge holen“ tippst, und eine Notiz nur, wenn du sie bei „Rezept hinzufügen“ als Quelle wählst.")
    }

    // MARK: Fixed folders (P5)

    @Test func routineTitle_showsTheDay() {
        let entry = note(kind: .morning, dayKey: "2026-11-19", updated: at(19, 7))
        #expect(NotesListView.routineTitle(entry, calendar: calendar) == "Do. 19. Nov.")
        // Without a day key the creation day counts.
        #expect(NotesListView.routineTitle(note(kind: .dream, dayKey: nil, updated: at(18, 7)), calendar: calendar) == "Mi. 18. Nov.")
    }

    @Test func morningPreview_listsGratitude() {
        let entry = note("Kopf leeren\nZweite Zeile\nDritte", kind: .morning, dayKey: "2026-11-19", updated: at(19, 7))
        #expect(NotesListView.gratitudeLine(["Kaffee", " ", "Sonne", "Familie"]) == "Dankbar für: Kaffee · Sonne · Familie")
        #expect(NotesListView.routinePreview(entry, gratitude: ["Kaffee", "Sonne"]) == "Dankbar für: Kaffee · Sonne\nKopf leeren")
    }

    @Test func morningPreview_withoutGratitude_isEmpty() {
        let entry = note("Kopf leeren\nZweite Zeile\nDritte", kind: .morning, dayKey: "2026-11-19", updated: at(19, 7))
        #expect(NotesListView.gratitudeLine([]).isEmpty && NotesListView.gratitudeLine(["  "]).isEmpty)
        #expect(NotesListView.routinePreview(entry, gratitude: []) == "Kopf leeren\nZweite Zeile")
        // Only morning entries show gratitude.
        let evening = note("Ruhig", kind: .evening, dayKey: "2026-11-19", updated: at(19, 7))
        #expect(NotesListView.routinePreview(evening, gratitude: ["Kaffee"]) == "Ruhig")
    }

    @Test func routineEntries_sortNewestDayFirst() {
        let older = note(kind: .morning, dayKey: "2026-11-17", updated: at(19, 9))
        let newer = note(kind: .morning, dayKey: "2026-11-18", updated: at(18, 7))
        #expect(NotesListView.byDayDescending([older, newer]).map { $0.dayKey } == ["2026-11-18", "2026-11-17"])
    }

    @Test func footer_dream_namesTheDreamLogAndDay() {
        #expect(footer(note(kind: .dream, dayKey: "2026-11-18", updated: at(19, 7))) == "Dream Log · 18.11.")
    }

    @Test func symbol_dreamLogDiffersFromEvening() {
        #expect(NotesFoldersView.symbol(for: .dreamLog) == "cloud.moon")
        #expect(NotesFoldersView.symbol(for: .dreamLog) != NotesFoldersView.symbol(for: .eveningRoutine))
        // Every role keeps its own symbol, so the sections stay readable at a glance.
        let symbols = NoteFolderRole.allCases.map { NotesFoldersView.symbol(for: $0) }
        #expect(Set(symbols).count == symbols.count)
    }

    // MARK: Sorting, groups, selection and the trash (NF3)

    @Test func trashFooter_namesDateAndFolder() {
        let trashed = note(updated: at(10, 9))
        trashed.deletedAt = at(15, 23, 30)
        #expect(NotesListView.trashFooter(for: trashed, folderName: "Notizen", now: now, calendar: calendar) == "Gelöscht am 15.11. · aus „Notizen“")
    }

    @Test func trashFooter_deletedFolderFallsBackToNotizen() {
        // The view passes "Notizen" when the folder of the note is gone; the text keeps its shape.
        let trashed = note(updated: at(10, 9))
        trashed.deletedAt = at(2, 8)
        #expect(NotesListView.trashFooter(for: trashed, folderName: "Notizen", now: now, calendar: calendar).hasSuffix("aus „Notizen“"))
        #expect(NotesListView.trashFooter(for: note(updated: at(10, 9)), folderName: "Notizen", now: now, calendar: calendar).isEmpty)
    }

    @Test func daysLeft_singularAndPlural() {
        #expect(NotesListView.daysLeftText(1) == "noch 1 Tag")
        #expect(NotesListView.daysLeftText(3) == "noch 3 Tage")
        #expect(NotesListView.daysLeftText(0) == "noch 0 Tage")
    }

    @Test func selectionTitle_counts() {
        #expect(NotesListView.selectionTitle(2) == "2 ausgewählt")
        #expect(NotesListView.selectionTitle(1) == "1 ausgewählt")
        #expect(NotesListView.selectionTitle(0) == "Notizen auswählen")
    }

    @Test func shouldPin_whenOneChosenNoteIsNotPinned() {
        let pinned = note(updated: at(10, 9)); pinned.isPinned = true
        let loose = note(updated: at(10, 9))
        #expect(NotesListView.shouldPin([pinned, loose]))
        #expect(NotesListView.shouldPin([loose]))
        #expect(!NotesListView.shouldPin([pinned]))
    }

    @Test func groupTitle_namesTheGroups() {
        let german = Locale(identifier: "de_DE")
        #expect(NotesListView.groupTitle(.pinned, calendar: calendar, locale: german) == "Angeheftet")
        #expect(NotesListView.groupTitle(.today, calendar: calendar, locale: german) == "Heute")
        #expect(NotesListView.groupTitle(.lastSevenDays, calendar: calendar, locale: german) == "Letzte 7 Tage")
        #expect(NotesListView.groupTitle(.month(year: 2026, month: 10), calendar: calendar, locale: german) == "Oktober 2026")
    }

    @Test func directionNames_followTheOrder() {
        #expect(NotesListView.directionNames(for: .modified) == ("Neueste zuerst", "Älteste zuerst"))
        #expect(NotesListView.directionNames(for: .created) == ("Neueste zuerst", "Älteste zuerst"))
        #expect(NotesListView.directionNames(for: .title) == ("A bis Z", "Z bis A"))
    }

    @Test func sections_groupByTheSortDate() {
        let pinned = note("Angeheftet", updated: at(1, 8)); pinned.isPinned = true
        let today = note("Heute", updated: at(19, 8))
        let week = note("Woche", updated: at(15, 8))
        let old = note("Alt", updated: at(3, 8))
        let notes = [pinned, today, week, old]
        let grouped = NotesListView.sections(of: notes, order: .modified, groupsByDate: true, now: now, calendar: calendar)
        #expect(grouped.map(\.group) == [.pinned, .today, .lastSevenDays, .month(year: 2026, month: 11)])
        #expect(grouped.map { $0.notes.map(\.text) } == [["Angeheftet"], ["Heute"], ["Woche"], ["Alt"]])
        // The title order and a switched-off grouping give one block.
        #expect(NotesListView.sections(of: notes, order: .title, groupsByDate: true, now: now, calendar: calendar).count == 1)
        let flat = NotesListView.sections(of: notes, order: .modified, groupsByDate: false, now: now, calendar: calendar)
        #expect(flat.count == 1 && flat[0].group == nil && flat[0].notes.count == 4)
    }

    // MARK: Gratitude in "Tagesstart" (NF4)

    @Test func listSearch_matchesGratitude() {
        let entry = note("Heute steht die Abgabe an", kind: .morning, dayKey: "2026-11-19", updated: at(19, 7))
        #expect(NotesListView.matchesSearch(entry, gratitude: ["Kaffee mit Jonas"], query: "kaffee"))
        #expect(NotesListView.matchesSearch(entry, gratitude: ["Kaffee mit Jonas"], query: "abgabe"))
        #expect(!NotesListView.matchesSearch(entry, gratitude: ["Kaffee mit Jonas"], query: "zebra"))
        #expect(NotesListView.matchesSearch(gratitude: ["Sonne"], query: "sonne"))
        #expect(!NotesListView.matchesSearch(gratitude: [], query: "sonne"))
        #expect(NotesListView.matchesSearch(gratitude: ["Sonne"], query: ""))
    }

    @Test func morningEntries_listGratitudeOnlyDaysBetweenTheNotes() {
        let first = note("Alt", kind: .morning, dayKey: "2026-11-17", updated: at(17, 7))
        let second = note("Neu", kind: .morning, dayKey: "2026-11-19", updated: at(19, 7))
        let days: [PlanDay: [String]] = [PlanDay(year: 2026, month: 11, day: 18): ["Ruhe"], PlanDay(year: 2026, month: 11, day: 19): ["Sonne"]]
        let entries = NotesListView.morningEntries(notes: [second, first], gratitudeDays: days, query: "")
        #expect(entries == [.note(id: second.id, day: PlanDay(year: 2026, month: 11, day: 19)),
                            .gratitudeOnly(day: PlanDay(year: 2026, month: 11, day: 18)),
                            .note(id: first.id, day: PlanDay(year: 2026, month: 11, day: 17))])
        // The search keeps only the days whose gratitude matches.
        #expect(NotesListView.morningEntries(notes: [], gratitudeDays: days, query: "ruhe")
            == [.gratitudeOnly(day: PlanDay(year: 2026, month: 11, day: 18))])
    }

    @Test func gratitudeOnlyFooter_namesTheOriginAndDay() {
        #expect(NotesListView.gratitudeOnlyFooter(day: PlanDay(year: 2026, month: 11, day: 19), calendar: calendar)
            == "Tagesstart · 19.11. · nur Dankbarkeit")
        #expect(NotesListView.routineTitle(day: PlanDay(year: 2026, month: 11, day: 19), calendar: calendar) == "Do. 19. Nov.")
    }

    // MARK: Markdown and attachments (P5)

    @Test func card_previewUsesPlainText() {
        let text = "# Urlaub planen\n- [ ] **Koffer** packen\n[Plan.pdf](attachment:A1B2C3D4-0000-4000-8000-000000000002)"
        let entry = note(text, updated: at(19, 8))
        #expect(NoteText.title(entry.text) == "Urlaub planen")
        #expect(NoteText.preview(entry.text) == "Koffer packen\nPlan.pdf")
    }

    @Test func cardInfo_findsTheFirstPictureAndCountsFiles() {
        let picture = NoteAttachmentRecord(noteID: nil, fileName: "Foto.jpg", typeIdentifier: "public.jpeg", byteCount: 1)
        let secondPicture = NoteAttachmentRecord(noteID: nil, fileName: "Zwei.jpg", typeIdentifier: "public.jpeg", byteCount: 1)
        let file = NoteAttachmentRecord(noteID: nil, fileName: "Plan.pdf", typeIdentifier: "com.adobe.pdf", byteCount: 1)
        let index = Dictionary(uniqueKeysWithValues: [picture, secondPicture, file].map { ($0.id, $0) })
        let text = [MarkdownText.reference(for: file.id, name: "Plan.pdf", isImage: false),
                    MarkdownText.reference(for: secondPicture.id, name: "Bild", isImage: true),
                    MarkdownText.reference(for: picture.id, name: "Bild", isImage: true),
                    MarkdownText.reference(for: UUID(), name: "Fehlt", isImage: false)].joined(separator: "\n")
        let info = NoteAttachmentStore.cardInfo(text: text, index: index)
        #expect(info.firstImageID == secondPicture.id && info.fileCount == 1)
        #expect(NoteAttachmentStore.cardInfo(text: "ohne", index: index) == NoteAttachmentStore.CardInfo())
    }
}
