import Foundation
import Testing
@testable import TagwerkCore

struct RoutineFolderEntriesTests {
    private func day(_ number: Int, month: Int = 11) -> PlanDay { PlanDay(year: 2026, month: month, day: number) }

    @Test func merge_dayWithNoteAndGratitude_isOneNoteEntry() {
        let entries = RoutineFolderEntries.merge(notes: [(id: 1, day: day(18))], gratitudeDays: [day(18)])
        #expect(entries == [.note(id: 1, day: day(18))])
    }

    @Test func merge_gratitudeOnlyDay_isListed() {
        let entries = RoutineFolderEntries.merge(notes: [(id: 1, day: day(18))], gratitudeDays: [day(18), day(19)])
        #expect(entries == [.gratitudeOnly(day: day(19)), .note(id: 1, day: day(18))])
    }

    @Test func merge_sortsDaysDescending() {
        let entries = RoutineFolderEntries.merge(notes: [(id: 1, day: day(10)), (id: 2, day: day(20))],
                                                 gratitudeDays: [day(15), day(25, month: 10)])
        #expect(entries == [.note(id: 2, day: day(20)), .gratitudeOnly(day: day(15)), .note(id: 1, day: day(10)),
                            .gratitudeOnly(day: day(25, month: 10))])
    }

    @Test func merge_noteWithoutDayGoesLast() {
        let entries = RoutineFolderEntries.merge(notes: [(id: 1, day: nil), (id: 2, day: day(10)), (id: 3, day: nil)],
                                                 gratitudeDays: [day(5)])
        #expect(entries == [.note(id: 2, day: day(10)), .gratitudeOnly(day: day(5)), .note(id: 1, day: nil), .note(id: 3, day: nil)])
    }

    @Test func merge_trashedNoteDay_isGratitudeOnly() {
        // The caller passes live notes only: the day of a note in the trash has none, so its gratitude shows as an entry.
        let entries: [RoutineFolderEntry<Int>] = RoutineFolderEntries.merge(notes: [], gratitudeDays: [day(18)])
        #expect(entries == [.gratitudeOnly(day: day(18))])
    }

    @Test func merge_sameDayKeepsInputOrder() {
        let entries = RoutineFolderEntries.merge(notes: [(id: 7, day: day(18)), (id: 3, day: day(18))], gratitudeDays: [])
        #expect(entries == [.note(id: 7, day: day(18)), .note(id: 3, day: day(18))])
    }

    @Test func merge_withoutAnything_isEmpty() {
        let entries: [RoutineFolderEntry<Int>] = RoutineFolderEntries.merge(notes: [], gratitudeDays: [])
        #expect(entries.isEmpty)
    }

    @Test func count_addsGratitudeOnlyDays() {
        #expect(RoutineFolderEntries.count(noteDays: [day(18), day(19), nil], gratitudeDays: [day(18), day(20), day(21)]) == 5)
        #expect(RoutineFolderEntries.count(noteDays: [], gratitudeDays: []) == 0)
    }
}
