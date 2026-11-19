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

    /// Drops cached calendars and items, e.g. after another `EKEventStore` created calendars.
    public func discardCachedData() {
        store.reset()
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

    public func completionDates(in interval: DateInterval, listIDs: Set<String>?) async -> [Date] {
        guard accessState == .fullAccess else { return [] }
        var calendars: [EKCalendar]?
        if let listIDs {
            let selected = store.calendars(for: .reminder).filter { listIDs.contains($0.calendarIdentifier) }
            if selected.isEmpty { return [] }
            calendars = selected
        }
        let predicate = store.predicateForCompletedReminders(withCompletionDateStarting: interval.start, ending: interval.end,
                                                             calendars: calendars)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                // Only dates leave the callback; titles are not needed for counting.
                continuation.resume(returning: (reminders ?? []).compactMap(\.completionDate))
            }
        }
    }

    public func completedReminders(in interval: DateInterval, listIDs: Set<String>) async -> [ReminderRecord] {
        guard accessState == .fullAccess else { return [] }
        let calendars = store.calendars(for: .reminder).filter { listIDs.contains($0.calendarIdentifier) }
        if calendars.isEmpty { return [] }
        let predicate = store.predicateForCompletedReminders(withCompletionDateStarting: interval.start, ending: interval.end,
                                                             calendars: calendars)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(Self.record))
            }
        }
    }

    public func defaultListID() -> String? {
        store.defaultCalendarForNewReminders()?.calendarIdentifier
    }

    public func reminder(id: String) -> ReminderRecord? {
        guard let reminder = ekReminder(id: id) else { return nil }
        return Self.record(reminder)
    }

    /// Writes only the fields of `record` that differ from the freshly loaded reminder, and the repetition
    /// only when `recurrence` is `.set`.
    public func save(_ record: ReminderRecord, recurrence: FieldChange<Recurrence?>) throws -> ReminderRecord {
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
        // After the due date, so a new rule is checked against the due date that will be saved.
        if case .set(let newRecurrence) = recurrence { try replaceRecurrence(of: reminder, with: newRecurrence) }
        try store.save(reminder, commit: true)
        return Self.record(reminder)
    }

    public func delete(id: String) throws {
        guard let reminder = ekReminder(id: id) else { throw TaskWriteError.notFound }
        try store.remove(reminder, commit: true)
    }

    public func create(title: String, notes: String?, due: DueDate?, ekPriority: Int, listID: String?,
                       recurrence: Recurrence?) throws -> ReminderRecord {
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.dueDateComponents = Self.components(due)
        if let alarmDate = ReminderMapping.alarmDate(for: due, calendar: .current) {
            reminder.addAlarm(EKAlarm(absoluteDate: alarmDate))
        }
        reminder.priority = ekPriority
        guard let list = listID.flatMap({ store.calendar(withIdentifier: $0) }) ?? store.defaultCalendarForNewReminders() else {
            throw TaskWriteError.failed(String(localized: "Keine Erinnerungsliste gefunden", bundle: .module))
        }
        reminder.calendar = list
        if recurrence != nil { try replaceRecurrence(of: reminder, with: recurrence) }
        try store.save(reminder, commit: true)
        return Self.record(reminder)
    }

    // MARK: Helpers

    /// Replaces all rules of the reminder by the one for `recurrence`; `nil` removes them all.
    /// Unverified assumption (plan §3, item 7): a reminder may carry several rules, so every one is removed.
    private func replaceRecurrence(of reminder: EKReminder, with recurrence: Recurrence?) throws {
        var newRule: EKRecurrenceRule?
        if let recurrence {
            guard reminder.dueDateComponents != nil else { throw ReminderMapping.recurrenceNeedsDue }
            guard let rule = RecurrenceMapping.ekRule(for: recurrence, calendar: .current) else {
                throw ReminderMapping.invalidRecurrence
            }
            newRule = rule
        }
        for existing in reminder.recurrenceRules ?? [] { reminder.removeRecurrenceRule(existing) }
        if let newRule { reminder.addRecurrenceRule(newRule) }
    }

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
            lastModified: reminder.lastModifiedDate,
            recurrence: recurrence(reminder),
            createdAt: reminder.creationDate,
            completedAt: reminder.completionDate
        )
    }

    /// Maps the first EventKit rule (see `RecurrenceMapping`); Tagwerk reads only one rule per reminder.
    nonisolated static func recurrence(_ reminder: EKReminder) -> Recurrence? {
        guard let rule = reminder.recurrenceRules?.first, let due = dueDate(reminder.dueDateComponents) else { return nil }
        return RecurrenceMapping.recurrence(from: rule, due: due, calendar: .current)
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
                 colorHex: hex(calendar.cgColor), kind: kind(calendar.type),
                 isWritable: calendar.allowsContentModifications)
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

// MARK: - Calendar events and the plan calendar

extension EventKitGateway: CalendarStore {
    public func events(in interval: DateInterval, calendarIDs: Set<String>?) -> [CalendarEvent] {
        var calendars: [EKCalendar]?
        if let calendarIDs {
            let selected = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
            if selected.isEmpty { return [] }
            calendars = selected
        }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: calendars)
        return CalendarBlockRules.uniqueIDs(store.events(matching: predicate).map(Self.calendarEvent))
    }

    public func event(id: String) -> CalendarEvent? {
        ekEvent(id: id).map(Self.calendarEvent)
    }

    public func planCalendar(id: String?) -> ListInfo? {
        guard let id, let calendar = store.calendar(withIdentifier: id), calendar.allowsContentModifications else { return nil }
        return Self.listInfo(calendar)
    }

    /// New calendar in iCloud when available (visible on Mac and Watch), otherwise on the device.
    public func createPlanCalendar(named name: String) throws -> ListInfo {
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = name
        calendar.cgColor = CGColor(srgbRed: 0.18, green: 0.72, blue: 0.63, alpha: 1)
        let sources = store.sources
        guard let source = sources.first(where: { $0.sourceType == .calDAV && $0.title == "iCloud" })
            ?? sources.first(where: { $0.sourceType == .local }) else {
            throw TaskWriteError.failed(String(localized: "Keine Kalenderquelle verfügbar", bundle: .module))
        }
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        return Self.listInfo(calendar)
    }

    public func createBlock(_ draft: BlockDraft, in calendarID: String) throws -> CalendarEvent {
        guard let calendar = store.calendar(withIdentifier: calendarID), calendar.allowsContentModifications else {
            throw TaskWriteError.failed(String(localized: "Kein Plan-Kalender", bundle: .module))
        }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.end
        event.url = TaskLinkURL.make(draft.taskID)
        event.notes = CalendarBlockRules.blockNotes
        try store.save(event, span: .thisEvent, commit: true)
        return Self.calendarEvent(event)
    }

    public func eventCalendars() -> [ListInfo] {
        calendars()
    }

    /// The store and event for Apple's event editor ("Weitere Optionen …"); a new event when `id` is nil.
    public func eventForSystemEditor(id: String?, calendarID: String?) -> (store: EKEventStore, event: EKEvent) {
        if let id, let event = ekEvent(id: id) { return (store, event) }
        let event = EKEvent(eventStore: store)
        event.calendar = calendarID.flatMap { store.calendar(withIdentifier: $0) } ?? store.defaultCalendarForNewEvents
        return (store, event)
    }

    public func writableCalendars() -> [ListInfo] {
        store.calendars(for: .event).filter(\.allowsContentModifications).map(Self.listInfo)
    }

    public func createEvent(_ draft: EventDraft) throws -> CalendarEvent {
        guard let calendar = store.calendar(withIdentifier: draft.calendarID), calendar.allowsContentModifications else {
            throw TaskWriteError.failed(String(localized: "Dieser Kalender kann nicht geändert werden.", bundle: .module))
        }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        apply(draft, to: event)
        try store.save(event, span: .thisEvent, commit: true)
        return Self.calendarEvent(event)
    }

    public func updateEvent(id: String, with draft: EventDraft, span: EventSpan, expectedVersion: String?) throws -> CalendarEvent {
        guard let event = ekEvent(id: id) else { throw TaskWriteError.notFound }
        let current = Self.calendarEvent(event)
        try CalendarBlockRules.checkEditable(current)
        try CalendarBlockRules.checkVersion(of: current, expected: expectedVersion)
        if draft.calendarID != current.calendarID {
            guard let target = store.calendar(withIdentifier: draft.calendarID), target.allowsContentModifications else {
                throw TaskWriteError.failed(String(localized: "Dieser Kalender kann nicht geändert werden.", bundle: .module))
            }
            event.calendar = target
        }
        apply(draft, to: event)
        try store.save(event, span: Self.ekSpan(span), commit: true)
        return Self.calendarEvent(event)
    }

    public func deleteEvent(id: String, span: EventSpan, expectedVersion: String?) throws {
        guard let event = ekEvent(id: id) else { throw TaskWriteError.notFound }
        let current = Self.calendarEvent(event)
        try CalendarBlockRules.checkEditable(current)
        try CalendarBlockRules.checkVersion(of: current, expected: expectedVersion)
        try store.remove(event, span: Self.ekSpan(span), commit: true)
    }

    private func apply(_ draft: EventDraft, to event: EKEvent) {
        event.title = draft.title
        event.isAllDay = draft.isAllDay
        event.startDate = draft.start
        event.endDate = draft.end
        event.notes = draft.notes
        event.location = draft.location
        event.url = draft.url
    }

    nonisolated static func ekSpan(_ span: EventSpan) -> EKSpan {
        switch span {
        case .thisEvent: .thisEvent
        case .futureEvents: .futureEvents
        }
    }

    private func ekEvent(id: String) -> EKEvent? {
        let (scopedIdentifier, occurrence) = CalendarBlockRules.parseOccurrenceID(id)
        let (identifier, calendarID) = CalendarBlockRules.parseCalendarScope(scopedIdentifier)
        guard let occurrence else {
            let event = store.event(withIdentifier: identifier)
            event?.refresh()
            return event
        }
        let calendars = calendarID.flatMap { store.calendar(withIdentifier: $0) }.map { [$0] }
        // One occurrence of a series: `occurrenceDate` keeps the original time even after the occurrence was
        // moved on its own, so search a wide window around it.
        let predicate = store.predicateForEvents(withStart: occurrence.addingTimeInterval(-60 * 86_400),
                                                 end: occurrence.addingTimeInterval(60 * 86_400), calendars: calendars)
        return store.events(matching: predicate).first {
            $0.eventIdentifier == identifier && abs(($0.occurrenceDate ?? $0.startDate).timeIntervalSince(occurrence)) < 1
        }
    }

    nonisolated static func calendarEvent(_ event: EKEvent) -> CalendarEvent {
        let declined = event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
        let identifier = event.eventIdentifier ?? event.calendarItemIdentifier
        var result = CalendarEvent(
            // Subscribed calendars and detached occurrences can share one identifier across many events, so
            // they always get the occurrence in their ID (see `CalendarBlockRules.uniqueIDs` for the rest).
            id: CalendarBlockRules.occurrenceID(eventIdentifier: identifier, occurrence: event.occurrenceDate ?? event.startDate,
                                                isRecurring: event.hasRecurrenceRules || event.isDetached
                                                    || event.calendar?.type == .subscription),
            externalID: event.calendarItemExternalIdentifier,
            calendarID: event.calendar?.calendarIdentifier ?? "",
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            url: event.url,
            isBusy: event.availability != .free && !declined,
            version: event.lastModifiedDate.map { String($0.timeIntervalSince1970) } ?? "0"
        )
        result.isRecurring = event.hasRecurrenceRules
        result.isInvitation = event.hasAttendees && event.organizer?.isCurrentUser == false
        result.isEditable = event.calendar?.allowsContentModifications ?? false
        result.notes = event.notes
        result.location = event.location
        return result
    }
}

