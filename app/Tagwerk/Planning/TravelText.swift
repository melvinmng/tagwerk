import Foundation
import TagwerkCore

/// Wording of the travel time in the grid, the list, the entry sheet and the settings.
enum TravelText {
    static func symbol(_ transport: TravelTransport) -> String {
        switch transport {
        case .automobile: "car.fill"
        case .transit: "tram.fill"
        case .walking: "figure.walk"
        case .cycling: "bicycle"
        }
    }

    /// The name in the settings picker.
    static func name(_ transport: TravelTransport) -> String {
        switch transport {
        case .automobile: String(localized: "Auto")
        case .transit: String(localized: "Bus und Bahn")
        case .walking: String(localized: "Zu Fuß")
        case .cycling: String(localized: "Fahrrad")
        }
    }

    /// "mit dem Auto", for sentences.
    static func phrase(_ transport: TravelTransport) -> String {
        switch transport {
        case .automobile: String(localized: "mit dem Auto")
        case .transit: String(localized: "mit Bus und Bahn")
        case .walking: String(localized: "zu Fuß")
        case .cycling: String(localized: "mit dem Fahrrad")
        }
    }

    /// "ab Zuhause" or "ab vorherigem Termin".
    static func origin(_ origin: TravelLeg.Origin) -> String {
        switch origin {
        case .home: String(localized: "ab Zuhause")
        case .previousEvent: String(localized: "ab vorherigem Termin")
        }
    }

    /// Inside the block in the grid: "25 min", or "25 min · knapp" when the trip starts before the previous event ends.
    static func gridText(_ segment: TravelSegment) -> String {
        let duration = CapacityText.duration(segment.minutes)
        return segment.isTight ? String(localized: "\(duration) · knapp") : duration
    }

    /// The list row: "Fahrzeit 25 min · ab Zuhause", with "· knapp" when tight.
    static func rowText(_ segment: TravelSegment) -> String {
        let duration = CapacityText.duration(segment.minutes)
        let text: String
        switch segment.origin {
        case .home: text = String(localized: "Fahrzeit \(duration) · ab Zuhause")
        case .previousEvent: text = String(localized: "Fahrzeit \(duration) · ab vorherigem Termin")
        }
        return segment.isTight ? String(localized: "\(text) · knapp") : text
    }

    /// What VoiceOver reads: "Fahrzeit 25 Minuten mit dem Auto, ab Zuhause".
    static func accessibilityLabel(_ segment: TravelSegment, transport: TravelTransport) -> String {
        let text = String(localized: "Fahrzeit \(segment.minutes) Minuten \(phrase(transport)), \(origin(segment.origin))")
        return segment.isTight ? String(localized: "\(text), knapp") : text
    }

    /// The row in the entry sheet: "Fahrzeit · 25 min mit dem Auto ab Zuhause".
    static func entryText(_ segment: TravelSegment, transport: TravelTransport) -> String {
        String(localized: "Fahrzeit · \(CapacityText.duration(segment.minutes)) \(phrase(transport)) \(origin(segment.origin))")
    }

    /// The row in the planning settings: "Auto · Zuhause gesetzt", "Auto · ohne Heimadresse" or "Aus".
    static func settingsSummary(enabled: Bool, transport: TravelTransport, hasHome: Bool) -> String {
        guard enabled else { return String(localized: "Aus") }
        let name = name(transport)
        return hasHome ? String(localized: "\(name) · Zuhause gesetzt") : String(localized: "\(name) · ohne Heimadresse")
    }
}
