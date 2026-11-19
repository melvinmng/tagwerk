import Foundation
import Testing
@testable import TagwerkCore

struct ReminderTextTests {
    let calendar = makeCalendar()
    let german = Locale(identifier: "de_DE")
    let english = Locale(identifier: "en_US")

    private func german(_ offset: ReminderOffset) -> String { ReminderText.describe(offset, locale: german, calendar: calendar) }
    private func english(_ offset: ReminderOffset) -> String { ReminderText.describe(offset, locale: english, calendar: calendar).replacingOccurrences(of: "\u{202F}", with: " ") }

    @Test func describe_german() {
        #expect(german(.before(amount: 0, unit: .minutes)) == "Zum Zeitpunkt")
        #expect(german(.before(amount: 1, unit: .minutes)) == "1 Minute vorher")
        #expect(german(.before(amount: 15, unit: .minutes)) == "15 Minuten vorher")
        #expect(german(.before(amount: 1, unit: .hours)) == "1 Stunde vorher")
        #expect(german(.before(amount: 2, unit: .hours)) == "2 Stunden vorher")
        #expect(german(.before(amount: 1, unit: .days)) == "1 Tag vorher")
        #expect(german(.before(amount: 3, unit: .days)) == "3 Tage vorher")
        #expect(german(.before(amount: 1, unit: .weeks)) == "1 Woche vorher")
        #expect(german(.before(amount: 2, unit: .weeks)) == "2 Wochen vorher")
        #expect(german(.at(daysBefore: 0, hour: 9, minute: 0)) == "Am selben Tag um 09:00")
        #expect(german(.at(daysBefore: 1, hour: 18, minute: 0)) == "1 Tag vorher um 18:00")
        #expect(german(.at(daysBefore: 2, hour: 18, minute: 30)) == "2 Tage vorher um 18:30")
    }

    @Test func describe_english() {
        #expect(english(.before(amount: 0, unit: .minutes)) == "At time of event")
        #expect(english(.before(amount: 1, unit: .minutes)) == "1 minute before")
        #expect(english(.before(amount: 15, unit: .minutes)) == "15 minutes before")
        #expect(english(.before(amount: 2, unit: .weeks)) == "2 weeks before")
        #expect(english(.at(daysBefore: 0, hour: 9, minute: 0)) == "On the same day at 9:00 AM")
        #expect(english(.at(daysBefore: 1, hour: 18, minute: 0)) == "1 day before at 6:00 PM")
        #expect(english(.at(daysBefore: 3, hour: 18, minute: 0)) == "3 days before at 6:00 PM")
    }

    @Test func describe_absolute_usesTheCalendarTimeZone() {
        let text = ReminderText.describe(.absolute(instant(2026, 11, 21, 9, 5, in: calendar)), locale: german, calendar: calendar)
        #expect(text.contains("21.11.2026"))
        #expect(text == "21.11.2026, 09:05")
    }

    @Test func summary_countsTheRest() {
        let list: [ReminderOffset] = [.before(amount: 2, unit: .weeks), .before(amount: 1, unit: .days), .before(amount: 1, unit: .hours)]
        #expect(ReminderText.summary([], locale: german, calendar: calendar) == "Keine")
        #expect(ReminderText.summary([], locale: english, calendar: calendar) == "None")
        #expect(ReminderText.summary([list[0]], locale: german, calendar: calendar) == "2 Wochen vorher")
        #expect(ReminderText.summary(list, locale: german, calendar: calendar) == "2 Wochen vorher + 2 weitere")
        #expect(ReminderText.summary(list, locale: english, calendar: calendar) == "2 weeks before + 2 more")
    }
}
