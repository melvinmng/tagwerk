import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct RecurringEffortStoreTests {
    let container: ModelContainer
    let store: RecurringEffortStore
    let today = PlanDay(year: 2026, month: 11, day: 18)
    let yesterday = PlanDay(year: 2026, month: 11, day: 17)
    let karteikarten = TaskID(source: .reminders, rawValue: "karteikarten")
    let k = TaskID(source: .reminders, rawValue: "k")

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        store = RecurringEffortStore(context: container.mainContext)
    }

    @Test func setForAll_fromToday_keepsPastValue() {
        store.setForAll(180, task: karteikarten, from: PlanDay(year: 2026, month: 11, day: 1))
        store.setForAll(120, task: karteikarten, from: today)
        #expect(store.minutes(for: karteikarten, on: yesterday) == 180)
        #expect(store.minutes(for: karteikarten, on: today) == 120)
        #expect(store.minutes(for: karteikarten, on: PlanDay(year: 2026, month: 10, day: 31)) == nil)
    }

    @Test func setForDay_overridesOnlyThatDay() {
        store.setForAll(180, task: k, from: PlanDay(year: 2026, month: 11, day: 1))
        store.setForDay(60, task: k, day: PlanDay(year: 2026, month: 11, day: 21))
        #expect(store.minutes(for: k, on: PlanDay(year: 2026, month: 11, day: 21)) == 60)
        #expect(store.minutes(for: k, on: PlanDay(year: 2026, month: 11, day: 22)) == 180)
    }

    @Test func override_zero_removesEffort() {
        store.setForAll(180, task: k, from: PlanDay(year: 2026, month: 11, day: 1))
        store.setForDay(0, task: k, day: today)
        #expect(store.minutes(for: k, on: today) == 0)
    }

    /// A reminder and a local task with the same raw identifier keep separate efforts.
    @Test func sources_doNotShareEfforts() {
        let local = TaskID(source: .local, rawValue: "k")
        store.setForAll(180, task: k, from: today)
        store.setForAll(30, task: local, from: today)
        store.markDone(task: local, day: today)
        #expect(store.minutes(for: k, on: today) == 180)
        #expect(store.minutes(for: local, on: today) == 30)
        #expect(store.isDone(task: k, day: today) == false)
        #expect(store.isDone(task: local, day: today))
    }

    @Test func reservedMinutes_sumsOccurringSeries() {
        let calendar = testCalendar()
        let daily = RecurringSeries(id: TaskID(source: .reminders, rawValue: "daily"), title: "Karteikarten",
                                    recurrence: Recurrence(rule: .daily(interval: 1), start: PlanDay(year: 2026, month: 11, day: 16),
                                                           end: nil, count: nil))
        let weekly = RecurringSeries(id: TaskID(source: .local, rawValue: "weekly"), title: "Wochenrückblick",
                                     recurrence: Recurrence(rule: .weekly(interval: 1, weekdays: [6]),
                                                            start: PlanDay(year: 2026, month: 11, day: 20), end: nil, count: nil))
        store.setForAll(180, task: daily.id, from: PlanDay(year: 2026, month: 11, day: 1))
        store.setForAll(60, task: weekly.id, from: PlanDay(year: 2026, month: 11, day: 1))
        #expect(store.reservedMinutes(on: today, series: [daily, weekly], calendar: calendar) == 180)
        #expect(store.reservedMinutes(on: PlanDay(year: 2026, month: 11, day: 20), series: [daily, weekly], calendar: calendar) == 240)
    }
}

/// Entries written before local tasks could repeat are keyed by the bare reminder ID; they stay readable.
@MainActor
struct RecurringEffortMigrationTests {
    let container: ModelContainer
    let today = PlanDay(year: 2026, month: 11, day: 18)
    let reminder = TaskID(source: .reminders, rawValue: "x-apple-reminder-1")

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        let context = container.mainContext
        context.insert(RecurringEffortValue(reminderID: "x-apple-reminder-1", from: PlanDay(year: 2026, month: 11, day: 1), minutes: 90))
        context.insert(RecurringEffortOverride(reminderID: "x-apple-reminder-1", day: today, minutes: 45))
        context.insert(RecurringOccurrenceDone(reminderID: "x-apple-reminder-1", day: today))
        try context.save()
    }

    @Test func legacyEntries_areReadThroughTheTaskKey() {
        let store = RecurringEffortStore(context: container.mainContext)
        #expect(store.minutes(for: reminder, on: today) == 45)
        #expect(store.minutes(for: reminder, on: today.adding(days: 1, calendar: testCalendar())) == 90)
        #expect(store.isDone(task: reminder, day: today))
    }

    @Test func legacyEntries_areRewrittenOnce() throws {
        _ = RecurringEffortStore(context: container.mainContext)
        _ = RecurringEffortStore(context: container.mainContext)
        let context = container.mainContext
        #expect(try context.fetch(FetchDescriptor<RecurringEffortValue>()).map(\.reminderID) == [reminder.key])
        #expect(try context.fetch(FetchDescriptor<RecurringEffortOverride>()).map(\.reminderID) == [reminder.key])
        #expect(try context.fetch(FetchDescriptor<RecurringOccurrenceDone>()).map(\.key) == ["\(reminder.key)|2026-11-18"])
    }

    /// Changing the effort after the migration replaces the old value instead of adding a second one.
    @Test func legacyEntries_canBeChanged() {
        let store = RecurringEffortStore(context: container.mainContext)
        store.setForDay(20, task: reminder, day: today)
        store.unmarkDone(task: reminder, day: today)
        #expect(store.minutes(for: reminder, on: today) == 20)
        #expect(store.isDone(task: reminder, day: today) == false)
    }
}
