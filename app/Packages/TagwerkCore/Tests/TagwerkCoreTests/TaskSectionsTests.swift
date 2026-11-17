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
            makeItem("C", due: DueDate(year: 2026, month: 11, day: 20), priority: .p3),
            makeItem("B", due: DueDate(year: 2026, month: 11, day: 20), priority: .p1),
            makeItem("A", due: DueDate(year: 2026, month: 11, day: 20), priority: .p3),
            makeItem("D", due: DueDate(year: 2026, month: 11, day: 19)),
            makeItem("E", due: DueDate(year: 2026, month: 11, day: 20)),
        ]
        let groups = groupedSections(items, now: now, calendar: calendar)
        #expect(groups.count == 1)
        #expect(groups.first?.0 == .thisWeek)
        #expect(groups.first?.1.map(\.title) == ["D", "B", "A", "C", "E"])
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
        #expect(TaskSection.allCases.map(\.title) == ["Überfällig", "Heute", "Diese Woche", "Später", "Ohne Datum"])
    }
}
