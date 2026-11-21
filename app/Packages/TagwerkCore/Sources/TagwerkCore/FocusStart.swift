import Foundation

/// What the user picks in the start sheet (FO7b).
public enum FocusStartChoice: Equatable, Sendable {
    /// One work phase of this many minutes, without Pomodoro.
    case minutes(Int)
    /// One work phase up to the end of the time block, without Pomodoro.
    case untilBlockEnd
    /// Rounds with breaks, with the durations of the settings.
    case pomodoro
}

public enum FocusStart {
    /// The duration capsules of the start sheet in minutes.
    public static let presets = [15, 25, 45, 60]

    /// The settings of a session. `nil` keeps the behaviour of before the start sheet: a block without Pomodoro runs
    /// to its end (at least 5 minutes), everything else uses the settings as they are.
    public static func settings(base: FocusTimerSettings, choice: FocusStartChoice?, blockRemainingMinutes: Int?) -> FocusTimerSettings {
        var result = base
        switch choice {
        case .minutes(let minutes):
            result.isPomodoro = false
            result.workMinutes = minutes
        case .untilBlockEnd:
            result.isPomodoro = false
            result.workMinutes = blockRemainingMinutes ?? base.workMinutes
        case .pomodoro:
            result.isPomodoro = true
        case nil:
            if let blockRemainingMinutes, !base.isPomodoro { result.workMinutes = blockRemainingMinutes }
        }
        return result.clamped
    }

    /// Minutes left of a block at `now`, rounded up and never negative.
    public static func remainingMinutes(blockStart: Date, blockEnd: Date, now: Date) -> Int {
        max(0, Int((blockEnd.timeIntervalSince(max(now, blockStart)) / 60).rounded(.up)))
    }

    /// What the start sheet preselects: "bis Blockende" for a block, else the last choice, else the settings.
    public static func preselected(base: FocusTimerSettings, lastMinutes: Int?, hasBlock: Bool) -> FocusStartChoice {
        if hasBlock { return .untilBlockEnd }
        if let lastMinutes { return .minutes(lastMinutes) }
        return base.isPomodoro ? .pomodoro : .minutes(base.workMinutes)
    }

    /// The minutes the menu entry names: the last choice of the start sheet, else the work time of the settings.
    public static func plannedMinutes(base: FocusTimerSettings, lastMinutes: Int?) -> Int {
        lastMinutes ?? base.workMinutes
    }
}

/// The templates of the focus settings: classic Pomodoro, a longer rhythm, or the user's own values.
public enum FocusPreset: Equatable, Sendable, CaseIterable {
    case classic, long, custom

    /// 25 / 5 and 50 / 10 (work / short break) are templates; anything else is custom.
    public static func matching(_ settings: FocusTimerSettings) -> FocusPreset {
        switch (settings.workMinutes, settings.shortBreakMinutes) {
        case (25, 5): .classic
        case (50, 10): .long
        default: .custom
        }
    }

    /// The settings with the template's work and break time; rounds and the long break stay.
    public func applied(to settings: FocusTimerSettings) -> FocusTimerSettings {
        var result = settings
        switch self {
        case .classic: result.workMinutes = 25; result.shortBreakMinutes = 5
        case .long: result.workMinutes = 50; result.shortBreakMinutes = 10
        case .custom: break
        }
        return result.clamped
    }
}
