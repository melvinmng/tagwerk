import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

struct TravelTextTests {
    private func segment(_ minutes: Int = 25, origin: TravelLeg.Origin = .home, tight: Bool = false) -> TravelSegment {
        TravelSegment(eventID: "e", range: (840 - minutes)..<840, minutes: minutes, origin: origin, isTight: tight)
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

    @Test func entryText_namesDurationTransportAndOrigin() {
        #expect(TravelText.entryText(segment(), transport: .automobile) == "Fahrzeit · 25 min mit dem Auto ab Zuhause")
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
