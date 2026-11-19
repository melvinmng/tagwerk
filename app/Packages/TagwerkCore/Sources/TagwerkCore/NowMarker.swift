import Foundation

/// Rules for the "now" marker in the day views: where the current time sits in the hour grid and in the row list.
public enum NowMarker {
    /// Minutes since midnight of `now` (wall clock) when `day` is today, otherwise nil.
    public static func minutes(now: Date, day: PlanDay, calendar: Calendar) -> Int? {
        guard PlanDay(date: now, calendar: calendar) == day else { return nil }
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Position in the shown grid range; nil outside it.
    public static func position(nowMinutes: Int, shown: Range<Int>) -> Int? {
        shown.contains(nowMinutes) ? nowMinutes : nil
    }

    /// Index in a time-ordered row list before which the "Jetzt" line goes: before the first row that starts
    /// after now. A row that is running now (or has ended) keeps the line after it.
    public static func insertionIndex(rowStarts: [Int], nowMinutes: Int) -> Int {
        rowStarts.firstIndex { $0 > nowMinutes } ?? rowStarts.count
    }

    /// Content offset that puts `nowMinutes` at a third of the visible height (scroll on opening); never negative.
    /// `canvasTop` is the top of the grid inside the scroll content, `inset` the grid's top inset.
    public static func scrollTarget(nowMinutes: Int, shown: Range<Int>, hourHeight: Double, inset: Double,
                                    canvasTop: Double, viewportHeight: Double) -> Double {
        let nowY = canvasTop + inset + Double(nowMinutes - shown.lowerBound) / 60 * hourHeight
        return max(0, nowY - viewportHeight / 3)
    }
}
