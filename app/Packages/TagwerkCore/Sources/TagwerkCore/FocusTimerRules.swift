import Foundation

/// Durations of the focus timer. Every value is clamped to its bounds, so a stored or typed value can never produce an
/// empty or endless phase.
public struct FocusTimerSettings: Sendable, Equatable, Codable {
    public static let workRange = 5...120
    public static let shortBreakRange = 1...30
    public static let longBreakRange = 5...60
    public static let roundsRange = 1...8

    public var workMinutes: Int
    public var shortBreakMinutes: Int
    public var longBreakMinutes: Int
    public var rounds: Int
    /// Off: one work phase, then the timer is finished.
    public var isPomodoro: Bool

    public init(workMinutes: Int = 25, shortBreakMinutes: Int = 5, longBreakMinutes: Int = 15, rounds: Int = 4,
                isPomodoro: Bool = true) {
        self.workMinutes = min(max(workMinutes, Self.workRange.lowerBound), Self.workRange.upperBound)
        self.shortBreakMinutes = min(max(shortBreakMinutes, Self.shortBreakRange.lowerBound), Self.shortBreakRange.upperBound)
        self.longBreakMinutes = min(max(longBreakMinutes, Self.longBreakRange.lowerBound), Self.longBreakRange.upperBound)
        self.rounds = min(max(rounds, Self.roundsRange.lowerBound), Self.roundsRange.upperBound)
        self.isPomodoro = isPomodoro
    }

    /// The same settings with every value inside its bounds again (after a property was set directly).
    public var clamped: FocusTimerSettings {
        FocusTimerSettings(workMinutes: workMinutes, shortBreakMinutes: shortBreakMinutes, longBreakMinutes: longBreakMinutes,
                           rounds: rounds, isPomodoro: isPomodoro)
    }
}

/// A phase of a focus session. Rounds count from 1.
public enum FocusPhase: Sendable, Equatable, Codable {
    case work(round: Int)
    case shortBreak(round: Int)
    case longBreak
    case finished

    public var isWork: Bool {
        if case .work = self { return true }
        return false
    }

    public var isBreak: Bool {
        switch self {
        case .shortBreak, .longBreak: true
        case .work, .finished: false
        }
    }
}

/// Everything the timer remembers about a session. The current phase is always computed from these timestamps, never
/// from a running counter, so a closed or killed app loses nothing.
public struct FocusTimerState: Sendable, Equatable, Codable {
    public var start: Date
    /// Finished pauses; they stop the clock.
    public var pauses: [DateInterval]
    /// Start of the pause that is still going on.
    public var pausedSince: Date?
    /// Moments at which the user skipped a break; the break ends right there.
    public var skips: [Date]
    public var settings: FocusTimerSettings
    /// Set when the session was stopped; later moments change nothing.
    public var endedAt: Date?

    public init(start: Date, settings: FocusTimerSettings, pauses: [DateInterval] = [], pausedSince: Date? = nil,
                skips: [Date] = [], endedAt: Date? = nil) {
        self.start = start
        self.settings = settings.clamped
        self.pauses = pauses
        self.pausedSince = pausedSince
        self.skips = skips
        self.endedAt = endedAt
    }
}

/// The state of a session at one moment.
public struct FocusTimerSnapshot: Sendable, Equatable {
    public let phase: FocusPhase
    /// Planned length of the current phase in seconds (a skipped break counts up to the skip); 0 when finished.
    public let phaseSeconds: Int
    /// When the current phase ends; `nil` while paused or finished.
    public let phaseEnd: Date?
    /// Seconds left in the current phase, rounded up; 0 when finished.
    public let remainingSeconds: Int
    public let isPaused: Bool
    /// Time spent in work phases only, without breaks and pauses.
    public let focusedSeconds: Int
    /// Work phases that ran to their end.
    public let completedRounds: Int
    /// When the last phase ended; `nil` while the session still runs.
    public let finishedAt: Date?
}

public enum FocusTimerRules {
    /// One planned phase in active time (seconds of running clock, pauses removed).
    private struct Segment {
        let phase: FocusPhase
        var start: Double
        var end: Double
    }

    /// The state of `state` at `date`.
    public static func snapshot(of state: FocusTimerState, at date: Date) -> FocusTimerSnapshot {
        let moment = state.endedAt.map { min($0, date) } ?? date
        let pauses = effectivePauses(state)
        let active = activeSeconds(of: state, pauses: pauses, until: moment)
        let segments = timeline(for: state, pauses: pauses)
        let focused = Int(focusedActive(in: segments, until: active).rounded(.down))
        let isPaused = state.endedAt == nil && pauses.contains { $0.start <= moment && moment < $0.end }
        let completed = segments.filter { $0.phase.isWork && $0.end <= active }.count

        guard let current = segments.first(where: { active < $0.end }) else {
            let finish = segments.last.map { wallDate(forActive: $0.end, state: state, pauses: pauses) } ?? state.start
            return FocusTimerSnapshot(phase: .finished, phaseSeconds: 0, phaseEnd: nil, remainingSeconds: 0, isPaused: false,
                                      focusedSeconds: focused, completedRounds: completed, finishedAt: finish)
        }
        return FocusTimerSnapshot(
            phase: current.phase, phaseSeconds: Int((current.end - current.start).rounded()),
            phaseEnd: isPaused ? nil : wallDate(forActive: current.end, state: state, pauses: pauses),
            remainingSeconds: Int((current.end - active).rounded(.up)), isPaused: isPaused, focusedSeconds: focused,
            completedRounds: completed, finishedAt: nil)
    }

    /// The stretches of wall-clock time in which the timer counted focus: the work phases up to `date` (or the end of the
    /// session), without breaks and pauses, in order. Their lengths add up to `snapshot(of:at:).focusedSeconds`.
    public static func workIntervals(of state: FocusTimerState, at date: Date = .distantFuture) -> [DateInterval] {
        let moment = state.endedAt.map { min($0, date) } ?? date
        let pauses = effectivePauses(state)
        let active = activeSeconds(of: state, pauses: pauses, until: moment)
        var result: [DateInterval] = []
        for segment in timeline(for: state, pauses: pauses) where segment.phase.isWork {
            let end = min(segment.end, active)
            guard end > segment.start else { continue }
            var cursor = wallDate(forActive: segment.start, state: state, pauses: pauses)
            let stop = wallDate(forActive: end, state: state, pauses: pauses)
            // Cut the stretch at every pause inside it.
            for pause in pauses where pause.end > cursor && pause.start < stop {
                if pause.start > cursor { result.append(DateInterval(start: cursor, end: pause.start)) }
                cursor = max(cursor, pause.end)
            }
            if stop > cursor { result.append(DateInterval(start: cursor, end: stop)) }
        }
        return result
    }

    // MARK: Timeline

    /// The phases in order, with skipped breaks cut at the skip. Skips that do not fall into a break are ignored.
    private static func timeline(for state: FocusTimerState, pauses: [DateInterval]) -> [Segment] {
        let settings = state.settings
        var plan: [(FocusPhase, Double)] = []
        if settings.isPomodoro {
            for round in 1...settings.rounds {
                plan.append((.work(round: round), Double(settings.workMinutes * 60)))
                plan.append(round < settings.rounds ? (.shortBreak(round: round), Double(settings.shortBreakMinutes * 60))
                                                    : (.longBreak, Double(settings.longBreakMinutes * 60)))
            }
        } else {
            plan.append((.work(round: 1), Double(settings.workMinutes * 60)))
        }
        var skips = state.skips.sorted().map { activeSeconds(of: state, pauses: pauses, until: $0) }
        var segments: [Segment] = []
        var cursor = 0.0
        for (phase, length) in plan {
            var end = cursor + length
            skips.removeAll { $0 < cursor }
            if phase.isBreak, let skip = skips.first(where: { $0 < end }) { end = skip }
            segments.append(Segment(phase: phase, start: cursor, end: end))
            cursor = end
        }
        return segments
    }

    private static func focusedActive(in segments: [Segment], until active: Double) -> Double {
        segments.filter(\.phase.isWork).reduce(0) { total, segment in
            total + max(0, min(active, segment.end) - segment.start)
        }
    }

    // MARK: Clock

    /// Finished pauses plus the open one, sorted, clipped to start at the session start.
    private static func effectivePauses(_ state: FocusTimerState) -> [DateInterval] {
        var all = state.pauses.compactMap { pause -> DateInterval? in
            let start = max(pause.start, state.start)
            return pause.end > start ? DateInterval(start: start, end: pause.end) : nil
        }
        if let since = state.pausedSince { all.append(DateInterval(start: max(since, state.start), end: .distantFuture)) }
        return all.sorted { $0.start < $1.start }
    }

    /// Seconds of running clock between the start and `moment`.
    private static func activeSeconds(of state: FocusTimerState, pauses: [DateInterval], until moment: Date) -> Double {
        guard moment > state.start else { return 0 }
        var paused = 0.0
        for pause in pauses {
            let overlap = min(pause.end, moment).timeIntervalSince(pause.start)
            if overlap > 0 { paused += overlap }
        }
        return max(0, moment.timeIntervalSince(state.start) - paused)
    }

    /// The wall-clock moment at which `active` seconds of running clock have passed.
    private static func wallDate(forActive active: Double, state: FocusTimerState, pauses: [DateInterval]) -> Date {
        var cursor = state.start
        var remaining = active
        for pause in pauses {
            let gap = pause.start.timeIntervalSince(cursor)
            if gap > 0 {
                if remaining <= gap { return cursor.addingTimeInterval(remaining) }
                remaining -= gap
            }
            cursor = max(cursor, pause.end)
        }
        return cursor.addingTimeInterval(remaining)
    }
}
