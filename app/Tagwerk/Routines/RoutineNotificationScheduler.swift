import Foundation
import Observation
import os
import TagwerkCore

/// Keeps the repeating routine reminders in line with the settings (phase 7 design §8): every pending request with the
/// routine prefix is removed and the wanted ones are added again, so a changed bedtime, checklist or switch needs no
/// bookkeeping. Runs at app start, when the app becomes active and after each change in the routine settings.
@MainActor
@Observable
final class RoutineNotificationScheduler {
    @ObservationIgnored private let center: any NotificationCenterClient
    @ObservationIgnored private let store: RoutineStore
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let locale: () -> Locale
    @ObservationIgnored private let log = Logger(subsystem: "de.tagwerk", category: "routine-notifications")
    @ObservationIgnored private var queue: Task<Void, Never>?

    /// Permission as seen at the last run; the settings page shows a hint while it is not granted.
    private(set) var authorization: NotificationAuthorization = .notDetermined

    init(center: any NotificationCenterClient, store: RoutineStore, settings: AppSettings,
         locale: @escaping () -> Locale = { .current }) {
        self.center = center
        self.store = store
        self.settings = settings
        self.locale = locale
    }

    /// Removes every pending routine request, then adds the wanted ones when notifications are allowed. Calls queue up,
    /// so two quick changes never interleave their removals and additions.
    func reschedule() async {
        let previous = queue
        let next = Task { @MainActor [weak self] in
            await previous?.value
            await self?.perform()
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
        var wanted = RoutineSchedule.eveningNotifications(items: store.checklist(), bedtimeMinutes: settings.bedtimeMinutes,
                                                          enabled: settings.eveningRemindersEnabled, locale: locale)
        if let morning = RoutineSchedule.morningNotification(enabled: settings.morningReminderEnabled,
                                                             minutes: settings.morningReminderMinutes, locale: locale) {
            wanted.append(morning)
        }
        for notification in wanted {
            do {
                try await center.addRepeating(notification)
            } catch {
                log.error("Adding a routine reminder failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
