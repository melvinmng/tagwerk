import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

struct TravelTextTests {
    private func segment(_ minutes: Int = 25, origin: TravelLeg.Origin = .home, tight: Bool = false,
                         source: TravelSegment.Source = .automatic) -> TravelSegment {
        TravelSegment(eventID: "e", range: (840 - minutes)..<840, minutes: minutes, origin: origin, isTight: tight, source: source)
    }

    @Test func segmentText_fromHome() {
        #expect(TravelText.rowText(segment()) == "Fahrzeit 25 min · ab Zuhause")
        #expect(TravelText.gridText(segment()) == "25 min")
    }

    @Test func segmentText_fromPreviousEvent() {
        #expect(TravelText.rowText(segment(origin: .previousEvent(id: "a"))) == "Fahrzeit 25 min · ab vorherigem Termin")
        #expect(TravelText.rowText(segment(75, origin: .home)) == "Fahrzeit 1 h 15 · ab Zuhause")
    }

    @Test func segmentText_tight() {
        #expect(TravelText.gridText(segment(tight: true)) == "25 min · knapp")
        #expect(TravelText.rowText(segment(origin: .previousEvent(id: "a"), tight: true))
                == "Fahrzeit 25 min · ab vorherigem Termin · knapp")
    }

    @Test func accessibilityLabel_namesTransport() {
        #expect(TravelText.accessibilityLabel(segment(), transport: .automobile) == "Fahrzeit 25 Minuten mit dem Auto, ab Zuhause")
        #expect(TravelText.accessibilityLabel(segment(origin: .previousEvent(id: "a")), transport: .transit)
                == "Fahrzeit 25 Minuten mit Bus und Bahn, ab vorherigem Termin")
        #expect(TravelText.accessibilityLabel(segment(tight: true), transport: .walking) == "Fahrzeit 25 Minuten zu Fuß, ab Zuhause, knapp")
        #expect(TravelText.accessibilityLabel(segment(), transport: .cycling) == "Fahrzeit 25 Minuten mit dem Fahrrad, ab Zuhause")
    }

    // MARK: Estimate and manual time (F2)

    @Test func provisionalSegment_isMarkedAsEstimate() {
        let estimate = segment(30, source: .provisional)
        #expect(TravelText.gridText(estimate) == "~30 min")
        #expect(TravelText.rowText(estimate) == "Fahrzeit ~30 min · ab Zuhause · geschätzt")
        #expect(TravelText.rowText(segment(30, origin: .previousEvent(id: "a"), tight: true, source: .provisional))
                == "Fahrzeit ~30 min · ab vorherigem Termin · geschätzt · knapp")
        #expect(TravelText.accessibilityLabel(estimate, transport: .automobile) == "Fahrzeit 30 Minuten mit dem Auto, ab Zuhause, geschätzt")
    }

    @Test func manualSegment_isMarkedAsSetByHand() {
        let manual = segment(20, source: .manual)
        #expect(TravelText.gridText(manual) == "20 min · manuell")
        #expect(TravelText.rowText(manual) == "Fahrzeit 20 min · manuell")
        #expect(TravelText.rowText(segment(20, origin: .previousEvent(id: "a"), tight: true, source: .manual)) == "Fahrzeit 20 min · manuell · knapp")
        #expect(TravelText.accessibilityLabel(manual, transport: .transit) == "Fahrzeit 20 Minuten, manuell festgelegt")
        #expect(TravelText.gridText(segment(20, tight: true, source: .manual)) == "20 min · manuell · knapp")
    }

    @Test func overrideSummary_sayswhatAppliesToTheEvent() {
        #expect(TravelText.overrideSummary(.automatic, segment: nil, transport: .automobile) == "Automatisch")
        #expect(TravelText.overrideSummary(.automatic, segment: segment(), transport: .automobile) == "25 min mit dem Auto ab Zuhause")
        #expect(TravelText.overrideSummary(.automatic, segment: segment(origin: .previousEvent(id: "a"), tight: true), transport: .walking)
                == "25 min zu Fuß ab vorherigem Termin · knapp")
        #expect(TravelText.overrideSummary(.automatic, segment: segment(30, source: .provisional), transport: .automobile) == "~30 min · geschätzt")
        #expect(TravelText.overrideSummary(.none, segment: nil, transport: .automobile) == "Keine")
        #expect(TravelText.overrideSummary(.fixed(minutes: 45), segment: segment(45, source: .manual), transport: .automobile) == "45 min · manuell")
    }

    @Test func settingsSummary_off() {
        #expect(TravelText.settingsSummary(enabled: false, transport: .automobile, hasHome: true) == "Aus")
    }

    @Test func settingsSummary_withHome() {
        #expect(TravelText.settingsSummary(enabled: true, transport: .automobile, hasHome: true) == "Auto · Zuhause gesetzt")
        #expect(TravelText.settingsSummary(enabled: true, transport: .cycling, hasHome: false) == "Fahrrad · ohne Heimadresse")
    }

    @Test func everyTransport_hasSymbolAndName() {
        for transport in TravelTransport.allCases {
            #expect(!TravelText.symbol(transport).isEmpty)
            #expect(!TravelText.name(transport).isEmpty)
            #expect(!TravelText.phrase(transport).isEmpty)
        }
    }
}
