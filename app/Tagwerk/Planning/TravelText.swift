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

    /// The minutes of a block: "25 min", or "~30 min" for an estimate while no value can be fetched.
    private static func duration(_ segment: TravelSegment) -> String {
        let value = CapacityText.duration(segment.minutes)
        return segment.source == .provisional ? String(localized: "~\(value)") : value
    }

    /// Inside the block in the grid: "25 min", "~30 min" for an estimate, "25 min · manuell" for a time set by hand;
    /// "· knapp" is added when the trip starts before the previous event ends.
    static func gridText(_ segment: TravelSegment) -> String {
        let value = duration(segment)
        let text = segment.source == .manual ? String(localized: "\(value) · manuell") : value
        return segment.isTight ? String(localized: "\(text) · knapp") : text
    }

    /// The list row: "Fahrzeit 25 min · ab Zuhause", "Fahrzeit ~30 min · ab Zuhause · geschätzt" for an estimate,
    /// "Fahrzeit 25 min · manuell" for a time set by hand, with "· knapp" when tight.
    static func rowText(_ segment: TravelSegment) -> String {
        let value = duration(segment)
        var text: String
        switch (segment.source, segment.origin) {
        case (.manual, _): text = String(localized: "Fahrzeit \(value) · manuell")
        case (_, .home): text = String(localized: "Fahrzeit \(value) · ab Zuhause")
        case (_, .previousEvent): text = String(localized: "Fahrzeit \(value) · ab vorherigem Termin")
        }
        if segment.source == .provisional { text = String(localized: "\(text) · geschätzt") }
        return segment.isTight ? String(localized: "\(text) · knapp") : text
    }

    /// What VoiceOver reads: "Fahrzeit 25 Minuten mit dem Auto, ab Zuhause"; an estimate adds "geschätzt", a time set by
    /// hand reads "Fahrzeit 25 Minuten, manuell festgelegt".
    static func accessibilityLabel(_ segment: TravelSegment, transport: TravelTransport) -> String {
        var text: String
        if segment.source == .manual {
            text = String(localized: "Fahrzeit \(segment.minutes) Minuten, manuell festgelegt")
        } else {
            text = String(localized: "Fahrzeit \(segment.minutes) Minuten \(phrase(transport)), \(origin(segment.origin))")
            if segment.source == .provisional { text = String(localized: "\(text), geschätzt") }
        }
        return segment.isTight ? String(localized: "\(text), knapp") : text
    }

    /// The value of the row "Fahrzeit" in the entry sheet: what applies to the event now.
    /// "Automatisch" without a block, "25 min mit dem Auto ab Zuhause", "~30 min · geschätzt", "Keine" or "25 min · manuell".
    static func overrideSummary(_ mode: TravelOverrideMode, segment: TravelSegment?, transport: TravelTransport) -> String {
        switch mode {
        case .none:
            return String(localized: "Keine")
        case .fixed(let minutes):
            return String(localized: "\(CapacityText.duration(minutes)) · manuell")
        case .automatic:
            guard let segment else { return String(localized: "Automatisch") }
            let value = duration(segment)
            var text = [value, phrase(transport), origin(segment.origin)].joined(separator: " ")
            if segment.source == .provisional { text = String(localized: "\(value) · geschätzt") }
            return segment.isTight ? String(localized: "\(text) · knapp") : text
        }
    }

    /// The row in the planning settings: "Auto · Zuhause gesetzt", "Auto · ohne Heimadresse" or "Aus".
    static func settingsSummary(enabled: Bool, transport: TravelTransport, hasHome: Bool) -> String {
        guard enabled else { return String(localized: "Aus") }
        let name = name(transport)
        return hasHome ? String(localized: "\(name) · Zuhause gesetzt") : String(localized: "\(name) · ohne Heimadresse")
    }
}
