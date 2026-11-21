#if DEBUG && targetEnvironment(simulator)
import Foundation
import TagwerkCore

/// Simulator-only travel times for `-TagwerkDemoTravel`: MapKit is unreliable in the simulator, so every address is
/// "found" and every trip takes a fixed time that depends on the destination text.
struct DemoTravelEstimator: TravelTimeEstimating {
    static let launchArgument = "-TagwerkDemoTravel"
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(launchArgument) }

    func lookUp(address: String, near: TravelCoordinate?) async throws -> PlaceLookup {
        PlaceLookup(latitude: 52.52, longitude: 13.405, description: address)
    }

    func minutes(from: TravelPlace, to: TravelPlace, transport: TravelTransport, arrival: Date) async throws -> Int {
        let base = 15 + (to.text.count % 4) * 5
        switch transport {
        case .automobile: return base
        case .transit: return base + 10
        case .cycling: return base + 5
        case .walking: return base * 3
        }
    }
}

/// Simulator-only address suggestions for `-TagwerkDemoTravel`: MapKit's completer is unreliable in the simulator, so every
/// fragment of three characters or more gets two fixed suggestions in Berlin.
struct DemoAddressSuggester: AddressSuggesting {
    func suggestions(for query: String) async -> [AddressSuggestion] {
        guard query.count >= HomeAddressModel.minimumQueryLength else { return [] }
        return [AddressSuggestion(id: "demo-1", title: "\(query) 1", subtitle: "10115 Berlin"),
                AddressSuggestion(id: "demo-2", title: "\(query) 22", subtitle: "10117 Berlin")]
    }

    func resolve(_ suggestion: AddressSuggestion) async throws -> PlaceLookup {
        PlaceLookup(latitude: 52.52, longitude: 13.405, description: "\(suggestion.text), Deutschland")
    }
}
#endif
