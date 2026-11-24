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

    @Test func nonRecurringDeadline_storesAListForItsOwnOccurrenceWithoutAskingForReach() throws {
        var single = series()[0]
        single.id = "einzeln"
        single.isRecurring = false
        let reminders = model(single)
        reminders.list.customize()
        reminders.list.add(.before(amount: 1, unit: .weeks))
        #expect(!reminders.asksReach)
        try reminders.save(reach: .onlyThis)
        #expect(overrides.overrides(for: ReminderOverride.key(deadlineSeries: "einzeln")).map(\.scope) == [.occurrence("einzeln")])
        #expect(offsets(single) == [.before(amount: 1, unit: .weeks), .before(amount: 2, unit: .hours)])
    }

    @Test func allDayDeadline_hasItsOwnDefault() {
        var event = series()[0]
        event.isAllDay = true
        #expect(offsets(event) == [.at(daysBefore: 1, hour: 18, minute: 0)])
    }

    // MARK: Calendar alarms next to the Tagwerk notifications (plan g1, ER5b)

    private func alarmModel(_ event: CalendarEvent, alarms: [ReminderOffset] = []) -> DeadlineReminderModel {
        DeadlineReminderModel(event: event, overrides: overrides, defaults: defaults, calendar: calendar, calendarAlarms: alarms)
    }

    @Test func save_writesBothLists() async throws {
        let event = series()[0]
        var event1 = event
        event1.isRecurring = false
        let reminders = alarmModel(event1, alarms: [.before(amount: 1, unit: .days)])
        reminders.list.customize()
        reminders.list.add(.before(amount: 1, unit: .weeks))
        reminders.calendarAlarms.toggle(.before(amount: 15, unit: .minutes))
        var written: [([ReminderOffset], EventSpan)] = []
        try await reminders.saveAll(reach: .allFollowing) { alarms, span in written.append((alarms, span)) }
        #expect(written.count == 1)
        #expect(written.first?.0 == [.before(amount: 1, unit: .days), .before(amount: 15, unit: .minutes)])
        #expect(written.first?.1 == .thisEvent)
        #expect(offsets(event1) == [.before(amount: 1, unit: .weeks), .before(amount: 2, unit: .hours)])
    }

    @Test func save_series_usesTheReachForTheAlarms() async throws {
        let events = series()
        for (reach, span) in [(DeadlineReminderModel.Reach.onlyThis, EventSpan.thisEvent), (.allFollowing, .futureEvents)] {
            let reminders = alarmModel(events[1])
            reminders.calendarAlarms.toggle(.before(amount: 1, unit: .days))
            #expect(reminders.asksReach)
            var spans: [EventSpan] = []
            try await reminders.saveAll(reach: reach) { _, span in spans.append(span) }
            #expect(spans == [span])
        }
    }

    @Test func save_readOnlyEvent_writesOnlyTagwerk() async throws {
        var event = series()[0]
        event.isRecurring = false
        event.isEditable = false
        let reminders = alarmModel(event, alarms: [.before(amount: 1, unit: .days)])
        #expect(!reminders.canEditCalendarAlarms)
        #expect(reminders.calendarAlarmsReadOnlyReason != nil)
        reminders.calendarAlarms.toggle(.before(amount: 15, unit: .minutes))
        #expect(!reminders.hasChanges)
        reminders.list.customize()
        reminders.list.add(.before(amount: 1, unit: .weeks))
        var writes = 0
        try await reminders.saveAll(reach: .allFollowing) { _, _ in writes += 1 }
        #expect(writes == 0)
        #expect(offsets(event) == [.before(amount: 1, unit: .weeks), .before(amount: 2, unit: .hours)])
    }

    @Test func save_invitation_isReadOnly() {
        var event = series()[0]
        event.isInvitation = true
        #expect(!alarmModel(event).canEditCalendarAlarms)
    }

    @Test func save_alarmFailure_leavesTheNotificationsAsTheyWere() async {
        var event = series()[0]
        event.isRecurring = false
        let reminders = alarmModel(event)
        reminders.list.customize()
        reminders.list.add(.before(amount: 1, unit: .weeks))
        reminders.calendarAlarms.toggle(.before(amount: 1, unit: .days))
        struct Refused: Error {}
        await #expect(throws: Refused.self) {
            try await reminders.saveAll(reach: .allFollowing) { _, _ in throw Refused() }
        }
        #expect(offsets(event) == defaultList)
    }

    @Test func duplicates_areReported() {
        var event = series()[0]
        event.isRecurring = false
        let reminders = alarmModel(event, alarms: [.before(amount: 3, unit: .days)])
        #expect(reminders.duplicates.isEmpty)
        reminders.list.customize()
        reminders.list.add(.before(amount: 72, unit: .hours))
        #expect(reminders.duplicates.count == 1)
        #expect(reminders.duplicates.first?.offset == .before(amount: 72, unit: .hours))
    }
}
