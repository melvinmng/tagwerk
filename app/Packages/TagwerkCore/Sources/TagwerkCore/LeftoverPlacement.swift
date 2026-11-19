import Foundation

/// "In den nächsten freien Block" (#163): puts leftover tasks into the first free stretch that holds them, day by day,
/// without overlapping existing time or the blocks placed before. Pure rule; the caller creates the calendar blocks.
public enum LeftoverPlacement {
    /// One task to place. `minutes` is the block length, already computed with `blockMinutes(...)`.
    public struct Item: Sendable, Hashable {
        public var taskKey: String
        public var minutes: Int
        public var due: PlanDay?
        public var priority: Priority?

        public init(taskKey: String, minutes: Int, due: PlanDay?, priority: Priority?) {
            self.taskKey = taskKey
            self.minutes = minutes
            self.due = due
            self.priority = priority
        }
    }

    public struct Placed: Sendable, Hashable {
        public var taskKey: String
        public var day: PlanDay
        /// Minutes since midnight of `day`.
        public var range: Range<Int>
        /// The block lies after the due day because the days up to it were full.
        public var lateForDue: Bool
    }

    public struct Result: Sendable, Hashable {
        public var placed: [Placed]
        public var unplaced: [String]
    }

    /// Order of the work: earliest due first (none last), then priority (P1 first, none last), then the input order.
    /// A task with a due day takes only days up to and including it first; when none of them has room it takes the first
    /// free place after it and is marked `lateForDue`. Today starts at `nowMinutes`; days off hold nothing. A task that
    /// fits nowhere is `unplaced`.
    public static func place(tasks: [Item], days: [PlanInputDay], nowMinutes: Int?, today: PlanDay) -> Result {
        let ordered = tasks.enumerated().sorted { lhs, rhs in
            let (left, right) = (lhs.element, rhs.element)
            if left.due != right.due {
                switch (left.due, right.due) {
                case let (leftDue?, rightDue?): return leftDue < rightDue
                case (nil, _): return false
                case (_, nil): return true
                }
            }
            let leftPriority = left.priority?.rawValue ?? Int.max
            let rightPriority = right.priority?.rawValue ?? Int.max
            if leftPriority != rightPriority { return leftPriority < rightPriority }
            return lhs.offset < rhs.offset
        }.map(\.element)

        var sortedDays = days.sorted { $0.day < $1.day }
        var placed: [Placed] = []
        var unplaced: [String] = []
        for task in ordered {
            func slot(in index: Int) -> Range<Int>? {
                let day = sortedDays[index]
                guard let hours = day.hours, hours.minutes > 0 else { return nil }
                let from = day.day == today ? nowMinutes : nil
                guard let found = nextFreeSlot(day, after: hours.startMinutes, minutes: task.minutes, fromMinutes: from),
                      found.count >= task.minutes else { return nil }
                return found.lowerBound..<(found.lowerBound + task.minutes)
            }
            let indices = Array(sortedDays.indices)
            let withinDue = task.due.map { due in indices.filter { sortedDays[$0].day <= due } } ?? indices
            let afterDue = task.due == nil ? [] : indices.filter { !withinDue.contains($0) }
            var chosen: (index: Int, range: Range<Int>, late: Bool)?
            for index in withinDue { if let range = slot(in: index) { chosen = (index, range, false); break } }
            if chosen == nil {
                for index in afterDue { if let range = slot(in: index) { chosen = (index, range, true); break } }
            }
            guard let chosen else { unplaced.append(task.taskKey); continue }
            sortedDays[chosen.index].blocks.append(chosen.range)
            placed.append(Placed(taskKey: task.taskKey, day: sortedDays[chosen.index].day, range: chosen.range, lateForDue: chosen.late))
        }
        return Result(placed: placed, unplaced: unplaced)
    }
}
