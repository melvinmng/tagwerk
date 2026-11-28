import SwiftUI
import TagwerkCore

/// Time blocks against available time (mockups a/b): filled part = time blocks, red when overbooked. Tasks without a
/// time block take no free time and do not fill the bar.
struct CapacityBar: View {
    let capacity: DayCapacity

    var body: some View {
        GeometryReader { proxy in
            let ratio = capacity.availableMinutes > 0
                ? min(1, Double(capacity.plannedMinutes) / Double(capacity.availableMinutes))
                : (capacity.plannedMinutes > 0 ? 1 : 0)
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(capacity.isOverbooked ? Color.red : Color.green)
                    .frame(width: proxy.size.width * ratio)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

enum CapacityText {
    /// "2 h 15 frei von 5 h", "45 min zu viel", "frei".
    static func summary(_ capacity: DayCapacity) -> String {
        if capacity.isDayOff && capacity.plannedMinutes == 0 { return String(localized: "kein Arbeitstag") }
        if capacity.isOverbooked { return String(localized: "\(duration(-capacity.freeMinutes)) zu viel") }
        return String(localized: "\(duration(capacity.freeMinutes)) frei von \(duration(capacity.availableMinutes))")
    }

    /// What the number counts, as one line: "9:00–18:00 · 1 h Pause · 2 h 20 Termine · 30 min Fahrzeit · 3 h 50 eingeplant".
    /// Only the parts that occur on the day are named; effort that recurring tasks merely reserve is no part of it.
    /// `nil` on a day off. `clock` formats minutes since midnight as a time of day.
    static func explanation(_ capacity: DayCapacity, hours: WorkHours?, clock: (Int) -> String) -> String? {
        guard !capacity.isDayOff, let hours else { return nil }
        let parts = capacity.breakdown
        var line = ["\(clock(hours.startMinutes))–\(clock(hours.endMinutes))"]
        if parts.lunchMinutes > 0 { line.append(String(localized: "\(duration(parts.lunchMinutes)) Pause")) }
        if parts.eventMinutes > 0 { line.append(String(localized: "\(duration(parts.eventMinutes)) Termine")) }
        if parts.travelMinutes > 0 { line.append(String(localized: "\(duration(parts.travelMinutes)) Fahrzeit")) }
        if capacity.plannedMinutes > 0 { line.append(String(localized: "\(duration(capacity.plannedMinutes)) eingeplant")) }
        return line.joined(separator: " · ")
    }

    /// Hint line under the explanation: the tasks of the day without a time block, their effort and whether they fit into
    /// the free time ("noch frei" today). They use no free time; `nil` without such tasks. A day off names only the effort.
    static func untimedHint(_ capacity: DayCapacity) -> String? {
        let count = capacity.untimedCount
        guard count > 0 else { return nil }
        let effort = duration(capacity.untimedMinutes)
        if capacity.isDayOff { return String(localized: "\(count) Aufgabe(n) ohne Uhrzeit · \(effort)") }
        let over = duration(capacity.untimedOverflowMinutes)
        switch (capacity.remainingMinutes != nil, capacity.untimedOverflowMinutes > 0) {
        case (false, false): return String(localized: "\(count) Aufgabe(n) ohne Uhrzeit · \(effort) – passt in die freie Zeit")
        case (true, false): return String(localized: "\(count) Aufgabe(n) ohne Uhrzeit · \(effort) – passt in die noch freie Zeit")
        case (false, true): return String(localized: "\(count) Aufgabe(n) ohne Uhrzeit · \(effort) – \(over) mehr als frei")
        case (true, true): return String(localized: "\(count) Aufgabe(n) ohne Uhrzeit · \(effort) – \(over) mehr als noch frei")
        }
    }

    /// Extra line of the hint: how many of the tasks without a time block have no effort and count with the default
    /// duration. `nil` when there are none.
    static func estimateNote(_ capacity: DayCapacity) -> String? {
        guard capacity.untimedCount > 0, capacity.estimatedCount > 0 else { return nil }
        return String(localized: "\(capacity.estimatedCount) davon ohne Aufwand mit Standarddauer gerechnet")
    }

    /// Short form of the hint for week, page preview and month: "3 h ohne Uhrzeit", or "7 h 30 ohne Uhrzeit (50 min zu
    /// viel)" when the tasks exceed the free time. `nil` without tasks that have no time block.
    static func untimedCompact(_ capacity: DayCapacity) -> String? {
        guard capacity.untimedCount > 0 else { return nil }
        let effort = duration(capacity.untimedMinutes)
        guard capacity.untimedOverflowMinutes > 0 else { return String(localized: "\(effort) ohne Uhrzeit") }
        return String(localized: "\(effort) ohne Uhrzeit (\(duration(capacity.untimedOverflowMinutes)) zu viel)")
    }

    /// `summary` with the short hint appended: "6 h 40 frei von 6 h 40 · 3 h ohne Uhrzeit".
    static func summaryWithUntimed(_ capacity: DayCapacity) -> String {
        [summary(capacity), untimedCompact(capacity)].compactMap { $0 }.joined(separator: " · ")
    }

    /// Whether the day is shown in red: time blocks overbook it, or the tasks without a time block exceed the free time.
    static func isOverloaded(_ capacity: DayCapacity) -> Bool {
        capacity.isOverbooked || capacity.untimedOverflowMinutes > 0
    }

    /// Today: "1 h 10 noch frei" or "30 min zu viel", from now on.
    static func remaining(_ capacity: DayCapacity) -> String {
        guard let remaining = capacity.remainingMinutes else { return summary(capacity) }
        if capacity.isDayOff && capacity.plannedMinutes == 0 { return String(localized: "kein Arbeitstag") }
        return remaining < 0 ? String(localized: "\(duration(-remaining)) zu viel")
            : String(localized: "\(duration(remaining)) noch frei")
    }

    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return String(localized: "\(rest) min")
        case (_, 0): return String(localized: "\(hours) h")
        default: return String(localized: "\(hours) h \(String(format: "%02d", rest))")
        }
    }
}
