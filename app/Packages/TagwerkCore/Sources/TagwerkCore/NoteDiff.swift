import Foundation

/// The line difference between the old and the new text of a note, for the card and the sheet "Änderungen" of the assistant
/// (#233). It works on lines of the raw Markdown text.
public enum NoteDiff {
    public struct Line: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case same, added, removed
        }

        public let kind: Kind
        public let text: String

        public init(kind: Kind, text: String) {
            self.kind = kind
            self.text = text
        }
    }

    /// How much changes: the number of new and removed lines and whether the title (first non-empty line) differs.
    public struct Summary: Equatable, Sendable {
        public let added: Int
        public let removed: Int
        public let titleChanged: Bool

        public init(added: Int, removed: Int, titleChanged: Bool) {
            self.added = added
            self.removed = removed
            self.titleChanged = titleChanged
        }

        public var isEmpty: Bool { added == 0 && removed == 0 && !titleChanged }
    }

    /// Every line of both texts in reading order: unchanged lines once, removed lines of the old text and new lines of
    /// the new text where they differ. At one spot the removed lines come before the new ones.
    public static func lines(old: String, new: String) -> [Line] {
        let oldLines = split(old), newLines = split(new)
        let difference = newLines.difference(from: oldLines)
        var removedOffsets = Set<Int>(), insertedOffsets = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removedOffsets.insert(offset)
            case .insert(let offset, _, _): insertedOffsets.insert(offset)
            }
        }
        var result: [Line] = []
        var oldIndex = 0, newIndex = 0
        while oldIndex < oldLines.count || newIndex < newLines.count {
            if oldIndex < oldLines.count, removedOffsets.contains(oldIndex) {
                result.append(Line(kind: .removed, text: oldLines[oldIndex]))
                oldIndex += 1
            } else if newIndex < newLines.count, insertedOffsets.contains(newIndex) {
                result.append(Line(kind: .added, text: newLines[newIndex]))
                newIndex += 1
            } else if oldIndex < oldLines.count, newIndex < newLines.count {
                result.append(Line(kind: .same, text: oldLines[oldIndex]))
                oldIndex += 1
                newIndex += 1
            } else {
                break   // cannot happen: both sides advance together outside the changes
            }
        }
        return result
    }

    public static func summary(old: String, new: String) -> Summary {
        let all = lines(old: old, new: new)
        return Summary(added: all.filter { $0.kind == .added }.count, removed: all.filter { $0.kind == .removed }.count,
                       titleChanged: NoteText.title(old) != NoteText.title(new))
    }

    private static func split(_ text: String) -> [String] {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
    }
}
