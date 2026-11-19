import Foundation

/// The span in which a Focus filter holds task and deadline notifications back (plan quiet-hours, decision 5).
public struct FocusHold: Sendable, Hashable {
    /// When the Focus filter became active; notifications that came due before are not touched.
    public let from: Date
    /// Where held notifications go.
    public let until: Date

    public init(from: Date, until: Date) {
        self.from = from
        self.until = until
    }
}

/// Rules of the Focus filter "Mitteilungen ruhen lassen". iOS tells the app only when a Focus filter starts and when it
/// ends, never when it will end. So the app keeps the start, holds notifications back to a known target, and after the
/// end lets those that came due meanwhile fire once.
public enum FocusQuiet {
    /// Without quiet hours there is no known end: notifications wait this long after the start at most.
    public static let openEndedHold: TimeInterval = 8 * 3600
    /// A start older than this is treated as lost: a missed end must never silence the app for good.
    public static let maximumAge: TimeInterval = 24 * 3600

    /// What Tagwerk remembers about the filter.
    public struct State: Equatable, Sendable {
        /// Set while a Focus with the filter is active.
        public var since: Date?
        /// Set after the filter ended, until the next notification run has caught up the notifications held meanwhile.
        public var catchUpFrom: Date?

        public init(since: Date? = nil, catchUpFrom: Date? = nil) {
            self.since = since
            self.catchUpFrom = catchUpFrom
        }
    }

    /// The state after iOS ran the filter with "ruhen lassen" on (`active`) or off. An active filter that runs again
    /// keeps its start; the end hands the start over to the catch-up. A start that is too old is dropped without catch-up.
    public static func applying(active: Bool, now: Date, to state: State) -> State {
        var next = dropping(staleIn: state, now: now)
        if active {
            next.since = next.since ?? now
        } else if let since = next.since {
            next.catchUpFrom = min(since, next.catchUpFrom ?? since)
            next.since = nil
        }
        return next
    }

    /// The state without a start older than `maximumAge`.
    public static func dropping(staleIn state: State, now: Date) -> State {
        var next = state
        if let since = next.since, now.timeIntervalSince(since) >= maximumAge { next.since = nil }
        return next
    }

    /// Where notifications go while the filter is active: to the end of the quiet hours (the current one, or the next
    /// one when none is running), without quiet hours for `openEndedHold` after the start. `nil` when inactive, stale or
    /// when the target has passed.
    public static func hold(since: Date?, now: Date, quietHours: QuietHours?, calendar: Calendar) -> FocusHold? {
        guard let since, now.timeIntervalSince(since) < maximumAge else { return nil }
        let target = quietHours?.nextEnd(after: now, calendar: calendar) ?? since.addingTimeInterval(openEndedHold)
        return target > now ? FocusHold(from: since, until: target) : nil
    }
}
