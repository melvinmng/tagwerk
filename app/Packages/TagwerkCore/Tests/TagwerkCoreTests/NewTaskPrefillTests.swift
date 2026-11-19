import Foundation
import Testing
@testable import TagwerkCore

struct NewTaskPrefillTests {
    private let link = URL(string: "https://example.com/artikel")!

    @Test func notes_appendURLOnOwnLine() {
        #expect(NewTaskPrefill.notes(text: " Zum Lesen\n", url: link) == "Zum Lesen\nhttps://example.com/artikel")
        // A link that is already in the text is not repeated.
        #expect(NewTaskPrefill.notes(text: "Siehe https://example.com/artikel", url: link) == "Siehe https://example.com/artikel")
    }

    @Test func notes_withoutText_isOnlyURL() {
        #expect(NewTaskPrefill.notes(text: nil, url: link) == "https://example.com/artikel")
        #expect(NewTaskPrefill.notes(text: "  ", url: link) == "https://example.com/artikel")
    }

    @Test func notes_withoutAnything_isNil() {
        #expect(NewTaskPrefill.notes(text: nil, url: nil) == nil)
        #expect(NewTaskPrefill.notes(text: "\n", url: nil) == nil)
        #expect(NewTaskPrefill.notes(text: "Nur Text", url: nil) == "Nur Text")
    }

    @Test func sharedNotes_dropTheTitleLine() {
        #expect(NewTaskPrefill.sharedNotes(title: "Erste Zeile", text: "Erste Zeile\nzweite\ndritte") == "zweite\ndritte")
        #expect(NewTaskPrefill.sharedNotes(title: "Erste Zeile", text: "Erste Zeile") == nil)
        #expect(NewTaskPrefill.sharedNotes(title: "Anderer Titel", text: "Text") == "Text")
        #expect(NewTaskPrefill.sharedNotes(title: "x", text: nil) == nil)
    }

    @Test func due_dateOnly_setsNoTime() {
        let calendar = makeCalendar()
        let fallback = instant(2026, 11, 19, 9)
        let fields = NewTaskPrefill.dueFields(DueDate(year: 2026, month: 12, day: 1), calendar: calendar, fallback: fallback)
        #expect(fields == .init(hasDue: true, date: instant(2026, 12, 1), hasTime: false))
    }

    @Test func due_withTime_setsTime() {
        let calendar = makeCalendar()
        let fields = NewTaskPrefill.dueFields(DueDate(year: 2026, month: 12, day: 1, hour: 14, minute: 30), calendar: calendar,
                                              fallback: instant(2026, 11, 19))
        #expect(fields == .init(hasDue: true, date: instant(2026, 12, 1, 14, 30), hasTime: true))
    }

    @Test func due_nil_keepsTheFallback() {
        let fallback = instant(2026, 11, 19, 9)
        #expect(NewTaskPrefill.dueFields(nil, calendar: makeCalendar(), fallback: fallback) == .init(hasDue: false, date: fallback, hasTime: false))
    }
}
