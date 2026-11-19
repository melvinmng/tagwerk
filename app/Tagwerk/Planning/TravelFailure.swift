import CoreLocation
import Foundation
import MapKit

/// What a failed travel request means for the plan.
enum TravelFailure: Equatable {
    /// No answer could be fetched now (no network, server error, throttled, unknown). The trip gets a provisional block
    /// and is tried again later.
    case offline
    /// Apple Maps answered that there is no such place or no route. Remembered, so the plan shows no block.
    case notFound
    /// The trip cannot be asked at all (no starting point with coordinates). Not remembered beyond the session.
    case unresolvable

    /// Sorts an error. Unknown errors count as `offline` on purpose: the failure to avoid is a missing network that makes
    /// the travel time look free, so an unrecognised error keeps a provisional block instead of hiding it.
    static func classify(_ error: Error) -> TravelFailure {
        if let known = error as? TravelTimeError {
            switch known {
            case .addressNotFound: return .notFound
            case .missingCoordinates, .noReferencePoint: return .unresolvable
            }
        }
        if error is CancellationError { return .offline }
        let nsError = error as NSError
        // A network error below another one (MapKit wraps it as "directions not available") wins.
        if containsNetworkError(nsError) { return .offline }
        switch nsError.domain {
        case MKError.errorDomain:
            switch MKError.Code(rawValue: UInt(max(0, nsError.code))) {
            case .placemarkNotFound, .directionsNotFound: return .notFound
            default: return .offline
            }
        case CLError.errorDomain:
            return nsError.code == CLError.Code.geocodeFoundNoResult.rawValue ? .notFound : .offline
        default:
            return .offline
        }
    }

    private static func containsNetworkError(_ error: NSError) -> Bool {
        if error.domain == NSURLErrorDomain { return true }
        var underlying: [NSError] = []
        if let single = error.userInfo[NSUnderlyingErrorKey] as? NSError { underlying.append(single) }
        if let several = error.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError] { underlying.append(contentsOf: several) }
        return underlying.contains(where: containsNetworkError)
    }
}
