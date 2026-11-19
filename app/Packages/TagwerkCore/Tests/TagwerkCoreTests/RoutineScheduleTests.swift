import Foundation
import Testing
@testable import TagwerkCore

struct RoutineScheduleTests {
    let calendar = makeCalendar()

    private func item(_ title: String, order: Int, offset: Int?) -> ChecklistItem {
        ChecklistItem(id: UUID(), title: title, order: order, offsetMinutes: offset)
    }

    @Test func anchor_wrapsAroundMidnight() {
        #expect(RoutineSchedule.anchorMinutes(bedtimeMinutes: 1380, offsetMinutes: 90) == 1290)
        #expect(RoutineSchedule.anchorMinutes(bedtimeMinutes: 30, offsetMinutes: 90) == 1380)
        #expect(RoutineSchedule.anchorMinutes(bedtimeMinutes: 1380, offsetMinutes: 0) == 1380)
    }

    @Test func routineDay_beforeFourBelongsToTheDayBefore() {
        #expect(RoutineSchedule.routineDay(at: instant(2026, 11, 19, 3, 59), calendar: calendar) == PlanDay(year: 2026, month: 11, day: 18))
        #expect(RoutineSchedule.routineDay(at: instant(2026, 11, 19, 4, 0), calendar: calendar) == PlanDay(year: 2026, month: 11, day: 19))
        #expect(RoutineSchedule.routineDay(at: instant(2026, 12, 1, 0, 10), calendar: calendar) == PlanDay(year: 2026, month: 11, day: 30))
    }

    @Test func morningCard_showsFromFourToNoon() {
        #expect(!RoutineSchedule.showsMorningCard(minutesOfDay: 239, completed: false, dismissed: false))
        #expect(RoutineSchedule.showsMorningCard(minutesOfDay: 240, completed: false, dismissed: false))
        #expect(RoutineSchedule.showsMorningCard(minutesOfDay: 719, completed: false, dismissed: false))
        #expect(!RoutineSchedule.showsMorningCard(minutesOfDay: 720, completed: false, dismissed: false))
        #expect(!RoutineSchedule.showsMorningCard(minutesOfDay: 600, completed: true, dismissed: false))
        #expect(!RoutineSchedule.showsMorningCard(minutesOfDay: 600, completed: false, dismissed: true))
    }

    @Test func eveningLine_startsAtTheEarliestAnchor() {
        let offsets = [90, 60, 30]
        #expect(!RoutineSchedule.showsEveningLine(minutesOfDay: 1289, bedtimeMinutes: 1380, offsets: offsets))
        #expect(RoutineSchedule.showsEveningLine(minutesOfDay: 1290, bedtimeMinutes: 1380, offsets: offsets))
        #expect(RoutineSchedule.showsEveningLine(minutesOfDay: 100, bedtimeMinutes: 1380, offsets: offsets))
        #expect(!RoutineSchedule.showsEveningLine(minutesOfDay: 240, bedtimeMinutes: 1380, offsets: offsets))
    }

    @Test func eveningLine_withoutAnchors_startsNinetyMinutesBeforeBedtime() {
        #expect(!RoutineSchedule.showsEveningLine(minutesOfDay: 1289, bedtimeMinutes: 1380, offsets: []))
        #expect(RoutineSchedule.showsEveningLine(minutesOfDay: 1290, bedtimeMinutes: 1380, offsets: []))
    }

    @Test func eveningLine_bedtimeAfterMidnight() {
        #expect(!RoutineSchedule.showsEveningLine(minutesOfDay: 1400, bedtimeMinutes: 60, offsets: [30]))
        #expect(!RoutineSchedule.showsEveningLine(minutesOfDay: 29, bedtimeMinutes: 60, offsets: [30]))
        #expect(RoutineSchedule.showsEveningLine(minutesOfDay: 30, bedtimeMinutes: 60, offsets: [30]))
        #expect(RoutineSchedule.showsEveningLine(minutesOfDay: 239, bedtimeMinutes: 60, offsets: [30]))
    }

    @Test func reminderItems_areTheFirstFourWithAnOffset() {
        let items = [item("A", order: 0, offset: nil), item("B", order: 1, offset: 90), item("C", order: 2, offset: 60),
                     item("D", order: 3, offset: 45), item("E", order: 4, offset: 30), item("F", order: 5, offset: 15)]
        #expect(RoutineSchedule.reminderItems(items).map(\.title) == ["B", "C", "D", "E"])
        // Order, not array position, decides.
        #expect(RoutineSchedule.reminderItems(items.reversed()).map(\.title) == ["B", "C", "D", "E"])
    }

    @Test func checkedCount_ignoresDeletedItems() {
        let first = item("A", order: 0, offset: 30), second = item("B", order: 1, offset: nil)
        var day = RoutineDayValue.empty
        day.checkedItemIDs = [first.id, UUID()]
        #expect(RoutineSchedule.checkedCount(day, items: [first, second]) == 1)
    }

    @Test func suggestedItems_areThreeWithNinetySixtyThirtyMinutes() {
        #expect(RoutineSchedule.suggestedItems.map(\.offsetMinutes) == [90, 60, 30])
        #expect(RoutineSchedule.suggestedItems.map(\.title) == ["Tagesabschluss öffnen", "Handy weglegen", "Ins Bett"])
    }

    @Test func gratitude_keepsAtMostThreeNonEmptyEntries() {
        #expect(RoutineDayValue.normalizedGratitude(["  Kaffee ", "", "Sonne", "   ", "Ruhe", "Vierte"]) == ["Kaffee", "Sonne", "Ruhe"])
    }
}
