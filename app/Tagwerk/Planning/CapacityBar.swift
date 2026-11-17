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
        if capacity.isDayOff && capacity.plannedMinutes == 0 { return "kein Arbeitstag" }
        if capacity.isOverbooked { return "\(duration(-capacity.freeMinutes)) zu viel" }
        return "\(duration(capacity.freeMinutes)) frei von \(duration(capacity.availableMinutes))"
    }

    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) min"
        case (_, 0): return "\(hours) h"
        default: return "\(hours) h \(rest)"
        }
    }
}
