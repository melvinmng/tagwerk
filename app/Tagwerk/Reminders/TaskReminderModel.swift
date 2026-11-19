import Foundation
import Observation
import RemindersKit
import TagwerkCore

/// The reminders of one task in the task editor (plan P4, Task 9): the list on screen, and where it is stored on saving.
/// GitHub issues and local tasks keep their own list as a Tagwerk override; an Apple reminder gets it as alarms in the
/// Reminders app, marked by an override that records which alarms Tagwerk wrote.
@MainActor
@Observable
final class TaskReminderModel {
    /// For a repeating local task: whether the own list applies to this due date only or to all that follow.
    enum Reach: Equatable { case onlyThis, allFollowing }

    let list: ReminderListModel
    @ObservationIgnored private let item: TaskItem
    @ObservationIgnored private let overrides: ReminderOverrideStore
    @ObservationIgnored private let reminderStore: (any ReminderStore)?
    @ObservationIgnored private let defaults: ReminderDefaults
    @ObservationIgnored private let initial: ReminderListResult
    /// The answer to the question "Nur diese" / "Alle folgenden"; asked once per save.
    var reach: Reach = .onlyThis

    /// `item` is the task as it was opened; `reminderStore` is needed for Apple reminders only.
    init(item: TaskItem, overrides: ReminderOverrideStore, reminderStore: (any ReminderStore)?, defaults: ReminderDefaults) {
        self.item = item
        self.overrides = overrides
        self.reminderStore = reminderStore
        self.defaults = defaults
        let isAllDay = !(item.due?.hasTime ?? false)
        let resolved = ReminderOverrideResolution.resolve(
            itemKey: ReminderOverride.key(task: item.id), due: item.due, isAllDay: isAllDay,
            overrides: overrides.overrides(), defaults: defaults.offsets(for: .task, isAllDay: isAllDay))
        list = ReminderListModel(offsets: resolved.isCustom ? resolved.offsets : nil,
                                 defaultOffsets: defaults.offsets(for: .task, isAllDay: isAllDay), isAllDay: isAllDay)
        initial = list.result
    }

    /// The time of the due date changed: a date without time offers no hour distances and has its own default.
    func dueChanged(to due: DueDate?) {
        let isAllDay = !(due?.hasTime ?? false)
        list.configure(isAllDay: isAllDay, defaultOffsets: defaults.offsets(for: .task, isAllDay: isAllDay))
    }

    var hasChanges: Bool { list.result != initial }

    /// Reminders need a due date to count from.
    func isEditable(due: DueDate?) -> Bool { due != nil }

    /// Repeating Apple reminders have one alarm list for all repetitions; the editor says so.
    func appliesToAllRepetitions(recurring: Bool) -> Bool { item.id.source == .reminders && recurring }

    /// Whether saving asks "Nur diese" / "Alle folgenden": a changed list of a repeating local task.
    func needsReachQuestion(due: DueDate?, recurring: Bool) -> Bool {
        item.id.source == .local && recurring && due != nil && hasChanges
    }

    /// Writes the list. A task without due date keeps what it had. Throws when the Reminders app refuses the alarms; the
    /// override is then left as it was.
    func save(due: DueDate?, recurring: Bool) throws {
        guard due != nil, hasChanges else { return }
        let key = ReminderOverride.key(task: item.id)
        switch item.id.source {
        case .reminders:
            try saveAppleReminder(key: key)
        case .github, .local:
            try saveTagwerk(key: key, due: due, recurring: recurring)
        }
    }

    private func saveTagwerk(key: String, due: DueDate?, recurring: Bool) throws {
        let onlyThis = item.id.source == .local && recurring && reach == .onlyThis
        let scope: ReminderOverride.Scope = onlyThis ? due.map { .onlyDue($0) } ?? .always : .always
        switch list.result {
        case .useDefault:
            if onlyThis {
                try overrides.remove(itemKey: key, scope: scope)
            } else {
                // For all following due dates the default applies again, also over an earlier "only this one".
                try overrides.removeAll(itemKey: key)
            }
        case .custom(let offsets):
            try overrides.save(ReminderOverride(itemKey: key, scope: scope, storage: .tagwerk, offsets: offsets))
            // An own list for all following due dates replaces the ones that were set for single dates.
            if !onlyThis {
                for existing in overrides.overrides(for: key) where existing.scope != .always {
                    try overrides.remove(itemKey: key, scope: existing.scope)
                }
            }
        }
    }

    private func saveAppleReminder(key: String) throws {
        guard let reminderStore else { throw TaskWriteError.failed(String(localized: "Die Erinnerungen-App ist nicht erreichbar.")) }
        let id = item.id.rawValue
        let previous = overrides.overrides(for: key).first { $0.scope == .always && $0.storage == .eventKit }
        switch list.result {
        case .useDefault:
            if let previous {
                // Only the alarms Tagwerk wrote; alarms made in the Reminders app stay.
                try reminderStore.removeAlarms(previous.offsets, forReminder: id)
                try overrides.remove(itemKey: key, scope: .always)
            }
        case .custom(let offsets):
            if let previous {
                let dropped = previous.offsets.filter { old in !offsets.contains { $0.isEquivalent(to: old) } }
                if !dropped.isEmpty { try reminderStore.removeAlarms(dropped, forReminder: id) }
            }
            if !offsets.isEmpty { try reminderStore.setAlarms(offsets, forReminder: id) }
            try overrides.save(ReminderOverride(itemKey: key, scope: .always, storage: .eventKit, offsets: offsets))
        }
    }
}
