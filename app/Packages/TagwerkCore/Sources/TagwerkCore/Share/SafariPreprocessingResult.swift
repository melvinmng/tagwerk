import Foundation

/// What the Safari preprocessing script (`SafariPreprocessing.js` of the share extension) read from the page: its address,
/// its title and the selected text. Safari hands it to the extension inside a property list, under the key
/// `NSExtensionJavaScriptPreprocessingResultsKey`. Pure rules, so they are tested in the package.
public struct SafariPreprocessingResult: Sendable, Equatable {
    public static let resultsKey = "NSExtensionJavaScriptPreprocessingResultsKey"
    /// The selection is cut here; a note holds more, but a share that large is no selection.
    public static let maximumSelectionLength = 100_000

    public var url: URL?
    public var title: String?
    public var selection: String?

    public init(url: URL? = nil, title: String? = nil, selection: String? = nil) {
        self.url = url
        self.title = title
        self.selection = selection
    }

    /// Reads the item the provider loaded for the property list type: a dictionary with the results under `resultsKey`.
    /// Any other property list (a shared .plist file) is no result. `nil` when it holds nothing usable: only web addresses
    /// count, an empty title or an empty selection is left out.
    public static func parse(_ item: Any?) -> SafariPreprocessingResult? {
        guard let dictionary = item as? [AnyHashable: Any], let results = dictionary[resultsKey] as? [AnyHashable: Any] else { return nil }
        func string(_ key: String) -> String? {
            guard let value = results[key] as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let url = string("url").flatMap(URL.init(string:)).flatMap { value -> URL? in
            let scheme = value.scheme?.lowercased()
            return (scheme == "http" || scheme == "https") && value.host(percentEncoded: false) != nil ? value : nil
        }
        let parsed = SafariPreprocessingResult(url: url, title: string("title"),
                                               selection: string("selection").map { String($0.prefix(maximumSelectionLength)) })
        return parsed.parts.isEmpty ? nil : parsed
    }

    /// The pieces for `SharePayload.classify`: the address, the page title and the selected text.
    public var parts: [SharePart] {
        var parts: [SharePart] = []
        if let url { parts.append(.url(url)) }
        if let title { parts.append(.pageTitle(title)) }
        if let selection { parts.append(.text(selection)) }
        return parts
    }
}
