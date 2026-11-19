import Foundation
import Testing
@testable import TagwerkCore

struct QuietHoursRoutineTests {
    /// Starts at bedtime 23:00 and ends at 07:00.
    let night = QuietHours(startMinutes: 23 * 60, endMinutes: 7 * 60)

    private func item(_ title: String, order: Int, offset: Int?) -> ChecklistItem {
        ChecklistItem(title: title, order: order, offsetMinutes: offset)
    }

    private func conflict(_ window: QuietHours?, items: [ChecklistItem] = [], bedtime: Int = 23 * 60, evening: Bool = true,
                          morning: Bool = false, morningMinutes: Int = 450) -> QuietHoursConflict {
        RoutineSchedule.quietHoursConflict(window, items: items, bedtimeMinutes: bedtime, eveningEnabled: evening,
                                           morningEnabled: morning, morningMinutes: morningMinutes)
    }

    @Test func noWindow_noConflict() {
        #expect(conflict(nil, items: [item("Bett", order: 0, offset: 0)], morning: true, morningMinutes: 60).isEmpty)
    }

    @Test func eveningPointsBeforeBedtime_areOutsideTheWindow() {
        let items = [item("Aufräumen", order: 0, offset: 90), item("Handy", order: 1, offset: 60), item("Bett", order: 2, offset: 30)]
        #expect(conflict(night, items: items).isEmpty)
    }

    @Test func pointAtBedtime_sitsOnTheInclusiveStart() {
        let result = conflict(night, items: [item("Schlafen", order: 0, offset: 0)])
        #expect(result == QuietHoursConflict(evening: true, morning: false))
    }

    @Test func pointAtBedtime_withEarlierStart_isCovered() {
        let early = QuietHours(startMinutes: 22 * 60, endMinutes: 7 * 60)
        #expect(conflict(early, items: [item("Handy", order: 0, offset: 30)]).evening)
    }

    @Test func pointsWithoutReminder_andSwitchedOffEvening_doNotCount() {
        #expect(conflict(night, items: [item("Ohne", order: 0, offset: nil)]).isEmpty)
        #expect(conflict(night, items: [item("Schlafen", order: 0, offset: 0)], evening: false).isEmpty)
    }

    @Test func onlyTheFourReminders_thatActuallyRemind_count() {
        // The fifth reminder point never reminds, so its position does not matter.
        var items = (0..<4).map { item("P\($0)", order: $0, offset: 60) }
        items.append(item("Fünfter", order: 4, offset: 0))
        #expect(conflict(night, items: items).isEmpty)
    }

    @Test func morningReminder_insideTheWindow_conflicts() {
        #expect(conflict(night, morning: true, morningMinutes: 6 * 60 + 30) == QuietHoursConflict(evening: false, morning: true))
        #expect(conflict(night, morning: true, morningMinutes: 7 * 60).isEmpty)
        #expect(conflict(night, morning: false, morningMinutes: 6 * 60).isEmpty)
    }
}
