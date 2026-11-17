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
