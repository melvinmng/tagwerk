import Foundation

/// Set arithmetic on stretches of time, shared by the effort measurement and the time per project.
enum DateIntervals {
    /// The intervals sorted, with those that touch or overlap joined. Intervals without length are dropped.
    static func merged(_ intervals: [DateInterval]) -> [DateInterval] {
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
    static func subtracting(_ removed: [DateInterval], from intervals: [DateInterval]) -> [DateInterval] {
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

    /// Seconds of `intervals` (merged, sorted) that lie inside `window`.
    static func seconds(of intervals: [DateInterval], within window: DateInterval) -> TimeInterval {
        intervals.reduce(0) { total, interval in
            let start = max(interval.start, window.start), end = min(interval.end, window.end)
            return end > start ? total + end.timeIntervalSince(start) : total
        }
    }
}
