import Foundation

/// Rules for filling the "Neue Aufgabe" sheet from shared content or a mail (plan P6, task 6).
public enum NewTaskPrefill {
    /// The notes of the new task: the text, and the link as its own last line. A link the text already contains is not
    /// repeated. `nil` when there is neither text nor link.
    public static func notes(text: String?, url: URL?) -> String? {
        let body = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let link = url?.absoluteString ?? ""
        if link.isEmpty || body.contains(link) { return body.isEmpty ? nil : body }
        return body.isEmpty ? link : body + "\n" + link
    }

    /// The notes for shared text: the text without a first line that is the title already. `nil` when nothing is left.
    public static func sharedNotes(title: String, text: String?) -> String? {
        let lines = (text ?? "").split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        guard let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
        var rest = lines
        if lines[first].trimmingCharacters(in: .whitespaces) == title.trimmingCharacters(in: .whitespaces) {
            rest.removeSubrange(...first)
        }
        let joined = rest.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    /// The fields of the due switch, date and time switch.
    public struct DueFields: Sendable, Equatable {
        public var hasDue: Bool
        public var date: Date
        public var hasTime: Bool
    }

    /// `due == nil` leaves the sheet's own start values (`fallback`). A date without a time sets no time.
    public static func dueFields(_ due: DueDate?, calendar: Calendar, fallback: Date) -> DueFields {
        guard let due else { return DueFields(hasDue: false, date: fallback, hasTime: false) }
        return DueFields(hasDue: true, date: due.startDate(in: calendar), hasTime: due.hasTime)
    }
}
