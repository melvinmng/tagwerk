import Foundation
import Testing
@testable import TagwerkCore

/// Rules of the weight entry, the merge of own and foreign measurements and the day value. All dates come from an explicit
/// calendar, so the tests do not depend on the time zone of the machine.
struct WeightTests {
    private static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.firstWeekday = 2
        return calendar
    }

    private let berlin = WeightTests.calendar("Europe/Berlin")

    private func date(_ day: Int, _ hour: Int = 7, _ minute: Int = 0, month: Int = 11, calendar: Calendar? = nil) -> Date {
        (calendar ?? berlin).date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func own(_ day: Int, _ hour: Int = 7, _ minute: Int = 0, kg: Double, id: UUID = UUID()) -> WeightMeasurement {
        WeightMeasurement(id: id, date: date(day, hour, minute), kilograms: kg)
    }

    private func foreign(_ day: Int, _ hour: Int = 7, _ minute: Int = 0, kg: Double, source: String = "Waage", id: UUID = UUID()) -> WeightMeasurement {
        WeightMeasurement(id: id, date: date(day, hour, minute), kilograms: kg, sourceName: source)
    }

    // MARK: Entry limits

    @Test func clamped_roundsToTenthsAndHoldsLimits() {
        #expect(WeightRules.clamped(81.44) == 81.4)
        #expect(WeightRules.clamped(81.46) == 81.5)
        #expect(WeightRules.clamped(5) == 20)
        #expect(WeightRules.clamped(900) == 400)
    }

    @Test func clampedBodyFat_nilStaysUnknown() {
        #expect(WeightRules.clampedBodyFat(nil) == nil)
        #expect(WeightRules.clampedBodyFat(22.26) == 22.3)
        #expect(WeightRules.clampedBodyFat(0) == WeightRules.minimumBodyFatPercent)
    }

    // MARK: Day value

    @Test func dayValue_earliestOfDay() {
        let days = WeightRules.dayValues([own(20, 21, 30, kg: 82.9), own(20, 6, 45, kg: 82.1), own(20, 12, 0, kg: 82.5)], calendar: berlin)
        #expect(days[PlanDay(year: 2026, month: 11, day: 20)]?.kilograms == 82.1)
        #expect(days.count == 1)
    }

    @Test func dayValue_ownAndForeignCompeteByTime() {
        let days = WeightRules.dayValues([own(20, 8, 0, kg: 82.0), foreign(20, 6, 30, kg: 82.6)], calendar: berlin)
        #expect(days[PlanDay(year: 2026, month: 11, day: 20)]?.kilograms == 82.6)
    }

    @Test func dayValue_assignsLateAndEarlyMomentsToTheirCalendarDay() {
        // 23:30 belongs to the 20th, 00:30 to the 21st, in every time zone the calendar names.
        for zone in ["Europe/Berlin", "UTC", "America/Los_Angeles"] {
            let calendar = WeightTests.calendar(zone)
            let late = WeightMeasurement(id: UUID(), date: date(20, 23, 30, calendar: calendar), kilograms: 80)
            let early = WeightMeasurement(id: UUID(), date: date(21, 0, 30, calendar: calendar), kilograms: 81)
            let days = WeightRules.dayValues([late, early], calendar: calendar)
            #expect(days[PlanDay(year: 2026, month: 11, day: 20)]?.kilograms == 80, "zone \(zone)")
            #expect(days[PlanDay(year: 2026, month: 11, day: 21)]?.kilograms == 81, "zone \(zone)")
        }
    }

    @Test func dayValue_keepsBodyFatOfTheChosenMeasurement() {
        let first = WeightMeasurement(id: UUID(), date: date(20, 6), kilograms: 82, bodyFatPercent: 21.5)
        let second = WeightMeasurement(id: UUID(), date: date(20, 18), kilograms: 83, bodyFatPercent: 23)
        #expect(WeightRules.dayValues([second, first], calendar: berlin).values.first?.bodyFatPercent == 21.5)
    }

    // MARK: Merge

    @Test func merge_ownAndForeign_noDuplicates() {
        let shared = UUID()
        let mine = own(20, 7, 0, kg: 82.0)
        let echoOfMine = foreign(20, 7, 0, kg: 82.0)
        let other = foreign(19, 7, 5, kg: 82.4, id: shared)
        let sameIdAgain = foreign(19, 7, 5, kg: 82.4, id: shared)
        let merged = WeightRules.merge(own: [mine], foreign: [other, echoOfMine, sameIdAgain])
        #expect(merged.count == 2)
        #expect(merged.map(\.kilograms) == [82.4, 82.0])
        #expect(merged.last?.isOwn == true)
    }

    @Test func merge_keepsForeignThatDiffersFromOwn() {
        let merged = WeightRules.merge(own: [own(20, 7, 0, kg: 82.0)], foreign: [foreign(20, 7, 0, kg: 83.5)])
        #expect(merged.count == 2)
    }

    @Test func merge_isIndependentOfInputOrder() {
        let a = own(20, 7, 0, kg: 82.0), b = foreign(20, 7, 0, kg: 83.5), c = foreign(18, 8, 0, kg: 82.7)
        #expect(WeightRules.merge(own: [a], foreign: [b, c]) == WeightRules.merge(own: [a], foreign: [c, b]))
    }
}
