import Foundation
import GitHubKit
import SwiftUI
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct SearchTextsTests {
    let calendar = testCalendar()
    let now = testNow()   // Wed 2026-11-18 10:00

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func event(on year: Int, _ month: Int, _ day: Int, hour: Int = 9, allDay: Bool = false) -> CalendarEvent {
        let start = date(year, month, day, hour)
        return CalendarEvent(id: "e", externalID: nil, calendarID: "cal", title: "Termin", start: start,
                             end: start.addingTimeInterval(3600), isAllDay: allDay, url: nil, isBusy: true, version: "1")
    }

    private func row(more: Int, last: Date?, rhythm: SeriesRhythm?) -> EventRow {
        EventRow(event: event(on: 2026, 11, 20), moreOccurrences: more, lastOccurrence: last, rhythm: rhythm)
    }

    private func group(completed: Date?, list: String, more: Int) -> CompletedGroup {
        var item = makeTask("Aufgabe", source: .reminders)
        item.isCompleted = true
        let container = TaskContainer(id: list, name: list, colorHex: nil)
        item = TaskItem(id: item.id, title: item.title, notes: nil, due: nil, priority: nil, estimateMinutes: nil, isCompleted: true,
                        container: container, url: nil, version: "1", editableFields: [])
        return CompletedGroup(latest: CompletedTask(item: item, completedAt: completed), moreCount: more)
    }

    @Test func headersCarryCounters() {
        #expect(SearchTexts.header(.upcomingEvents, count: 3) == "Termine · 3 kommende")
        #expect(SearchTexts.header(.openTasks, count: 3) == "Aufgaben · 3 offen")
        #expect(SearchTexts.header(.completedTasks, count: 2) == "Erledigt · 2")
        #expect(SearchTexts.header(.online, count: 2) == "GitHub · online · 2 weitere")
        #expect(SearchTexts.header(.pastEvents, count: 2) == "Vergangene Termine · 2")
        #expect(SearchTexts.header(.notes, count: 1) == "Notizen · 1")
        #expect(SearchTexts.header(.shopping, count: 2) == "Einkaufsliste · 2")
        #expect(SearchTexts.header(.openTasks, count: nil) == "Aufgaben")
        #expect(SearchTexts.header(.online, count: nil) == "GitHub · online")
        #expect(SearchTexts.headerAccessibility(.upcomingEvents, count: 3) == "Termine, 3 kommende")
        #expect(SearchTexts.headerAccessibility(.shopping, count: 2) == "Einkaufsliste, 2")
        #expect(SearchTexts.headerAccessibility(.pastEvents, count: nil) == "Vergangene Termine")
    }

    @Test func footerNamesTheWindow() {
        let may2026 = date(2026, 5, 18), may2025 = date(2025, 5, 18)
        #expect(SearchTexts.footer(windowStart: may2026, isExtended: false, calendar: calendar) == "Durchsucht: 6 Monate zurück, 12 Monate voraus.")
        #expect(SearchTexts.footer(windowStart: may2025, isExtended: true, calendar: calendar) == "Durchsucht: ab Mai 2025, 12 Monate voraus.")
        #expect(SearchTexts.olderEventsRow(before: may2026, calendar: calendar) == "Ältere Termine durchsuchen · vor Mai 2026")
    }

    @Test func eventDateShowsYearOutsideTheCurrentYear() {
        #expect(SearchTexts.eventDate(event(on: 2026, 11, 27), now: now, calendar: calendar) == "Fr. 27.11.")
        // The spec says "Mo. 12.10.2025"; 12 Oct 2025 is a Sunday, so the calendar value counts.
        #expect(SearchTexts.eventDate(event(on: 2025, 10, 12), now: now, calendar: calendar) == "So. 12.10.2025")
        #expect(SearchTexts.eventTime(event(on: 2026, 11, 27, allDay: true), calendar: calendar) == "ganztägig")
        #expect(SearchTexts.eventTime(event(on: 2026, 11, 27, hour: 10), calendar: calendar) == "10:00")
    }

    @Test func agoTextOnlyWithinSevenDays() {
        #expect(SearchTexts.agoText(event(on: 2026, 11, 16), now: now, calendar: calendar) == "vor 2 Tagen")
        #expect(SearchTexts.agoText(event(on: 2026, 11, 17), now: now, calendar: calendar) == "gestern")
        #expect(SearchTexts.agoText(event(on: 2026, 11, 11), now: now, calendar: calendar) == "vor 7 Tagen")
        #expect(SearchTexts.agoText(event(on: 2026, 11, 10), now: now, calendar: calendar) == nil)
        #expect(SearchTexts.agoText(event(on: 2026, 11, 18, hour: 8), now: now, calendar: calendar) == nil)
        #expect(SearchTexts.agoText(event(on: 2026, 11, 25), now: now, calendar: calendar) == nil)
    }

    @Test func seriesTextWithAndWithoutRhythm() {
        let feb2027 = date(2027, 2, 12)
        #expect(SearchTexts.seriesText(row(more: 9, last: feb2027, rhythm: .weekly), calendar: calendar) == "↻ wöchentlich · 9 weitere bis Februar")
        #expect(SearchTexts.seriesText(row(more: 9, last: feb2027, rhythm: nil), calendar: calendar) == "↻ · 9 weitere bis Februar")
        #expect(SearchTexts.seriesText(row(more: 0, last: nil, rhythm: nil), calendar: calendar) == nil)
        #expect(SearchTexts.seriesText(row(more: 3, last: feb2027, rhythm: .biweekly), calendar: calendar) == "↻ alle 2 Wochen · 3 weitere bis Februar")
        #expect(SearchTexts.seriesText(row(more: 3, last: feb2027, rhythm: .daily), calendar: calendar) == "↻ täglich · 3 weitere bis Februar")
        #expect(SearchTexts.seriesText(row(more: 3, last: feb2027, rhythm: .monthly), calendar: calendar) == "↻ monatlich · 3 weitere bis Februar")
    }

    @Test func completedTextNamesDateListAndCounter() {
        let nov12 = date(2026, 11, 12)
        #expect(SearchTexts.completedText(group(completed: nov12, list: "To Do", more: 0), calendar: calendar) == "erledigt 12.11. · To Do")
        #expect(SearchTexts.completedText(group(completed: nov12, list: "To Do", more: 2), calendar: calendar) == "erledigt 12.11. · To Do · 2 weitere")
        #expect(SearchTexts.completedText(group(completed: nil, list: "Lokal", more: 0), calendar: calendar) == "erledigt · Lokal")
        #expect(SearchTexts.completedText(group(completed: date(2025, 3, 4), list: "To Do", more: 0), calendar: calendar, now: now)
                == "erledigt 04.03.2025 · To Do")
    }

    @Test func snippetLabelsNameTheField() {
        #expect(SearchTexts.snippetLabel(.notes) == "Notiz")
        #expect(SearchTexts.snippetLabel(.location) == "Ort")
        #expect(SearchTexts.snippetLabel(.calendar) == "Kalender")
        #expect(SearchTexts.snippetLabel(.container) == "Liste")
        #expect(SearchTexts.snippetLabel(.project) == "GitHub-Projekt")
        #expect(SearchTexts.snippetLabel(.label) == "Label")
    }

    @Test func onlineTextsNameMarkerRepositoryAndDate() {
        let issue = OnlineIssue(id: "I", number: 42, title: "Bug", repository: "octo/app", url: URL(string: "https://github.com/octo/app/issues/42")!,
                                updatedAt: date(2026, 11, 12), marker: .closed)
        #expect(SearchTexts.onlineSubtitle(issue, now: now, calendar: calendar) == "octo/app · 12.11.")
        let old = OnlineIssue(id: "I", number: 1, title: "Alt", repository: "octo/app", url: issue.url, updatedAt: date(2025, 3, 4), marker: nil)
        #expect(SearchTexts.onlineSubtitle(old, now: now, calendar: calendar) == "octo/app · 04.03.2025")
        #expect([OnlineIssueMarker.closed, .unassigned, .assignedToOthers, .noProject].map(SearchTexts.markerText)
                == ["geschlossen", "nicht zugewiesen", "anderen zugewiesen", "ohne Projekt"])
        #expect(SearchTexts.onlineError(.offline) == "Keine Verbindung zu GitHub.")
        #expect(SearchTexts.onlineError(.rateLimited) == "GitHub nimmt gerade keine Suche an. Später erneut versuchen.")
        #expect(SearchTexts.onlineError(.failed("Boom")) == "Boom")
    }

    @Test func noteSubtitleNamesKindAndDay() {
        #expect(SearchTexts.noteSubtitle(kindLabel: "Notiz", updatedAt: date(2026, 11, 12), dayKey: nil, calendar: calendar) == "Notiz · 12.11.")
        #expect(SearchTexts.noteSubtitle(kindLabel: "Tagesabschluss", updatedAt: date(2026, 11, 19), dayKey: "2026-11-18", calendar: calendar)
                == "Tagesabschluss · 18.11.")
        #expect(SearchTexts.noteSubtitle(kindLabel: "Tagesstart", updatedAt: date(2026, 11, 19), dayKey: "kaputt", calendar: calendar)
                == "Tagesstart · 19.11.")
    }

    @Test func highlightMarksOnlyTheGivenRanges() {
        let text = "Hauptstraße 5"
        let ranges = SearchText.ranges(of: "strasse", in: text)
        let attributed = SearchTexts.highlighted(text, ranges: ranges)
        #expect(String(attributed.characters) == text)
        let marked = attributed.runs.filter { $0.backgroundColor != nil }
        #expect(marked.count == 1)
        #expect(marked.allSatisfy { String(attributed[$0.range].characters) == "straße" && $0.inlinePresentationIntent == .stronglyEmphasized })
        #expect(attributed.runs.filter { $0.backgroundColor == nil }.allSatisfy { $0.inlinePresentationIntent == nil })
        #expect(SearchTexts.highlighted(text, ranges: []).runs.allSatisfy { $0.backgroundColor == nil })
    }
}
