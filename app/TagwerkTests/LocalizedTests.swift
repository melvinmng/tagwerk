import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

struct LocalizedTests {
    @Test func picksTheRequestedLanguage() {
        #expect(Localized.string("Planen", in: .english, bundle: .main) == "Plan")
        #expect(Localized.string("Planen", in: .german, bundle: .main) == "Planen")
    }

    /// The one-form keys come from the catalog's German plural variations (the singular is no `count == 1` branch).
    @Test func pluralKeys_germanSingularAndPlural() {
        func suggestions(_ count: Int) -> String { String(localized: "\(count) Vorschläge") }
        func risks(_ count: Int) -> String { String(localized: "\(count) Risiken") }
        func days(_ count: Int) -> String { String(localized: "\(count) Tagen") }
        func applied(_ count: Int) -> String { String(localized: "\(count) Vorschläge übernommen") }
        func fields(_ count: Int) -> String { String(localized: "Seit dem Öffnen wurden \(count) Felder geändert.") }
        #expect([suggestions(1), suggestions(3)] == ["1 Vorschlag", "3 Vorschläge"])
        #expect([risks(1), risks(2)] == ["1 Risiko", "2 Risiken"])
        #expect([days(1), days(4)] == ["1 Tag", "4 Tagen"])
        #expect([applied(1), applied(2)] == ["1 Vorschlag übernommen", "2 Vorschläge übernommen"])
        #expect([fields(1), fields(2)] == ["Seit dem Öffnen wurde 1 Feld geändert.", "Seit dem Öffnen wurden 2 Felder geändert."])
    }

    @Test func appLanguage_followsTheTestLanguage() {
        #expect(VoiceLanguage.app == .german)
    }
}
