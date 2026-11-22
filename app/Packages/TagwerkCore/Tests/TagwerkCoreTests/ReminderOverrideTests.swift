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

    // MARK: Mark in the task row (plan g1, ER4b)

    private func task(source: TaskSource = .local, due: DueDate? = DueDate(year: 2026, month: 11, day: 27, hour: 12)) -> TaskItem {
        TaskItem(id: TaskID(source: source, rawValue: "t1"), title: "Bericht", notes: nil, due: due, priority: nil,
                 estimateMinutes: nil, isCompleted: false, container: TaskContainer(id: "l", name: "Liste", colorHex: nil),
                 url: nil, version: "1", editableFields: [])
    }

    private func overrides(for task: TaskItem, _ offsets: [ReminderOffset], storage: ReminderOverride.Storage = .tagwerk)
        -> [String: [ReminderOverride]] {
        let itemKey = ReminderOverride.key(task: task.id)
        return [itemKey: [ReminderOverride(itemKey: itemKey, scope: .always, storage: storage, offsets: offsets)]]
    }

    @Test func mark_default_isNil() {
        #expect(ReminderMark.of(task: task(), overrides: [:]) == nil)
    }

    @Test func mark_ownList_countsIt() {
        let item = task()
        let own = overrides(for: item, [.before(amount: 1, unit: .days), .before(amount: 2, unit: .hours), .before(amount: 1, unit: .weeks)])
        #expect(ReminderMark.of(task: item, overrides: own) == .custom(count: 3))
    }

    @Test func mark_emptyOwnList_isNone() {
        let item = task()
        #expect(ReminderMark.of(task: item, overrides: overrides(for: item, [])) == ReminderMark.none)
    }

    @Test func mark_withoutDue_isNil() {
        let item = task(due: nil)
        #expect(ReminderMark.of(task: item, overrides: overrides(for: item, [.before(amount: 1, unit: .days)])) == nil)
    }

    @Test func mark_appleReminderWithOwnAlarms_counts() {
        let item = task(source: .reminders)
        let own = overrides(for: item, [.before(amount: 15, unit: .minutes)], storage: .eventKit)
        #expect(ReminderMark.of(task: item, overrides: own) == .custom(count: 1))
    }

    @Test func mark_ownListEqualToTheDefault_isNil() {
        let item = task()
        var defaults = ReminderDefaults()
        defaults.set([.before(amount: 1, unit: .days)], for: .localTask, isAllDay: false)
        let same = overrides(for: item, [.before(amount: 24, unit: .hours)])
        #expect(ReminderMark.of(task: item, overrides: same, defaults: defaults) == nil)
        let other = overrides(for: item, [.before(amount: 1, unit: .weeks)])
        #expect(ReminderMark.of(task: item, overrides: other, defaults: defaults) == .custom(count: 1))
    }

    @Test func mark_onlyThisDueDate_endsWithTheDueDate() {
        let item = task()
        let itemKey = ReminderOverride.key(task: item.id)
        let onlyThis = [itemKey: [ReminderOverride(itemKey: itemKey, scope: .onlyDue(item.due!), offsets: [])]]
        #expect(ReminderMark.of(task: item, overrides: onlyThis) == ReminderMark.none)
        var moved = item
        moved.due = DueDate(year: 2026, month: 12, day: 4, hour: 12)
        #expect(ReminderMark.of(task: moved, overrides: onlyThis) == nil)
    }
}
