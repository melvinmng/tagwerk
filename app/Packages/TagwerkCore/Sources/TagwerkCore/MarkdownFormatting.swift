import Foundation

/// The formatting actions of the note editor's bar, as pure edits of the text and the selection. Offsets count
/// characters (`Character`), like `NoteEditTarget`, so they map straight to `String.index(offsetBy:)`.
public enum MarkdownFormatting {
    public struct Edit: Sendable, Equatable {
        public var text: String
        /// Character offsets of the new selection (`lowerBound == upperBound` is a cursor).
        public var selection: Range<Int>

        public init(text: String, selection: Range<Int>) {
            self.text = text
            self.selection = selection
        }
    }

    public enum Action: Sendable, CaseIterable { case heading, bold, italic, list, checkbox }

    /// Applies an action to the selection or, without one, to the line of the cursor.
    ///
    /// - heading: none → "# " → "## " → none, on every selected line (the first line decides the next step).
    /// - bold / italic: wraps the selection in "**" / "*" and unwraps it when it is already wrapped; spaces at the ends of
    ///   the selection stay outside, because a closing marker behind a space does not close anything. Without a
    ///   selection it inserts the pair and puts the cursor between.
    /// - list / checkbox: toggles "- " / "- [ ] " at the start of every selected line. A list line becomes a checkbox line
    ///   and back without doubling the marker. Indentation stays; blank lines of a multi-line selection are skipped.
    public static func apply(_ action: Action, to text: String, selection: Range<Int>) -> Edit {
        let characters = Array(text)
        let lower = min(max(selection.lowerBound, 0), characters.count)
        let upper = min(max(selection.upperBound, lower), characters.count)
        switch action {
        case .bold: return wrap(in: characters, lower: lower, upper: upper, marker: "**")
        case .italic: return wrap(in: characters, lower: lower, upper: upper, marker: "*")
        case .heading, .list, .checkbox: return editLines(of: characters, lower: lower, upper: upper, action: action)
        }
    }

    private typealias Change = (position: Int, remove: Int, insert: [Character])

    // MARK: Emphasis

    private static let star: Character = "*"

    private static func wrap(in characters: [Character], lower: Int, upper: Int, marker: String) -> Edit {
        let markerLength = marker.count
        // The markers hug the text: surrounding white space stays outside.
        var start = lower, end = upper
        while start < end, characters[start].isWhitespace { start += 1 }
        while end > start, characters[end - 1].isWhitespace { end -= 1 }
        guard start < end else {
            return replace(characters, edits: [(lower, 0, Array(marker + marker))], selection: lower + markerLength ..< lower + markerLength)
        }
        // One star is italic, two are bold, three are both; a run of the other kind is not ours to take away.
        func isEmphasis(_ run: Int) -> Bool { markerLength == 1 ? run % 2 == 1 : run >= 2 }

        // The run of stars at each end of the text, counted across the edge of the selection: "**text**" may be inside the
        // selection, around it, or half and half (the selection a wrap left behind).
        let leading = run(of: star, from: start, step: 1, in: characters, limit: end)
        let trailing = run(of: star, from: end - 1, step: -1, in: characters, limit: start)
        if leading + trailing < end - start, !characters[(start + leading) ..< (end - trailing)].contains(star) {
            let before = run(of: star, from: start - 1, step: -1, in: characters, limit: 0)
            let after = run(of: star, from: end, step: 1, in: characters, limit: characters.count)
            if isEmphasis(min(before + leading, trailing + after)) {
                let edits: [Change] = [(start - before, markerLength, []), (end + after - markerLength, markerLength, [])]
                return replace(characters, edits: edits, selection: map(start, through: edits) ..< map(end, through: edits))
            }
        }
        return replace(characters, edits: [(start, 0, Array(marker)), (end, 0, Array(marker))],
                       selection: start + markerLength ..< end + markerLength)
    }

    /// How many `character`s in a row start at `index`, walking by `step`, without passing `limit` (exclusive).
    private static func run(of character: Character, from index: Int, step: Int, in characters: [Character], limit: Int) -> Int {
        var count = 0, position = index
        while step > 0 ? position < limit : position >= limit, position >= 0, position < characters.count, characters[position] == character {
            count += 1
            position += step
        }
        return count
    }

    // MARK: Lines

    private struct Line {
        var start: Int
        /// Offset of the line break, or the end of the text.
        var end: Int
    }

    private static func lines(of characters: [Character]) -> [Line] {
        var result: [Line] = []
        var start = 0
        for (offset, character) in characters.enumerated() where character == "\n" || character == "\r" || character == "\r\n" {
            result.append(Line(start: start, end: offset))
            start = offset + 1
        }
        result.append(Line(start: start, end: characters.count))
        return result
    }

    private enum ListKind { case none, bullet, checkbox }

    /// The marker at the start of a line after its indentation: its kind and its length in characters.
    private static func marker(of line: Line, in characters: [Character]) -> (kind: ListKind, indentation: Int, length: Int) {
        var indentation = 0
        while line.start + indentation < line.end, characters[line.start + indentation] == " " || characters[line.start + indentation] == "\t" {
            indentation += 1
        }
        let rest = String(characters[(line.start + indentation) ..< line.end])
        for box in ["- [ ] ", "- [x] ", "- [X] "] where rest.hasPrefix(box) { return (.checkbox, indentation, box.count) }
        for box in ["- [ ]", "- [x]", "- [X]"] where rest == box { return (.checkbox, indentation, box.count) }
        for bullet in ["- ", "* ", "+ "] where rest.hasPrefix(bullet) { return (.bullet, indentation, bullet.count) }
        return (.none, indentation, 0)
    }

    private static func editLines(of characters: [Character], lower: Int, upper: Int, action: Action) -> Edit {
        let all = lines(of: characters)
        let first = all.lastIndex { $0.start <= lower } ?? 0
        var last = all.lastIndex { $0.start <= upper } ?? first
        // A selection that ends right at the start of a line does not reach into it.
        if upper > lower, last > first, all[last].start == upper { last -= 1 }
        let selected = Array(all[first ... last])

        var edits: [Change] = []
        switch action {
        case .heading:
            func level(_ line: Line) -> Int {
                var hashes = 0
                while line.start + hashes < line.end, characters[line.start + hashes] == "#" { hashes += 1 }
                return (1 ... 6).contains(hashes) && line.start + hashes < line.end && characters[line.start + hashes] == " " ? hashes : 0
            }
            let next: Int = switch level(selected[0]) { case 0: 1; case 1: 2; default: 0 }
            for line in selected {
                let existing = level(line)
                edits.append((line.start, existing == 0 ? 0 : existing + 1, next == 0 ? [] : Array(String(repeating: "#", count: next) + " ")))
            }
        default:
            let target: ListKind = action == .list ? .bullet : .checkbox
            let text: [Character] = action == .list ? Array("- ") : Array("- [ ] ")
            let considered = selected.count > 1 ? selected.filter { !characters[$0.start ..< $0.end].allSatisfy(\.isWhitespace) } : selected
            let allHaveTarget = !considered.isEmpty && considered.allSatisfy { marker(of: $0, in: characters).kind == target }
            for line in considered {
                let found = marker(of: line, in: characters)
                let position = line.start + found.indentation
                if allHaveTarget {
                    edits.append((position, found.length, []))
                } else if found.kind != target {
                    edits.append((position, found.length, text))
                }
            }
        }
        let mapped = { (offset: Int) in map(offset, through: edits) }
        return replace(characters, edits: edits, selection: mapped(lower) ..< mapped(upper))
    }

    // MARK: Applying edits

    /// Where a position ends up after the edits: behind an insertion at the same place, at the start of a removal that
    /// covers it.
    private static func map(_ position: Int, through edits: [Change]) -> Int {
        edits.reduce(position) { result, edit in
            guard position >= edit.position else { return result }
            return result + edit.insert.count - min(edit.remove, position - edit.position)
        }
    }

    /// Applies edits given against the original text (they must not overlap) and returns the result with `selection`.
    private static func replace(_ characters: [Character], edits: [Change],
                                selection: Range<Int>) -> Edit {
        var result = characters
        for edit in edits.sorted(by: { $0.position > $1.position }) {
            result.replaceSubrange(edit.position ..< min(edit.position + edit.remove, result.count), with: edit.insert)
        }
        return Edit(text: String(result), selection: selection)
    }
}
