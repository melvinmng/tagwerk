import Foundation
import Testing
@testable import Tagwerk

/// Control Center and the lock screen show these texts on a locked device (#167 privacy rule).
struct ControlTextTests {
    private func text(_ resource: LocalizedStringResource) -> String {
        String(localized: resource)
    }

    @Test func labelsAreGeneric() {
        let allowed: Set<String> = [
            "Wasser", "Gewohnheit", "Notiz diktieren", "Fokus", "Erfassen", "Tagesroutine", "Einkaufsliste", "Läuft", "Aus",
            "Trägt Wasser ein, ohne Tagwerk zu öffnen.",
            "Hakt eine Gewohnheit für heute ab, ohne Tagwerk zu öffnen.",
            "Öffnet eine neue Notiz in Brain Dump und startet das Diktat.",
            "Startet oder beendet einen freien Fokus-Timer.",
            "Öffnet Erfassen für Essen, Wasser und Training.",
            "Öffnet morgens den Tagesstart, sonst den Tagesabschluss.",
            "Öffnet die Einkaufsliste.",
        ]
        // The tests run in German; a missing entry here means a text was added without a decision about its privacy.
        let found = Set(ControlText.allFixedTexts.map(text))
        #expect(found == allowed)
    }

    @Test func fixedTexts_holdNoFigures() {
        for resource in ControlText.allFixedTexts {
            #expect(text(resource).allSatisfy { !$0.isNumber })
        }
    }

    @Test func waterLabel_namesOnlyTheConfiguredAmount() {
        #expect(text(ControlText.waterLabel(milliliters: 250)) == "+250 ml")
        #expect(text(ControlText.waterLabel(milliliters: 1000)) == "+1000 ml")
    }
}
