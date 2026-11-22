import Foundation

/// Field of an entry the search looks into. The declaration order is the order of `matchedFields`
/// and decides which field supplies the snippet.
public enum SearchField: String, Sendable, Hashable, CaseIterable {
    case title, notes, location, calendar, container, project, label, issueNumber, kind, quantity
    /// Text recognised in a scanned document of a note; searched last, so a hit in the note itself supplies the snippet.
    case scan
}

/// Searchable fields of one entry (event, task, note or shopping item).
public struct SearchDocument: Sendable {
    struct Entry: Sendable {
        let field: SearchField
        let text: String
        let folded: String
    }

    /// Title as shown in the row; highlight ranges refer to this string.
    public let title: String
    /// Number of a GitHub issue, read from the last path component of its URL.
    public let issueNumber: Int?
    let entries: [Entry]

    private init(title: String, issueNumber: Int?, fields: [(SearchField, String?)]) {
        self.title = title
        self.issueNumber = issueNumber
        var entries = [Entry(field: .title, text: title, folded: SearchText.fold(title))]
        for (field, text) in fields {
            guard let text, !text.isEmpty else { continue }
            entries.append(Entry(field: field, text: text, folded: SearchText.fold(text)))
        }
        self.entries = entries
    }

    public init(event: CalendarEvent, calendarName: String?) {
        self.init(title: event.title, issueNumber: nil,
                  fields: [(.notes, event.notes), (.location, event.location), (.calendar, calendarName)])
    }

    public init(task: TaskItem) {
        var fields: [(SearchField, String?)] = [(.notes, task.notes), (.container, task.container.name)]
        fields += task.subContainers.map { (.project, $0.name) }
        fields += (task.labels ?? []).map { (.label, $0) }
        let number = task.id.source == .github ? task.url.flatMap { Int($0.lastPathComponent) } : nil
        self.init(title: task.title, issueNumber: number, fields: fields)
    }

    /// The first line of the text is the title; the rest is searched as notes. `scanText` is the text recognised in the
    /// scans of the note: it is searched and can supply the snippet, but it is not part of the note.
    public init(noteText: String, kindLabel: String, scanText: String = "") {
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let title = lines.first.map(String.init) ?? ""
        let rest = lines.count > 1 ? String(lines[1]).trimmingCharacters(in: .whitespacesAndNewlines) : nil
        self.init(title: title, issueNumber: nil, fields: [(.notes, rest), (.kind, kindLabel), (.scan, scanText)])
    }

    public init(shoppingName: String, quantity: String?) {
        self.init(title: shoppingName, issueNumber: nil, fields: [(.quantity, quantity)])
    }
}
