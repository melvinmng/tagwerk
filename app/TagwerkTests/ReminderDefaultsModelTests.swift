import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct ReminderDefaultsModelTests {
    @Test func firstOpening_showsTheMigratedValues() {
        let model = ReminderDefaultsModel(defaults: .legacy(leadTimeMinutes: 90))
        for kind in [ReminderKind.localTask, .githubIssue, .appleReminder] {
            #expect(model.list(.init(kind: kind, isAllDay: false)).offsets == [.before(amount: 90, unit: .minutes)])
            #expect(model.list(.init(kind: kind, isAllDay: true)).offsets == [.at(daysBefore: 0, hour: 9, minute: 0)])
        }
        #expect(model.list(.init(kind: .deadline, isAllDay: true)).offsets == [.at(daysBefore: 1, hour: 18, minute: 0)])
        #expect(model.list(.init(kind: .event, isAllDay: false)).offsets.isEmpty)
        #expect(model.defaults == ReminderDefaults.legacy(leadTimeMinutes: 90))
    }

    @Test func editing_changesTheDefaults() {
        let model = ReminderDefaultsModel(defaults: .legacy(leadTimeMinutes: 120))
        let events = model.list(.init(kind: .event, isAllDay: false))
        events.add(.before(amount: 15, unit: .minutes))
        let issues = model.list(.init(kind: .githubIssue, isAllDay: false))
        issues.add(.before(amount: 1, unit: .days))
        #expect(model.defaults.offsets(for: .event, isAllDay: false) == [.before(amount: 15, unit: .minutes)])
        #expect(model.defaults.offsets(for: .githubIssue, isAllDay: false) == [.before(amount: 1, unit: .days), .before(amount: 2, unit: .hours)])
        // The other task kinds keep their own lists.
        #expect(model.defaults.offsets(for: .localTask, isAllDay: false) == [.before(amount: 2, unit: .hours)])
        #expect(model.defaults.offsets(for: .appleReminder, isAllDay: false) == [.before(amount: 2, unit: .hours)])
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
        #expect(settings.reminderDefaults.offsets(for: .localTask, isAllDay: false) == [.before(amount: 1, unit: .hours)])
    }

    private let german = Locale(identifier: "de_DE")

    @Test func kindTitle_forEveryKind() {
        let titles = ReminderKind.allCases.map { ReminderDefaultsModel.kindTitle($0) }
        #expect(titles == ["Kalendertermine", "Apple Erinnerungen", "GitHub-Issues", "Lokale Aufgaben", "Deadline-Termine"])
    }

    @Test func slotTitle_namesTheTimeOfDay() {
        #expect(ReminderDefaultsModel.slotTitle(.init(kind: .localTask, isAllDay: false)) == "Mit Uhrzeit")
        #expect(ReminderDefaultsModel.slotTitle(.init(kind: .localTask, isAllDay: true)) == "Ohne Uhrzeit")
        #expect(ReminderDefaultsModel.slotTitle(.init(kind: .event, isAllDay: true)) == "Ganztägig")
        #expect(ReminderDefaultsModel.slotTitle(.init(kind: .deadline, isAllDay: true)) == "Ganztägig")
    }

    @Test func rowSummary_usesTheSubjectOfTheKind() {
        var defaults = ReminderDefaults()
        for kind in ReminderKind.allCases { defaults.set([.before(amount: 0, unit: .minutes)], for: kind, isAllDay: false) }
        let model = ReminderDefaultsModel(defaults: defaults)
        #expect(model.rowSummary(for: .init(kind: .event, isAllDay: false), locale: german) == "Zum Beginn")
        #expect(model.rowSummary(for: .init(kind: .deadline, isAllDay: false), locale: german) == "Zur Deadline")
        #expect(model.rowSummary(for: .init(kind: .localTask, isAllDay: false), locale: german) == "Zur Fälligkeit")
        #expect(model.rowSummary(for: .init(kind: .githubIssue, isAllDay: false), locale: german) == "Zur Fälligkeit")
        #expect(model.rowSummary(for: .init(kind: .appleReminder, isAllDay: false), locale: german) == "Zur Fälligkeit")
    }

    @Test func rowSummary_allDay_saysTheDayItself() {
        var defaults = ReminderDefaults()
        defaults.set([.before(amount: 0, unit: .days)], for: .event, isAllDay: true)
        let model = ReminderDefaultsModel(defaults: defaults)
        #expect(model.rowSummary(for: .init(kind: .event, isAllDay: true), locale: german) == "Am Tag selbst")
    }

    @Test func changingOneList_keepsTheOtherNine() {
        let before = ReminderDefaultsModel(defaults: .legacy(leadTimeMinutes: 120))
        let model = ReminderDefaultsModel(defaults: .legacy(leadTimeMinutes: 120))
        let changed = ReminderDefaultsModel.Slot(kind: .deadline, isAllDay: false)
        model.list(changed).toggle(.before(amount: 1, unit: .weeks))
        #expect(model.list(changed).offsets != before.list(changed).offsets)
        let others = ReminderDefaultsModel.slots.filter { $0 != changed }
        #expect(others.count == 9)
        for slot in others { #expect(model.list(slot).offsets == before.list(slot).offsets) }
    }
}
