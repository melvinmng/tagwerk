import Foundation

/// Targets of `tagwerk://` links (widgets, shortcuts). Links only navigate; they never write data or start an
/// estimate, because any app or web page can open them (phase 4 design §5.5).
public enum AppRoute: String, Sendable, Hashable, CaseIterable {
    case planToday = "plan/today"
    case capture = "capture"
    case captureMeal = "capture/meal"
    case captureWorkout = "capture/workout"
    case review = "review"

    public static let scheme = "tagwerk"

    /// Parses `tagwerk://<host>/<path>`; query parameters are ignored on purpose.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host(percentEncoded: false)?.lowercased() else { return nil }
        let path = url.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        self.init(rawValue: path.isEmpty ? host : "\(host)/\(path)")
    }

    public var url: URL {
        URL(string: "\(Self.scheme)://\(rawValue)")!
    }
}
