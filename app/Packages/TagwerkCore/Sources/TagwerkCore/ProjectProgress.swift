import Foundation

/// How an item of a project stands (#332). "Nicht geplant" and "Duplikat" close an item without counting as done.
public enum ProjectItemState: String, Sendable, Hashable, Codable {
    case open
    case completed
    case closedNotPlanned
}

/// One task of a project as the project progress counts it: only the fields the calculation needs, independent of the source.
public struct ProjectItemFact: Sendable, Hashable, Identifiable {
    public let id: String
    public var title: String
    /// Issue number (GitHub); `nil` for reminders and local tasks.
    public var number: Int?
    /// When the item was created; `nil` when the source does not know. Such an item counts as existing before every period.
    public var createdAt: Date?
    /// When the item was closed or completed; `nil` while open and for items whose completion time is unknown (local tasks that
    /// were completed before the weekly review stored it). Those count as done but never fall into a period.
    public var closedAt: Date?
    public var state: ProjectItemState
    public var due: DueDate?
    /// The Status of the item in the project (GitHub), e.g. "In progress".
    public var status: String?
    public var assignees: [String]
    public var url: URL?
    /// Open issues that block this one (native GitHub dependency "Blocked by"); closed ones do not count.
    public var openBlockedByCount: Int
    /// Open issues that wait for this one (native GitHub dependency "Blocking").
    public var openBlockingCount: Int
    /// The task in Tagwerk (`TaskID.key`) when the item is one of the user's tasks, so a tap can open the editor.
    public var taskKey: String?
    /// The effort estimate in minutes; `nil` when the source has none (GitHub: the Estimate field of the project, local tasks and
    /// reminders: the estimate set in Tagwerk).
    public var estimateMinutes: Int?

    public init(id: String, title: String, number: Int? = nil, createdAt: Date? = nil, closedAt: Date? = nil,
                state: ProjectItemState = .open, due: DueDate? = nil, status: String? = nil, assignees: [String] = [],
                url: URL? = nil, openBlockedByCount: Int = 0, openBlockingCount: Int = 0, taskKey: String? = nil,
                estimateMinutes: Int? = nil) {
        self.id = id
        self.title = title
        self.number = number
        self.createdAt = createdAt
        self.closedAt = closedAt
        self.state = state
        self.due = due
        self.status = status
        self.assignees = assignees
        self.url = url
        self.openBlockedByCount = openBlockedByCount
        self.openBlockingCount = openBlockingCount
        self.taskKey = taskKey
        self.estimateMinutes = estimateMinutes
    }

    public var isOpen: Bool { state == .open }

    /// Decision #332: blocked is an open item that has an open "Blocked by" dependency or the Status "Blocked". No free text, no label.
    public var isBlocked: Bool {
        guard isOpen else { return false }
        return openBlockedByCount > 0 || ProjectProgress.isBlockedStatus(status)
    }

    /// Decision #332: a blocker is an open item that other items wait for through the native dependency "Blocking".
    public var isBlocker: Bool { isOpen && openBlockingCount > 0 }
}

/// The periods the project page offers: "4 Wochen", "3 Monate", "1 Jahr" and a free range.
public enum ProjectPeriod: Sendable, Hashable {
    case fourWeeks
    case threeMonths
    case oneYear
    /// First and last day, both included. A start after the end is swapped, an end in the future is cut to today.
    case custom(start: PlanDay, end: PlanDay)

    /// Number of weeks of a preset, the current week included.
    var presetWeeks: Int? {
        switch self {
        case .fourWeeks: 4
        case .threeMonths: 13
        case .oneYear: 52
        case .custom: nil
        }
    }
}

/// A period resolved to instants: `start` is inclusive, `end` exclusive.
public struct ProjectRange: Sendable, Hashable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public func contains(_ date: Date) -> Bool { date >= start && date < end }
}

/// One week of the weekly chart.
public struct ProjectWeekBucket: Sendable, Hashable, Identifiable {
    /// Start of the calendar week (Monday), or the start of the period for the first week of a free range.
    public var start: Date
    public var created: Int
    public var completed: Int
    public var closedNotPlanned: Int
    /// Items that existed and were still open at the end of the week (at the end of the period for the last one).
    public var openAtEnd: Int
    public var id: Date { start }

    public init(start: Date, created: Int, completed: Int, closedNotPlanned: Int, openAtEnd: Int) {
        self.start = start
        self.created = created
        self.completed = completed
        self.closedNotPlanned = closedNotPlanned
        self.openAtEnd = openAtEnd
    }
}

/// What the project page and a row of the overview say about one project.
public struct ProjectSummary: Sendable, Hashable {
    public var open: Int
    public var completed: Int
    public var closedNotPlanned: Int
    /// Created and completed within the period.
    public var periodCreated: Int
    public var periodCompleted: Int
    /// Newest creation or closing of any item; `nil` when no date is known.
    public var lastMovement: Date?
    public var trend: ProjectTrend
    public var blocked: Int
    public var blockers: Int
    public var buckets: [ProjectWeekBucket]

    public var total: Int { open + completed + closedNotPlanned }
    /// Created minus completed within the period; negative while the backlog shrinks.
    public var net: Int { periodCreated - periodCompleted }
    /// Share of the items that are done, 0...1; 0 for an empty project.
    public var completedShare: Double { total == 0 ? 0 : Double(completed) / Double(total) }
}

/// The wording of the trend. `resting` wins over the comparison of the period: a project nobody touched for two weeks is not "steady".
public enum ProjectTrend: Sendable, Hashable {
    /// No items.
    case empty
    /// Items, but nothing open.
    case finished
    /// Open items, but no movement for `days` days (at least `ProjectProgress.restingAfterDays`).
    case resting(days: Int)
    /// More completed than created in the period.
    case advancing
    /// More created than completed in the period.
    case growingBacklog
    case steady
}

/// An entry of the history of a project.
public struct ProjectEvent: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case created, completed, closedNotPlanned
    }

    public var kind: Kind
    public var date: Date
    public var item: ProjectItemFact
    public var id: String { "\(item.id)#\(kind.rawValue)" }

    public init(kind: Kind, date: Date, item: ProjectItemFact) {
        self.kind = kind
        self.date = date
        self.item = item
    }
}

/// The open items of a project in the order the page shows them; an item sits in the first group that fits.
public struct ProjectOpenGroups: Sendable, Hashable {
    public var blocked: [ProjectItemFact]
    public var blockers: [ProjectItemFact]
    public var overdue: [ProjectItemFact]
    public var soon: [ProjectItemFact]
    public var rest: [ProjectItemFact]

    public var isEmpty: Bool { blocked.isEmpty && blockers.isEmpty && overdue.isEmpty && soon.isEmpty && rest.isEmpty }
}

/// The pure calculations of the project progress (#332). Everything is derived from the created and closed dates of the items, so the
/// history exists from the first day without any snapshots.
public enum ProjectProgress {
    /// Days without movement after which an open project counts as "ruht" (decision #332: start with 14 days, check against real data
    /// after two weeks of use).
    public static let restingAfterDays = 14
    /// Days ahead in which a due date counts as "soon" on the project page.
    public static let soonDays = 14
    /// A free range is cut to this many weeks (counted back from its end), so a chart stays readable.
    public static let maxCustomWeeks = 104

    /// A Status that blocks, matched without regard to case ("Blocked", "blocked").
    public static func isBlockedStatus(_ status: String?) -> Bool {
        status?.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Blocked") == .orderedSame
    }

    /// The instants of `period` at `now`. A preset ends now and starts on the Monday of its first week; a free range covers whole
    /// days and ends at the latest now.
    public static func range(of period: ProjectPeriod, now: Date, calendar: Calendar) -> ProjectRange {
        if let weeks = period.presetWeeks {
            let thisWeek = weekStart(of: now, calendar: calendar)
            let start = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek) ?? thisWeek
            return ProjectRange(start: start, end: now)
        }
        guard case .custom(let first, let last) = period else { return ProjectRange(start: now, end: now) }
        let ordered = first <= last ? (first, last) : (last, first)
        let startDay = ordered.0.startDate(in: calendar)
        let afterLast = ordered.1.adding(days: 1, calendar: calendar).startDate(in: calendar)
        let end = min(afterLast, now)
        var start = min(startDay, end)
        let earliest = calendar.date(byAdding: .weekOfYear, value: -(maxCustomWeeks - 1), to: weekStart(of: end, calendar: calendar))
        if let earliest, start < earliest { start = earliest }
        return ProjectRange(start: start, end: end)
    }

    /// Monday 00:00 of the week of `date`.
    public static func weekStart(of date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// Whether the item existed and was still open at `instant`. An unknown creation date counts as "existed", an unknown closing date
    /// of a closed item as "closed from the start".
    static func isOpen(_ item: ProjectItemFact, at instant: Date) -> Bool {
        if let createdAt = item.createdAt, createdAt > instant { return false }
        if item.isOpen { return true }
        guard let closedAt = item.closedAt else { return false }
        return closedAt > instant
    }

    /// Whether the item existed and was still open at the end of a bucket, which `ProjectRange.contains` treats as exclusive: an
    /// item belongs to the bucket when it was created or closed before `end`, so it has left exactly when its closing date is before
    /// `end`. This uses the same comparison as `contains`, so an item created or closed within a millisecond before `end` is
    /// counted the same way in `created`/`completed` and in `openAtEnd`.
    static func isOpen(_ item: ProjectItemFact, before end: Date) -> Bool {
        if let createdAt = item.createdAt, createdAt >= end { return false }
        if item.isOpen { return true }
        guard let closedAt = item.closedAt else { return false }
        return closedAt >= end
    }

    /// The calendar weeks of `range` as the weekly charts show them: each from its Monday (the start of the range for the first one)
    /// to the next Monday (the end of the range for the last one). Both charts of the project page use this, so their weeks match.
    public static func weekIntervals(of range: ProjectRange, calendar: Calendar) -> [ProjectRange] {
        guard range.start <= range.end else { return [] }
        var weeks: [ProjectRange] = []
        var weekFirst = weekStart(of: range.start, calendar: calendar)
        while weekFirst <= range.end {
            let next = calendar.date(byAdding: .weekOfYear, value: 1, to: weekFirst) ?? range.end.addingTimeInterval(1)
            weeks.append(ProjectRange(start: max(weekFirst, range.start), end: min(next, range.end)))
            weekFirst = next
            if next >= range.end { break }
        }
        return weeks
    }

    public static func buckets(facts: [ProjectItemFact], range: ProjectRange, calendar: Calendar) -> [ProjectWeekBucket] {
        weekIntervals(of: range, calendar: calendar).map { interval in
            var bucket = ProjectWeekBucket(start: interval.start, created: 0, completed: 0, closedNotPlanned: 0, openAtEnd: 0)
            for item in facts {
                if let createdAt = item.createdAt, interval.contains(createdAt) { bucket.created += 1 }
                if let closedAt = item.closedAt, interval.contains(closedAt) {
                    switch item.state {
                    case .completed: bucket.completed += 1
                    case .closedNotPlanned: bucket.closedNotPlanned += 1
                    case .open: break
                    }
                }
            }
            // The end of a bucket is exclusive (see `ProjectRange.contains`), so the state at its end is the state just before it.
            // An empty bucket has no such moment and takes the state at its single instant.
            bucket.openAtEnd = facts.filter {
                interval.end > interval.start ? isOpen($0, before: interval.end) : isOpen($0, at: interval.end)
            }.count
            return bucket
        }
    }

    public static func summary(facts: [ProjectItemFact], period: ProjectPeriod, now: Date, calendar: Calendar) -> ProjectSummary {
        let periodRange = range(of: period, now: now, calendar: calendar)
        let buckets = buckets(facts: facts, range: periodRange, calendar: calendar)
        let open = facts.filter(\.isOpen).count
        let completed = facts.filter { $0.state == .completed }.count
        let notPlanned = facts.filter { $0.state == .closedNotPlanned }.count
        let periodCreated = facts.filter { $0.createdAt.map(periodRange.contains) ?? false }.count
        let periodCompleted = facts.filter { $0.state == .completed && ($0.closedAt.map(periodRange.contains) ?? false) }.count
        let movement = lastMovement(facts: facts)
        var summary = ProjectSummary(
            open: open, completed: completed, closedNotPlanned: notPlanned,
            periodCreated: periodCreated, periodCompleted: periodCompleted, lastMovement: movement,
            trend: .steady, blocked: facts.filter(\.isBlocked).count, blockers: facts.filter(\.isBlocker).count,
            buckets: buckets)
        summary.trend = trend(summary, now: now, calendar: calendar)
        return summary
    }

    /// The newest creation or closing of any item.
    public static func lastMovement(facts: [ProjectItemFact]) -> Date? {
        facts.flatMap { [$0.createdAt, $0.closedAt] }.compactMap { $0 }.max()
    }

    static func trend(_ summary: ProjectSummary, now: Date, calendar: Calendar) -> ProjectTrend {
        if summary.total == 0 { return .empty }
        if summary.open == 0 { return .finished }
        if let movement = summary.lastMovement {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: movement), to: calendar.startOfDay(for: now)).day ?? 0
            if days >= restingAfterDays { return .resting(days: days) }
        }
        if summary.net < 0 { return .advancing }
        if summary.net > 0 { return .growingBacklog }
        return .steady
    }

    /// Creations and closings of the items, newest first. With a range only those inside it.
    public static func events(facts: [ProjectItemFact], in range: ProjectRange? = nil) -> [ProjectEvent] {
        var events: [ProjectEvent] = []
        for item in facts {
            if let createdAt = item.createdAt, range?.contains(createdAt) ?? true {
                events.append(ProjectEvent(kind: .created, date: createdAt, item: item))
            }
            if let closedAt = item.closedAt, range?.contains(closedAt) ?? true {
                switch item.state {
                case .completed: events.append(ProjectEvent(kind: .completed, date: closedAt, item: item))
                case .closedNotPlanned: events.append(ProjectEvent(kind: .closedNotPlanned, date: closedAt, item: item))
                case .open: break
                }
            }
        }
        return events.sorted { ($0.date, $0.id) > ($1.date, $1.id) }
    }

    /// The open items by what asks for attention first: blocked, blocking others, overdue, due within `soonDays`, the rest. Inside a
    /// group the earliest due date comes first, items without one last, then by title.
    public static func openGroups(facts: [ProjectItemFact], today: PlanDay, calendar: Calendar) -> ProjectOpenGroups {
        let soonLimit = today.adding(days: soonDays, calendar: calendar)
        var groups = ProjectOpenGroups(blocked: [], blockers: [], overdue: [], soon: [], rest: [])
        for item in facts where item.isOpen {
            let dueDay = item.due.map(PlanDay.init)
            if item.isBlocked {
                groups.blocked.append(item)
            } else if item.isBlocker {
                groups.blockers.append(item)
            } else if let dueDay, dueDay < today {
                groups.overdue.append(item)
            } else if let dueDay, dueDay <= soonLimit {
                groups.soon.append(item)
            } else {
                groups.rest.append(item)
            }
        }
        func ordered(_ items: [ProjectItemFact]) -> [ProjectItemFact] {
            items.sorted { lhs, rhs in
                switch (lhs.due.map(PlanDay.init), rhs.due.map(PlanDay.init)) {
                case let (left?, right?) where left != right: return left < right
                case (nil, _?): return false
                case (_?, nil): return true
                default: return (lhs.title, lhs.id) < (rhs.title, rhs.id)
                }
            }
        }
        groups.blocked = ordered(groups.blocked)
        groups.blockers = ordered(groups.blockers)
        groups.overdue = ordered(groups.overdue)
        groups.soon = ordered(groups.soon)
        groups.rest = ordered(groups.rest)
        return groups
    }

    /// Created and completed items over all projects since `since` (the overview header).
    public static func counts(facts: [[ProjectItemFact]], since: Date, until: Date) -> (created: Int, completed: Int) {
        let range = ProjectRange(start: since, end: until)
        let all = facts.joined()
        return (all.filter { $0.createdAt.map(range.contains) ?? false }.count,
                all.filter { $0.state == .completed && ($0.closedAt.map(range.contains) ?? false) }.count)
    }
}
