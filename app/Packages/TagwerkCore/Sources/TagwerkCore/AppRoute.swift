import Foundation

/// Targets of `tagwerk://` links (widgets, shortcuts). Links only navigate; they never write data or start an
/// estimate, because any app or web page can open them (phase 4 design §5.5).
public enum AppRoute: String, Sendable, Hashable, CaseIterable {
    case planToday = "plan/today"
    case capture = "capture"
    case captureMeal = "capture/meal"
    case captureWorkout = "capture/workout"
    case review = "review"
    /// The shopping list (phase 5); without a chosen list the app shows its settings page instead.
    case shopping = "shopping"
    /// The morning start and the evening wrap-up (phase 7): "Planen" on today with the sheet above it.
    case routineStart = "routine/start"
    case routineEvening = "routine/evening"
    /// The guided weekly planning (#164).
    case routineWeek = "routine/week"

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
