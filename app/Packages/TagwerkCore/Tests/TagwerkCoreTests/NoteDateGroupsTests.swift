import Foundation
import Testing
@testable import TagwerkCore

struct NoteDateGroupsTests {
    private func calendar(_ zone: String = "Europe/Berlin") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func group_today() {
        let calendar = calendar()
        let now = date(2026, 11, 19, 10, calendar: calendar)
        #expect(NoteDateGroups.group(of: date(2026, 11, 19, 0, 1, calendar: calendar), isPinned: false, now: now, calendar: calendar) == .today)
        #expect(NoteDateGroups.group(of: date(2026, 11, 19, 23, 59, calendar: calendar), isPinned: false, now: now, calendar: calendar) == .today)
        // A date after now (clock skew, a note from another device) is not pushed into a month group.
        #expect(NoteDateGroups.group(of: date(2026, 11, 21, calendar: calendar), isPinned: false, now: now, calendar: calendar) == .today)
    }

    @Test func group_yesterdayIsLastSevenDays() {
        let calendar = calendar()
        let now = date(2026, 11, 19, 10, calendar: calendar)
        #expect(NoteDateGroups.group(of: date(2026, 11, 18, 23, 59, calendar: calendar), isPinned: false, now: now, calendar: calendar) == .lastSevenDays)
        #expect(NoteDateGroups.group(of: date(2026, 11, 12, 0, 0, calendar: calendar), isPinned: false, now: now, calendar: calendar) == .lastSevenDays)
    }

    @Test func group_eightDaysAgoIsMonth() {
        let calendar = calendar()
        let now = date(2026, 11, 19, 10, calendar: calendar)
        #expect(NoteDateGroups.group(of: date(2026, 11, 11, 23, 59, calendar: calendar), isPinned: false, now: now, calendar: calendar)
            == .month(year: 2026, month: 11))
        #expect(NoteDateGroups.group(of: date(2026, 10, 3, calendar: calendar), isPinned: false, now: now, calendar: calendar)
            == .month(year: 2026, month: 10))
    }

    @Test func group_pinnedWins() {
        let calendar = calendar()
        let now = date(2026, 11, 19, 10, calendar: calendar)
        #expect(NoteDateGroups.group(of: now, isPinned: true, now: now, calendar: calendar) == .pinned)
        #expect(NoteDateGroups.group(of: date(2020, 1, 1, calendar: calendar), isPinned: true, now: now, calendar: calendar) == .pinned)
    }

    @Test func group_summerTimeDay() {
        // 2026-03-29 is the day the clocks go forward in Germany (23 hours long): the day count must not be off by one.
        let calendar = calendar()
        let now = date(2026, 3, 29, 23, 30, calendar: calendar)
        #expect(NoteDateGroups.group(of: date(2026, 3, 29, 0, 30, calendar: calendar), isPinned: false, now: now, calendar: calendar) == .today)
        #expect(NoteDateGroups.group(of: date(2026, 3, 28, 23, 30, calendar: calendar), isPinned: false, now: now, calendar: calendar) == .lastSevenDays)
        let next = date(2026, 4, 5, 10, calendar: calendar)
        #expect(NoteDateGroups.group(of: date(2026, 3, 29, 23, 30, calendar: calendar), isPinned: false, now: next, calendar: calendar) == .lastSevenDays)
        #expect(NoteDateGroups.group(of: date(2026, 3, 28, 23, 30, calendar: calendar), isPinned: false, now: next, calendar: calendar)
            == .month(year: 2026, month: 3))
    }

    @Test func group_usesTheMonthOfTheCalendarTimeZone() {
        // 2026-10-31 23:30 UTC is already November in Berlin.
        let utc = calendar("UTC")
        let berlin = calendar("Europe/Berlin")
        let instant = date(2026, 10, 31, 23, 30, calendar: utc)
        let now = date(2027, 3, 1, calendar: berlin)
        #expect(NoteDateGroups.group(of: instant, isPinned: false, now: now, calendar: utc) == .month(year: 2026, month: 10))
        #expect(NoteDateGroups.group(of: instant, isPinned: false, now: now, calendar: berlin) == .month(year: 2026, month: 11))
    }

    @Test func grouped_keepsInputOrderInsideGroup() {
        let calendar = calendar()
        let now = date(2026, 11, 19, 10, calendar: calendar)
        let items: [(id: Int, date: Date, isPinned: Bool)] = [
            (1, date(2026, 5, 1, calendar: calendar), true),
            (2, date(2026, 11, 19, 9, calendar: calendar), false),
            (3, date(2026, 11, 19, 8, calendar: calendar), false),
            (4, date(2026, 11, 15, calendar: calendar), false),
            (5, date(2026, 10, 20, calendar: calendar), false),
            (6, date(2026, 10, 2, calendar: calendar), false)
        ]
        let groups = NoteDateGroups.grouped(items, now: now, calendar: calendar)
        #expect(groups.map(\.group) == [.pinned, .today, .lastSevenDays, .month(year: 2026, month: 10)])
        #expect(groups.map(\.ids) == [[1], [2, 3], [4], [5, 6]])
    }

    @Test func grouped_ascendingInputListsOldGroupsFirst() {
        let calendar = calendar()
        let now = date(2026, 11, 19, 10, calendar: calendar)
        let items: [(id: Int, date: Date, isPinned: Bool)] = [
            (1, date(2026, 10, 2, calendar: calendar), false),
            (2, date(2026, 11, 15, calendar: calendar), false),
            (3, date(2026, 11, 19, 8, calendar: calendar), false)
        ]
        #expect(NoteDateGroups.grouped(items, now: now, calendar: calendar).map(\.group)
            == [.month(year: 2026, month: 10), .lastSevenDays, .today])
    }

    @Test func grouped_yearChange() {
        let calendar = calendar()
        let now = date(2027, 1, 20, 10, calendar: calendar)
        let items: [(id: Int, date: Date, isPinned: Bool)] = [
            (1, date(2026, 12, 10, calendar: calendar), false),
            (2, date(2026, 12, 1, calendar: calendar), false),
            (3, date(2026, 1, 5, calendar: calendar), false)
        ]
        let groups = NoteDateGroups.grouped(items, now: now, calendar: calendar)
        #expect(groups.map(\.group) == [.month(year: 2026, month: 12), .month(year: 2026, month: 1)])
        #expect(groups.map(\.ids) == [[1, 2], [3]])
    }

    @Test func grouped_emptyInputGivesNoGroups() {
        let calendar = calendar()
        let none: [(id: Int, date: Date, isPinned: Bool)] = []
        #expect(NoteDateGroups.grouped(none, now: .now, calendar: calendar).isEmpty)
    }
}
