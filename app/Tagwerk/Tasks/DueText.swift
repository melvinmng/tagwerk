import Foundation
import TagwerkCore

/// Short German text for a due date, relative to today where that reads better.
enum DueText {
    static func text(_ due: DueDate, now: Date, calendar: Calendar) -> String {
        let today = calendar.startOfDay(for: now)
        let dueDay = DueDate(year: due.year, month: due.month, day: due.day).startDate(in: calendar)
        let offset = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0

        let day: String
        switch offset {
        case -1: day = "gestern"
        case 0: day = "heute"
        case 1: day = "morgen"
        default:
            let currentYear = calendar.component(.year, from: now)
            day = due.year == currentYear
                ? String(format: "%02d.%02d.", due.day, due.month)
                : String(format: "%02d.%02d.%04d", due.day, due.month, due.year)
        }
        guard let hour = due.hour else { return day }
        return day + String(format: ", %02d:%02d", hour, due.minute ?? 0)
    }
}
