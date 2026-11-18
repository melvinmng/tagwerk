import Foundation
import Testing
@testable import TagwerkCore

/// One case per row of the plain-text table in the mockup (RK3), in German and English.
struct RecurrenceTextTests {
    let german = Locale(identifier: "de_DE")
    let english = Locale(identifier: "en_US")
    let mondayFirst = makeCalendar()
    /// Wednesday, the start of every series below.
    let start = PlanDay(year: 2026, month: 11, day: 18)

    private func text(_ rule: RecurrenceRule, end: PlanDay? = nil, count: Int? = nil, locale: Locale,
                      calendar: Calendar? = nil) -> String {
        RecurrenceText.summary(Recurrence(rule: rule, start: start, end: end, count: count),
                               locale: locale, calendar: calendar ?? mondayFirst)
    }

    private func sundayFirst() -> Calendar {
        var calendar = makeCalendar()
        calendar.firstWeekday = 1
        return calendar
    }

    @Test func daily() {
        #expect(text(.daily(interval: 1), locale: german) == "Jeden Tag")
        #expect(text(.daily(interval: 1), locale: english) == "Every day")
        #expect(text(.daily(interval: 3), locale: german) == "Alle 3 Tage")
        #expect(text(.daily(interval: 3), locale: english) == "Every 3 days")
    }

    @Test func weekdays_mondayToFriday() {
        let rule = RecurrenceRule.weekly(interval: 1, weekdays: [2, 3, 4, 5, 6])
        #expect(text(rule, locale: german) == "Jeden Werktag (Mo bis Fr)")
        #expect(text(rule, locale: english) == "Every weekday (Mon to Fri)")
        #expect(text(rule, locale: german, calendar: sundayFirst()) == "Jeden Werktag (Mo bis Fr)")
    }

    @Test func weekend() {
        let rule = RecurrenceRule.weekly(interval: 1, weekdays: [7, 1])
        #expect(text(rule, locale: german) == "Jedes Wochenende (Sa und So)")
        #expect(text(rule, locale: english) == "Every weekend (Sat and Sun)")
    }

    @Test func weekly_listsDaysInWeekOrder() {
        let rule = RecurrenceRule.weekly(interval: 2, weekdays: [5, 2])
        #expect(text(rule, locale: german) == "Alle 2 Wochen am Mo und Do")
        #expect(text(rule, locale: english) == "Every 2 weeks on Mon and Thu")
        #expect(text(.weekly(interval: 1, weekdays: [5]), locale: german) == "Jede Woche am Do")
        #expect(text(.weekly(interval: 1, weekdays: [5]), locale: english) == "Every week on Thu")
        #expect(text(.weekly(interval: 1, weekdays: [6, 2, 4]), locale: german) == "Jede Woche am Mo, Mi und Fr")
        #expect(text(.weekly(interval: 1, weekdays: [6, 2, 4]), locale: english) == "Every week on Mon, Wed, and Fri")
    }

    @Test func weekly_withoutDays_usesWeekdayOfStart() {
        #expect(text(.weekly(interval: 1, weekdays: []), locale: german) == "Jede Woche am Mi")
    }

    @Test func weekly_followsFirstWeekdayOfCalendar() {
        let rule = RecurrenceRule.weekly(interval: 2, weekdays: [1, 2])
        #expect(text(rule, locale: german) == "Alle 2 Wochen am Mo und So")
        #expect(text(rule, locale: german, calendar: sundayFirst()) == "Alle 2 Wochen am So und Mo")
        #expect(text(rule, locale: english, calendar: sundayFirst()) == "Every 2 weeks on Sun and Mon")
    }

    @Test func monthly_dayOfMonth() {
        #expect(text(.monthly(interval: 1, day: 18), locale: german) == "Jeden Monat am 18.")
        #expect(text(.monthly(interval: 1, day: 18), locale: english) == "Every month on day 18")
        #expect(text(.monthly(interval: 2, day: 18), locale: german) == "Alle 2 Monate am 18.")
        #expect(text(.monthly(interval: 2, day: 18), locale: english) == "Every 2 months on day 18")
    }

    @Test func monthly_nthWeekday() {
        let rule = RecurrenceRule.monthlyWeekday(interval: 1, ordinal: 3, weekday: 4)
        #expect(text(rule, locale: german) == "Jeden Monat am 3. Mittwoch")
        #expect(text(rule, locale: english) == "Every month on the 3rd Wednesday")
        #expect(text(.monthlyWeekday(interval: 2, ordinal: 1, weekday: 2), locale: german) == "Alle 2 Monate am 1. Montag")
        #expect(text(.monthlyWeekday(interval: 2, ordinal: 1, weekday: 2), locale: english) == "Every 2 months on the 1st Monday")
    }

    @Test func yearly() {
        #expect(text(.yearly(interval: 1), locale: german) == "Jedes Jahr am 18. November")
        #expect(text(.yearly(interval: 1), locale: english) == "Every year on November 18")
        #expect(text(.yearly(interval: 2), locale: german) == "Alle 2 Jahre am 18. November")
        #expect(text(.yearly(interval: 2), locale: english) == "Every 2 years on November 18")
    }

    @Test func endDate() {
        let end = PlanDay(year: 2027, month: 3, day: 31)
        #expect(text(.daily(interval: 1), end: end, locale: german) == "Jeden Tag, bis 31. März 2027")
        #expect(text(.daily(interval: 1), end: end, locale: english) == "Every day, until March 31, 2027")
    }

    @Test func count() {
        let rule = RecurrenceRule.monthlyWeekday(interval: 1, ordinal: 3, weekday: 4)
        #expect(text(rule, count: 12, locale: german) == "Jeden Monat am 3. Mittwoch, 12 Mal")
        #expect(text(rule, count: 12, locale: english) == "Every month on the 3rd Wednesday, 12 times")
        #expect(text(.daily(interval: 1), count: 1, locale: german) == "Jeden Tag, 1 Mal")
        #expect(text(.daily(interval: 1), count: 1, locale: english) == "Every day, once")
    }

    @Test func unsupported() {
        #expect(text(.unsupported, locale: german) == "Eigene Regel aus Erinnerungen")
        #expect(text(.unsupported, locale: english) == "Custom rule from Reminders")
    }
}
