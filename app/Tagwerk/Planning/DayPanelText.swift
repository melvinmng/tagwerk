import Foundation
import TagwerkCore

/// Texts of the day panel, list sections and AI button that depend on the shown day (plan-tomorrow, F3):
/// today, tomorrow or a later day. Whole sentences per case, so that translations can inflect them.
enum DayPanelText {
    enum Relation: Equatable {
        case today, tomorrow, later
    }

    /// Past days count as "today": the panel never offers to commit work to them.
    static func relation(of day: PlanDay, today: PlanDay, calendar: Calendar) -> Relation {
        if day <= today { return .today }
        return day == today.adding(days: 1, calendar: calendar) ? .tomorrow : .later
    }

    /// The row button that commits a task to the shown day.
    static func commitTitle(day: PlanDay, today: PlanDay, calendar: Calendar) -> String {
        switch relation(of: day, today: today, calendar: calendar) {
        case .today: String(localized: "Heute")
        case .tomorrow: String(localized: "Morgen")
        case .later: String(localized: "Einplanen")
        }
    }

    /// Section of tasks due on the shown day that are not committed to a day.
    static func dueSectionTitle(day: PlanDay, today: PlanDay, calendar: Calendar) -> String {
        switch relation(of: day, today: today, calendar: calendar) {
        case .today: String(localized: "Heute offen, nicht zugeordnet")
        case .tomorrow: String(localized: "Morgen fällig, nicht zugeordnet")
        case .later: String(localized: "An diesem Tag fällig, nicht zugeordnet")
        }
    }

    /// The bar after moving the lunch break: "Pause morgen 12:00–13:00" or "Morgen keine Pause".
    static func lunchLine(_ range: Range<Int>?, day: PlanDay, today: PlanDay, calendar: Calendar) -> String {
        let relation = relation(of: day, today: today, calendar: calendar)
        let weekday = DateText.shortWeekday(day, calendar: calendar)
        guard let range else {
            switch relation {
            case .today: return String(localized: "Heute keine Pause")
            case .tomorrow: return String(localized: "Morgen keine Pause")
            case .later: return String(localized: "\(weekday) keine Pause")
            }
        }
        let from = DateText.time(minutes: range.lowerBound, calendar: calendar)
        let to = DateText.time(minutes: range.upperBound, calendar: calendar)
        switch relation {
        case .today: return String(localized: "Pause heute \(from)–\(to)")
        case .tomorrow: return String(localized: "Pause morgen \(from)–\(to)")
        case .later: return String(localized: "Pause \(weekday) \(from)–\(to)")
        }
    }

    /// The AI button: "Morgen planen" (with the leftovers it takes along) on the day after today.
    static func planTitle(scope: PlanScope, day: PlanDay, today: PlanDay, leftCount: Int, calendar: Calendar) -> String {
        guard scope == .day, relation(of: day, today: today, calendar: calendar) == .tomorrow else {
            return AIPlanBar.planTitle(scope)
        }
        return leftCount > 0 ? String(localized: "Morgen planen mit \(leftCount) von heute") : String(localized: "Morgen planen")
    }

    /// The evening line on today's card: "Morgen planen", or "Mo. planen" when tomorrow is off.
    static func eveningTitle(day: PlanDay, today: PlanDay, calendar: Calendar) -> String {
        if relation(of: day, today: today, calendar: calendar) == .tomorrow { return String(localized: "Morgen planen") }
        let weekday = DateText.shortWeekday(day, calendar: calendar)
        return String(localized: "\(weekday) planen")
    }

    /// "Do. 19. Nov. · 3 h 15 frei · 2 von heute übrig" (date in the locale's format).
    static func eveningDetail(day: PlanDay, freeMinutes: Int, leftCount: Int, calendar: Calendar) -> String {
        let date = day.startDate(in: calendar)
            .formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated).day().month(.abbreviated))
        let free = String(localized: "\(CapacityText.duration(freeMinutes)) frei")
        guard leftCount > 0 else { return "\(date) · \(free)" }
        return "\(date) · \(free) · " + String(localized: "\(leftCount) von heute übrig")
    }

    /// The header button of "Von heute übrig".
    static func moveAllTitle(day: PlanDay, today: PlanDay, calendar: Calendar) -> String {
        relation(of: day, today: today, calendar: calendar) == .tomorrow
            ? String(localized: "Alle auf morgen") : String(localized: "Alle einplanen")
    }

    /// Footer of the due section in list mode.
    static func commitFooter(day: PlanDay, today: PlanDay, calendar: Calendar) -> String {
        switch relation(of: day, today: today, calendar: calendar) {
        case .today: String(localized: "„Heute“ legt die Aufgabe für heute fest; dann lässt sie sich ins Raster ziehen.")
        case .tomorrow: String(localized: "„Morgen“ legt die Aufgabe für morgen fest; dann lässt sie sich ins Raster ziehen.")
        case .later: String(localized: "„Einplanen“ legt die Aufgabe für diesen Tag fest; dann lässt sie sich ins Raster ziehen.")
        }
    }

    /// Shown in list mode when nothing is committed to the day yet.
    static func emptyPlannedHint(day: PlanDay, today: PlanDay, calendar: Calendar) -> String {
        switch relation(of: day, today: today, calendar: calendar) {
        case .today: String(localized: "Nutze „Heute“ unten oder „Einplanen“ im Menü einer Aufgabe.")
        case .tomorrow: String(localized: "Nutze „Morgen“ unten oder „Einplanen“ im Menü einer Aufgabe.")
        case .later: String(localized: "Nutze „Einplanen“ unten oder im Menü einer Aufgabe.")
        }
    }
}
