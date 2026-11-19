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
                "Notizen liegen nur auf diesem iPhone. An ChatGPT geht eine Gedanken-Notiz nur, wenn du bei ihr auf „Vorschläge holen“ tippst.")
    }
}
