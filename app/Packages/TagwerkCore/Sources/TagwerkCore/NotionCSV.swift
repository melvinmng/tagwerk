import Foundation

/// A small CSV reader for the database files of a Notion export: quoted fields with doubled quotes and line breaks,
/// CRLF or LF, an optional byte order mark. It reads text, not files, so it can be tested without a file system.
public enum NotionCSV {
    /// All rows including the header row. Rows without any content are dropped.
    public static func rows(_ text: String) -> [[String]] {
        var source = Substring(text)
        if source.hasPrefix("\u{FEFF}") { source = source.dropFirst() }
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var iterator = source.makeIterator()
        var pending: Character?

        func finishField() { row.append(field); field = "" }
        func finishRow() {
            finishField()
            if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
            row = []
        }

        while let character = pending ?? iterator.next() {
            pending = nil
            if isQuoted {
                if character == "\"" {
                    // A doubled quote is a literal quote; a single one closes the field.
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { isQuoted = false; pending = next }
                    } else {
                        isQuoted = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"": if field.isEmpty { isQuoted = true } else { field.append(character) }
                case ",": finishField()
                // Swift treats "\r\n" as one Character.
                case "\n", "\r\n", "\r": finishRow()
                default: field.append(character)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { finishRow() }
        return rows
    }

    /// The rows as dictionaries keyed by the header row.
    public static func records(_ text: String) -> [[String: String]] {
        let all = rows(text)
        guard let header = all.first else { return [] }
        return all.dropFirst().map { row in
            var record: [String: String] = [:]
            for (index, name) in header.enumerated() where index < row.count { record[name] = row[index] }
            return record
        }
    }
}
