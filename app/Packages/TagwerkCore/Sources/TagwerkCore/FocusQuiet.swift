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

/// After a Focus filter ended: what came due since `from` while it was held back fires once at `at`.
public struct FocusCatchUp: Sendable, Hashable {
    public let from: Date
    public let at: Date

    public init(from: Date, at: Date) {
        self.from = from
        self.at = at
    }
}

/// Rules of the Focus filter "Mitteilungen zurückhalten". iOS tells the app only when a Focus filter starts and when it
/// ends, never when it will end. So the app keeps the start, holds notifications back to a known target, and after the
/// end lets those that came due meanwhile fire once.
public enum FocusQuiet {
    /// With quiet hours set up: held notifications wait this long after the start when iOS never reports the end.
    public static let unreportedEndHold: TimeInterval = 4 * 3600
    /// Without quiet hours: 8 hours, so a sleep Focus does not end in the middle of the night.
    public static let openEndedHold: TimeInterval = 8 * 3600
    /// A start older than this is treated as lost: a missed end must never silence the app for good.
    public static let maximumAge: TimeInterval = 24 * 3600

    /// What Tagwerk remembers about the filter.
    public struct State: Equatable, Sendable {
        /// Set while a Focus with the filter is active.
        public var since: Date?
        /// Set after the filter ended, until the notifications held meanwhile have fired.
        public var catchUpFrom: Date?
        /// When they fire; chosen by the first notification run after the end and then kept, so repeated runs plan the same
        /// moment and nothing fires twice.
        public var catchUpAt: Date?

        public init(since: Date? = nil, catchUpFrom: Date? = nil, catchUpAt: Date? = nil) {
            self.since = since
            self.catchUpFrom = catchUpFrom
            self.catchUpAt = catchUpAt
        }
    }

    /// The state after iOS ran the filter with "zurückhalten" on (`active`) or off. An active filter that runs again
    /// keeps its start. The end hands the start over to the catch-up only while the fallback target has not passed:
    /// what was held has been delivered at the target otherwise, and what came due after it was never held, so a catch-up
    /// would deliver it a second time. A start that is too old is dropped without catch-up.
    public static func applying(active: Bool, now: Date, to state: State, quietHours: QuietHours? = nil,
                                calendar: Calendar = .current) -> State {
        var next = dropping(staleIn: state, now: now)
        if active {
            next.since = next.since ?? now
        } else if let since = next.since {
            if fallbackTarget(since: since, quietHours: quietHours, calendar: calendar) > now {
                next.catchUpFrom = min(since, next.catchUpFrom ?? since)
            }
            next.catchUpAt = nil
            next.since = nil
        }
        return next
    }

    /// What a notification run at `now` does with the catch-up: the catch-up to plan (none while a Focus is active) and the
    /// state to store. The first run after the end picks the moment a minute ahead; once it has passed, the catch-up is over.
    public static func scheduling(_ state: State, now: Date) -> (state: State, catchUp: FocusCatchUp?) {
        var next = dropping(staleIn: state, now: now)
        guard next.since == nil, let from = next.catchUpFrom else { return (next, nil) }
        let at = next.catchUpAt ?? now.addingTimeInterval(NotificationRules.defaultMinimumDelay)
        guard at > now else {
            next.catchUpFrom = nil
            next.catchUpAt = nil
            return (next, nil)
        }
        next.catchUpAt = at
        return (next, FocusCatchUp(from: from, at: at))
    }

    /// The state without a start older than `maximumAge` and without a catch-up whose moment has passed: that catch-up
    /// fired already, and it must not widen the catch-up of a later Focus.
    public static func dropping(staleIn state: State, now: Date) -> State {
        var next = state
        if let since = next.since, now.timeIntervalSince(since) >= maximumAge { next.since = nil }
        if let at = next.catchUpAt, at <= now {
            next.catchUpFrom = nil
            next.catchUpAt = nil
        }
        return next
    }

    /// Where held notifications go when the end is never reported: `unreportedEndHold` after the start, moved to the end
    /// of the quiet hours when that moment lies inside them; `openEndedHold` after the start without quiet hours.
    public static func fallbackTarget(since: Date, quietHours: QuietHours?, calendar: Calendar) -> Date {
        guard let quietHours, !quietHours.isEmpty else { return since.addingTimeInterval(openEndedHold) }
        return quietHours.shifted(since.addingTimeInterval(unreportedEndHold), calendar: calendar)
    }

    /// Where notifications go while the filter is active: to `fallbackTarget`, which the reported end of the filter
    /// replaces when it comes earlier. `nil` when inactive, stale or when the target has passed.
    public static func hold(since: Date?, now: Date, quietHours: QuietHours?, calendar: Calendar) -> FocusHold? {
        guard let since, now.timeIntervalSince(since) < maximumAge else { return nil }
        let target = fallbackTarget(since: since, quietHours: quietHours, calendar: calendar)
        return target > now ? FocusHold(from: since, until: target) : nil
    }
}
