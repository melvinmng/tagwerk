import Foundation
import Observation
import os
import TagwerkCore

/// Keeps the pending deadline notifications in line with tasks, deadline calendars and settings
/// (design 2b §9, Phase 2 §8). Never calls any AI feature (§8.4).
@MainActor
@Observable
final class NotificationScheduler {
    private(set) var authorization: NotificationAuthorization = .notDetermined

    /// Deadline events ahead are read this far.
    static let eventHorizonDays = 60
    /// iOS keeps 64 pending requests per app; Tagwerk stays below that.
    static let limit = 50

    @ObservationIgnored private let center: any NotificationCenterClient
    @ObservationIgnored private let taskList: TaskListModel
    /// Events of the given deadline calendars in the interval; `nil` without calendar access.
    @ObservationIgnored private let deadlineEvents: (DateInterval, Set<String>) -> [CalendarEvent]?
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var pendingRun: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "local.tagwerk", category: "notifications")

    init(center: any NotificationCenterClient, taskList: TaskListModel,
         deadlineEvents: @escaping (DateInterval, Set<String>) -> [CalendarEvent]?,
         settings: AppSettings, now: @escaping () -> Date = Date.init, calendar: Calendar = .tagwerk) {
        self.center = center
        self.taskList = taskList
        self.deadlineEvents = deadlineEvents
        self.settings = settings
        self.now = now
        self.calendar = calendar
    }

    /// Reads the permission again, e.g. after returning from the iOS settings.
    func refreshAuthorization() async {
        authorization = await center.authorization()
    }

    /// Asks iOS for permission (only shown while undetermined) and schedules at once when granted.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await center.requestAuthorization()) ?? false
        await refreshAuthorization()
        if granted { await reschedule() }
        return granted
    }

    /// Reschedules after a short pause, so a burst of changes leads to one run.
    func scheduleSoon() {
        pendingRun?.cancel()
        pendingRun = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.reschedule()
        }
    }

    /// Brings the pending requests in line with the current tasks and deadline events.
    func reschedule() async {
        await refreshAuthorization()
        guard authorization == .authorized else { return }
        let current = now()
        let ours = await center.pendingRequests().filter { $0.id.hasPrefix(PlannedNotification.identifierPrefix) }

        // Sources that are not loaded right now keep their notifications (a background launch before
        // GitHub is registered, a failing source, missing access). A sign-out clears them.
        let replaceable = Set(TaskSource.allCases.filter { source in
            switch taskList.sourceStates[source] {
            case .loaded, .offline, .signedOut: true
            default: false
            }
        })
        let events = currentDeadlineEvents(now: current)
        let kept = ours.filter { request in
            guard let fireDate = request.fireDate, fireDate > current else { return false }
            if request.id.hasPrefix(PlannedNotification.eventIdentifierPrefix) { return events == nil }
            return !replaceable.contains { request.id.hasPrefix(PlannedNotification.identifierPrefix(for: $0)) }
        }

        let rules = NotificationRules(leadTimeMinutes: settings.leadTimeMinutes,
                                      includesDeadlineCalendars: settings.deadlineCalendarNotifications,
                                      limit: max(0, Self.limit - kept.count))
        let tasks = taskList.items.filter { replaceable.contains($0.id.source) }
        let plan = notificationPlan(tasks: tasks, deadlineEvents: events ?? [], rules: rules, now: current, calendar: calendar)

        let keep = Set(kept.map(\.id)).union(plan.map(\.id))
        let stale = ours.map(\.id).filter { !keep.contains($0) }
        if !stale.isEmpty { await center.removePending(stale) }
        for notification in plan {
            do {
                try await center.add(notification)
            } catch {
                log.error("Adding a notification failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Removes the notifications of a source after a voluntary sign-out (its state is gone, not `.signedOut`).
    func removeNotifications(of source: TaskSource) async {
        let prefix = PlannedNotification.identifierPrefix(for: source)
        let ids = await center.pendingRequests().map(\.id).filter { $0.hasPrefix(prefix) }
        if !ids.isEmpty { await center.removePending(ids) }
    }

    /// Deadline events of the next days; `[]` when switched off or none selected, `nil` without calendar access.
    private func currentDeadlineEvents(now: Date) -> [CalendarEvent]? {
        let ids = Set(settings.deadlineCalendarIDs ?? [])
        guard settings.deadlineCalendarNotifications, !ids.isEmpty else { return [] }
        let end = calendar.date(byAdding: .day, value: Self.eventHorizonDays, to: now) ?? now
        return deadlineEvents(DateInterval(start: now, end: end), ids)
    }
}
