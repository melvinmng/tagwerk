import Foundation
import TagwerkCore

/// The texts of the status card on the backup page (DS1b). Pure, so the wording is tested without a view.
enum BackupStatusText {
    /// The first line of the card: what the state is.
    static func headline(_ status: BackupStatus) -> String {
        switch status {
        case .backedUp: String(localized: "Gesichert")
        case .overdue(let since, _): since == nil ? String(localized: "Noch nicht gesichert") : String(localized: "Nicht gesichert")
        case .folderMissing: String(localized: "Kein Sicherungsordner")
        case .failed: String(localized: "Sicherung fehlgeschlagen")
        case .off: String(localized: "Automatische Sicherung aus")
        }
    }

    /// The second, large line: when, or since when it is not backed up. `nil` where there is nothing to say.
    static func title(_ status: BackupStatus, now: Date, calendar: Calendar) -> String? {
        switch status {
        case .backedUp(let date): dayAndTime(date, now: now, calendar: calendar)
        case .overdue(_, let days) where days > 0: String(localized: "Seit \(days) Tagen")
        case .overdue: String(localized: "Noch keine automatische Sicherung")
        case .folderMissing: String(localized: "Wähle einen Ordner")
        case .failed, .off: nil
        }
    }

    /// The small line under the title. `folderName` is only shown, never interpreted: the card does not claim where the folder lives.
    static func detail(_ status: BackupStatus, folderName: String?, summary: (count: Int, bytes: Int)?, includesPrivate: Bool,
                       encrypted: Bool = false) -> String {
        switch status {
        case .off:
            return String(localized: "Mit „Jetzt sichern“ legst du eine Datei an, wo du willst.")
        case .folderMissing:
            return String(localized: "Ohne Ordner kann Tagwerk nicht automatisch sichern.")
        case .failed(let message):
            return message
        case .overdue, .backedUp:
            var parts: [String] = []
            if let folderName { parts.append(String(localized: "Automatisch nach „\(folderName)“")) }
            if let summary, summary.count > 0 {
                parts.append(String(localized: "Sicherungen: \(summary.count)"))
                parts.append(summary.bytes.formatted(.byteCount(style: .file)))
            }
            parts.append(includesPrivate ? String(localized: "mit Tagebuch und Bible Study") : String(localized: "ohne Tagebuch und Bible Study"))
            if encrypted { parts.append(String(localized: "verschlüsselt")) }
            return parts.joined(separator: " · ")
        }
    }

    /// "Heute, 07:12" on the same day, otherwise "20.11.2026, 07:12" in the calendar's time zone.
    static func dayAndTime(_ date: Date, now: Date, calendar: Calendar) -> String {
        let locale = calendar.locale ?? .current
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Heute, \(time)") }
        let day = date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
        return "\(day), \(time)"
    }
}
