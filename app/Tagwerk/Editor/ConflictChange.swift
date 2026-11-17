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
            ("Titel", { $0.title }),
            ("Fällig", { $0.due.map(dueText) ?? "–" }),
            ("Priorität", { $0.priority?.label ?? "–" }),
            ("Geschätzt", { EstimateHours.text(minutes: $0.estimateMinutes) }),
            ("Liste", { $0.container.name }),
            ("Labels", { ($0.labels ?? []).joined(separator: ", ").ifEmpty("–") }),
            ("Notiz", { ($0.notes ?? "").ifEmpty("–") }),
            ("Erledigt", { $0.isCompleted ? "ja" : "nein" }),
        ]
        return fields.compactMap { name, value in
            let before = value(original), after = value(current), mine = value(draft)
            guard before != after else { return nil }
            return ConflictChange(field: name, before: before, after: after, mine: mine != before ? mine : nil)
        }
    }

    private static func dueText(_ due: DueDate) -> String {
        let day = String(format: "%02d.%02d.%04d", due.day, due.month, due.year)
        guard let hour = due.hour else { return day }
        return day + String(format: ", %02d:%02d", hour, due.minute ?? 0)
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
