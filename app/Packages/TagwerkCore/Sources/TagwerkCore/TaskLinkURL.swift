import Foundation

/// Link stored in the URL field of calendar events that Tagwerk creates: `tagwerk://task/<source>/<id>`.
public enum TaskLinkURL {
    static let scheme = "tagwerk"
    static let host = "task"

    private static let allowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/:")
        return set
    }()

    public static func make(_ id: TaskID) -> URL {
        let encoded = id.rawValue.addingPercentEncoding(withAllowedCharacters: allowed) ?? id.rawValue
        return URL(string: "\(scheme)://\(host)/\(id.source.rawValue)/\(encoded)")!
    }

    public static func parse(_ url: URL) -> TaskID? {
        guard url.scheme == scheme, url.host() == host else { return nil }
        let parts = url.path(percentEncoded: true).split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let source = TaskSource(rawValue: parts[0]),
              let raw = parts[1].removingPercentEncoding, !raw.isEmpty else { return nil }
        return TaskID(source: source, rawValue: raw)
    }
}
