import Foundation
import Observation
import RemindersKit
import TagwerkCore

/// The Tagwerk reminders of a deadline event (plan P4, Task 10): its list on screen and the override it is saved as. A
/// repeating deadline asks whether the list is for this occurrence only or for it and all following ones.
@MainActor
@Observable
final class DeadlineReminderModel {
    enum Reach: Equatable { case onlyThis, allFollowing }

    let list: ReminderListModel
    @ObservationIgnored private let event: CalendarEvent
    @ObservationIgnored private let overrides: ReminderOverrideStore
    @ObservationIgnored private let defaultOffsets: [ReminderOffset]
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let initial: ReminderListResult

    init(event: CalendarEvent, overrides: ReminderOverrideStore, defaults: ReminderDefaults, calendar: Calendar) {
        self.event = event
        self.overrides = overrides
        self.calendar = calendar
        defaultOffsets = defaults.offsets(for: .deadline, isAllDay: event.isAllDay)
        let resolved = Self.resolve(event, overrides: overrides.overrides(), defaultOffsets: defaultOffsets, calendar: calendar)
        list = ReminderListModel(offsets: resolved.isCustom ? resolved.offsets : nil, defaultOffsets: defaultOffsets,
                                 isAllDay: event.isAllDay)
        initial = list.result
    }

    var hasChanges: Bool { list.result != initial }

    /// Saving asks "Nur diese Deadline" / "Diese und alle folgenden" for a repeating deadline.
    var asksReach: Bool { event.isRecurring && hasChanges }

    /// What the notification plan uses for `event`: the summary row of the deadline section shows it.
    static func offsets(for event: CalendarEvent, overrides: ReminderOverrideStore, defaults: ReminderDefaults,
                        calendar: Calendar) -> [ReminderOffset] {
        resolve(event, overrides: overrides.overrides(), defaultOffsets: defaults.offsets(for: .deadline, isAllDay: event.isAllDay),
                calendar: calendar).offsets
    }

    private static func resolve(_ event: CalendarEvent, overrides: [String: [ReminderOverride]], defaultOffsets: [ReminderOffset],
                                calendar: Calendar) -> ResolvedReminders {
        ReminderOverrideResolution.resolve(itemKey: itemKey(for: event), occurrenceID: event.id,
                                           day: PlanDay(date: event.start, calendar: calendar), isAllDay: event.isAllDay,
                                           overrides: overrides, defaults: defaultOffsets)
    }

    private static func itemKey(for event: CalendarEvent) -> String {
        ReminderOverride.key(deadlineSeries: seriesIdentifier(of: event.id))
    }

    /// Writes the list. Without a repetition it counts for the deadline itself.
    func save(reach: Reach) throws {
        guard hasChanges else { return }
        let key = Self.itemKey(for: event)
        let day = PlanDay(date: event.start, calendar: calendar)
        // A deadline that does not repeat gets a list for its own occurrence ID: calendars can share an identifier, and the
        // series part of the key would then reach several deadlines.
        let scope: ReminderOverride.Scope = !event.isRecurring || reach == .onlyThis ? .occurrence(event.id) : .seriesFrom(day)
        let following = event.isRecurring && reach == .allFollowing
        switch list.result {
        case .custom(let offsets):
            if following { try removeLaterLists(of: key, from: day) }
            try overrides.save(ReminderOverride(itemKey: key, scope: scope, storage: .tagwerk, offsets: offsets))
        case .useDefault:
            try overrides.remove(itemKey: key, scope: scope)
            if following { try removeLaterLists(of: key, from: day) }
            // A broader list (a series list from an earlier day) would still apply: the default is written down explicitly.
            let remaining = Self.resolve(event, overrides: overrides.overrides(), defaultOffsets: defaultOffsets, calendar: calendar)
            if remaining.isCustom {
                try overrides.save(ReminderOverride(itemKey: key, scope: scope, storage: .tagwerk, offsets: defaultOffsets))
            }
        }
    }

    /// "This and all following" replaces what was set for later occurrences before.
    private func removeLaterLists(of key: String, from day: PlanDay) throws {
        for existing in overrides.overrides(for: key) {
            switch existing.scope {
            case .seriesFrom(let start) where start > day:
                try overrides.remove(itemKey: key, scope: existing.scope)
            case .occurrence(let id):
                if let date = CalendarBlockRules.parseOccurrenceID(id).1, date > event.start {
                    try overrides.remove(itemKey: key, scope: existing.scope)
                }
            default:
                break
            }
        }
    }
}
