import Foundation

/// A time block of a task in the plan calendar.
public struct EffortBlock: Sendable, Equatable {
    public let id: String
    public let start: Date
    public let end: Date

    public init(id: String, start: Date, end: Date) {
        self.id = id
        self.start = start
        self.end = end
    }
}

/// Where the actual effort of a completion comes from.
public enum EffortMethod: String, Sendable, Codable, Equatable {
    /// Focus timer sessions.
    case focus
    /// Time blocks that ended before the completion.
    case blocks
    /// Ended blocks plus the part of the running block up to the completion.
    case partialBlock
}

/// The new end of a block that was still running when the task was completed.
public struct BlockTrim: Sendable, Equatable {
    public let blockID: String
    public let newEnd: Date
    public let oldEnd: Date
}

public struct EffortOutcome: Sendable, Equatable {
    /// `nil` when nothing was measured; no sample is stored then.
    public let actualMinutes: Int?
    public let method: EffortMethod?
    public let trim: BlockTrim?
    /// The completion came within the first minutes of a running block, so the block stays as it is.
    public let tooShortToTrim: Bool
}

public enum EffortRules {
    /// A running block is cut only when at least this long has passed since its start.
    public static let minimumTrimSeconds: TimeInterval = 5 * 60
    /// Block ends are set to a multiple of this many minutes (rounded up).
    public static let trimGridMinutes = 5
    /// Focus time below this is not a measurement.
    public static let minimumFocusSeconds = 60

    /// Actual effort of a completion.
    ///
    /// - Parameters:
    ///   - completedAt: when the task was ticked off.
    ///   - blocks: blocks of the task in the plan calendar.
    ///   - focusedSeconds: focus time of the task since the previous completion.
    ///   - since: the previous completion of the same task; blocks that started before it were counted then.
    public static func outcome(completedAt: Date, blocks: [EffortBlock], focusedSeconds: Int, since: Date? = nil) -> EffortOutcome {
        let relevant = blocks.filter { since == nil || $0.start >= since! }.sorted { $0.start < $1.start }
        let running = relevant.first { $0.start <= completedAt && completedAt < $0.end }
        let trimDecision = running.map { trim(running: $0, completedAt: completedAt) }

        if focusedSeconds >= minimumFocusSeconds {
            return EffortOutcome(actualMinutes: max(1, minutes(Double(focusedSeconds))), method: .focus,
                                 trim: trimDecision?.trim, tooShortToTrim: trimDecision?.tooShort ?? false)
        }
        let pastSeconds = relevant.filter { $0.end <= completedAt }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        let runningSeconds = running.map { completedAt.timeIntervalSince($0.start) } ?? 0
        let total = minutes(pastSeconds + runningSeconds)
        guard total >= 1 else {
            return EffortOutcome(actualMinutes: nil, method: nil, trim: trimDecision?.trim, tooShortToTrim: trimDecision?.tooShort ?? false)
        }
        return EffortOutcome(actualMinutes: total, method: running == nil ? .blocks : .partialBlock,
                             trim: trimDecision?.trim, tooShortToTrim: trimDecision?.tooShort ?? false)
    }

    /// The next multiple of `trimGridMinutes` on the clock at or after `date`.
    public static func roundedUp(_ date: Date) -> Date {
        let step = TimeInterval(trimGridMinutes * 60)
        return Date(timeIntervalSince1970: (date.timeIntervalSince1970 / step).rounded(.up) * step)
    }

    private static func trim(running block: EffortBlock, completedAt: Date) -> (trim: BlockTrim?, tooShort: Bool) {
        guard completedAt.timeIntervalSince(block.start) >= minimumTrimSeconds else { return (nil, true) }
        let newEnd = roundedUp(completedAt)
        // Never extend a block and never cut away nothing.
        guard newEnd < block.end else { return (nil, false) }
        return (BlockTrim(blockID: block.id, newEnd: newEnd, oldEnd: block.end), false)
    }

    private static func minutes(_ seconds: Double) -> Int { Int((seconds / 60).rounded()) }
}
