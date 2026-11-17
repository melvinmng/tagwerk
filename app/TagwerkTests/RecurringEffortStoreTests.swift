import Foundation
import RemindersKit
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

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        store = RecurringEffortStore(context: container.mainContext)
    }

    @Test func setForAll_fromToday_keepsPastValue() {
        store.setForAll(180, reminderID: "karteikarten", from: PlanDay(year: 2026, month: 11, day: 1))
        store.setForAll(120, reminderID: "karteikarten", from: today)
        #expect(store.minutes(for: "karteikarten", on: yesterday) == 180)
        #expect(store.minutes(for: "karteikarten", on: today) == 120)
        #expect(store.minutes(for: "karteikarten", on: PlanDay(year: 2026, month: 10, day: 31)) == nil)
    }

    @Test func setForDay_overridesOnlyThatDay() {
        store.setForAll(180, reminderID: "k", from: PlanDay(year: 2026, month: 11, day: 1))
        store.setForDay(60, reminderID: "k", day: PlanDay(year: 2026, month: 11, day: 21))
        #expect(store.minutes(for: "k", on: PlanDay(year: 2026, month: 11, day: 21)) == 60)
        #expect(store.minutes(for: "k", on: PlanDay(year: 2026, month: 11, day: 22)) == 180)
    }

    @Test func override_zero_removesEffort() {
        store.setForAll(180, reminderID: "k", from: PlanDay(year: 2026, month: 11, day: 1))
        store.setForDay(0, reminderID: "k", day: today)
        #expect(store.minutes(for: "k", on: today) == 0)
    }

    @Test func reservedMinutes_sumsOccurringSeries() {
        let calendar = testCalendar()
        store.setForAll(180, reminderID: "daily", from: PlanDay(year: 2026, month: 11, day: 1))
        store.setForAll(60, reminderID: "weekly", from: PlanDay(year: 2026, month: 11, day: 1))
        let daily = ReminderRecord(id: "daily", title: "Karteikarten", notes: nil, due: DueDate(year: 2026, month: 11, day: 16),
                                   ekPriority: 0, isCompleted: false, listID: "l", lastModified: nil,
                                   recurrence: Recurrence(rule: .daily(interval: 1), start: PlanDay(year: 2026, month: 11, day: 16),
                                                          end: nil, count: nil))
        let weekly = ReminderRecord(id: "weekly", title: "Wochenrückblick", notes: nil, due: DueDate(year: 2026, month: 11, day: 20),
                                    ekPriority: 0, isCompleted: false, listID: "l", lastModified: nil,
                                    recurrence: Recurrence(rule: .weekly(interval: 1, weekdays: [6]),
                                                           start: PlanDay(year: 2026, month: 11, day: 20), end: nil, count: nil))
        #expect(store.reservedMinutes(on: today, reminders: [daily, weekly], calendar: calendar) == 180)
        #expect(store.reservedMinutes(on: PlanDay(year: 2026, month: 11, day: 20), reminders: [daily, weekly], calendar: calendar) == 240)
    }
}
