import Foundation
import Testing
@testable import TagwerkCore

struct RecurrencePresetTests {
    let calendar = makeCalendar()
    /// Thursday.
    let start = PlanDay(year: 2026, month: 11, day: 19)

    @Test func weekdays_isMondayToFriday() {
        #expect(RecurrencePreset.weekdays.rule(for: start, calendar: calendar) == .weekly(interval: 1, weekdays: [2, 3, 4, 5, 6]))
        #expect(RecurrencePreset.weekend.rule(for: start, calendar: calendar) == .weekly(interval: 1, weekdays: [7, 1]))
    }

    @Test func biweekly_usesWeekdayOfStart() {
        #expect(RecurrencePreset.biweekly.rule(for: start, calendar: calendar) == .weekly(interval: 2, weekdays: [5]))
        #expect(RecurrencePreset.weekly.rule(for: start, calendar: calendar) == .weekly(interval: 1, weekdays: [5]))
        #expect(RecurrencePreset.monthly.rule(for: start, calendar: calendar) == .monthly(interval: 1, day: 19))
        #expect(RecurrencePreset.yearly.rule(for: start, calendar: calendar) == .yearly(interval: 1))
        #expect(RecurrencePreset.daily.rule(for: start, calendar: calendar) == .daily(interval: 1))
    }

    @Test func matching_findsEveryPresetFromItsRule() {
        for preset in RecurrencePreset.allCases {
            #expect(RecurrencePreset.matching(preset.rule(for: start, calendar: calendar), start: start, calendar: calendar) == preset)
        }
    }

    @Test func matching_weeklyWithoutDaysMeansWeekdayOfStart() {
        #expect(RecurrencePreset.matching(.weekly(interval: 2, weekdays: []), start: start, calendar: calendar) == .biweekly)
    }

    @Test func matching_returnsNilForCustomRule() {
        #expect(RecurrencePreset.matching(.weekly(interval: 2, weekdays: [2, 5]), start: start, calendar: calendar) == nil)
        #expect(RecurrencePreset.matching(.daily(interval: 3), start: start, calendar: calendar) == nil)
        #expect(RecurrencePreset.matching(.monthly(interval: 1, day: 3), start: start, calendar: calendar) == nil)
        #expect(RecurrencePreset.matching(.monthlyWeekday(interval: 1, ordinal: 3, weekday: 5), start: start, calendar: calendar) == nil)
        #expect(RecurrencePreset.matching(.unsupported, start: start, calendar: calendar) == nil)
    }
}
