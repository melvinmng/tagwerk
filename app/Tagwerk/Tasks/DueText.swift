import Foundation
import TagwerkCore

/// Short text for a due date, relative to today where that reads better, in the language of `locale`.
enum DueText {
    static func text(_ due: DueDate, now: Date, calendar: Calendar, locale: Locale = .current) -> String {
        let today = calendar.startOfDay(for: now)
        let dueDay = DueDate(year: due.year, month: due.month, day: due.day).startDate(in: calendar)
        let offset = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0

        let day: String
        switch offset {
        case -1: day = String(localized: "gestern")
        case 0: day = String(localized: "heute")
        case 1: day = String(localized: "morgen")
        default:
            let planDay = PlanDay(year: due.year, month: due.month, day: due.day)
            let currentYear = calendar.component(.year, from: now)
            day = due.year == currentYear
                ? DateText.numericDay(planDay, calendar: calendar, locale: locale)
                : DateText.numericDate(planDay, calendar: calendar, locale: locale)
        }
        guard let hour = due.hour else { return day }
        return day + ", " + DateText.time(minutes: hour * 60 + (due.minute ?? 0), calendar: calendar, locale: locale)
    }
}
