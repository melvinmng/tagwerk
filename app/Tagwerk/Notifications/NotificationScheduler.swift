import Foundation
import Observation
import os
import TagwerkCore

/// Events marked as deadlines in Tagwerk (plan deadline-marking): the calendars to read and which of the read
/// events are marked.
struct MarkedDeadlineSource {
    var calendarIDs: @MainActor () -> Set<String>
    var markedIDs: @MainActor ([CalendarEvent]) -> Set<String>

    static var none: MarkedDeadlineSource { MarkedDeadlineSource(calendarIDs: { [] }, markedIDs: { _ in [] }) }
}

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
    @ObservationIgnored private let markedDeadlines: MarkedDeadlineSource
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    /// The locale of the texts and formats. Every run replaces the requests of all loaded sources, so a language
    /// change reaches them on the next run; sources that are not loaded keep their requests until they load.
    @ObservationIgnored private let locale: () -> Locale
    @ObservationIgnored private var pendingRun: Task<Void, Never>?
    /// The last queued change; runs wait for it, so an older run never re-adds what a newer one removed.
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "local.tagwerk", category: "notifications")

    init(center: any NotificationCenterClient, taskList: TaskListModel,
         deadlineEvents: @escaping (DateInterval, Set<String>) -> [CalendarEvent]?,
         markedDeadlines: MarkedDeadlineSource = .none,
         settings: AppSettings, now: @escaping () -> Date = Date.init, calendar: Calendar = .tagwerk,
         locale: @escaping () -> Locale = { .current }) {
        self.center = center
        self.taskList = taskList
        self.deadlineEvents = deadlineEvents
        self.markedDeadlines = markedDeadlines
        self.settings = settings
        self.now = now
        self.calendar = calendar
        self.locale = locale
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
        await enqueue { await $0.performReschedule() }
    }

    /// Runs `work` after every earlier queued run has finished.
    private func enqueue(_ work: @escaping @MainActor (NotificationScheduler) async -> Void) async {
        let previous = queue
        let next = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            await work(self)
        }
        queue = next
        await next.value
    }

    private func performReschedule() async {
        await refreshAuthorization()
        guard authorization == .authorized else { return }
        let current = now()
        // The routine reminders (phase 7) share the prefix but have their own scheduler and their own five places.
        let ours = await center.pendingRequests().filter {
            $0.id.hasPrefix(PlannedNotification.identifierPrefix) && !$0.id.hasPrefix(PlannedNotification.routineIdentifierPrefix)
        }

        // Sources that are not loaded right now keep their notifications (a background launch before
        // GitHub is registered, a failing source, missing access). A sign-out or a switched-off source clears them.
        let enabled = settings.notifiedTaskSources
        let replaceable = Set(TaskSource.allCases.filter { source in
            guard enabled.contains(source) else { return true }
            switch taskList.sourceStates[source] {
            case .loaded, .offline, .signedOut: return true
            default: return false
            }
        })
        let events = currentDeadlineEvents(now: current)
        let kept = ours.filter { request in
            guard let fireDate = request.fireDate, fireDate > current else { return false }
            if request.id.hasPrefix(PlannedNotification.eventIdentifierPrefix) { return events == nil }
            return !replaceable.contains { request.id.hasPrefix(PlannedNotification.identifierPrefix(for: $0)) }
        }

        // Quiet hours and the Focus filter (plan quiet-hours). A Focus start that iOS never ended is dropped here.
        let quietHours = settings.quietHours
        let (focus, catchUp) = FocusQuiet.scheduling(settings.focusQuietState, now: current)
        if focus != settings.focusQuietState { settings.focusQuietState = focus }
        let focusHold = FocusQuiet.hold(since: focus.since, now: current, quietHours: quietHours, calendar: calendar)

        // Planned without the margin: a request that fires within the next minute stays when it is still wanted
        // unchanged, but nothing new is added that close (it could be in the past once iOS receives it).
        let rules = NotificationRules(leadTimeMinutes: settings.leadTimeMinutes,
                                      includesDeadlineCalendars: settings.deadlineCalendarNotifications,
                                      taskSources: enabled,
                                      limit: max(0, Self.limit - kept.count), minimumDelay: 0,
                                      quietHours: quietHours, focusHold: focusHold, focusCatchUp: catchUp)
        let tasks = taskList.items.filter { replaceable.contains($0.id.source) }
        let locale = locale()
        let wanted = notificationPlan(tasks: tasks, deadlineEvents: events ?? [], rules: rules, now: current, calendar: calendar,
                                      locale: locale)
        let earliestNew = current.addingTimeInterval(NotificationRules.defaultMinimumDelay)
        let pendingDates = Dictionary(ours.map { ($0.id, $0.fireDate) }, uniquingKeysWith: { first, _ in first })
        var plan: [PlannedNotification] = []
        var keep = Set(kept.map(\.id))
        for notification in wanted {
            if notification.fireDate >= earliestNew {
                plan.append(notification)
                keep.insert(notification.id)
            } else if let pending = pendingDates[notification.id] ?? nil,
                      abs(pending.timeIntervalSince(notification.fireDate)) < 1 {
                keep.insert(notification.id)
            }
        }

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
        await enqueue { await $0.performRemoval(of: source) }
    }

    private func performRemoval(of source: TaskSource) async {
        let prefix = PlannedNotification.identifierPrefix(for: source)
        let ids = await center.pendingRequests().map(\.id).filter { $0.hasPrefix(prefix) }
        if !ids.isEmpty { await center.removePending(ids) }
    }

    /// Deadline events of the next days (deadline calendars and marked events, one switch for both); `[]` when
    /// switched off or there are none, `nil` without calendar access.
    private func currentDeadlineEvents(now: Date) -> [CalendarEvent]? {
        guard settings.deadlineCalendarNotifications else { return [] }
        let deadlineCalendars = Set(settings.deadlineCalendarIDs ?? [])
        let ids = deadlineCalendars.union(markedDeadlines.calendarIDs())
        guard !ids.isEmpty else { return [] }
        let end = calendar.date(byAdding: .day, value: Self.eventHorizonDays, to: now) ?? now
        guard let events = deadlineEvents(DateInterval(start: now, end: end), ids) else { return nil }
        let marked = markedDeadlines.markedIDs(events)
        return events.filter { deadlineCalendars.contains($0.calendarID) || marked.contains($0.id) }
    }
}
