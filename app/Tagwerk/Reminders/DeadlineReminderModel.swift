import Foundation
import Observation
import RemindersKit
import TagwerkCore

/// The reminders of a deadline event (plan P4, Task 10; plan g1, ER5b): the Tagwerk notifications and the alarms of the calendar
/// event, each with its own list on screen. The notifications are saved as an override, the alarms in the calendar event. A
/// repeating deadline asks whether the lists are for this occurrence only or for it and all following ones.
@MainActor
@Observable
final class DeadlineReminderModel {
    enum Reach: Equatable { case onlyThis, allFollowing }

    let list: ReminderListModel
    /// The alarms of the calendar event ("Hinweise im Kalender"); a list without a default behind it.
    let calendarAlarms: ReminderListModel
    @ObservationIgnored private let initialAlarms: [ReminderOffset]
    @ObservationIgnored private let event: CalendarEvent
    @ObservationIgnored private let overrides: ReminderOverrideStore
    @ObservationIgnored private let defaultOffsets: [ReminderOffset]
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let initial: ReminderListResult

    init(event: CalendarEvent, overrides: ReminderOverrideStore, defaults: ReminderDefaults, calendar: Calendar,
         calendarAlarms alarms: [ReminderOffset] = []) {
        calendarAlarms = ReminderListModel(list: alarms, isAllDay: event.isAllDay)
        initialAlarms = calendarAlarms.offsets
        self.event = event
        self.overrides = overrides
        self.calendar = calendar
        defaultOffsets = defaults.offsets(for: .deadline, isAllDay: event.isAllDay)
        let resolved = Self.resolve(event, overrides: overrides.overrides(), defaultOffsets: defaultOffsets, calendar: calendar)
        list = ReminderListModel(offsets: resolved.isCustom ? resolved.offsets : nil, defaultOffsets: defaultOffsets,
                                 isAllDay: event.isAllDay)
        initial = list.result
    }

    /// Whether the alarms of the calendar event can be changed here: not for read-only calendars and invitations.
    var canEditCalendarAlarms: Bool { event.isEditable && !event.isInvitation }

    /// Why the alarms are shown read-only; `nil` while they can be changed.
    var calendarAlarmsReadOnlyReason: String? {
        if event.isInvitation { return String(localized: "Einladungen lassen sich hier nicht ändern.") }
        if !event.isEditable { return String(localized: "Dieser Kalender ist schreibgeschützt.") }
        return nil
    }

    private var alarmsChanged: Bool { canEditCalendarAlarms && calendarAlarms.offsets != initialAlarms }

    var hasChanges: Bool { list.result != initial || alarmsChanged }

    /// Reminders of both lists that fire in the same minute: the user would be reminded twice.
    var duplicates: [(offset: ReminderOffset, fire: Date)] {
        ReminderDuplicates.find(tagwerk: list.displayed, calendarAlarms: calendarAlarms.offsets, anchor: event.start,
                                isAllDay: event.isAllDay, calendar: calendar)
    }

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

    /// Writes both lists: first the alarms of the calendar event, which the calendar can refuse, then the notifications of
    /// Tagwerk. A series gets the alarms for this occurrence or for it and all following ones, as asked.
    func saveAll(reach: Reach, writeAlarms: (_ alarms: [ReminderOffset], _ span: EventSpan) async throws -> Void) async throws {
        guard hasChanges else { return }
        if alarmsChanged {
            try await writeAlarms(calendarAlarms.offsets, event.isRecurring && reach == .allFollowing ? .futureEvents : .thisEvent)
        }
        try save(reach: reach)
    }

    /// Writes the notifications of Tagwerk. Without a repetition they count for the deadline itself.
    func save(reach: Reach) throws {
        guard list.result != initial else { return }
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
