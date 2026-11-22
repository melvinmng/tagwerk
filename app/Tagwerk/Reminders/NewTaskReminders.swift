import Foundation
import Observation
import RemindersKit
import TagwerkCore

/// The reminders of a task that is being created (plan g1, ER9b): the default of its source until the user picks an own list on
/// the selection page. Nothing is stored for an untouched list. After the task was created, an own list is written like the
/// editor writes it (`TaskReminderModel`): Apple reminders get alarms, the other sources a Tagwerk override.
@MainActor
@Observable
final class NewTaskReminders {
    let list: ReminderListModel
    @ObservationIgnored private let defaults: ReminderDefaults
    @ObservationIgnored private var source: TaskSource

    init(defaults: ReminderDefaults, source: TaskSource, hasTime: Bool) {
        self.defaults = defaults
        self.source = source
        let isAllDay = !hasTime
        list = ReminderListModel(offsets: nil, defaultOffsets: defaults.offsets(for: .forTask(source: source), isAllDay: isAllDay),
                                 isAllDay: isAllDay)
    }

    /// The task got or lost its time of day (`hasTime`), or the source changed. A source change drops an own list and shows the
    /// default of the new source, because every source has its own default and Apple reminders store alarms instead of
    /// notifications. A change of the time only adapts the list (an all-day task has no hour distances).
    func configure(source newSource: TaskSource, hasTime: Bool) {
        if newSource != source {
            source = newSource
            list.useDefault()
        }
        let isAllDay = !hasTime
        list.configure(isAllDay: isAllDay, defaultOffsets: defaults.offsets(for: .forTask(source: newSource), isAllDay: isAllDay))
    }

    /// The own list; `nil` while the default applies.
    var ownList: [ReminderOffset]? { list.isUsingDefault ? nil : list.offsets }

    /// Writes the own list for the created task. A repeating local task gets it for all following due dates. Throws when the
    /// Reminders app refuses the alarms; the task stays created.
    func save(for created: TaskItem, overrides: ReminderOverrideStore, reminderStore: (any ReminderStore)?) throws {
        guard let own = ownList, created.due != nil else { return }
        let model = TaskReminderModel(item: created, overrides: overrides, reminderStore: reminderStore, defaults: defaults)
        model.list.setList(own)
        model.reach = .allFollowing
        try model.save(due: created.due, recurring: created.recurrence != nil)
    }
}
