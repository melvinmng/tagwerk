import Foundation
import TagwerkCore

/// Texts of the focus timer screens. Pure, so they can be tested.
enum FocusTimerText {
    /// "24:10", or "1:05:00" from one hour on.
    static func clock(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600, minutes = total % 3600 / 60, rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%02d:%02d", minutes, rest)
    }

    /// For VoiceOver: "24 Minuten, 10 Sekunden".
    static func spoken(_ seconds: Int) -> String {
        Duration.seconds(max(0, seconds)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }

    static func phaseName(_ phase: FocusPhase) -> String {
        switch phase {
        case .work: String(localized: "Fokus")
        case .shortBreak: String(localized: "Kurze Pause")
        case .longBreak: String(localized: "Lange Pause")
        case .finished: String(localized: "Geschafft")
        }
    }

    /// "Runde 2 von 4"; `nil` without Pomodoro and when the timer is finished.
    static func roundText(phase: FocusPhase, settings: FocusTimerSettings) -> String? {
        guard settings.isPomodoro else { return nil }
        switch phase {
        case .work(let round), .shortBreak(let round): return String(localized: "Runde \(round) von \(settings.rounds)")
        case .longBreak: return String(localized: "Runde \(settings.rounds) von \(settings.rounds)")
        case .finished: return nil
        }
    }

    /// "42 Minuten Fokus" for a finished session.
    static func focusedText(seconds: Int) -> String {
        let minutes = seconds / 60
        return String(localized: "\(minutes) min Fokus")
    }

    /// Summary line of the collection: "7 Bausteine", "7 Bausteine · 2 vorzeitig beendet", "Noch leer".
    static func collectionSummary(_ summary: FocusCollectionSummary) -> String {
        if summary.total == 0 { return String(localized: "Noch leer") }
        let bricks = String(localized: "\(summary.total) Bausteine")
        guard summary.endedEarly > 0 else { return bricks }
        let endedEarly = String(localized: "\(summary.endedEarly) vorzeitig beendet")
        return "\(bricks) · \(endedEarly)"
    }

    /// "bis 14:51" (EN "until 2:51 PM"); `nil` while paused.
    static func endsAt(_ phaseEnd: Date?, calendar: Calendar, locale: Locale = .current) -> String? {
        guard let phaseEnd else { return nil }
        let time = phaseEnd.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar,
                                                       timeZone: calendar.timeZone))
        return String(localized: "bis \(time)")
    }

    /// "Fokus · Runde 1 von 4", "Fokus" without Pomodoro.
    static func phaseLine(phase: FocusPhase, settings: FocusTimerSettings) -> String {
        [phaseName(phase), roundText(phase: phase, settings: settings)].compactMap { $0 }.joined(separator: " · ")
    }

    /// "18 min bleiben als Fokuszeit für „Bericht schreiben“ gespeichert." / "… als Fokuszeit gespeichert." without a task.
    static func stopMessage(focusedSeconds: Int, title: String) -> String {
        let minutes = focusedSeconds / 60
        if title.isEmpty { return String(localized: "\(minutes) min bleiben als Fokuszeit gespeichert.") }
        return String(localized: "\(minutes) min bleiben als Fokuszeit für „\(title)“ gespeichert.")
    }

    /// "Woche ab 16. Nov. · 4 h 35 min Fokus".
    static func weekHeader(start: Date, focusedMinutes: Int) -> String {
        let date = start.formatted(.dateTime.day().month())
        return String(localized: "Woche ab \(date) · \(IntakeFormat.duration(minutes: focusedMinutes)) Fokus")
    }

    /// Weekday names in the order of the calendar's week: short ("Mo") and long ("Montag").
    static func weekdayNames(calendar: Calendar) -> (short: [String], long: [String]) {
        let first = calendar.firstWeekday - 1
        let short = calendar.shortStandaloneWeekdaySymbols, long = calendar.standaloneWeekdaySymbols
        let order = (0..<7).map { (first + $0) % 7 }
        return (order.map { short[$0].trimmingCharacters(in: CharacterSet(charactersIn: ".")) }, order.map { long[$0] })
    }

    /// For VoiceOver, one element per weekday: "Montag: 2 Bausteine, 50 Minuten Fokus, 1 vorzeitig beendet".
    static func dayAccessibility(weekday: String, bricks: [FocusBrick]) -> String {
        guard !bricks.isEmpty else { return String(localized: "\(weekday): keine Bausteine") }
        let count = String(localized: "\(bricks.count) Bausteine")
        let minutes = IntakeFormat.spokenDuration(minutes: bricks.reduce(0) { $0 + $1.focusedMinutes })
        let endedEarly = bricks.filter(\.piece.isEndedEarly).count
        var text = "\(weekday): \(count), \(minutes) \(String(localized: "Fokus"))"
        if endedEarly > 0 { text += ", \(String(localized: "\(endedEarly) vorzeitig beendet"))" }
        return text
    }

    /// "Fokus starten · 25 min" with the planned minutes, "Fokus starten" without, "Fokus öffnen" while a session runs.
    static func startTitle(plannedMinutes: Int?, isRunning: Bool) -> String {
        if isRunning { return String(localized: "Fokus öffnen") }
        guard let plannedMinutes else { return String(localized: "Fokus starten") }
        return String(localized: "Fokus starten · \(plannedMinutes) min")
    }

    /// "4 × 25 / 5": rounds, work minutes and short break minutes of a Pomodoro session.
    static func pomodoroSummary(_ settings: FocusTimerSettings) -> String {
        String(localized: "\(settings.rounds) × \(settings.workMinutes) / \(settings.shortBreakMinutes)")
    }

    /// The value of the settings row: "25 min · Pomodoro aus", or "4 × 25 / 5" with Pomodoro.
    static func settingsSummary(_ settings: FocusTimerSettings) -> String {
        settings.isPomodoro ? pomodoroSummary(settings) : String(localized: "\(settings.workMinutes) min · Pomodoro aus")
    }

    /// "Bericht schreiben, noch 18 Minuten 42 Sekunden, Fokus" for VoiceOver; without a title "noch 18 Minuten, Fokus".
    static func barAccessibility(title: String, remainingSeconds: Int, phase: FocusPhase) -> String {
        let remaining = String(localized: "noch \(spoken(remainingSeconds))")
        let parts = [title.isEmpty ? nil : title, remaining, phaseName(phase)].compactMap { $0 }
        return parts.joined(separator: ", ")
    }
}
