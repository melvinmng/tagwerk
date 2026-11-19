import Foundation
import SwiftUI
import TagwerkCore

/// Texts of the search sheet: section headers, footers and the lines of the rows.
enum SearchTexts {
    // MARK: Sections

    static func header(_ kind: SearchSectionKind, count: Int?) -> String {
        guard let count else {
            switch kind {
            case .upcomingEvents: return String(localized: "Termine")
            case .openTasks: return String(localized: "Aufgaben")
            case .completedTasks: return String(localized: "Erledigt")
            case .online: return String(localized: "GitHub · online")
            case .pastEvents: return String(localized: "Vergangene Termine")
            case .notes: return String(localized: "Notizen")
            case .shopping: return String(localized: "Einkaufsliste")
            }
        }
        switch kind {
        case .upcomingEvents: return String(localized: "Termine · \(count) kommende")
        case .openTasks: return String(localized: "Aufgaben · \(count) offen")
        case .completedTasks: return String(localized: "Erledigt · \(count)")
        case .online: return String(localized: "GitHub · online · \(count) weitere")
        case .pastEvents: return String(localized: "Vergangene Termine · \(count)")
        case .notes: return String(localized: "Notizen · \(count)")
        case .shopping: return String(localized: "Einkaufsliste · \(count)")
        }
    }

    /// The spoken header: the counter is part of the label.
    static func headerAccessibility(_ kind: SearchSectionKind, count: Int?) -> String {
        guard let count else { return header(kind, count: nil) }
        switch kind {
        case .upcomingEvents: return String(localized: "Termine, \(count) kommende")
        case .openTasks: return String(localized: "Aufgaben, \(count) offen")
        case .completedTasks: return String(localized: "Erledigt, \(count)")
        case .online: return String(localized: "GitHub online, \(count) weitere")
        case .pastEvents: return String(localized: "Vergangene Termine, \(count)")
        case .notes: return String(localized: "Notizen, \(count)")
        case .shopping: return String(localized: "Einkaufsliste, \(count)")
        }
    }

    // MARK: Footer and window

    static func footer(windowStart: Date, isExtended: Bool, calendar: Calendar) -> String {
        guard isExtended else { return String(localized: "Durchsucht: 6 Monate zurück, 12 Monate voraus.") }
        return String(localized: "Durchsucht: ab \(monthAndYear(windowStart, calendar: calendar)), 12 Monate voraus.")
    }

    static func olderEventsRow(before start: Date, calendar: Calendar) -> String {
        let before = String(localized: "vor \(monthAndYear(start, calendar: calendar))")
        return "\(String(localized: "Ältere Termine durchsuchen")) · \(before)"
    }

    private static func monthAndYear(_ date: Date, calendar: Calendar) -> String {
        date.formatted(Date.FormatStyle(locale: .current, calendar: calendar, timeZone: calendar.timeZone).month(.wide).year())
    }

    // MARK: Event rows

    /// "Fr. 27.11."; with the year when the event is not in the current year.
    static func eventDate(_ event: CalendarEvent, now: Date, calendar: Calendar) -> String {
        let day = PlanDay(date: event.start, calendar: calendar)
        let weekday = DateText.shortWeekday(day, calendar: calendar)
        let sameYear = calendar.component(.year, from: event.start) == calendar.component(.year, from: now)
        let date = sameYear ? DateText.numericDay(day, calendar: calendar) : DateText.numericDate(day, calendar: calendar)
        return "\(weekday) \(date)"
    }

    static func eventTime(_ event: CalendarEvent, calendar: Calendar) -> String {
        event.isAllDay ? String(localized: "ganztägig") : DateText.time(event.start, calendar: calendar)
    }

    /// "gestern" or "vor 2 Tagen" for an event that began up to seven days ago; otherwise `nil`.
    static func agoText(_ event: CalendarEvent, now: Date, calendar: Calendar) -> String? {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: event.start), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case 1: return String(localized: "gestern")
        case 2...7: return String(localized: "vor \(days) Tagen")
        default: return nil
        }
    }

    /// "↻ wöchentlich · 9 weitere bis Februar"; the rhythm only when it is known.
    static func seriesText(_ row: EventRow, calendar: Calendar) -> String? {
        guard row.moreOccurrences > 0, let last = row.lastOccurrence else { return nil }
        let month = last.formatted(Date.FormatStyle(locale: .current, calendar: calendar, timeZone: calendar.timeZone).month(.wide))
        let more = String(localized: "\(row.moreOccurrences) weitere bis \(month)")
        guard let rhythm = row.rhythm else { return "↻ · \(more)" }
        return "↻ \(rhythmText(rhythm)) · \(more)"
    }

    private static func rhythmText(_ rhythm: SeriesRhythm) -> String {
        switch rhythm {
        case .daily: String(localized: "täglich")
        case .weekly: String(localized: "wöchentlich")
        case .biweekly: String(localized: "alle 2 Wochen")
        case .monthly: String(localized: "monatlich")
        }
    }

    // MARK: Task rows

    /// "erledigt 12.11. · To Do · 2 weitere". With `now`, a date outside the current year carries its year.
    static func completedText(_ group: CompletedGroup, calendar: Calendar, now: Date? = nil) -> String {
        let task = group.latest
        var text: String
        if let date = task.completedAt {
            let day = PlanDay(date: date, calendar: calendar)
            let sameYear = now.map { calendar.component(.year, from: date) == calendar.component(.year, from: $0) } ?? true
            let formatted = sameYear ? DateText.numericDay(day, calendar: calendar) : DateText.numericDate(day, calendar: calendar)
            text = String(localized: "erledigt \(formatted) · \(task.item.container.name)")
        } else {
            text = String(localized: "erledigt · \(task.item.container.name)")
        }
        if group.moreCount > 0 { text += " · " + String(localized: "\(group.moreCount) weitere") }
        return text
    }

    /// Name of the field a snippet comes from ("Notiz: …").
    static func snippetLabel(_ field: SearchField) -> String {
        switch field {
        case .title: String(localized: "Titel")
        case .notes: String(localized: "Notiz")
        case .location: String(localized: "Ort")
        case .calendar: String(localized: "Kalender")
        case .container: String(localized: "Liste")
        case .project: String(localized: "Project")
        case .label: String(localized: "Label")
        case .issueNumber: String(localized: "Nummer")
        case .kind: String(localized: "Art")
        case .quantity: String(localized: "Menge")
        }
    }

    // MARK: Highlighting

    /// The text with the found passages marked: yellow background and bold, so the mark does not rely on color alone.
    static func highlighted(_ text: String, ranges: [Range<String.Index>]) -> AttributedString {
        var attributed = AttributedString(text)
        for range in ranges {
            guard let target = Range(range, in: attributed) else { continue }
            attributed[target].backgroundColor = Color.yellow.opacity(0.4)
            attributed[target].inlinePresentationIntent = .stronglyEmphasized
        }
        return attributed
    }
}
