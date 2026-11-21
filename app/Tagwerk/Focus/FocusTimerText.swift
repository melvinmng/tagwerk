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
}
