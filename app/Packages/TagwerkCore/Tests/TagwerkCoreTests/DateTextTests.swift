import Foundation
import Testing
@testable import TagwerkCore

struct DateTextTests {
    let calendar = makeCalendar()
    let german = Locale(identifier: "de_DE")
    let english = Locale(identifier: "en_US")
    /// Saturday, 21 Nov 2026, 09:05 in Berlin.
    var moment: Date { instant(2026, 11, 21, 9, 5, in: calendar) }
    let saturday = PlanDay(year: 2026, month: 11, day: 21)

    @Test func time_followsTheLocale() {
        #expect(DateText.time(moment, calendar: calendar, locale: german) == "09:05")
        #expect(DateText.time(moment, calendar: calendar, locale: english) == "9:05\u{202F}AM")
    }

    @Test func time_ofMinutesSinceMidnight() {
        #expect(DateText.time(minutes: 9 * 60 + 5, calendar: calendar, locale: german) == "09:05")
        #expect(DateText.time(minutes: 14 * 60 + 30, calendar: calendar, locale: english) == "2:30\u{202F}PM")
    }

    @Test func shortWeekday_followsTheLocale() {
        #expect(DateText.shortWeekday(saturday, calendar: calendar, locale: german) == "Sa.")
        #expect(DateText.shortWeekday(saturday, calendar: calendar, locale: english) == "Sat")
    }

    @Test func numericDay_followsTheLocale() {
        #expect(DateText.numericDay(saturday, calendar: calendar, locale: german) == "21.11.")
        #expect(DateText.numericDay(saturday, calendar: calendar, locale: english) == "11/21")
    }

    @Test func weekdaySymbols_startOnTheFirstWeekday() {
        #expect(DateText.shortWeekdaySymbols(calendar: calendar, locale: german) == ["Mo.", "Di.", "Mi.", "Do.", "Fr.", "Sa.", "So."])
        #expect(DateText.shortWeekdaySymbols(calendar: calendar, locale: english) == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
    }
}
