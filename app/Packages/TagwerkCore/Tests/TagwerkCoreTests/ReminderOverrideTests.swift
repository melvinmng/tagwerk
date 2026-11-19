import Foundation
import Testing
@testable import TagwerkCore

struct ReminderOverrideTests {
    let key = "deadline:series"
    let defaults: [ReminderOffset] = [.before(amount: 2, unit: .hours)]
    let day = PlanDay(year: 2026, month: 11, day: 20)

    private func resolve(_ overrides: [ReminderOverride], occurrenceID: String? = nil, day: PlanDay? = nil, due: DueDate? = nil,
                         storage: Bool = false) -> ResolvedReminders {
        ReminderOverrideResolution.resolve(itemKey: key, occurrenceID: occurrenceID, day: day, due: due, isAllDay: false,
                                           overrides: [key: overrides], defaults: defaults)
    }

    private func override(_ scope: ReminderOverride.Scope, days: Int, storage: ReminderOverride.Storage = .tagwerk) -> ReminderOverride {
        ReminderOverride(itemKey: key, scope: scope, storage: storage, offsets: [.before(amount: days, unit: .days)])
    }

    @Test func noOverride_usesDefaults() {
        let result = ReminderOverrideResolution.resolve(itemKey: key, isAllDay: false, overrides: [:], defaults: defaults)
        #expect(result.offsets == defaults)
        #expect(result.storage == .tagwerk)
        #expect(!result.isCustom)
    }

    @Test func always_replacesTheDefault_evenWithAnEmptyList() {
        let result = resolve([ReminderOverride(itemKey: key, scope: .always, offsets: [])])
        #expect(result.offsets.isEmpty)
        #expect(result.isCustom)
    }

    @Test func onlyDue_appliesWhileDueUnchanged_thenFallsBack() {
        let due = DueDate(year: 2026, month: 11, day: 20, hour: 10)
        let list = [override(.onlyDue(due), days: 3)]
        #expect(resolve(list, due: due).offsets == [.before(amount: 3, unit: .days)])
        let next = DueDate(year: 2026, month: 11, day: 27, hour: 10)
        #expect(resolve(list, due: next).offsets == defaults)
        #expect(resolve(list, due: nil).offsets == defaults)
    }

    @Test func occurrence_beatsSeries() {
        let list = [override(.seriesFrom(day), days: 2), override(.occurrence("occ-2"), days: 5)]
        #expect(resolve(list, occurrenceID: "occ-2", day: day).offsets == [.before(amount: 5, unit: .days)])
        #expect(resolve(list, occurrenceID: "occ-3", day: day.adding(days: 7, calendar: makeCalendar())).offsets
                == [.before(amount: 2, unit: .days)])
    }

    @Test func seriesFrom_appliesFromItsDayOn_notBefore() {
        let calendar = makeCalendar()
        let list = [override(.seriesFrom(day), days: 2)]
        #expect(resolve(list, day: day.adding(days: -7, calendar: calendar)).offsets == defaults)
        #expect(resolve(list, day: day).offsets == [.before(amount: 2, unit: .days)])
        #expect(resolve(list, day: day.adding(days: 14, calendar: calendar)).offsets == [.before(amount: 2, unit: .days)])
        #expect(resolve(list, day: nil).offsets == defaults)
    }

    @Test func laterSeriesFrom_winsOverEarlier() {
        let calendar = makeCalendar()
        let later = day.adding(days: 14, calendar: calendar)
        let list = [override(.seriesFrom(later), days: 4), override(.seriesFrom(day), days: 2)]
        #expect(resolve(list, day: day.adding(days: 7, calendar: calendar)).offsets == [.before(amount: 2, unit: .days)])
        #expect(resolve(list, day: later).offsets == [.before(amount: 4, unit: .days)])
    }

    @Test func eventKitStorage_isReported() {
        let result = resolve([override(.always, days: 1, storage: .eventKit)])
        #expect(result.storage == .eventKit)
        #expect(result.isCustom)
    }

    @Test func overrideOffsets_areNormalizedForAllDay() {
        let list = [ReminderOverride(itemKey: key, scope: .always, offsets: [.before(amount: 30, unit: .minutes), .before(amount: 1, unit: .days)])]
        let result = ReminderOverrideResolution.resolve(itemKey: key, isAllDay: true, overrides: [key: list], defaults: [])
        #expect(result.offsets == [.before(amount: 1, unit: .days)])
    }

    @Test func keys_areStable() {
        #expect(ReminderOverride.key(task: TaskID(source: .github, rawValue: "o/r#4")) == "task:github:o/r#4")
        #expect(ReminderOverride.key(deadlineSeries: "abc") == "deadline:abc")
    }
}
