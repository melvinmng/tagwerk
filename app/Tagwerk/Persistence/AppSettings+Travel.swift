import Foundation
import TagwerkCore

extension AppSettings {
    var travelTransport: TravelTransport {
        get { TravelTransport(rawValue: travelTransportRaw) ?? .automobile }
        set { travelTransportRaw = newValue.rawValue }
    }

    /// The home address as a place for trips; `nil` while none is set. With coordinates once the address was checked.
    var homePlace: TravelPlace? {
        guard let text = homeAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return TravelPlace(text: text, latitude: homeLatitude, longitude: homeLongitude)
    }
}
