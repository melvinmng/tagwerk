import Foundation
import RemindersKit
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// The reminders of a task in the editor (plan P4, Task 9). All data is invented.
@MainActor
struct TaskReminderTests {
    let container: ModelContainer
    let overrides: ReminderOverrideStore
    let defaults = ReminderDefaults.legacy(leadTimeMinutes: 120)
    let due = DueDate(year: 2026, month: 11, day: 27, hour: 12)

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        overrides = ReminderOverrideStore(context: container.mainContext)
    }

    private func task(_ title: String, source: TaskSource, due: DueDate? = nil, recurrence: Recurrence? = nil) -> TaskItem {
        var item = makeTask(title, source: source, due: due ?? self.due)
        item.recurrence = recurrence
        item.editableFields.insert(.due)
        return item
    }

    private func weekly(from due: DueDate) -> Recurrence {
        Recurrence(rule: .weekly(interval: 1, weekdays: []), start: PlanDay(due), end: nil, count: nil)
    }

    private func editor(_ item: TaskItem, store: (any ReminderStore)? = nil) -> (TaskEditorModel, TaskReminderModel, FakeTaskProvider) {
        let provider = FakeTaskProvider(source: item.id.source, tasks: [item])
        let model = TaskEditorModel(item: item, provider: provider)
        let reminders = TaskReminderModel(item: item, overrides: overrides, reminderStore: store, defaults: defaults)
        model.reminders = reminders
        return (model, reminders, provider)
    }

    @Test func newTask_followsTheDefault() {
        let (_, reminders, _) = editor(task("Issue", source: .github))
        #expect(reminders.list.isUsingDefault)
        #expect(reminders.list.displayed == [.before(amount: 2, unit: .hours)])
        #expect(!reminders.hasChanges)
    }

    @Test func save_githubTask_storesTagwerkOverride() async {
        let item = task("Issue", source: .github)
        let (model, reminders, provider) = editor(item)
        reminders.list.customize()
        reminders.list.add(.before(amount: 1, unit: .weeks))
        #expect(await model.save())
        // Only the reminders changed, so the task itself is not written.
        #expect(provider.appliedEdits.isEmpty)
        let stored = overrides.overrides(for: ReminderOverride.key(task: item.id))
        #expect(stored.map(\.scope) == [.always])
        #expect(stored.first?.storage == .tagwerk)
        #expect(stored.first?.offsets == [.before(amount: 1, unit: .weeks), .before(amount: 2, unit: .hours)])
    }

    @Test func save_unchangedReminders_writeNothing() async {
        let (model, _, _) = editor(task("Issue", source: .github))
        #expect(await model.save())
        #expect(overrides.overrides().isEmpty)
    }

    @Test func useDefault_removesTheOwnList() async throws {
        let item = task("Issue", source: .github)
        try overrides.save(ReminderOverride(itemKey: ReminderOverride.key(task: item.id), scope: .always, offsets: []))
        let (model, reminders, _) = editor(item)
        #expect(!reminders.list.isUsingDefault)
        reminders.list.useDefault()
        #expect(await model.save())
        #expect(overrides.overrides().isEmpty)
    }

    @Test func save_reminder_writesAlarmsAndMarksEventKit() async {
        let record = ReminderRecord(id: "r1", title: "Abgabe", notes: nil, due: due, ekPriority: 0, isCompleted: false, listID: "list",
                                    lastModified: Date(timeIntervalSince1970: 1))
        let store = InMemoryReminderStore(lists: [ListInfo(id: "list", title: "Liste", colorHex: nil, kind: .local)], records: [record])
        let item = task("Abgabe", source: .reminders)
        let renamed = TaskItem(id: TaskID(source: .reminders, rawValue: "r1"), title: "Abgabe", notes: nil, due: due, priority: nil,
                               estimateMinutes: nil, isCompleted: false, container: item.container, url: nil, version: "1",
                               editableFields: item.editableFields)
        let (model, reminders, _) = editor(renamed, store: store)
        reminders.list.customize()
        reminders.list.add(.before(amount: 1, unit: .days))
        #expect(await model.save())
        #expect(store.records["r1"]?.alarms.contains(.before(amount: 1, unit: .days)) == true)
        let stored = overrides.overrides(for: ReminderOverride.key(task: renamed.id))
        #expect(stored.first?.storage == .eventKit)
        #expect(stored.first?.offsets == [.before(amount: 1, unit: .days), .before(amount: 2, unit: .hours)])
    }

    @Test func useDefault_onReminder_removesOnlyOwnAlarms() async throws {
        let foreign = ReminderOffset.before(amount: 10, unit: .minutes)
        let own = ReminderOffset.before(amount: 1, unit: .days)
        let record = ReminderRecord(id: "r1", title: "Abgabe", notes: nil, due: due, ekPriority: 0, isCompleted: false, listID: "list",
                                    lastModified: Date(timeIntervalSince1970: 1), alarms: [foreign, own])
        let store = InMemoryReminderStore(lists: [ListInfo(id: "list", title: "Liste", colorHex: nil, kind: .local)], records: [record])
        let id = TaskID(source: .reminders, rawValue: "r1")
        try overrides.save(ReminderOverride(itemKey: ReminderOverride.key(task: id), scope: .always, storage: .eventKit, offsets: [own]))
        var item = task("Abgabe", source: .reminders)
        item = TaskItem(id: id, title: "Abgabe", notes: nil, due: due, priority: nil, estimateMinutes: nil, isCompleted: false,
                        container: item.container, url: nil, version: "1", editableFields: item.editableFields)
        let (model, reminders, _) = editor(item, store: store)
        #expect(reminders.list.offsets == [own])
        reminders.list.useDefault()
        #expect(await model.save())
        #expect(store.records["r1"]?.alarms == [foreign])
        #expect(overrides.overrides().isEmpty)
    }

    @Test func customList_replacesTheOwnAlarmsOnly() async throws {
        let foreign = ReminderOffset.before(amount: 10, unit: .minutes)
        let old = ReminderOffset.before(amount: 1, unit: .days)
        let record = ReminderRecord(id: "r1", title: "Abgabe", notes: nil, due: due, ekPriority: 0, isCompleted: false, listID: "list",
                                    lastModified: Date(timeIntervalSince1970: 1), alarms: [foreign, old])
        let store = InMemoryReminderStore(lists: [ListInfo(id: "list", title: "Liste", colorHex: nil, kind: .local)], records: [record])
        let id = TaskID(source: .reminders, rawValue: "r1")
        try overrides.save(ReminderOverride(itemKey: ReminderOverride.key(task: id), scope: .always, storage: .eventKit, offsets: [old]))
        let base = task("Abgabe", source: .reminders)
        let item = TaskItem(id: id, title: "Abgabe", notes: nil, due: due, priority: nil, estimateMinutes: nil, isCompleted: false,
                            container: base.container, url: nil, version: "1", editableFields: base.editableFields)
        let (model, reminders, _) = editor(item, store: store)
        reminders.list.remove(at: 0)
        reminders.list.add(.before(amount: 3, unit: .days))
        #expect(await model.save())
        #expect(Set(store.records["r1"]?.alarms ?? []) == [foreign, .before(amount: 3, unit: .days)])
    }

    @Test func recurringLocal_onlyThis_bindsToCurrentDue() async {
        let item = task("Serie", source: .local, recurrence: weekly(from: due))
        let (model, reminders, _) = editor(item)
        #expect(!model.asksReminderReach)
        reminders.list.customize()
        reminders.list.add(.before(amount: 1, unit: .weeks))
        #expect(model.asksReminderReach)
        reminders.reach = .onlyThis
        #expect(await model.save())
        let stored = overrides.overrides(for: ReminderOverride.key(task: item.id))
        #expect(stored.map(\.scope) == [.onlyDue(due)])
    }

    @Test func recurringLocal_allFollowing_isPermanent_andReplacesSingleDates() async throws {
        let item = task("Serie", source: .local, recurrence: weekly(from: due))
        let key = ReminderOverride.key(task: item.id)
        try overrides.save(ReminderOverride(itemKey: key, scope: .onlyDue(DueDate(year: 2026, month: 12, day: 4, hour: 12)), offsets: []))
        let (model, reminders, _) = editor(item)
        reminders.list.customize()
        reminders.list.add(.before(amount: 1, unit: .weeks))
        reminders.reach = .allFollowing
        #expect(await model.save())
        #expect(overrides.overrides(for: key).map(\.scope) == [.always])
    }

    @Test func nonRecurringTask_asksNoReachQuestion() {
        let (model, reminders, _) = editor(task("Einmalig", source: .local))
        reminders.list.customize()
        reminders.list.add(.before(amount: 1, unit: .weeks))
        #expect(!model.asksReminderReach)
        #expect(TaskEditorModel.saveQuestion(effortChanged: false, blocksOffSeries: [], remindersReach: false) == nil)
        #expect(TaskEditorModel.saveQuestion(effortChanged: false, blocksOffSeries: [], remindersReach: true) == .remindersReach)
    }

    @Test func noDue_hidesReminders() async {
        var item = task("Ohne", source: .github)
        item.due = nil
        let (model, reminders, _) = editor(item)
        #expect(!reminders.isEditable(due: model.draft.due))
        reminders.list.customize()
        reminders.list.add(.before(amount: 1, unit: .weeks))
        #expect(await model.save())
        #expect(overrides.overrides().isEmpty)
    }

    @Test func dueWithoutTime_usesTheAllDayDefault() {
        let (_, reminders, _) = editor(task("Datum", source: .local, due: DueDate(year: 2026, month: 11, day: 27)))
        #expect(reminders.list.isAllDay)
        #expect(reminders.list.displayed == [.at(daysBefore: 0, hour: 9, minute: 0)])
        reminders.dueChanged(to: due)
        #expect(!reminders.list.isAllDay)
        #expect(reminders.list.displayed == [.before(amount: 2, unit: .hours)])
    }

    @Test func alarmWriteFailure_keepsTheTaskSaved_andShowsTheError() async throws {
        let record = ReminderRecord(id: "r1", title: "Abgabe", notes: nil, due: due, ekPriority: 0, isCompleted: false, listID: "list",
                                    lastModified: Date(timeIntervalSince1970: 1))
        let store = InMemoryReminderStore(lists: [ListInfo(id: "list", title: "Liste", colorHex: nil, kind: .local)], records: [record])
        store.alarmWriteError = "Kein Zugriff"
        let base = task("Abgabe", source: .reminders)
        let item = TaskItem(id: TaskID(source: .reminders, rawValue: "r1"), title: "Abgabe", notes: nil, due: due, priority: nil,
                            estimateMinutes: nil, isCompleted: false, container: base.container, url: nil, version: "1",
                            editableFields: base.editableFields)
        let (model, reminders, provider) = editor(item, store: store)
        model.draft.title = "Abgabe 2"
        reminders.list.customize()
        reminders.list.add(.before(amount: 1, unit: .days))
        #expect(await model.save() == false)
        #expect(provider.appliedEdits.count == 1)
        #expect(model.saved != nil)
        #expect(model.errorMessage?.contains("Kein Zugriff") == true)
        #expect(model.reminderFailureAfterSave)
        #expect(overrides.overrides().isEmpty)
        // A second try writes the reminders only; the task is not written again.
        store.alarmWriteError = nil
        #expect(await model.save())
        #expect(provider.appliedEdits.count == 1)
        #expect(overrides.overrides().count == 1)
        #expect(!model.reminderFailureAfterSave)
    }
}
