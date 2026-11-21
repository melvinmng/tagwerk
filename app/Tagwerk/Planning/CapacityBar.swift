import SwiftUI
import TagwerkCore

/// Planned load against available time (mockups a/b): filled part = planned, red when overbooked.
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
