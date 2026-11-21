import Foundation

/// Rounds minutes to the nearest `step` (time blocks move and resize in 15-minute steps).
public func snapped(minutes: Int, step: Int = 15) -> Int {
    Int((Double(minutes) / Double(step)).rounded()) * step
}

/// A block of `duration` minutes (at least 15) starting at `startMinutes`, kept inside the day.
public func clampedBlock(startMinutes: Int, duration: Int, dayLength: Int) -> Range<Int> {
    let length = min(max(15, duration), dayLength)
    let start = min(max(0, startMinutes), dayLength - length)
    return start..<(start + length)
}

/// Free stretches within the working hours, after `from` when given, around busy time widened by
/// `buffer` and the lunch break; stretches shorter than `minimum` are left out.
public func freeGaps(hours: WorkHours, busy: [Range<Int>], lunch: Range<Int>?, buffer: Int, from: Int?,
                     minimum: Int = 15) -> [Range<Int>] {
    let start = max(hours.startMinutes, from ?? hours.startMinutes)
    guard start < hours.endMinutes else { return [] }
    var blocked = busy.map { ($0.lowerBound - buffer)..<($0.upperBound + buffer) }
    if let lunch { blocked.append(lunch) }
    var gaps: [Range<Int>] = []
    var cursor = start
    for range in blocked.sorted(by: { $0.lowerBound < $1.lowerBound }) {
        if range.lowerBound > cursor {
            gaps.append(cursor..<min(range.lowerBound, hours.endMinutes))
        }
        cursor = max(cursor, range.upperBound)
        if cursor >= hours.endMinutes { break }
    }
    if cursor < hours.endMinutes { gaps.append(cursor..<hours.endMinutes) }
    return gaps.filter { $0.count >= minimum }
}

/// Column index for each interval so that overlapping intervals sit side by side (hour grid).
public func columns(for intervals: [Range<Int>]) -> [Int] {
    var columnEnds: [Int] = []
    var result = Array(repeating: 0, count: intervals.count)
    for index in intervals.indices.sorted(by: { intervals[$0].lowerBound < intervals[$1].lowerBound }) {
        let interval = intervals[index]
        if let free = columnEnds.firstIndex(where: { $0 <= interval.lowerBound }) {
            result[index] = free
            columnEnds[free] = interval.upperBound
        } else {
            result[index] = columnEnds.count
            columnEnds.append(interval.upperBound)
        }
    }
    return result
}

/// Indices grouped by overlap, directly or through others, each group in start order; single entries are groups of one.
/// The groups run from the early to the late one. Intervals that only touch (one ends when the next starts) do not overlap.
public func overlapGroups(for intervals: [Range<Int>]) -> [[Int]] {
    var groups: [[Int]] = []
    var groupEnd = Int.min
    for index in intervals.indices.sorted(by: { (intervals[$0].lowerBound, $0) < (intervals[$1].lowerBound, $1) }) {
        let interval = intervals[index]
        if !groups.isEmpty, interval.lowerBound < groupEnd {
            groups[groups.count - 1].append(index)
            groupEnd = max(groupEnd, interval.upperBound)
        } else {
            groups.append([index])
            groupEnd = interval.upperBound
        }
    }
    return groups
}

/// When the hour grid gives up its side-by-side columns for one block (BF1c).
public enum GridCollapse {
    /// A group becomes one block when it needs more than one column and a column would be narrower than the minimum.
    public static func collapses(columnCount: Int, availableWidth: Double, minimumColumnWidth: Double) -> Bool {
        columnCount > 1 && availableWidth / Double(columnCount) < minimumColumnWidth
    }
}

