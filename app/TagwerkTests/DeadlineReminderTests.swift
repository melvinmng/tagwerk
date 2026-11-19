import Foundation
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The Tagwerk reminders of deadline events, series included (plan P4, Task 10). All data is invented.
@MainActor
struct DeadlineReminderTests {
    let container: ModelContainer
    let overrides: ReminderOverrideStore
    let calendar = testCalendar()
    let defaults = ReminderDefaults.legacy(leadTimeMinutes: 120)

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        overrides = ReminderOverrideStore(context: container.mainContext)
    }

    private func at(_ day: Int, _ hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    /// Three weekly occurrences of one series: 20th, 27th and 4 Dec.
    private func series() -> [CalendarEvent] {
        [(11, 20), (11, 27), (12, 4)].map { month, day in
            let start = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 10))!
            var event = CalendarEvent(id: "serie|\(Int(start.timeIntervalSince1970))", externalID: nil, calendarID: "deadlines",
                                      title: "Abgabe", start: start, end: start.addingTimeInterval(3600), isAllDay: false, url: nil,
                                      isBusy: true, version: "1")
            event.isRecurring = true
            return event
        }
    }

    private func model(_ event: CalendarEvent) -> DeadlineReminderModel {
        DeadlineReminderModel(event: event, overrides: overrides, defaults: defaults, calendar: calendar)
    }

    private func offsets(_ event: CalendarEvent) -> [ReminderOffset] {
        DeadlineReminderModel.offsets(for: event, overrides: overrides, defaults: defaults, calendar: calendar)
    }

    private let defaultList: [ReminderOffset] = [.before(amount: 2, unit: .hours)]
    private let own: [ReminderOffset] = [.before(amount: 3, unit: .days)]

    @Test func newDeadline_followsTheDefault() {
        let event = series()[0]
        let reminders = model(event)
        #expect(reminders.list.isUsingDefault)
        #expect(reminders.list.displayed == defaultList)
        #expect(!reminders.asksReach)
        #expect(offsets(event) == defaultList)
    }

    @Test func deadlineOverride_onlyThis_storesOccurrenceScope() throws {
        let events = series()
        let reminders = model(events[1])
        reminders.list.customize()
        reminders.list.remove(at: 0)
        reminders.list.add(.before(amount: 3, unit: .days))
        #expect(reminders.asksReach)
        try reminders.save(reach: .onlyThis)
        let key = ReminderOverride.key(deadlineSeries: "serie")
        #expect(overrides.overrides(for: key).map(\.scope) == [.occurrence(events[1].id)])
        // Occurrence 1 and 3 keep the default; only occurrence 2 changes.
        #expect(offsets(events[0]) == defaultList)
        #expect(offsets(events[1]) == own)
        #expect(offsets(events[2]) == defaultList)
    }

    @Test func deadlineOverride_allFollowing_storesSeriesFromDay() throws {
        let events = series()
        let reminders = model(events[1])
        reminders.list.customize()
        reminders.list.remove(at: 0)
        reminders.list.add(.before(amount: 3, unit: .days))
        try reminders.save(reach: .allFollowing)
        let key = ReminderOverride.key(deadlineSeries: "serie")
        #expect(overrides.overrides(for: key).map(\.scope) == [.seriesFrom(PlanDay(year: 2026, month: 11, day: 27))])
        #expect(offsets(events[0]) == defaultList)
        #expect(offsets(events[1]) == own)
        #expect(offsets(events[2]) == own)
    }

    @Test func allFollowing_replacesLaterOccurrenceLists() throws {
        let events = series()
        let key = ReminderOverride.key(deadlineSeries: "serie")
        try overrides.save(ReminderOverride(itemKey: key, scope: .occurrence(events[2].id), offsets: [.before(amount: 9, unit: .days)]))
        let reminders = model(events[1])
        reminders.list.customize()
        reminders.list.remove(at: 0)
        reminders.list.add(.before(amount: 3, unit: .days))
        try reminders.save(reach: .allFollowing)
        #expect(offsets(events[2]) == own)
        #expect(overrides.overrides(for: key).count == 1)
    }

    @Test func useDefault_onlyThis_removesThatOccurrencesList() throws {
        let events = series()
        let key = ReminderOverride.key(deadlineSeries: "serie")
        try overrides.save(ReminderOverride(itemKey: key, scope: .occurrence(events[1].id), offsets: own))
        let reminders = model(events[1])
        #expect(!reminders.list.isUsingDefault)
        reminders.list.useDefault()
        try reminders.save(reach: .onlyThis)
        #expect(overrides.overrides(for: key).isEmpty)
        #expect(offsets(events[1]) == defaultList)
    }

    @Test func useDefault_whileASeriesListApplies_writesTheDefaultDown() throws {
        let events = series()
        let key = ReminderOverride.key(deadlineSeries: "serie")
        try overrides.save(ReminderOverride(itemKey: key, scope: .seriesFrom(PlanDay(year: 2026, month: 11, day: 20)), offsets: own))
        let reminders = model(events[1])
        reminders.list.useDefault()
        try reminders.save(reach: .onlyThis)
        #expect(offsets(events[0]) == own)
        #expect(offsets(events[1]) == defaultList)
        #expect(offsets(events[2]) == own)
    }

    @Test func nonRecurringDeadline_storesAnEntryWideListWithoutAskingForReach() throws {
        var single = series()[0]
        single.id = "einzeln"
        single.isRecurring = false
        let reminders = model(single)
        reminders.list.customize()
        reminders.list.add(.before(amount: 1, unit: .weeks))
        #expect(!reminders.asksReach)
        try reminders.save(reach: .onlyThis)
        #expect(overrides.overrides(for: ReminderOverride.key(deadlineSeries: "einzeln")).map(\.scope) == [.always])
    }

    @Test func allDayDeadline_hasItsOwnDefault() {
        var event = series()[0]
        event.isAllDay = true
        #expect(offsets(event) == [.at(daysBefore: 1, hour: 18, minute: 0)])
    }
}
