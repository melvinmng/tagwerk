import CoreGraphics
import EventKit
import Foundation
import TagwerkCore

/// The only owner of `EKEventStore`. Main-actor isolated so the non-Sendable store never
/// crosses threads; reminders are converted to `ReminderRecord` snapshots at the boundary.
@MainActor
public final class EventKitGateway: ReminderStore {
    private let store = EKEventStore()

    /// Emits whenever EventKit reports a change in reminders or events.
    public let changes: AsyncStream<Void>
    private let changesContinuation: AsyncStream<Void>.Continuation
    private var observer: (any NSObjectProtocol)?

    public init() {
        (changes, changesContinuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let continuation = changesContinuation
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { _ in
            continuation.yield()
        }
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        changesContinuation.finish()
    }

    // MARK: Access

    public var accessState: AccessState { Self.accessState(EKEventStore.authorizationStatus(for: .reminder)) }

    public var calendarAccessState: AccessState { Self.accessState(EKEventStore.authorizationStatus(for: .event)) }

    public func requestAccess() async throws -> AccessState {
        _ = try await store.requestFullAccessToReminders()
        return accessState
    }

    public func requestCalendarAccess() async throws -> AccessState {
        _ = try await store.requestFullAccessToEvents()
        return calendarAccessState
    }

    // MARK: Lists and calendars

    public func lists() -> [ListInfo] {
        store.calendars(for: .reminder).map(Self.listInfo)
    }

    public func calendars() -> [ListInfo] {
        store.calendars(for: .event).map(Self.listInfo)
    }

    // MARK: Reminders

    public func openReminders(in listIDs: Set<String>?) async -> [ReminderRecord] {
        var calendars: [EKCalendar]?
        if let listIDs {
            let selected = store.calendars(for: .reminder).filter { listIDs.contains($0.calendarIdentifier) }
            if selected.isEmpty { return [] }
            calendars = selected
        }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(Self.record))
            }
        }
    }

    public func reminder(id: String) -> ReminderRecord? {
        guard let reminder = ekReminder(id: id) else { return nil }
        return Self.record(reminder)
    }

    /// Writes only the fields of `record` that differ from the freshly loaded reminder.
    public func save(_ record: ReminderRecord) throws -> ReminderRecord {
        guard let reminder = ekReminder(id: record.id) else { throw TaskWriteError.notFound }
        let current = Self.record(reminder)
        if record.title != current.title { reminder.title = record.title }
        if record.notes != current.notes { reminder.notes = record.notes }
        if record.due != current.due {
            moveAlarms(of: reminder, from: current.due, to: record.due)
            reminder.dueDateComponents = Self.components(record.due)
        }
        if record.ekPriority != current.ekPriority { reminder.priority = record.ekPriority }
        if record.isCompleted != current.isCompleted { reminder.isCompleted = record.isCompleted }
        if record.listID != current.listID {
            guard let list = store.calendar(withIdentifier: record.listID) else { throw TaskWriteError.notFound }
            reminder.calendar = list
        }
        try store.save(reminder, commit: true)
        return Self.record(reminder)
    }

    public func create(title: String, notes: String?, due: DueDate?, ekPriority: Int, listID: String?) throws -> ReminderRecord {
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.dueDateComponents = Self.components(due)
        if let alarmDate = ReminderMapping.alarmDate(for: due, calendar: .current) {
            reminder.addAlarm(EKAlarm(absoluteDate: alarmDate))
        }
        reminder.priority = ekPriority
        guard let list = listID.flatMap({ store.calendar(withIdentifier: $0) }) ?? store.defaultCalendarForNewReminders() else {
            throw TaskWriteError.failed("Keine Erinnerungsliste gefunden")
        }
        reminder.calendar = list
        try store.save(reminder, commit: true)
        return Self.record(reminder)
    }

    // MARK: Helpers

    /// Moves absolute alarms that equal the old due time (see `ReminderMapping.movedAlarmDates`).
    private func moveAlarms(of reminder: EKReminder, from oldDue: DueDate?, to newDue: DueDate?) {
        let calendar = Calendar.current
        let oldMoment = ReminderMapping.alarmDate(for: oldDue, calendar: calendar)
        let newMoment = ReminderMapping.alarmDate(for: newDue, calendar: calendar)
        guard let oldMoment, let newMoment, let alarms = reminder.alarms else { return }
        for alarm in alarms {
            guard let date = alarm.absoluteDate,
                  let moved = ReminderMapping.movedAlarmDates([date], from: oldMoment, to: newMoment).first,
                  moved != date else { continue }
            alarm.absoluteDate = moved
        }
    }

    private func ekReminder(id: String) -> EKReminder? {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return nil }
        reminder.refresh()
        return reminder
    }

    nonisolated static func record(_ reminder: EKReminder) -> ReminderRecord {
        ReminderRecord(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            notes: reminder.notes,
            due: dueDate(reminder.dueDateComponents),
            ekPriority: reminder.priority,
            isCompleted: reminder.isCompleted,
            listID: reminder.calendar?.calendarIdentifier ?? "",
            lastModified: reminder.lastModifiedDate
        )
    }

    nonisolated static func dueDate(_ components: DateComponents?) -> DueDate? {
        guard let components, let year = components.year, let month = components.month, let day = components.day else {
            return nil
        }
        return DueDate(year: year, month: month, day: day, hour: components.hour, minute: components.minute)
    }

    nonisolated static func components(_ due: DueDate?) -> DateComponents? {
        guard let due else { return nil }
        var parts = due.dayComponents()
        if due.hasTime {
            parts.hour = due.hour
            parts.minute = due.minute
        }
        return parts
    }

    nonisolated static func listInfo(_ calendar: EKCalendar) -> ListInfo {
        ListInfo(id: calendar.calendarIdentifier, title: calendar.title,
                 colorHex: hex(calendar.cgColor), kind: kind(calendar.type))
    }

    nonisolated static func kind(_ type: EKCalendarType) -> CalendarKind {
        switch type {
        case .local: .local
        case .calDAV: .calDAV
        case .exchange: .exchange
        case .subscription: .subscription
        case .birthday: .birthday
        @unknown default: .other
        }
    }

    nonisolated static func accessState(_ status: EKAuthorizationStatus) -> AccessState {
        switch status {
        case .fullAccess: .fullAccess
        case .writeOnly: .writeOnly
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    nonisolated static func hex(_ color: CGColor?) -> String? {
        guard let color, let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.converted(to: srgb, intent: .defaultIntent, options: nil),
              let parts = converted.components, parts.count >= 3 else { return nil }
        let channels = parts.prefix(3).map { Int((max(0, min(1, $0)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
    }
}
