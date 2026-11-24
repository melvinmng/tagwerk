import Foundation
import SwiftUI

/// The change text of an adjusted card with the old value of each changed part struck through, as in mockup AN2a:
/// "Fällig ~~Fr., 27. Nov.~~ Mo., 23. Nov. · Liste Privat". The describer writes a change as parts separated by " · "
/// or a line break; two texts of the same function have the same parts, and only those that differ show the old value.
enum ProposalChangeText {
    struct Part: Equatable {
        /// The part as it reads now.
        var text: String
        /// What the model proposed for this part; `nil` when the part did not change.
        var proposed: String?
        /// What stands behind the part up to the next one (" · " or a line break); empty after the last.
        var separator: String
    }

    /// The parts of `current`, each with the proposed text where it differs; `nil` when the two texts do not have the
    /// same number of parts (a field was added or dropped), so the caller shows the whole proposed text instead.
    static func parts(current: String, proposed: String) -> [Part]? {
        let now = split(current), before = split(proposed)
        guard now.count == before.count else { return nil }
        return zip(now, before).map { new, old in
            Part(text: new.text, proposed: new.text == old.text ? nil : old.text, separator: new.separator)
        }
    }

    /// The text for the screen: the old value struck through and grey before the new one.
    static func attributed(_ parts: [Part]) -> AttributedString {
        var result = AttributedString()
        for part in parts {
            if let proposed = part.proposed {
                var old = AttributedString(proposed)
                old.strikethroughStyle = .single
                old.foregroundColor = .secondary
                result += old
                result += AttributedString(" ")
            }
            result += AttributedString(part.text + part.separator)
        }
        return result
    }

    /// The text for VoiceOver: the new value, then what the model proposed instead ("alt → neu" read the other way round,
    /// so the sentence starts with what will happen).
    static func spoken(_ parts: [Part]) -> String {
        parts.map { part in
            guard let proposed = part.proposed else { return part.text + part.separator }
            let hint = String(localized: "Vorschlag der KI: \(proposed)")
            return "\(part.text) (\(hint))" + part.separator
        }.joined()
    }

    private static let separators = [" · ", "\n"]

    private static func split(_ text: String) -> [(text: String, separator: String)] {
        var parts: [(String, String)] = []
        var current = ""
        var index = text.startIndex
        while index < text.endIndex {
            if let separator = separators.first(where: { text[index...].hasPrefix($0) }) {
                parts.append((current, separator))
                current = ""
                index = text.index(index, offsetBy: separator.count)
            } else {
                current.append(text[index])
                index = text.index(after: index)
            }
        }
        parts.append((current, ""))
        return parts
    }
}
