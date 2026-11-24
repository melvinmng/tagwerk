import Foundation
import Testing
@testable import TagwerkCore

struct ReminderDuplicatesTests {
    let calendar = makeCalendar()
    let german = Locale(identifier: "de_DE")
    let english = Locale(identifier: "en_US")
    /// The deadline: Monday 23 Nov. 2026, 18:00.
    var anchor: Date { instant(2026, 11, 23, 18, 0, in: calendar) }

    @Test func find_sameMinute_isADuplicate() {
        let found = ReminderDuplicates.find(tagwerk: [.before(amount: 1, unit: .days), .before(amount: 2, unit: .hours)],
                                            calendarAlarms: [.before(amount: 24, unit: .hours)], anchor: anchor, isAllDay: false,
                                            calendar: calendar)
        #expect(found.count == 1)
        #expect(found.first?.offset == .before(amount: 1, unit: .days))
        #expect(found.first?.fire == instant(2026, 11, 22, 18, 0, in: calendar))
    }

    @Test func find_differentKindsOfOffset_withTheSameMoment_areADuplicate() {
        let found = ReminderDuplicates.find(tagwerk: [.at(daysBefore: 1, hour: 18, minute: 0)],
                                            calendarAlarms: [.before(amount: 1, unit: .days)], anchor: anchor, isAllDay: false,
                                            calendar: calendar)
        #expect(found.count == 1)
    }

    @Test func find_differentTimes_isEmpty() {
        let found = ReminderDuplicates.find(tagwerk: [.before(amount: 1, unit: .days)], calendarAlarms: [.before(amount: 2, unit: .days)],
                                            anchor: anchor, isAllDay: false, calendar: calendar)
        #expect(found.isEmpty)
    }

    @Test func find_allDay_usesTheDayStart() {
        // An all-day entry counts from the start of its day: "1 day before" is 22 Nov. 00:00 for both lists.
        let found = ReminderDuplicates.find(tagwerk: [.before(amount: 1, unit: .days)], calendarAlarms: [.before(amount: 1, unit: .days)],
                                            anchor: instant(2026, 11, 23, 0, 0, in: calendar), isAllDay: true, calendar: calendar)
        #expect(found.first?.fire == instant(2026, 11, 22, 0, 0, in: calendar))
    }

    @Test func notice_namesTheReminderAndTheDay() {
        let duplicate = (offset: ReminderOffset.before(amount: 1, unit: .days), fire: instant(2026, 11, 22, 18, 0, in: calendar))
        #expect(ReminderDuplicates.notice(duplicate, subject: .deadline, isAllDay: false, locale: german, calendar: calendar)
                == "Doppelt: „1 Tag vorher“ – Tagwerk und Kalender erinnern beide am So. 22. Nov.")
        let text = ReminderDuplicates.notice(duplicate, subject: .deadline, isAllDay: false, locale: english, calendar: calendar)
        #expect(text == "Duplicate: “1 day before” – Tagwerk and the calendar both remind you on Sun, Nov 22")
    }

    @Test func reachText_namesTheDay_inBothLanguages() {
        let day = PlanDay(year: 2026, month: 11, day: 27)
        #expect(ReminderReachText.onlyThis(day, calendar: calendar, locale: german) == "Nur am 27. Nov.")
        #expect(ReminderReachText.fromThis(day, calendar: calendar, locale: german) == "Ab 27. Nov. für alle folgenden")
        #expect(ReminderReachText.onlyThis(day, calendar: calendar, locale: english) == "Only on Nov 27")
        #expect(ReminderReachText.fromThis(day, calendar: calendar, locale: english) == "From Nov 27 on, for all following")
    }

    @Test func reachText_title_namesTheSubject() {
        #expect(ReminderReachText.title(.deadline, locale: german) == "Erinnerungen für welche Termine ändern?")
        #expect(ReminderReachText.title(.task, locale: german) == "Erinnerungen für welche Fälligkeiten ändern?")
        #expect(ReminderReachText.title(.event, locale: english) == "Change reminders for which events?")
        #expect(ReminderReachText.title(.task, locale: english) == "Change reminders for which due dates?")
    }
}
