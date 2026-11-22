import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

/// Texts of the routine sheets (design group 2, strand RO).
struct RoutineSheetTextTests {
    @Test func focusHint_counts() {
        #expect(MorningSheet.focusHint(chosen: 1, maximum: 3) == "In „Planen“ setzen · 1 von 3 gewählt")
        #expect(MorningSheet.focusHint(chosen: 0, maximum: 3) == "In „Planen“ setzen · 0 von 3 gewählt")
    }
}

/// "Zeit mit Gott" (RO3).
@MainActor
struct TimeWithGodTextTests {
    private let calendar = testCalendar()
    private let locale = Locale(identifier: "de_DE")

    @Test func journalState_templateOnly_isNil() {
        #expect(TimeWithGodText.journalState(entry: nil, calendar: calendar) == nil)
        let entry = NoteRecord(text: JournalTemplate.text(locale: locale), kind: .journal, dayKey: "2026-11-18", now: testNow())
        #expect(TimeWithGodText.journalState(entry: entry, calendar: calendar) == nil)
    }

    @Test func journalState_namesTime() {
        let written = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 21, minute: 40))!
        let entry = NoteRecord(text: "Heute war ein guter Tag.", kind: .journal, dayKey: "2026-11-18", now: written)
        #expect(TimeWithGodText.journalState(entry: entry, calendar: calendar) == "Heute geschrieben · 21:40")
        #expect(TimeWithGodText.journalState(entry: entry, isToday: false, calendar: calendar) == "Geschrieben · 21:40")
    }

    @Test func bibleState_namesPassageAndDay() {
        let session = BibleStudySessionRecord(dayKey: "2026-11-17", book: "45", passage: "3,21-31", noteID: UUID(), startedAt: testNow())
        let today = PlanDay(year: 2026, month: 11, day: 18)
        #expect(TimeWithGodText.bibleState(last: session, today: today, calendar: calendar, locale: locale) == "Zuletzt: Römer 3,21-31 · gestern")
        let older = PlanDay(year: 2026, month: 11, day: 20)
        #expect(TimeWithGodText.bibleState(last: session, today: older, calendar: calendar, locale: locale) == "Zuletzt: Römer 3,21-31 · Dienstag")
        #expect(TimeWithGodText.bibleState(last: nil, today: today, calendar: calendar, locale: locale) == nil)
    }

    @Test func bibleState_openSession_saysContinue() {
        let session = BibleStudySessionRecord(dayKey: "2026-11-17", book: "45", passage: "3,21-31", noteID: UUID(), startedAt: testNow())
        #expect(TimeWithGodText.bibleTitle(last: session) == "Bible Study fortsetzen")
        session.completedAt = testNow()
        #expect(TimeWithGodText.bibleTitle(last: session) == "Bible Study starten")
        #expect(TimeWithGodText.bibleTitle(last: nil) == "Bible Study starten")
    }
}

/// The rows of the evening checklist (RO4).
struct ChecklistTextTests {
    private let calendar = testCalendar()

    private func item(offset: Int?) -> ChecklistItem { ChecklistItem(title: "Helle Lichter ausmachen", order: 0, offsetMinutes: offset) }

    @Test func sheetDetail_checked_saysNoReminderToday() {
        #expect(ChecklistText.sheetDetail(item(offset: 60), isChecked: true, reminds: true) == "abgehakt, erinnert heute nicht mehr")
        #expect(ChecklistText.sheetDetail(item(offset: 60), isChecked: false, reminds: true) == nil)
        // A point that does not remind has nothing to stop, checked or not.
        #expect(ChecklistText.sheetDetail(item(offset: 60), isChecked: true, reminds: false) == nil)
        #expect(ChecklistText.sheetDetail(item(offset: nil), isChecked: true, reminds: false) == nil)
    }

    @Test func clock_followsTheBedtime() {
        #expect(ChecklistText.clock(item(offset: 60), bedtime: 1380, calendar: calendar) == "22:00")
        #expect(ChecklistText.clock(item(offset: 60), bedtime: 1410, calendar: calendar) == "22:30")
        #expect(ChecklistText.clock(item(offset: nil), bedtime: 1380, calendar: calendar) == nil)
    }

    @Test func settingsDetail_namesOffsetAndTime() {
        #expect(ChecklistText.settingsDetail(item(offset: 60), bedtime: 1380, calendar: calendar) == "60 min vorher · 22:00")
        #expect(ChecklistText.settingsDetail(item(offset: nil), bedtime: 1380, calendar: calendar) == nil)
    }
}
