import Foundation
import SwiftUI
import TagwerkCore

/// Which sources the overview shows.
enum ProjectSourceFilter: String, CaseIterable, Identifiable {
    case all, gitHub, reminders, local
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .all: "Alle"
        case .gitHub: "GitHub"
        case .reminders: "Erinnerungen"
        case .local: "Lokal"
        }
    }

    func includes(_ kind: ProjectProgressReference.Kind) -> Bool {
        switch self {
        case .all: true
        case .gitHub: kind == .gitHubProject || kind == .gitHubRepository
        case .reminders: kind == .remindersList
        case .local: kind == .local
        }
    }
}

/// The choice of the period picker; "Frei" takes its days from the two date pickers.
enum ProjectPeriodChoice: String, CaseIterable, Identifiable {
    case fourWeeks, threeMonths, oneYear, custom
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .fourWeeks: "4 Wochen"
        case .threeMonths: "3 Monate"
        case .oneYear: "1 Jahr"
        case .custom: "Frei"
        }
    }

    /// The sentence part "in den letzten 4 Wochen"; a free range names its days.
    func periodName(range: ProjectRange, calendar: Calendar) -> String {
        switch self {
        case .fourWeeks: String(localized: "in den letzten 4 Wochen")
        case .threeMonths: String(localized: "in den letzten 3 Monaten")
        case .oneYear: String(localized: "im letzten Jahr")
        case .custom:
            String(localized: "vom \(DateText.numericDate(PlanDay(date: range.start, calendar: calendar), calendar: calendar)) bis \(DateText.numericDate(PlanDay(date: range.end.addingTimeInterval(-1), calendar: calendar), calendar: calendar))")
        }
    }
}

/// The wording of the project progress. Pure functions of the numbers, so the sentences are tested without a view.
enum ProjectProgressTexts {
    static func sourceLabel(_ kind: ProjectProgressReference.Kind) -> String {
        switch kind {
        case .gitHubProject: String(localized: "GitHub-Projekt")
        case .gitHubRepository: String(localized: "GitHub-Repository")
        case .remindersList: String(localized: "Erinnerungsliste")
        case .local: String(localized: "Lokal")
        }
    }

    static func sourceSymbol(_ kind: ProjectProgressReference.Kind) -> String {
        switch kind {
        case .gitHubProject: "rectangle.3.group"
        case .gitHubRepository: "shippingbox"
        case .remindersList: "checklist"
        case .local: "iphone"
        }
    }

    static func trendText(_ trend: ProjectTrend) -> String {
        switch trend {
        case .empty: String(localized: "noch leer")
        case .finished: String(localized: "abgeschlossen")
        case .resting(let days): String(localized: "ruht seit \(days) Tagen")
        case .advancing: String(localized: "geht voran")
        case .growingBacklog: String(localized: "Rückstand wächst")
        case .steady: String(localized: "gleichbleibend")
        }
    }

    static func trendSymbol(_ trend: ProjectTrend) -> String {
        switch trend {
        case .empty: "tray"
        case .finished: "checkmark.circle"
        case .resting: "pause.circle"
        case .advancing: "arrow.up.right"
        case .growingBacklog: "arrow.down.right"
        case .steady: "arrow.right"
        }
    }

    static func isResting(_ trend: ProjectTrend) -> Bool {
        if case .resting = trend { true } else { false }
    }

    /// "12 offen · 34 erledigt".
    static func countsText(_ summary: ProjectSummary) -> String {
        String(localized: "\(summary.open) offen · \(summary.completed) erledigt")
    }

    /// "Heute", "Gestern", "Vor 3 Tagen"; "Noch keine Bewegung" when no date is known.
    static func movementText(_ date: Date?, now: Date, calendar: Calendar) -> String {
        guard let date else { return String(localized: "Keine Bewegung bekannt") }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ...0: return String(localized: "Zuletzt bewegt: heute")
        case 1: return String(localized: "Zuletzt bewegt: gestern")
        default: return String(localized: "Zuletzt bewegt: vor \(days) Tagen")
        }
    }

    /// "In den letzten 4 Wochen: 9 erledigt, 5 neu."
    static func periodSentence(_ summary: ProjectSummary, periodName: String) -> String {
        let sentence = String(localized: "\(summary.periodCompleted) erledigt, \(summary.periodCreated) neu \(periodName).")
        return sentence
    }

    /// The text VoiceOver reads for the weekly chart: one sentence per week, and what the open stock did.
    static func chartSummary(_ buckets: [ProjectWeekBucket], calendar: Calendar) -> String {
        guard let first = buckets.first, let last = buckets.last else { return String(localized: "Keine Daten") }
        let weeks = buckets.map { bucket in
            let day = DateText.numericDay(PlanDay(date: bucket.start, calendar: calendar), calendar: calendar)
            return String(localized: "Woche ab \(day): \(bucket.completed) erledigt, \(bucket.created) neu, \(bucket.openAtEnd) offen am Ende")
        }
        let start = first.openAtEnd, end = last.openAtEnd
        let stock = start == end
            ? String(localized: "Der offene Bestand blieb bei \(end).")
            : String(localized: "Der offene Bestand ging von \(start) auf \(end).")
        return weeks.joined(separator: ". ") + ". " + stock
    }

    // MARK: Time

    /// "18 h 30 min", "2 h", "45 min"; whole minutes.
    static func durationText(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return String(localized: "\(rest) min") }
        return rest == 0 ? String(localized: "\(hours) h") : String(localized: "\(hours) h \(rest) min")
    }

    /// The value of "Eingeplant": the time, or a dash when no block lies in the period (nothing planned is not "0 h"), or the reason
    /// when the calendar cannot be read.
    static func plannedText(_ time: ProjectTimeSummary) -> String {
        if !time.calendarAvailable { return String(localized: "Kein Kalenderzugriff") }
        return time.hasPlanned ? durationText(time.plannedSeconds) : "–"
    }

    /// The value of "Investiert": the time, or a dash when nothing was measured.
    static func investedText(_ time: ProjectTimeSummary) -> String {
        time.hasInvested ? durationText(time.investedSeconds) : "–"
    }

    /// The value of "Offene Schätzungen": "7 h 30 min · 3 mit, 2 ohne Schätzung".
    static func estimateText(_ estimate: ProjectOpenEstimate) -> String {
        guard estimate.openCount > 0 else { return "–" }
        guard estimate.estimatedCount > 0 else { return String(localized: "Keine Schätzungen") }
        let time = durationText(TimeInterval(estimate.minutes * 60))
        return String(localized: "\(time) · \(estimate.estimatedCount) mit, \(estimate.withoutEstimateCount) ohne Schätzung")
    }

    /// The text VoiceOver reads for the time chart: one sentence per week.
    static func timeChartSummary(_ weeks: [ProjectTimeWeek], calendar: Calendar) -> String {
        guard !weeks.isEmpty else { return String(localized: "Keine Daten") }
        return weeks.map { week in
            let day = DateText.numericDay(PlanDay(date: week.start, calendar: calendar), calendar: calendar)
            return String(localized: "Woche ab \(day): \(durationText(week.plannedSeconds)) eingeplant, \(durationText(week.investedSeconds)) investiert")
        }.joined(separator: ". ") + "."
    }

    // MARK: Status history

    /// The time an item spent in a Status: "5 Tage" from two days on, otherwise hours and minutes.
    static func statusDurationText(_ seconds: TimeInterval) -> String {
        let days = Int((seconds / 86_400).rounded())
        return seconds >= 2 * 86_400 ? String(localized: "\(days) Tage") : durationText(seconds)
    }

    /// "Ready → In progress".
    static func transitionText(_ transition: ProjectStatusTransition) -> String { "\(transition.from) → \(transition.to)" }

    /// The note under the status history: it only covers what the user changed through Tagwerk on this device since the log began.
    static func statusHistoryNote(since: Date?) -> String {
        guard let since else {
            return String(localized: "Das Protokoll hat noch keine Einträge. Es hält nur Änderungen fest, die du in Tagwerk auf diesem Gerät machst. GitHub und Erinnerungen speichern keinen Verlauf.")
        }
        let date = since.formatted(date: .abbreviated, time: .omitted)
        return String(localized: "Nur Änderungen, die du in Tagwerk auf diesem Gerät gemacht hast, seit \(date). GitHub und Erinnerungen speichern keinen Verlauf.")
    }

    static func failureText(_ failure: ProjectLoadFailure) -> String {
        switch failure {
        case .notConnected: String(localized: "GitHub ist nicht verbunden.")
        case .noAccess: String(localized: "Tagwerk darf nicht auf Erinnerungen zugreifen.")
        case .offline: String(localized: "GitHub ist gerade nicht erreichbar.")
        case .rateLimited: String(localized: "GitHub nimmt gerade keine weiteren Abfragen an. Versuch es in einigen Minuten noch einmal.")
        case .other: String(localized: "Die Daten konnten nicht geladen werden.")
        }
    }

    /// "Erledigt: #319 Strichcode-Scan" and the like.
    static func eventText(_ event: ProjectEvent) -> String {
        let name = event.item.number.map { "#\($0) \(event.item.title)" } ?? event.item.title
        switch event.kind {
        case .created: return String(localized: "Angelegt: \(name)")
        case .completed: return String(localized: "Erledigt: \(name)")
        case .closedNotPlanned: return String(localized: "Geschlossen (nicht geplant): \(name)")
        }
    }

    static func eventSymbol(_ kind: ProjectEvent.Kind) -> String {
        switch kind {
        case .created: "plus.circle"
        case .completed: "checkmark.circle"
        case .closedNotPlanned: "xmark.circle"
        }
    }

    /// The line under an open item: "#332 · In progress · Frist heute · Blockiert".
    static func itemDetail(_ item: ProjectItemFact, now: Date, calendar: Calendar) -> String {
        var parts: [String] = []
        if let number = item.number { parts.append("#\(number)") }
        if let status = item.status { parts.append(status) }
        if let due = item.due { parts.append(String(localized: "Frist \(DueText.text(due, now: now, calendar: calendar))")) }
        if item.isBlocked { parts.append(String(localized: "blockiert")) }
        if item.isBlocker { parts.append(String(localized: "blockiert andere")) }
        if !item.assignees.isEmpty { parts.append(item.assignees.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}
