import Foundation

/// Turns the Markdown of a Notion page into the plain text the notes use.
public enum NotionMarkdown {
    /// A section of a page: headings that contain `needle` (compared without case and accents) become `heading`.
    public struct Section: Sendable, Equatable {
        public let needle: String
        public let heading: String

        public init(needle: String, heading: String) {
            self.needle = needle
            self.heading = heading
        }
    }

    /// Headings that name a known section become that section's heading on a line of their own, other headings become plain
    /// lines, and emphasis, quote marks, links and images lose their Markdown syntax. A blank line separates the sections.
    public static func plainText(_ markdown: String, sections: [Section]) -> String {
        var output: [String] = []
        for rawLine in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            let isHeading = line.hasPrefix("#")
            // A section name can also be a line in bold only, e.g. "**Tagebuch:**".
            let isBoldLine = line.hasPrefix("**") && (line.hasSuffix("**") || line.hasSuffix("**:"))
            if isHeading { line = String(line.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces) }
            if line.hasPrefix("> ") { line = String(line.dropFirst(2)) }
            line = stripInline(line)
            let bare = SearchText.fold(line.replacingOccurrences(of: ":", with: "")).trimmingCharacters(in: .whitespaces)
            if (isHeading || isBoldLine), let section = sections.first(where: { bare.contains($0.needle) }), bare.count <= 60 {
                if let last = output.last, !last.isEmpty { output.append("") }
                output.append(section.heading)
            } else {
                output.append(line)
            }
        }
        return collapseBlankLines(output).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Bold and italic markers, images and links reduced to their text.
    static func stripInline(_ line: String) -> String {
        var text = line
        text = text.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]*\)"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func collapseBlankLines(_ lines: [String]) -> [String] {
        var result: [String] = []
        for line in lines {
            if line.isEmpty, result.last?.isEmpty == true { continue }
            result.append(line)
        }
        return result
    }
}
