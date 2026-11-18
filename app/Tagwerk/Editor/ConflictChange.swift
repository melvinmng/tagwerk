import Foundation
import TagwerkCore

/// A field that changed at the source while the editor was open (conflict card, mockup 2A).
struct ConflictChange: Equatable, Identifiable {
    let field: String
    /// Value when the editor opened.
    let before: String
    /// Value now at the source.
    let after: String
    /// The user's own new value when they changed the same field (a real overlap), else `nil`.
    let mine: String?

    var id: String { field }

    static func changes(original: TaskItem, draft: TaskItem, current: TaskItem) -> [ConflictChange] {
        let fields: [(String, (TaskItem) -> String)] = [
            (String(localized: "Titel"), { $0.title }),
            (String(localized: "Fällig"), { $0.due.map(dueText) ?? "–" }),
            (String(localized: "Priorität"), { $0.priority?.label ?? "–" }),
            (String(localized: "Geschätzt"), { EstimateHours.text(minutes: $0.estimateMinutes) }),
            (String(localized: "Liste"), { $0.container.name }),
            (String(localized: "Labels"), { ($0.labels ?? []).joined(separator: ", ").ifEmpty("–") }),
            (String(localized: "Notiz"), { ($0.notes ?? "").ifEmpty("–") }),
            (String(localized: "Erledigt"), { $0.isCompleted ? String(localized: "ja") : String(localized: "nein") }),
        ]
        return fields.compactMap { name, value in
            let before = value(original), after = value(current), mine = value(draft)
            guard before != after else { return nil }
            return ConflictChange(field: name, before: before, after: after, mine: mine != before ? mine : nil)
        }
    }

    private static func dueText(_ due: DueDate) -> String {
        let day = DateText.numericDate(PlanDay(year: due.year, month: due.month, day: due.day), calendar: .tagwerk)
        guard let hour = due.hour else { return day }
        return day + ", " + DateText.time(minutes: hour * 60 + (due.minute ?? 0), calendar: .tagwerk)
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
