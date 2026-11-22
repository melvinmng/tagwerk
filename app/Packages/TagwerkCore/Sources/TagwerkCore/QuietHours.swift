import Foundation

/// A daily window in which Tagwerk keeps task and deadline notifications back (plan quiet-hours, #169).
/// The window may cross midnight. The start is inclusive, the end exclusive; equal values mean no window.
/// Edges count at minute resolution, so 06:59:59 is still inside a window that ends at 07:00.
public struct QuietHours: Equatable, Hashable, Sendable {
    public static let minutesPerDay = 1440

    /// Minutes after local midnight, 0 ..< 1440.
    public let startMinutes: Int
    public let endMinutes: Int

    public init(startMinutes: Int, endMinutes: Int) {
        self.startMinutes = Self.normalized(startMinutes)
        self.endMinutes = Self.normalized(endMinutes)
    }

    private static func normalized(_ minutes: Int) -> Int {
        ((minutes % minutesPerDay) + minutesPerDay) % minutesPerDay
    }

    /// No window at all: start equals end.
    public var isEmpty: Bool { startMinutes == endMinutes }

    /// The window as fractions of the day for a 24-hour bar: one part, or two when it crosses midnight (the part after
    /// midnight is left out when the window ends exactly at midnight); none for an empty window.
    public var dayFractions: [ClosedRange<Double>] {
        guard !isEmpty else { return [] }
        let day = Double(Self.minutesPerDay)
        let start = Double(startMinutes) / day
        let end = Double(endMinutes) / day
        if startMinutes < endMinutes { return [start...end] }
        return endMinutes == 0 ? [start...1.0] : [start...1.0, 0.0...end]
    }

    /// Whether a wall-clock time lies inside the window.
    public func contains(minutes: Int) -> Bool {
        guard !isEmpty else { return false }
        let minutes = Self.normalized(minutes)
        if startMinutes < endMinutes { return minutes >= startMinutes && minutes < endMinutes }
        return minutes >= startMinutes || minutes < endMinutes
    }

    /// Whether `date` lies inside the window, by the wall clock of `calendar`.
    public func contains(_ date: Date, calendar: Calendar) -> Bool {
        contains(minutes: RoutineSchedule.minutesOfDay(date, calendar: calendar))
    }

    /// The first window end after `date`, whether or not `date` lies inside the window; `nil` without a window.
    /// Found through the calendar, so a daylight saving change neither adds nor removes an hour: an end inside the
    /// skipped hour becomes the next valid time, an end inside the repeated hour is the first occurrence.
    public func nextEnd(after date: Date, calendar: Calendar) -> Date? {
        guard !isEmpty else { return nil }
        let components = DateComponents(hour: endMinutes / 60, minute: endMinutes % 60, second: 0)
        return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime, repeatedTimePolicy: .first,
                                 direction: .forward)
    }

    /// `date` itself outside the window, otherwise the end of the window it lies in.
    public func shifted(_ date: Date, calendar: Calendar) -> Date {
        guard contains(date, calendar: calendar) else { return date }
        return nextEnd(after: date, calendar: calendar) ?? date
    }

    /// The window the settings describe: the start follows the target bedtime while coupled to it; `nil` when
    /// switched off or empty.
    public static func resolved(enabled: Bool, startsAtBedtime: Bool, bedtimeMinutes: Int, startMinutes: Int,
                                endMinutes: Int) -> QuietHours? {
        guard enabled else { return nil }
        let window = QuietHours(startMinutes: startsAtBedtime ? bedtimeMinutes : startMinutes, endMinutes: endMinutes)
        return window.isEmpty ? nil : window
    }
}
