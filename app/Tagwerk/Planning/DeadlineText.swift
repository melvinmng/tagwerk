import Foundation
import TagwerkCore

/// Texts of the deadline card, the deadline marks in the timeline and the orphaned rows (plan deadline-marking, DL2/DV1).
struct DeadlineText {
    let calendar: Calendar

    /// "Stundenplan, 10:00" for a marked event (the mark "markiert" is `badge`), "Kalender Uni-Fristen" for a deadline
    /// calendar event, "P1" or "Epic" for tasks; the time follows when known.
    func detail(_ deadline: ImportantDeadline, calendarName: String?) -> String {
        let time = deadline.time.map { ", " + clock($0) } ?? ""
        switch deadline.kind {
        case .priorityOne: return "P1" + time
        case .epic: return String(localized: "Epic") + time
        case .deadlineCalendar:
            let name = calendarName.map { String(localized: "Kalender \($0)") } ?? String(localized: "Kalender")
            return name + time
        case .markedEvent: return (calendarName ?? String(localized: "Kalender")) + time
        }
    }

    /// The text mark of a marked event; deadlines of other kinds have none.
    func badge(_ deadline: ImportantDeadline) -> String? {
        deadline.kind == .markedEvent ? String(localized: "markiert") : nil
    }

    /// "Vorbereitung 6 h 30 · 3 Termine"; `nil` without upcoming linked events.
    func preparation(_ summary: PreparationSummary?) -> String? {
        guard let summary, summary.count > 0 else { return nil }
        return String(localized: "Vorbereitung \(CapacityText.duration(summary.minutes)) · \(String(localized: "\(summary.count) Termine"))")
    }

    /// "Klausur Statistik, Deadline, markiert, Stundenplan, 10:00, in 9 Tagen, Vorbereitung …" (text, not only colour).
    func accessibilityLabel(_ deadline: ImportantDeadline, calendarName: String?, today: PlanDay,
                            preparation summary: PreparationSummary?) -> String {
        var parts = [deadline.title, String(localized: "Deadline")]
        if let badge = badge(deadline) { parts.append(badge) }
        parts.append(detail(deadline, calendarName: calendarName))
        parts.append(relative(deadline.day, today: today))
        if let line = preparation(summary) { parts.append(line) }
        return parts.joined(separator: ", ")
    }

    func relative(_ day: PlanDay, today: PlanDay) -> String {
        let days = calendar.dateComponents([.day], from: today.startDate(in: calendar), to: day.startDate(in: calendar)).day ?? 0
        switch days {
        case ..<0: return String(localized: "überfällig")
        case 0: return String(localized: "heute")
        case 1: return String(localized: "morgen")
        default: return String(localized: "in \(days) Tagen")
        }
    }

    /// "Stundenplan · nicht mehr am Fr., 27.11., 10:00" (a candidate exists) or
    /// "Stundenplan · nicht mehr im Kalender (zuletzt Fr., 27.11., 10:00)".
    func orphan(_ orphan: OrphanedMark, calendarName: String?) -> String {
        let name = calendarName ?? String(localized: "Kalender")
        let when = moment(orphan.start, isAllDay: orphan.isAllDay)
        if orphan.candidate != nil { return String(localized: "\(name) · nicht mehr am \(when)") }
        return String(localized: "\(name) · nicht mehr im Kalender (zuletzt \(when))")
    }

    /// "Mo., 30.11., 10:00 übernehmen".
    func adopt(_ candidate: CalendarEvent) -> String {
        String(localized: "\(moment(candidate.start, isAllDay: candidate.isAllDay)) übernehmen")
    }

    /// "→ Klausur Statistik · in 8 Tagen" at an event that prepares for a deadline.
    func preparationMark(_ target: PreparationTarget, today: PlanDay) -> String {
        let day = PlanDay(date: target.until, calendar: calendar)
        return "→ " + target.title + " · " + relative(day, today: today)
    }

    /// The suffix of a deadline event in the timeline.
    func timelineMark(isMarked: Bool) -> String {
        isMarked ? String(localized: "Deadline, markiert") : String(localized: "Deadline")
    }

    /// "Fr., 27.11., 10:00", or the date alone for all-day events.
    func moment(_ date: Date, isAllDay: Bool) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.twoDigits)
        style.timeZone = calendar.timeZone
        let day = date.formatted(style)
        return isAllDay ? day : day + ", " + clock(date)
    }

    private func clock(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
}
