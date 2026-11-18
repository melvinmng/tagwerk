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

    @Test func englishLookups_useTheGlossary() {
        func english(_ key: String.LocalizationValue) -> String { Localized.string(key, in: .english, bundle: .main) }
        #expect(english("Neue Aufgabe") == "New task")
        #expect(english("Einstellungen") == "Settings")
        #expect(english("Zeitblock") == "Time block")
        #expect(english("Wochenrückblick") == "Weekly review")
        #expect(english("Überfällig") == "Overdue")
        #expect(english("Fällig am") == "Due on")
        #expect(english("Mittagspause") == "Lunch break")
    }

    @Test func languageChipLabels_areGermanKeysWithEnglishTranslations() {
        func english(_ key: String.LocalizationValue) -> String { Localized.string(key, in: .english, bundle: .main) }
        #expect(english("Sprache Deutsch, auf Englisch wechseln") == "Language German, switch to English")
        #expect(english("Sprache Englisch, auf Deutsch wechseln") == "Language English, switch to German")
    }

    @Test func englishLookups_keepPlaceholdersAndTheirOrder() {
        func english(_ key: String.LocalizationValue) -> String { Localized.string(key, in: .english, bundle: .main) }
        #expect(english("Fälligkeit: \("heute") → \("morgen")") == "Due date: heute → morgen")
        #expect(english("\(3) von \(5)") == "3 of 5")
    }

    @Test func pluralKeys_englishSingularAndPlural() {
        func english(_ key: String.LocalizationValue) -> String { Localized.string(key, in: .english, bundle: .main) }
        func suggestions(_ count: Int) -> String { english("\(count) Vorschläge") }
        func days(_ count: Int) -> String { english("\(count) Tagen") }
        func fields(_ count: Int) -> String { english("Seit dem Öffnen wurden \(count) Felder geändert.") }
        #expect([suggestions(1), suggestions(3)] == ["1 suggestion", "3 suggestions"])
        #expect([days(1), days(4)] == ["1 day", "4 days"])
        #expect([fields(1), fields(2)] == ["1 field has changed since you opened it.", "2 fields have changed since you opened it."])
    }

    @Test func appLanguage_followsTheTestLanguage() {
        #expect(VoiceLanguage.app == .german)
    }
}
