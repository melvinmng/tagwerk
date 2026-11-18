import EventKit
import Foundation
import Testing
import TagwerkCore
@testable import RemindersKit

/// Mapping between Tagwerk's recurrence and `EKRecurrenceRule`, without an event store.
/// These tests only show that a rule keeps the values it was given; how EventKit expands a rule
/// into dates is not covered here and stays on the device checklist (plan §3).
struct RecurrenceMappingTests {
    let calendar = makeBerlinCalendar()
    /// Wednesday, the third Wednesday of November 2026.
    let due = DueDate(year: 2026, month: 11, day: 18)
    var start: PlanDay { PlanDay(due) }

    private func roundTrip(_ recurrence: Recurrence) throws -> Recurrence {
        let rule = try #require(RecurrenceMapping.ekRule(for: recurrence, calendar: calendar))
        return RecurrenceMapping.recurrence(from: rule, due: due, calendar: calendar)
    }

    private func rule(_ frequency: EKRecurrenceFrequency, interval: Int = 1, weekdays: [EKRecurrenceDayOfWeek]? = nil,
                      monthDays: [Int]? = nil, months: [Int]? = nil, positions: [Int]? = nil) -> EKRecurrenceRule {
        EKRecurrenceRule(recurrenceWith: frequency, interval: interval, daysOfTheWeek: weekdays,
                         daysOfTheMonth: monthDays?.map { NSNumber(value: $0) },
                         monthsOfTheYear: months?.map { NSNumber(value: $0) }, weeksOfTheYear: nil, daysOfTheYear: nil,
                         setPositions: positions?.map { NSNumber(value: $0) }, end: nil)
    }

    /// Stage 0, item 1: a rule can be created and read back without access to the store.
    @Test func ekRecurrenceRule_worksWithoutStore() {
        let made = rule(.monthly, interval: 2, weekdays: [EKRecurrenceDayOfWeek(.wednesday, weekNumber: 3)])
        #expect(made.frequency == .monthly)
        #expect(made.interval == 2)
        #expect(made.daysOfTheWeek?.first?.dayOfTheWeek == .wednesday)
        #expect(made.daysOfTheWeek?.first?.weekNumber == 3)
    }

    @Test func roundTrip_everyRule() throws {
        let rules: [RecurrenceRule] = [
            .daily(interval: 1), .daily(interval: 3),
            .weekly(interval: 1, weekdays: [4]), .weekly(interval: 2, weekdays: [2, 5]),
            .weekly(interval: 1, weekdays: [2, 3, 4, 5, 6]), .weekly(interval: 1, weekdays: [7, 1]),
            .monthly(interval: 1, day: 18), .monthly(interval: 3, day: 31),
            .monthlyWeekday(interval: 1, ordinal: 3, weekday: 4), .monthlyWeekday(interval: 2, ordinal: 1, weekday: 2),
            .yearly(interval: 1), .yearly(interval: 2),
        ]
        for rule in rules {
            let recurrence = Recurrence(rule: rule, start: start, end: nil, count: nil)
            #expect(try roundTrip(recurrence) == recurrence, "\(rule)")
        }
    }

    @Test func roundTrip_weeklyWithoutDays_staysWithoutDays() throws {
        let recurrence = Recurrence(rule: .weekly(interval: 1, weekdays: []), start: start, end: nil, count: nil)
        #expect(try roundTrip(recurrence) == recurrence)
    }

    @Test func roundTrip_count() throws {
        let recurrence = Recurrence(rule: .monthlyWeekday(interval: 1, ordinal: 3, weekday: 4), start: start, end: nil, count: 12)
        #expect(try roundTrip(recurrence) == recurrence)
    }

    @Test(arguments: ["Europe/Berlin", "America/Los_Angeles", "Asia/Tokyo", "Pacific/Auckland"])
    func roundTrip_endDate_keepsCalendarDay(zone: String) throws {
        let calendar = makeBerlinCalendar(zone)
        // Ordinary days and both daylight-saving changes in Europe and the US.
        let ends = [PlanDay(year: 2027, month: 3, day: 31), PlanDay(year: 2027, month: 3, day: 28),
                    PlanDay(year: 2027, month: 10, day: 31), PlanDay(year: 2027, month: 3, day: 14),
                    PlanDay(year: 2027, month: 11, day: 7)]
        for end in ends {
            let recurrence = Recurrence(rule: .daily(interval: 1), start: start, end: end, count: nil)
            let ekRule = try #require(RecurrenceMapping.ekRule(for: recurrence, calendar: calendar))
            #expect(RecurrenceMapping.recurrence(from: ekRule, due: due, calendar: calendar) == recurrence, "\(zone) \(end)")
        }
    }

    /// A timed occurrence late on the end day still lies before the written end.
    @Test func endDate_includesTheWholeEndDay() {
        let end = PlanDay(year: 2027, month: 3, day: 31)
        let written = RecurrenceMapping.endDate(for: end, calendar: calendar)
        let lateOccurrence = calendar.date(from: DateComponents(year: 2027, month: 3, day: 31, hour: 23, minute: 30))!
        #expect(written >= lateOccurrence)
        #expect(PlanDay(date: written, calendar: calendar) == end)
    }

    @Test func reads_monthlyWeekday_bothForms() {
        let withWeekNumber = rule(.monthly, weekdays: [EKRecurrenceDayOfWeek(.wednesday, weekNumber: 3)])
        let withPosition = rule(.monthly, weekdays: [EKRecurrenceDayOfWeek(.wednesday)], positions: [3])
        for form in [withWeekNumber, withPosition] {
            #expect(RecurrenceMapping.recurrence(from: form, due: due, calendar: calendar).rule
                    == .monthlyWeekday(interval: 1, ordinal: 3, weekday: 4))
        }
    }

    @Test func reads_lastOrFifthWeekday_asUnsupported() {
        let last = rule(.monthly, weekdays: [EKRecurrenceDayOfWeek(.friday, weekNumber: -1)])
        let fifth = rule(.monthly, weekdays: [EKRecurrenceDayOfWeek(.friday)], positions: [5])
        let twoDays = rule(.monthly, weekdays: [EKRecurrenceDayOfWeek(.monday, weekNumber: 1), EKRecurrenceDayOfWeek(.friday, weekNumber: 1)])
        for form in [last, fifth, twoDays] {
            #expect(RecurrenceMapping.recurrence(from: form, due: due, calendar: calendar).rule == .unsupported)
        }
    }

    @Test func reads_multipleMonthDays_asUnsupported() {
        #expect(RecurrenceMapping.recurrence(from: rule(.monthly, monthDays: [1, 15]), due: due, calendar: calendar).rule
                == .unsupported)
    }

    /// "Last day of the month" (-1) is outside Tagwerk's model and used to become a day that never matches.
    @Test func reads_lastDayOfMonth_asUnsupported() {
        #expect(RecurrenceMapping.recurrence(from: rule(.monthly, monthDays: [-1]), due: due, calendar: calendar).rule
                == .unsupported)
    }

    @Test func reads_monthlyWithoutDay_usesDueDay() {
        #expect(RecurrenceMapping.recurrence(from: rule(.monthly), due: due, calendar: calendar).rule
                == .monthly(interval: 1, day: 18))
    }

    @Test func reads_yearlyWithOtherMonth_asUnsupported() {
        #expect(RecurrenceMapping.recurrence(from: rule(.yearly, months: [3]), due: due, calendar: calendar).rule == .unsupported)
        #expect(RecurrenceMapping.recurrence(from: rule(.yearly, monthDays: [2]), due: due, calendar: calendar).rule == .unsupported)
        #expect(RecurrenceMapping.recurrence(from: rule(.yearly, months: [11]), due: due, calendar: calendar).rule
                == .yearly(interval: 1))
        let nthWeekday = rule(.yearly, weekdays: [EKRecurrenceDayOfWeek(.thursday, weekNumber: 4)], months: [11])
        #expect(RecurrenceMapping.recurrence(from: nthWeekday, due: due, calendar: calendar).rule == .unsupported)
    }

    @Test func reads_dailyWithWeekdays_asUnsupported() {
        let weekdays = rule(.daily, weekdays: [EKRecurrenceDayOfWeek(.monday), EKRecurrenceDayOfWeek(.friday)])
        #expect(RecurrenceMapping.recurrence(from: weekdays, due: due, calendar: calendar).rule == .unsupported)
    }

    @Test func reads_startFromDueDate() {
        #expect(RecurrenceMapping.recurrence(from: rule(.daily), due: due, calendar: calendar).start == start)
    }

    @Test func unsupported_isNeverWritten() {
        let unsupported = Recurrence(rule: .unsupported, start: start, end: nil, count: nil)
        #expect(RecurrenceMapping.ekRule(for: unsupported, calendar: calendar) == nil)
        let invalid = Recurrence(rule: .daily(interval: 0), start: start, end: nil, count: nil)
        #expect(RecurrenceMapping.ekRule(for: invalid, calendar: calendar) == nil)
    }
    /// Device test: an hourly rule from the Reminders app was shown as daily. EventKit has no hourly frequency in its
    /// public API, so the rule's RRULE text decides.
    @Test func subDailyRuleText_isDetected() {
        #expect(RecurrenceMapping.isSubDaily(ruleText: "EKRecurrenceRule <0x1> RRULE FREQ=HOURLY;INTERVAL=1"))
        #expect(RecurrenceMapping.isSubDaily(ruleText: "RRULE FREQ=MINUTELY;INTERVAL=30"))
        #expect(!RecurrenceMapping.isSubDaily(ruleText: "EKRecurrenceRule <0x1> RRULE FREQ=DAILY;INTERVAL=1"))
    }
}

func makeBerlinCalendar(_ identifier: String = "Europe/Berlin") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.firstWeekday = 2
    calendar.timeZone = TimeZone(identifier: identifier)!
    return calendar

}
