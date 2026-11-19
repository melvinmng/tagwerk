import Foundation
import Testing
@testable import TagwerkCore

@Suite struct SearchEventsTests {
    private let calendar = makeCalendar()
    private let now = instant(2026, 11, 19, 10)

    private func event(_ id: String, _ title: String = "Termin", calendarID: String = "cal", start: Date,
                       hours: Double = 1, allDay: Bool = false, recurring: Bool = false, url: URL? = nil) -> CalendarEvent {
        var event = CalendarEvent(id: id, externalID: nil, calendarID: calendarID, title: title, start: start,
                                  end: start.addingTimeInterval(hours * 3600), isAllDay: allDay, url: url,
                                  isBusy: true, version: "1")
        event.isRecurring = recurring
        return event
    }

    private func occurrence(_ base: String, calendarID: String = "cal", start: Date, recurring: Bool = true) -> CalendarEvent {
        event("\(base)|\(Int(start.timeIntervalSince1970))", calendarID: calendarID, start: start, recurring: recurring)
    }

    private func series(_ base: String, from start: Date, count: Int, everyDays: Int) -> [CalendarEvent] {
        (0..<count).map { occurrence(base, start: calendar.date(byAdding: .day, value: $0 * everyDays, to: start)!) }
    }

    @Test func initialWindowIsSixMonthsBackTwelveAhead() {
        let window = SearchWindow.initial(now: now, calendar: calendar)
        #expect(window.start == instant(2026, 5, 19))
        #expect(window.end == instant(2027, 11, 19))
    }

    @Test func extensionFetchesOneYearBeforeStart() {
        let older = SearchWindow.extended(before: instant(2026, 5, 19), calendar: calendar)
        #expect(older.start == instant(2025, 5, 19))
        #expect(older.end == instant(2026, 5, 19))
    }

    @Test func extensionStopsOnEmptyYearOrAfterTenYears() {
        #expect(SearchWindow.canExtend(lastYearWasEmpty: false, start: instant(2025, 5, 19), now: now, calendar: calendar))
        #expect(!SearchWindow.canExtend(lastYearWasEmpty: true, start: instant(2025, 5, 19), now: now, calendar: calendar))
        #expect(!SearchWindow.canExtend(lastYearWasEmpty: false, start: instant(2016, 5, 19), now: now, calendar: calendar))
    }

    @Test func timeBlocksAreNotHits() {
        let link = TaskLinkURL.make(TaskID(source: .local, rawValue: "a"))
        let block = event("block", calendarID: "plan", start: now, url: link)
        let other = event("other", calendarID: "uni", start: now, url: link)
        let plain = event("plain", calendarID: "plan", start: now.addingTimeInterval(7200))
        let prepared = SearchEvents.prepare([block, other, plain], planCalendarID: "plan", merge: false)
        #expect(prepared.map(\.id) == ["other", "plain"])
    }

    @Test func duplicatesMergeOnlyWhenSwitchedOn() {
        let first = event("a", "Vorlesung", calendarID: "uni", start: now)
        let second = event("b", "Vorlesung", calendarID: "work", start: now)
        #expect(SearchEvents.prepare([first, second], planCalendarID: nil, merge: true).count == 1)
        #expect(SearchEvents.prepare([first, second], planCalendarID: nil, merge: false).count == 2)
    }

    @Test func upcomingSeriesIsOneRowWithCounter() {
        let weekly = series("abc", from: instant(2026, 11, 20, 9), count: 10, everyDays: 7)
        let rows = EventSeriesGrouping.rows(weekly, now: now, calendar: calendar)
        #expect(rows.upcoming.count == 1)
        #expect(rows.upcoming[0].event.start == instant(2026, 11, 20, 9))
        #expect(rows.upcoming[0].moreOccurrences == 9)
        #expect(rows.upcoming[0].lastOccurrence == instant(2027, 1, 22, 9))
        #expect(rows.upcoming[0].rhythm == .weekly)
        #expect(rows.past.isEmpty)
    }

    @Test func rhythmsAreDerivedFromTheGaps() {
        func rhythm(_ events: [CalendarEvent]) -> SeriesRhythm? {
            EventSeriesGrouping.rows(events, now: now, calendar: calendar).upcoming.first?.rhythm
        }
        #expect(rhythm(series("d", from: instant(2026, 11, 20, 9), count: 4, everyDays: 1)) == .daily)
        #expect(rhythm(series("b", from: instant(2026, 11, 20, 9), count: 4, everyDays: 14)) == .biweekly)
        let monthly = [instant(2026, 12, 15, 9), instant(2027, 1, 15, 9), instant(2027, 2, 15, 9)].map { occurrence("m", start: $0) }
        #expect(rhythm(monthly) == .monthly)
    }

    @Test func pastSeriesShowsOnlyLatestWithoutCounter() {
        let past = series("abc", from: instant(2026, 10, 1, 9), count: 3, everyDays: 7)
        let rows = EventSeriesGrouping.rows(past, now: now, calendar: calendar)
        #expect(rows.upcoming.isEmpty)
        #expect(rows.past.count == 1)
        #expect(rows.past[0].event.start == instant(2026, 10, 15, 9))
        #expect(rows.past[0].moreOccurrences == 0)
        #expect(rows.past[0].lastOccurrence == nil)
    }

    @Test func irregularSeriesHasNoRhythm() {
        let starts = [instant(2026, 11, 20, 9), instant(2026, 11, 27, 9), instant(2026, 12, 6, 9)]
        let rows = EventSeriesGrouping.rows(starts.map { occurrence("abc", start: $0) }, now: now, calendar: calendar)
        #expect(rows.upcoming.count == 1)
        #expect(rows.upcoming[0].moreOccurrences == 2)
        #expect(rows.upcoming[0].rhythm == nil)
    }

    @Test func detachedOccurrenceWithoutRuleStaysOwnRow() {
        var events = series("abc", from: instant(2026, 11, 20, 9), count: 2, everyDays: 7)
        events.append(occurrence("abc", start: instant(2026, 11, 25, 14), recurring: false))
        let rows = EventSeriesGrouping.rows(events, now: now, calendar: calendar)
        #expect(rows.upcoming.count == 2)
        #expect(rows.upcoming.map(\.moreOccurrences) == [1, 0])
    }

    @Test func sameBaseInOtherCalendarIsAnotherSeries() {
        let events = [occurrence("abc#uni", calendarID: "uni", start: instant(2026, 11, 20, 9)),
                      occurrence("abc#work", calendarID: "work", start: instant(2026, 11, 20, 9)),
                      occurrence("abc#uni", calendarID: "uni", start: instant(2026, 11, 27, 9))]
        let rows = EventSeriesGrouping.rows(events, now: now, calendar: calendar)
        #expect(rows.upcoming.count == 2)
        #expect(Set(rows.upcoming.map(\.moreOccurrences)) == [0, 1])
    }

    @Test func allDayEventOfTodayIsUpcomingAndEndedEventIsPast() {
        let allDay = event("day", start: instant(2026, 11, 19), hours: 24, allDay: true)
        let ended = event("ended", start: instant(2026, 11, 19, 8), hours: 1)
        let running = event("running", start: instant(2026, 11, 19, 9, 30), hours: 1)
        let rows = EventSeriesGrouping.rows([allDay, ended, running], now: now, calendar: calendar)
        #expect(rows.upcoming.map(\.id) == ["day", "running"])
        #expect(rows.past.map(\.id) == ["ended"])
    }

    @Test func orderIsNextFirstAndLatestFirst() {
        let events = [event("c", start: instant(2026, 12, 3, 9)), event("a", start: instant(2026, 11, 21, 9)),
                      event("y", start: instant(2026, 11, 2, 9)), event("z", start: instant(2026, 11, 12, 9))]
        let rows = EventSeriesGrouping.rows(events, now: now, calendar: calendar)
        #expect(rows.upcoming.map(\.id) == ["a", "c"])
        #expect(rows.past.map(\.id) == ["z", "y"])
    }
}
