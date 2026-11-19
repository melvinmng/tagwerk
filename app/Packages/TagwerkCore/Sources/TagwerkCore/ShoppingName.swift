import Foundation

/// Normalized form of an item name, used to detect duplicates, to reopen completed items and to remember
/// the category of a name.
public enum ShoppingName {
    /// Lowercased, trimmed, inner whitespace collapsed to one space, diacritics folded ("ä" becomes "a").
    /// Singular and plural are not merged.
    public static func key(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }
}
