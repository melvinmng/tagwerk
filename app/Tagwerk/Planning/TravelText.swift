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

    /// Inside the attachment in the grid: "Los 15:05 · 25 min", "Los 15:05 · ~30 min" for an estimate, "Los 15:05 · 25 min ·
    /// manuell" for a time set by hand; the way home reads "25 min nach Hause". How much too early the trip starts is
    /// not part of it (the capsule says that, `TravelWarningCapsule`).
    static func gridText(_ segment: TravelSegment, departure: String) -> String {
        let value = duration(segment)
        let timeText = segment.source == .manual ? String(localized: "\(value) · manuell") : value
        switch segment.direction {
        case .toEvent: return String(localized: "Los \(departure) · \(timeText)")
        case .returnHome: return String(localized: "\(timeText) nach Hause")
        }
    }

    /// The same content in shorter forms for a narrow column, longest first: the whole text, then what matters most (the
    /// departure; for the way home the time), the shortest last.
    static func gridCandidates(_ segment: TravelSegment, departure: String) -> [String] {
        switch segment.direction {
        case .toEvent:
            return [gridText(segment, departure: departure), String(localized: "Los \(departure)"), departure]
        case .returnHome:
            return [gridText(segment, departure: departure), duration(segment)]
        }
    }

    /// The list row: "Losfahren · 25 min ab Zuhause", "… ab vorherigem Termin", "Losfahren · 25 min · manuell", with
    /// "· geschätzt" for an estimate; the way home: "Nach Hause · 25 min".
    static func rowText(_ segment: TravelSegment) -> String {
        let value = duration(segment)
        var text: String
        switch (segment.direction, segment.source) {
        case (.returnHome, _):
            let home = String(localized: "Nach Hause · \(value)")
            text = segment.source == .manual ? String(localized: "\(home) · manuell") : home
        case (.toEvent, .manual): text = String(localized: "Losfahren · \(value) · manuell")
        case (.toEvent, _): text = String(localized: "Losfahren · \(value) \(origin(segment.origin))")
        }
        if segment.source == .provisional { text = String(localized: "\(text) · geschätzt") }
        return text
    }

    /// The capsule of a trip that starts before the previous event ends: "10 min zu früh".
    static func overlapText(minutes: Int) -> String {
        String(localized: "\(CapacityText.duration(minutes)) zu früh")
    }

    /// What VoiceOver reads for the capsule: "10 Minuten vor dem Ende des vorherigen Termins" (singular and plural by the catalog).
    static func overlapAccessibility(minutes: Int) -> String {
        String(localized: "\(minutes) Minuten vor dem Ende des vorherigen Termins")
    }

    /// What VoiceOver reads: "Fahrzeit 25 Minuten mit dem Auto, ab Zuhause"; an estimate adds "geschätzt", a time set by
    /// hand reads "Fahrzeit 25 Minuten, manuell festgelegt", the way home "Rückweg 25 Minuten zu Fuß, nach Hause".
    static func accessibilityLabel(_ segment: TravelSegment, transport: TravelTransport) -> String {
        var text: String
        if segment.source == .manual {
            text = segment.direction == .returnHome
                ? String(localized: "Rückweg \(segment.minutes) Minuten, manuell festgelegt")
                : String(localized: "Fahrzeit \(segment.minutes) Minuten, manuell festgelegt")
        } else if segment.direction == .returnHome {
            text = String(localized: "Rückweg \(segment.minutes) Minuten \(phrase(transport)), nach Hause")
        } else {
            text = String(localized: "Fahrzeit \(segment.minutes) Minuten \(phrase(transport)), \(origin(segment.origin))")
        }
        if segment.source == .provisional { text = String(localized: "\(text), geschätzt") }
        return text
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
