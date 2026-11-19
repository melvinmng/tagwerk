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
    /// Focus timer sessions only (the task had no time block that counts).
    case focus
    /// Time blocks that ended before the completion.
    case blocks
    /// Ended blocks plus the part of the running block up to the completion.
    case partialBlock
    /// Time blocks as above plus the focus time that lies outside the blocks of the task.
    case blocksAndFocus
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

    /// Actual effort of a completion. The time blocks of the task decide; focus time only adds what lies outside them.
    ///
    /// 1. Block time: ended blocks fully plus the running block up to `completedAt` (several blocks that overlap count
    ///    once). Blocks after `completedAt` do not count.
    /// 2. Focus time: the focus intervals up to `completedAt` without the parts that lie inside a block of the task, so
    ///    nothing is counted twice. Less than `minimumFocusSeconds` of it is no measurement.
    /// 3. Without any block time the focus time alone is the effort.
    ///
    /// - Parameters:
    ///   - completedAt: when the task was ticked off.
    ///   - blocks: blocks of the task in the plan calendar.
    ///   - focus: the stretches in which the focus timer counted focus for the task since the previous completion
    ///     (work phases without breaks and pauses, `FocusTimerRules.workIntervals`).
    ///   - since: the previous completion of the same task; blocks that started before it were counted then. The block
    ///     that is running at `completedAt` is always considered.
    public static func outcome(completedAt: Date, blocks: [EffortBlock], focus: [DateInterval] = [], since: Date? = nil) -> EffortOutcome {
        let ordered = blocks.sorted { $0.start < $1.start }
        // The running block is looked up among all blocks. A block that is running now cannot have been counted at the
        // previous completion (that would have ended it), so a measurement left behind (task reopened outside Tagwerk)
        // must never hide it from the cut.
        let running = ordered.first { $0.start <= completedAt && completedAt < $0.end }
        let relevant = ordered.filter { since == nil || $0.start >= since! || $0.id == running?.id }
        let trimDecision = running.map { trim(running: $0, completedAt: completedAt) }

        let countedBlocks = merged(relevant.filter { $0.start < completedAt }.map {
            DateInterval(start: $0.start, end: min($0.end, completedAt))
        })
        let blockSeconds = countedBlocks.reduce(0) { $0 + $1.duration }
        // Focus inside any block of the task (also one counted earlier) is not extra time.
        let focusBeforeCompletion = focus.compactMap { interval -> DateInterval? in
            interval.start < completedAt ? DateInterval(start: interval.start, end: min(interval.end, completedAt)) : nil
        }
        let outsideBlocks = subtracting(ordered.map { DateInterval(start: $0.start, end: $0.end) }, from: merged(focusBeforeCompletion))
        let focusSeconds = outsideBlocks.reduce(0) { $0 + $1.duration }
        let countsFocus = focusSeconds >= Double(minimumFocusSeconds)

        let total = blockSeconds + (countsFocus ? focusSeconds : 0)
        let tooShort = trimDecision?.tooShort ?? false
        var actual = minutes(total)
        if actual < 1 {
            guard countsFocus else {
                return EffortOutcome(actualMinutes: nil, method: nil, trim: trimDecision?.trim, tooShortToTrim: tooShort)
            }
            actual = 1
        }
        let method: EffortMethod
        switch (blockSeconds > 0, countsFocus) {
        case (true, true): method = .blocksAndFocus
        case (true, false): method = running == nil ? .blocks : .partialBlock
        default: method = .focus
        }
        return EffortOutcome(actualMinutes: actual, method: method, trim: trimDecision?.trim, tooShortToTrim: tooShort)
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

    /// The intervals sorted, with those that touch or overlap joined.
    private static func merged(_ intervals: [DateInterval]) -> [DateInterval] {
        var result: [DateInterval] = []
        for interval in intervals.filter({ $0.duration > 0 }).sorted(by: { $0.start < $1.start }) {
            if let last = result.last, interval.start <= last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                result.append(interval)
            }
        }
        return result
    }

    /// The parts of `intervals` (merged, sorted) that lie outside every interval of `removed`.
    private static func subtracting(_ removed: [DateInterval], from intervals: [DateInterval]) -> [DateInterval] {
        var result = intervals
        for cut in merged(removed) {
            result = result.flatMap { interval -> [DateInterval] in
                guard cut.start < interval.end, cut.end > interval.start else { return [interval] }
                var parts: [DateInterval] = []
                if cut.start > interval.start { parts.append(DateInterval(start: interval.start, end: cut.start)) }
                if cut.end < interval.end { parts.append(DateInterval(start: cut.end, end: interval.end)) }
                return parts
            }
        }
        return result
    }
}
