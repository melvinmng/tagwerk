import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

#if DEBUG && targetEnvironment(simulator)
/// The UI test mode makes today and tomorrow working days, so the screens do not depend on the weekday the tests run on.
struct DemoDataWorkdayTests {
    let calendar = testCalendar()
    let workday = DayOverride.hours(WorkHours(startMinutes: 540, endMinutes: 1080))

    /// 2026-11-14 is a Saturday; the days of that week cover every weekday.
    private func day(_ dayOfMonth: Int) -> PlanDay { PlanDay(year: 2026, month: 11, day: dayOfMonth) }

    @Test(arguments: [(14, "Saturday"), (15, "Sunday"), (20, "Friday"), (18, "Wednesday")])
    func todayAndTomorrowAreWorkdays(dayOfMonth: Int, name: String) {
        let today = day(dayOfMonth)
        let overrides = DemoData.uiTestWorkdayOverrides(today: today, calendar: calendar)
        #expect(overrides[today] == workday, "today (\(name))")
        #expect(overrides[today.adding(days: 1, calendar: calendar)] == workday, "tomorrow (\(name))")
        #expect(overrides.count == 2)
    }

    @Test(arguments: [14, 15, 20, 18])
    func workHoursAreNeverNilToday(dayOfMonth: Int) {
        let today = day(dayOfMonth)
        let overrides = DemoData.uiTestWorkdayOverrides(today: today, calendar: calendar)
        for offset in 0...1 {
            let target = today.adding(days: offset, calendar: calendar)
            #expect(TagwerkCore.workHours(on: target, schedule: .standard, overrides: overrides, calendar: calendar) != nil)
        }
    }

    @Test func withoutTheOverridesAWeekendIsADayOff() {
        let saturday = day(14)
        #expect(TagwerkCore.workHours(on: saturday, schedule: .standard, overrides: [:], calendar: calendar) == nil)
    }
}
#endif
