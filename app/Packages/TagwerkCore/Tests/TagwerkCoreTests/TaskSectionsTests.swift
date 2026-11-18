import Foundation
import Testing
@testable import TagwerkCore

/// Reference "now": Wednesday, 2026-11-18 10:00 in Berlin. The week runs Mon 16 – Sun 22.
struct TaskSectionsTests {
    let calendar = makeCalendar()
    var now: Date { instant(2026, 11, 18, 10, 0) }

    private func sectionOf(_ due: DueDate?) -> TaskSection {
        section(for: makeItem("x", due: due), now: now, calendar: calendar)
    }

    @Test func section_dateOnlyYesterday_isOverdue() {
        #expect(sectionOf(DueDate(year: 2026, month: 11, day: 17)) == .overdue)
    }

    @Test func section_timedEarlierToday_isOverdue() {
        #expect(sectionOf(DueDate(year: 2026, month: 11, day: 18, hour: 8, minute: 0)) == .overdue)
    }

    @Test func section_timedLaterToday_isToday() {
        #expect(sectionOf(DueDate(year: 2026, month: 11, day: 18, hour: 14, minute: 0)) == .today)
    }

    @Test func section_dateOnlyToday_isToday() {
        #expect(sectionOf(DueDate(year: 2026, month: 11, day: 18)) == .today)
    }

    @Test func section_dateOnlyTomorrow_isTomorrow() {
        #expect(sectionOf(DueDate(year: 2026, month: 11, day: 19)) == .tomorrow)
    }

    @Test func section_timedTomorrow_isTomorrow() {
        #expect(sectionOf(DueDate(year: 2026, month: 11, day: 19, hour: 23, minute: 59)) == .tomorrow)
    }

    @Test func section_dayAfterTomorrow_isThisWeek() {
        #expect(sectionOf(DueDate(year: 2026, month: 11, day: 20)) == .thisWeek)
    }

    /// On Sunday, tomorrow is the Monday of the next week; it still counts as tomorrow, not as later.
    @Test func section_mondayFromSunday_isTomorrow() {
        let sunday = instant(2026, 11, 22, 10, 0)
        let item = makeItem("x", due: DueDate(year: 2026, month: 11, day: 23))
        #expect(section(for: item, now: sunday, calendar: calendar) == .tomorrow)
    }

    /// On Saturday "Diese Woche" would only hold Sunday, which is already "Morgen": next week takes its place.
    @Test func section_fromSaturday_nextWeekReplacesThisWeek() {
        let saturday = instant(2026, 11, 21, 10, 0)
        let monday = makeItem("x", due: DueDate(year: 2026, month: 11, day: 23))
        let nextSunday = makeItem("y", due: DueDate(year: 2026, month: 11, day: 29))
        let later = makeItem("z", due: DueDate(year: 2026, month: 11, day: 30))
        #expect(section(for: monday, now: saturday, calendar: calendar) == .nextWeek)
        #expect(section(for: nextSunday, now: saturday, calendar: calendar) == .nextWeek)
        #expect(section(for: later, now: saturday, calendar: calendar) == .later)
    }

    /// On Sunday tomorrow is Monday; the rest of the next week is "Nächste Woche".
    @Test func section_fromSunday_restOfNextWeek() {
        let sunday = instant(2026, 11, 22, 10, 0)
        #expect(section(for: makeItem("x", due: DueDate(year: 2026, month: 11, day: 24)), now: sunday, calendar: calendar) == .nextWeek)
        #expect(section(for: makeItem("y", due: DueDate(year: 2026, month: 11, day: 29)), now: sunday, calendar: calendar) == .nextWeek)
        #expect(section(for: makeItem("z", due: DueDate(year: 2026, month: 11, day: 30)), now: sunday, calendar: calendar) == .later)
    }

    @Test func section_fromFriday_keepsThisWeek() {
        let friday = instant(2026, 11, 20, 10, 0)
        #expect(section(for: makeItem("x", due: DueDate(year: 2026, month: 11, day: 22)), now: friday, calendar: calendar) == .thisWeek)
        #expect(section(for: makeItem("y", due: DueDate(year: 2026, month: 11, day: 23)), now: friday, calendar: calendar) == .later)
    }

    @Test func section_sundayOfCurrentWeek_isThisWeek() {
        #expect(sectionOf(DueDate(year: 2026, month: 11, day: 22, hour: 23, minute: 30)) == .thisWeek)
    }

    @Test func section_nextMonday_isLater() {
        #expect(sectionOf(DueDate(year: 2026, month: 11, day: 23)) == .later)
    }

    @Test func section_nil_isNoDate() {
        #expect(sectionOf(nil) == .noDate)
    }

    @Test func grouped_sortsByDueThenPriorityThenTitle() {
        let items = [
            makeItem("C", due: DueDate(year: 2026, month: 11, day: 21), priority: .p3),
            makeItem("B", due: DueDate(year: 2026, month: 11, day: 21), priority: .p1),
            makeItem("A", due: DueDate(year: 2026, month: 11, day: 21), priority: .p3),
            makeItem("D", due: DueDate(year: 2026, month: 11, day: 20)),
            makeItem("E", due: DueDate(year: 2026, month: 11, day: 21)),
        ]
        let groups = groupedSections(items, now: now, calendar: calendar)
        #expect(groups.count == 1)
        #expect(groups.first?.0 == .thisWeek)
        #expect(groups.first?.1.map(\.title) == ["D", "B", "A", "C", "E"])
    }

    /// Same due date and priority: Reminders, then GitHub, then local tasks, so sources do not interleave.
    @Test func grouped_sameDueAndPriority_groupsBySource() {
        let due = DueDate(year: 2026, month: 11, day: 20)
        let items = [
            makeItem("A lokal", due: due, priority: .p2, source: .local),
            makeItem("B GitHub", due: due, priority: .p2, source: .github),
            makeItem("C Erinnerung", due: due, priority: .p2, source: .reminders),
            makeItem("D GitHub", due: due, priority: .p2, source: .github),
            makeItem("E Erinnerung P1", due: due, priority: .p1, source: .local),
        ]
        let groups = groupedSections(items, now: now, calendar: calendar)
        #expect(groups.first?.1.map(\.title) == ["E Erinnerung P1", "C Erinnerung", "B GitHub", "D GitHub", "A lokal"])
    }

    @Test func grouped_omitsEmptySections() {
        let items = [
            makeItem("Überfällig", due: DueDate(year: 2026, month: 11, day: 1)),
            makeItem("Irgendwann"),
        ]
        let groups = groupedSections(items, now: now, calendar: calendar)
        #expect(groups.map(\.0) == [.overdue, .noDate])
    }

    @Test func sectionTitles_areGerman() {
        #expect(TaskSection.allCases.map(\.title) == ["Überfällig", "Heute", "Morgen", "Diese Woche", "Nächste Woche", "Später", "Ohne Datum"])
    }
}
