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
        func events(_ count: Int) -> String { String(localized: "\(count) Termine") }
        func overlaps(_ count: Int) -> String { String(localized: "überschneidet \(count) Termine") }
        #expect([events(1), events(2)] == ["1 Termin", "2 Termine"])
        #expect([overlaps(1), overlaps(3)] == ["überschneidet 1 Termin", "überschneidet 3 Termine"])
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

    @Test func deadlineMarking_textsInBothLanguages() {
        func english(_ key: String.LocalizationValue) -> String { Localized.string(key, in: .english, bundle: .main) }
        func german(_ key: String.LocalizationValue) -> String { Localized.string(key, in: .german, bundle: .main) }
        #expect(english("Als Deadline markieren") == "Mark as deadline")
        #expect(english("markiert") == "marked")
        #expect(german("\(1) zugeordnete Termine werden gelöst. Im Kalender ändert sich nichts.")
                == "1 zugeordneter Termin wird gelöst. Im Kalender ändert sich nichts.")
        #expect(english("\(3) zugeordnete Termine werden gelöst. Im Kalender ändert sich nichts.")
                == "3 linked events will be removed. Nothing changes in the calendar.")
        #expect(english("Vorbereitung \("6 h 30") · \("3 events")") == "Preparation 6 h 30 · 3 events")
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

    /// Recurrence page (plan 2026-11-18): interval labels read "Jede Woche" for one, and the English texts exist.
    @Test func recurrenceKeys_pluralAndEnglish() {
        func weeks(_ count: Int) -> String { String(localized: "Alle \(count) Wochen") }
        func days(_ count: Int) -> String { String(localized: "Alle \(count) Tage") }
        #expect([weeks(1), weeks(2)] == ["Jede Woche", "Alle 2 Wochen"])
        #expect([days(1), days(3)] == ["Jeden Tag", "Alle 3 Tage"])
        func english(_ key: String.LocalizationValue) -> String { Localized.string(key, in: .english, bundle: .main) }
        #expect(english("Alle \(1) Monate") == "Every month")
        #expect(english("Alle \(2) Jahre") == "Every 2 years")
        #expect(english("Anzahl: \(12) Mal") == "Occurs 12 times")
        #expect(english("Wiederholen") == "Repeat")
        #expect(english("Nur in Tagwerk. Beim Abhaken rückt die Aufgabe auf den nächsten Termin.")
                == "Tagwerk only. Ticking it off moves the task to its next date.")
        #expect(english("Eine Wiederholung braucht ein Fälligkeitsdatum.") == "A repeating task needs a due date.")
        #expect(english("Am \("3rd") \("Wednesday")") == "On the 3rd Wednesday")
        #expect(english("Gilt ab \("Thu, Nov 19"). Geplante Blöcke an Tagen ohne Termin der Serie bleiben im Kalender: \("Thu, Nov 26")")
                == "Applies from Thu, Nov 19. Planned blocks on days without an occurrence stay in your calendar: Thu, Nov 26")
    }

    @Test func appLanguage_followsTheTestLanguage() {
        #expect(VoiceLanguage.app == .german)
    }
}
