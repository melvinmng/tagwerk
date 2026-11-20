import Foundation

/// Merges what an `NSExtensionItem` carries itself (its title and its text) into the parts the providers delivered.
/// Safari fills these fields when it shares a selection or a page: the item's text is the selected text or the page title,
/// often the same string a provider hands out as plain text, sometimes shortened with an ellipsis, and sometimes the
/// address of the page. Pure rules, so they are tested in the package with fake items.
public enum ShareItemText {
    /// Adds the item's title as a page title and the item's text as text, or as address when it is one. Empty strings are ignored.
    /// Duplicates of a text a provider delivered are left to `SharePayload.classify`, which merges texts.
    public static func merge(attributedTitle: String?, attributedContentText: String?, into parts: inout [SharePart]) {
        if let title = trimmed(attributedTitle) { parts.append(.pageTitle(title)) }
        guard let text = trimmed(attributedContentText) else { return }
        if let url = webAddress(in: text) {
            parts.append(.url(url))
        } else {
            parts.append(.text(text))
        }
    }

    /// The whole string as a web address, when that is all it holds.
    static func webAddress(in text: String) -> URL? {
        guard !text.contains(where: \.isWhitespace), let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host(percentEncoded: false) != nil else { return nil }
        return url
    }

    /// Texts that say the same: removes every text that another text contains (white space and a closing ellipsis are not
    /// compared), so a shortened copy and a repeated copy vanish and the fullest copy stays. Order of the rest is kept.
    static func mergeTexts(_ texts: [String]) -> [String] {
        let keys = texts.map(comparisonKey)
        var kept: [String] = []
        for (index, text) in texts.enumerated() {
            let key = keys[index]
            if key.isEmpty { continue }
            let covered = keys.enumerated().contains { other, otherKey in
                guard other != index else { return false }
                if otherKey == key { return other < index }
                return otherKey.contains(key)
            }
            if !covered { kept.append(text) }
        }
        return kept
    }

    private static func comparisonKey(_ text: String) -> String {
        var key = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        for ellipsis in ["…", "..."] where key.hasSuffix(ellipsis) {
            key.removeLast(ellipsis.count)
            key = key.trimmingCharacters(in: .whitespaces)
            break
        }
        return key
    }

    private static func trimmed(_ text: String?) -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
