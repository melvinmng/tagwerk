import Foundation
import Observation
import os
import TagwerkCore

/// Keeps the routine reminders in line with the settings (phase 7 design §8): every pending request with the routine
/// prefix is removed and the wanted ones are added again, so a changed bedtime, checklist or switch needs no bookkeeping.
/// The evening reminders are dated single notifications for the next three routine days, so a point checked on an evening
/// does not remind on it (#173); the morning start and the weekly planning repeat. Runs at app start, when the app becomes
/// active, after each change in the routine settings, after unchecking a point and in the background refresh.
@MainActor
@Observable
final class RoutineNotificationScheduler {
    @ObservationIgnored private let center: any NotificationCenterClient
    @ObservationIgnored private let store: RoutineStore
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let locale: () -> Locale
    @ObservationIgnored private let log = Logger(subsystem: "de.tagwerk", category: "routine-notifications")
    @ObservationIgnored private var queue: Task<Void, Never>?

    /// Permission as seen at the last run; the settings page shows a hint while it is not granted.
    private(set) var authorization: NotificationAuthorization = .notDetermined

    init(center: any NotificationCenterClient, store: RoutineStore, settings: AppSettings,
         now: @escaping () -> Date = Date.init, calendar: Calendar = .tagwerk, locale: @escaping () -> Locale = { .current }) {
        self.center = center
        self.store = store
        self.settings = settings
        self.now = now
        self.calendar = calendar
        self.locale = locale
    }

    /// Removes every pending routine request, then adds the wanted ones when notifications are allowed. Calls queue up,
    /// so two quick changes never interleave their removals and additions.
    func reschedule() async {
        await enqueue { await self.perform() }
    }

    /// Removes the reminder of one point for one routine day at once: the user just checked it, so it must not fire.
    /// Needs no full run; unchecking runs `reschedule()`, which adds it again while its moment is ahead.
    func itemChecked(_ id: UUID, on day: PlanDay) async {
        await enqueue { await self.center.removePending([RoutineSchedule.eveningIdentifier(item: id, day: day)]) }
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) async {
        let previous = queue
        let next = Task { @MainActor in
            await previous?.value
            await work()
        }
        queue = next
        await next.value
    }

    private func perform() async {
        authorization = await center.authorization()
        let existing = await center.pendingRequests().map(\.id).filter { $0.hasPrefix(PlannedNotification.routineIdentifierPrefix) }
        if !existing.isEmpty { await center.removePending(existing) }
        guard authorization == .authorized else { return }
        let locale = locale()
        let store = store
        // Evening points first: the routines keep to their own 14 places next to the 46 of the task reminders.
        let evening = RoutineSchedule.eveningNotifications(
            items: store.checklist(), bedtimeMinutes: settings.bedtimeMinutes, enabled: settings.eveningRemindersEnabled,
            checked: { store.day($0).checkedItemIDs }, now: now(), calendar: calendar, locale: locale)
        var repeating: [RoutineNotification] = []
        if let morning = RoutineSchedule.morningNotification(enabled: settings.morningReminderEnabled,
                                                             minutes: settings.morningReminderMinutes, locale: locale) {
            repeating.append(morning)
        }
        if let week = RoutineSchedule.weekPlanningNotification(enabled: settings.weekPlanningReminderEnabled,
                                                               weekday: settings.weekPlanningReminderWeekday,
                                                               minutes: settings.weekPlanningReminderMinutes, locale: locale) {
            repeating.append(week)
        }
        let datedLimit = min(RoutineSchedule.maximumEveningNotifications, RoutineSchedule.maximumRoutineNotifications - repeating.count)
        for notification in evening.prefix(datedLimit) {
            do {
                try await center.addDated(notification)
            } catch {
                log.error("Adding an evening reminder failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        for notification in repeating {
            do {
                try await center.addRepeating(notification)
            } catch {
                log.error("Adding a routine reminder failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
