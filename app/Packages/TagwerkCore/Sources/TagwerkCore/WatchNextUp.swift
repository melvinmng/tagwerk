import Foundation

/// What the "Als Nächstes" complication and the watch's first page show.
public enum WatchNextUp: Sendable, Hashable {
    /// An event, block or deadline of today; `isRunning` while it is under way.
    case entry(SnapshotEntry, isRunning: Bool)
    /// The next task of today with a time.
    case timedTask(WatchTask)
    /// An open task of today without a time (or already overdue); `more` counts the others ("+4").
    case untimedTask(WatchTask, more: Int)
    /// Nothing is left today; the first timed entry of tomorrow.
    case tomorrow(SnapshotEntry)
    case nothingLeft
    /// The snapshot describes another day: the phone has to refresh it.
    case stale

    /// An event or block that begins within this window (or runs) beats a task.
    public static let lookahead: TimeInterval = 3 * 3600

    /// The rule of issue #170: a running or soon starting entry, else the next timed task, else the first other open
    /// task with a count, else the first entry of tomorrow. All-day entries never count.
    public static func select(snapshot: WatchSnapshot, now: Date, calendar: Calendar) -> WatchNextUp {
        if snapshot.isStale(at: now, calendar: calendar) { return .stale }
        let today = snapshot.day
        let timedToday = snapshot.entries.filter { !$0.isAllDay && PlanDay(date: $0.start, calendar: calendar) == today }
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }

        let running = timedToday.first { $0.kind != .deadline && $0.start <= now && $0.end > now }
        if let running { return .entry(running, isRunning: true) }
        let soon = timedToday.first { entry in
            entry.start > now && entry.start.timeIntervalSince(now) <= lookahead
        }
        if let soon { return .entry(soon, isRunning: false) }

        let timedTasks = snapshot.tasks.filter { $0.hasTime && ($0.due ?? .distantPast) >= now }
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        if let first = timedTasks.first { return .timedTask(first) }

        let others = snapshot.tasks.filter { !($0.hasTime && ($0.due ?? .distantPast) >= now) }
        if let first = others.first { return .untimedTask(first, more: others.count - 1) }

        let tomorrow = today.adding(days: 1, calendar: calendar)
        let tomorrowEntry = snapshot.entries.filter { !$0.isAllDay && PlanDay(date: $0.start, calendar: calendar) == tomorrow }
            .min { ($0.start, $0.title) < ($1.start, $1.title) }
        if let tomorrowEntry { return .tomorrow(tomorrowEntry) }
        return .nothingLeft
    }

    /// Moments at which the selection can change: now, starts and ends, the moment an entry enters the look-ahead
    /// window, task times and midnight. At most `limit`, within the next 24 hours.
    public static func timelineDates(snapshot: WatchSnapshot, from now: Date, calendar: Calendar, limit: Int = 30) -> [Date] {
        let horizon = now.addingTimeInterval(86_400)
        var moments = Set<Date>([now])
        func add(_ moment: Date?) {
            if let moment, moment > now, moment <= horizon { moments.insert(moment) }
        }
        for entry in snapshot.entries where !entry.isAllDay {
            add(entry.start)
            add(entry.end)
            add(entry.start.addingTimeInterval(-lookahead))
        }
        for task in snapshot.tasks where task.hasTime { add(task.due) }
        add(PlanDay(date: now, calendar: calendar).adding(days: 1, calendar: calendar).startDate(in: calendar))
        return Array(moments.sorted().prefix(limit))
    }
}
