import Foundation

/// A time block that Tagwerk planned for a task in the plan calendar (#332, stage 2).
public struct ProjectTimeBlock: Sendable, Hashable {
    /// `TaskID.key` of the task the block belongs to.
    public var taskKey: String
    public var start: Date
    /// The end as the calendar has it now.
    public var end: Date
    /// The end before the block was cut when the task was completed early (`EffortTracker`); `nil` for a block that was never cut.
    /// "Eingeplant" counts the block as it was planned, so completing a task early does not shrink the plan it was measured against.
    public var plannedEnd: Date?

    public init(taskKey: String, start: Date, end: Date, plannedEnd: Date? = nil) {
        self.taskKey = taskKey
        self.start = start
        self.end = end
        self.plannedEnd = plannedEnd
    }

    var plannedInterval: DateInterval? {
        let stop = max(end, plannedEnd ?? end)
        return stop > start ? DateInterval(start: start, end: stop) : nil
    }
}

/// One stretch in which the focus timer counted focus for a task: a work phase without breaks and pauses
/// (`FocusTimerRules.workIntervals`).
public struct ProjectFocusSpan: Sendable, Hashable {
    public var taskKey: String
    public var start: Date
    public var end: Date

    public init(taskKey: String, start: Date, end: Date) {
        self.taskKey = taskKey
        self.start = start
        self.end = end
    }
}

/// A completion of a task that Tagwerk measured (`EffortSampleRecord`).
public struct ProjectCompletion: Sendable, Hashable {
    public var taskKey: String
    public var completedAt: Date
    /// The measurement counted time blocks (`EffortMethod` other than `.focus`). Only then the blocks of the task are time that was
    /// spent; a block of a task that was never completed in Tagwerk only says what was planned.
    public var countsBlocks: Bool

    public init(taskKey: String, completedAt: Date, countsBlocks: Bool) {
        self.taskKey = taskKey
        self.completedAt = completedAt
        self.countsBlocks = countsBlocks
    }
}

/// What the app recorded about time in a period, for any number of tasks. The calculation picks the tasks of one project.
public struct ProjectTimeInputs: Sendable, Hashable {
    public var blocks: [ProjectTimeBlock]
    public var focus: [ProjectFocusSpan]
    public var completions: [ProjectCompletion]
    /// The calendar could be read. Without it no block is known, and "eingeplant" says so instead of showing a zero.
    public var calendarAvailable: Bool

    public init(blocks: [ProjectTimeBlock] = [], focus: [ProjectFocusSpan] = [], completions: [ProjectCompletion] = [],
                calendarAvailable: Bool = true) {
        self.blocks = blocks
        self.focus = focus
        self.completions = completions
        self.calendarAvailable = calendarAvailable
    }
}

/// One week of the time chart; the weeks are those of `ProjectProgress.weekIntervals`.
public struct ProjectTimeWeek: Sendable, Hashable, Identifiable {
    public var start: Date
    public var plannedSeconds: TimeInterval
    public var investedSeconds: TimeInterval
    public var id: Date { start }

    public init(start: Date, plannedSeconds: TimeInterval, investedSeconds: TimeInterval) {
        self.start = start
        self.plannedSeconds = plannedSeconds
        self.investedSeconds = investedSeconds
    }
}

/// Planned and invested time of one project in a period.
public struct ProjectTimeSummary: Sendable, Hashable {
    public var weeks: [ProjectTimeWeek]
    public var plannedSeconds: TimeInterval
    public var investedSeconds: TimeInterval
    /// At least one block of the project's tasks lies in the period. `false` is "nothing planned" (or no calendar), not a measured zero.
    public var hasPlanned: Bool
    /// Focus time or counted block time lies in the period.
    public var hasInvested: Bool
    public var calendarAvailable: Bool

    /// Neither planned nor invested time is known: the page says "Keine Zeitdaten" instead of showing 0 h.
    public var hasData: Bool { hasPlanned || hasInvested }
}

/// The estimates of the open items of a project.
public struct ProjectOpenEstimate: Sendable, Hashable {
    /// Sum of the estimates of the open items that have one.
    public var minutes: Int
    public var estimatedCount: Int
    public var withoutEstimateCount: Int

    public var openCount: Int { estimatedCount + withoutEstimateCount }
}

/// The pure calculation of the time per project (#332, stage 2).
///
/// "Eingeplant" is the time of the blocks that Tagwerk planned for the tasks of the project, as they were planned (a block cut at an
/// early completion counts with its length before the cut). "Investiert" is time that was spent for these tasks, from two sources:
/// the work phases of the focus timer, and the time blocks of a task up to the moment it was completed in Tagwerk, but only when the
/// measurement of that completion counted blocks (the rule of `EffortRules`). Both sets of time are joined over the whole project
/// before they are cut into weeks, so time that two sources or two tasks both claim counts once.
public enum ProjectTime {
    public static func summary(inputs: ProjectTimeInputs, taskKeys: Set<String>, range: ProjectRange,
                               calendar: Calendar) -> ProjectTimeSummary {
        let blocks = inputs.calendarAvailable ? inputs.blocks.filter { taskKeys.contains($0.taskKey) } : []
        let completions = inputs.completions.filter { taskKeys.contains($0.taskKey) && $0.countsBlocks }
        let focus = inputs.focus.filter { taskKeys.contains($0.taskKey) }

        let planned = DateIntervals.merged(blocks.compactMap(\.plannedInterval))
        var investedIntervals = focus.compactMap { $0.end > $0.start ? DateInterval(start: $0.start, end: $0.end) : nil }
        for block in blocks {
            // The first completion after the start of the block ends the time the block counts.
            let completion = completions.filter { $0.taskKey == block.taskKey && $0.completedAt > block.start }
                .map(\.completedAt).min()
            guard let completion else { continue }
            let end = min(block.end, completion)
            if end > block.start { investedIntervals.append(DateInterval(start: block.start, end: end)) }
        }
        let invested = DateIntervals.merged(investedIntervals)

        let weeks = ProjectProgress.weekIntervals(of: range, calendar: calendar).map { week -> ProjectTimeWeek in
            let window = DateInterval(start: week.start, end: week.end)
            return ProjectTimeWeek(start: week.start,
                                   plannedSeconds: DateIntervals.seconds(of: planned, within: window),
                                   investedSeconds: DateIntervals.seconds(of: invested, within: window))
        }
        let plannedSeconds = weeks.reduce(0) { $0 + $1.plannedSeconds }
        let investedSeconds = weeks.reduce(0) { $0 + $1.investedSeconds }
        return ProjectTimeSummary(weeks: weeks, plannedSeconds: plannedSeconds, investedSeconds: investedSeconds,
                                  hasPlanned: plannedSeconds > 0, hasInvested: investedSeconds > 0,
                                  calendarAvailable: inputs.calendarAvailable)
    }

    /// The estimates of the open items; items without an estimate (or with one of 0 minutes) are counted separately.
    public static func openEstimate(facts: [ProjectItemFact]) -> ProjectOpenEstimate {
        var estimate = ProjectOpenEstimate(minutes: 0, estimatedCount: 0, withoutEstimateCount: 0)
        for item in facts where item.isOpen {
            if let minutes = item.estimateMinutes, minutes > 0 {
                estimate.minutes += minutes
                estimate.estimatedCount += 1
            } else {
                estimate.withoutEstimateCount += 1
            }
        }
        return estimate
    }
}
