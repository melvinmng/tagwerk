import Foundation

/// Where a tap on the rendered note should put the cursor. The rendered page links its text to the source line
/// (`tagwerk-edit:<line>`); the editor opens at the end of that line. Pure rules, no UI.
public enum NoteEditTarget {
    public static let scheme = "tagwerk-edit"
    public static let endToken = "end"

    /// "tagwerk-edit:12" → line 12, "tagwerk-edit:end" → `isEnd`; anything else is no edit link.
    public static func parse(_ url: String) -> (line: Int?, isEnd: Bool)? {
        let prefix = scheme + ":"
        guard url.lowercased().hasPrefix(prefix) else { return nil }
        let rest = url.dropFirst(prefix.count)
        if rest == endToken { return (nil, true) }
        guard !rest.isEmpty, rest.allSatisfy(\.isASCII), rest.allSatisfy(\.isNumber), let line = Int(rest), line >= 1 else { return nil }
        return (line, false)
    }

    /// The character offset right behind the last character of the 1-based source line (before its line break).
    /// Lines beyond the text clamp to the end; "\r\n" counts as one break. Offsets count characters, not UTF-16 units.
    public static func offset(endOfLine line: Int, in text: String) -> Int {
        let target = max(line, 1)
        var currentLine = 1
        var offset = 0
        for character in text {
            if isLineBreak(character) {
                if currentLine == target { return offset }
                currentLine += 1
            }
            offset += 1
        }
        return offset
    }

    /// Stage B: the source line for a tap at `fraction` (0…1) of the page height: the nearest non-empty line to
    /// `fraction × lineCount`, searching downwards first. Empty text gives line 1.
    public static func approximateLine(fraction: Double, in text: String) -> Int {
        let lines = sourceLines(of: text)
        guard !lines.isEmpty else { return 1 }
        let clamped = min(max(fraction.isFinite ? fraction : 0, 0), 1)
        // The line that contains the position; the last line is reachable at fraction 1.
        let start = min(Int(clamped * Double(lines.count)), lines.count - 1)
        func isBlank(_ index: Int) -> Bool { lines[index].allSatisfy(\.isWhitespace) }
        for index in start..<lines.count where !isBlank(index) { return index + 1 }
        for index in stride(from: start - 1, through: 0, by: -1) where !isBlank(index) { return index + 1 }
        return min(start + 1, lines.count)
    }

    private static func isLineBreak(_ character: Character) -> Bool {
        character == "\n" || character == "\r" || character == "\r\n"
    }

    private static func sourceLines(of text: String) -> [Substring] {
        guard !text.isEmpty else { return [] }
        return text.split(omittingEmptySubsequences: false, whereSeparator: isLineBreak)
    }
}
