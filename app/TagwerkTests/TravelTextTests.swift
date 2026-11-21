import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

struct TravelTextTests {
    private func segment(_ minutes: Int = 25, origin: TravelLeg.Origin = .home, overlap: Int = 0,
                         source: TravelSegment.Source = .automatic, direction: TravelLeg.Direction = .toEvent) -> TravelSegment {
        let range = direction == .toEvent ? (840 - minutes)..<840 : 840..<(840 + minutes)
        return TravelSegment(eventID: "e", range: range, minutes: minutes, origin: origin, overlapMinutes: overlap, source: source,
                             direction: direction)
    }

    // MARK: Grid text (PL8b)

    @Test func gridText_namesTheDeparture() {
        #expect(TravelText.gridText(segment(), departure: "13:35") == "Los 13:35 · 25 min")
        #expect(TravelText.gridText(segment(75), departure: "12:45") == "Los 12:45 · 1 h 15")
    }

    @Test func gridText_estimateKeepsTheTilde() {
        #expect(TravelText.gridText(segment(30, source: .provisional), departure: "13:30") == "Los 13:30 · ~30 min")
    }

    @Test func gridText_manualAndReturn() {
        #expect(TravelText.gridText(segment(20, source: .manual), departure: "13:40") == "Los 13:40 · 20 min · manuell")
        #expect(TravelText.gridText(segment(25, direction: .returnHome), departure: "14:00") == "25 min nach Hause")
        #expect(TravelText.gridText(segment(30, source: .provisional, direction: .returnHome), departure: "14:00") == "~30 min nach Hause")
    }

    @Test func gridText_hasNoTightMarkAnymore() {
        #expect(TravelText.gridText(segment(overlap: 10), departure: "13:35") == "Los 13:35 · 25 min")
    }

    @Test func gridCandidates_shortenInOrder() {
        let there = TravelText.gridCandidates(segment(), departure: "13:35")
        #expect(there == ["Los 13:35 · 25 min", "Los 13:35", "13:35"])
        #expect(there.first == TravelText.gridText(segment(), departure: "13:35"))
        let back = TravelText.gridCandidates(segment(direction: .returnHome), departure: "14:00")
        #expect(back == ["25 min nach Hause", "25 min"])
        // Longest first, each one shorter than the one before.
        for list in [there, back] { #expect(zip(list, list.dropFirst()).allSatisfy { $0.count > $1.count }) }
    }

    // MARK: List text (PL9b)

    @Test func rowText_saysLosfahren() {
        #expect(TravelText.rowText(segment()) == "Losfahren · 25 min ab Zuhause")
        #expect(TravelText.rowText(segment(origin: .previousEvent(id: "a"))) == "Losfahren · 25 min ab vorherigem Termin")
        #expect(TravelText.rowText(segment(75, origin: .home)) == "Losfahren · 1 h 15 ab Zuhause")
        #expect(TravelText.rowText(segment(overlap: 10)) == "Losfahren · 25 min ab Zuhause")
    }

    @Test func rowText_estimateAndManual() {
        #expect(TravelText.rowText(segment(30, source: .provisional)) == "Losfahren · ~30 min ab Zuhause · geschätzt")
        #expect(TravelText.rowText(segment(30, origin: .previousEvent(id: "a"), source: .provisional))
                == "Losfahren · ~30 min ab vorherigem Termin · geschätzt")
        #expect(TravelText.rowText(segment(20, source: .manual)) == "Losfahren · 20 min · manuell")
    }

    @Test func rowText_return() {
        #expect(TravelText.rowText(segment(25, direction: .returnHome)) == "Nach Hause · 25 min")
        #expect(TravelText.rowText(segment(30, source: .provisional, direction: .returnHome)) == "Nach Hause · ~30 min · geschätzt")
        #expect(TravelText.rowText(segment(20, source: .manual, direction: .returnHome)) == "Nach Hause · 20 min · manuell")
    }

    // MARK: Overlap capsule (PL10b)

    @Test func overlapText_inBothLanguages() throws {
        #expect(TravelText.overlapText(minutes: 10) == "10 min zu früh")
        #expect(TravelText.overlapAccessibility(minutes: 10) == "10 Minuten vor dem Ende des vorherigen Termins")
        #expect(TravelText.overlapAccessibility(minutes: 1) == "1 Minute vor dem Ende des vorherigen Termins")
        // English: the catalog carries "10 min early" (the German text is the key).
        let english = try #require(Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:)))
        #expect(english.localizedString(forKey: "%@ zu früh", value: nil, table: nil) == "%@ early")
    }

    // MARK: VoiceOver

    @Test func accessibilityLabel_namesTransport() {
        #expect(TravelText.accessibilityLabel(segment(), transport: .automobile) == "Fahrzeit 25 Minuten mit dem Auto, ab Zuhause")
        #expect(TravelText.accessibilityLabel(segment(origin: .previousEvent(id: "a")), transport: .transit)
                == "Fahrzeit 25 Minuten mit Bus und Bahn, ab vorherigem Termin")
        #expect(TravelText.accessibilityLabel(segment(), transport: .cycling) == "Fahrzeit 25 Minuten mit dem Fahrrad, ab Zuhause")
        #expect(TravelText.accessibilityLabel(segment(25, direction: .returnHome), transport: .walking)
                == "Rückweg 25 Minuten zu Fuß, nach Hause")
    }

    @Test func accessibilityLabel_isNotRepeatedByTheCapsule() {
        // The overlap has its own element (the capsule); the label of the block does not carry it a second time.
        #expect(!TravelText.accessibilityLabel(segment(overlap: 10), transport: .automobile).contains("knapp"))
    }

    // MARK: Estimate and manual time (F2)

    @Test func provisionalSegment_isMarkedForVoiceOver() {
        #expect(TravelText.accessibilityLabel(segment(30, source: .provisional), transport: .automobile)
                == "Fahrzeit 30 Minuten mit dem Auto, ab Zuhause, geschätzt")
    }

    @Test func manualSegment_isMarkedForVoiceOver() {
        #expect(TravelText.accessibilityLabel(segment(20, source: .manual), transport: .transit) == "Fahrzeit 20 Minuten, manuell festgelegt")
    }

    @Test func overrideSummary_sayswhatAppliesToTheEvent() {
        #expect(TravelText.overrideSummary(.automatic, segment: nil, transport: .automobile) == "Automatisch")
        #expect(TravelText.overrideSummary(.automatic, segment: segment(), transport: .automobile) == "25 min mit dem Auto ab Zuhause")
        #expect(TravelText.overrideSummary(.automatic, segment: segment(origin: .previousEvent(id: "a"), overlap: 10), transport: .walking)
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
