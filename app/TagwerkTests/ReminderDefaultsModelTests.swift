import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct ReminderDefaultsModelTests {
    @Test func firstOpening_showsTheMigratedValues() {
        let model = ReminderDefaultsModel(defaults: .legacy(leadTimeMinutes: 90))
        let task = model.list(.init(kind: .task, isAllDay: false))
        let allDayTask = model.list(.init(kind: .task, isAllDay: true))
        #expect(task.offsets == [.before(amount: 90, unit: .minutes)])
        #expect(allDayTask.offsets == [.at(daysBefore: 0, hour: 9, minute: 0)])
        #expect(model.list(.init(kind: .deadline, isAllDay: true)).offsets == [.at(daysBefore: 1, hour: 18, minute: 0)])
        #expect(model.list(.init(kind: .event, isAllDay: false)).offsets.isEmpty)
        #expect(model.defaults == ReminderDefaults.legacy(leadTimeMinutes: 90))
    }

    @Test func editing_changesTheDefaults() {
        let model = ReminderDefaultsModel(defaults: .legacy(leadTimeMinutes: 120))
        let events = model.list(.init(kind: .event, isAllDay: false))
        events.add(.before(amount: 15, unit: .minutes))
        let tasks = model.list(.init(kind: .task, isAllDay: false))
        tasks.add(.before(amount: 1, unit: .days))
        #expect(model.defaults.offsets(for: .event, isAllDay: false) == [.before(amount: 15, unit: .minutes)])
        #expect(model.defaults.offsets(for: .task, isAllDay: false) == [.before(amount: 1, unit: .days), .before(amount: 2, unit: .hours)])
        #expect(model.defaults.offsets(for: .deadline, isAllDay: false) == [.before(amount: 2, unit: .hours)])
    }

    @Test func allDayLists_offerNoHourUnits() {
        let model = ReminderDefaultsModel(defaults: .legacy(leadTimeMinutes: 120))
        #expect(model.list(.init(kind: .deadline, isAllDay: true)).availableUnits == [.days, .weeks])
        #expect(model.list(.init(kind: .deadline, isAllDay: false)).availableUnits == ReminderUnit.allCases)
    }

    @Test func writingTheDefaults_isReadBackByTheSettings() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let settings = try AppSettings.current(in: container.mainContext)
        settings.leadTimeMinutes = 60
        let model = ReminderDefaultsModel(defaults: settings.reminderDefaults)
        // Opening the page alone stores nothing.
        #expect(settings.reminderDefaultsData == nil)
        model.list(.init(kind: .event, isAllDay: true)).add(.at(daysBefore: 1, hour: 20, minute: 0))
        settings.reminderDefaults = model.defaults
        #expect(settings.reminderDefaults.offsets(for: .event, isAllDay: true) == [.at(daysBefore: 1, hour: 20, minute: 0)])
        #expect(settings.reminderDefaults.offsets(for: .task, isAllDay: false) == [.before(amount: 1, unit: .hours)])
    }
}
