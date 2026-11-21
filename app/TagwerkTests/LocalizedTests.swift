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

    // MARK: Issue assignees (#136)

    @Test func privacyNotice_namesGitHubUsernames() {
        #expect(AIStatusMessage.privacyNotice.contains("GitHub-Benutzernamen zuweisbarer und zugewiesener Personen"))
        let english = Localized.string(
            "Wenn du KI-Funktionen nutzt, gehen die dafür nötigen Daten (Termine, Aufgaben, bei Issues auch Repo-Inhalte und GitHub-Benutzernamen zuweisbarer und zugewiesener Personen) an OpenAI.",
            in: .english, bundle: .main)
        #expect(english.contains("GitHub usernames of assignable and assigned people"))
        #expect(english.hasPrefix("When you use AI features"))
    }

    @Test func handOverBlocks_pluralForms() {
        func german(_ count: Int) -> String { String(localized: "\(count) geplante Zeitblöcke werden gelöscht.") }
        func english(_ count: Int) -> String {
            Localized.string("\(count) geplante Zeitblöcke werden gelöscht.", in: .english, bundle: .main)
        }
        #expect([german(1), german(2)] == ["1 geplanter Zeitblock wird gelöscht.", "2 geplante Zeitblöcke werden gelöscht."])
        #expect([english(1), english(2)] == ["1 planned time block will be deleted.", "2 planned time blocks will be deleted."])
    }

    @Test func people_pluralForms() {
        #expect(Localized.string("\(3) Personen", in: .english, bundle: .main) == "3 people")
        #expect(Localized.string("\(3) Personen", in: .german, bundle: .main) == "3 Personen")
        #expect(Localized.string("\(4) weiteren Personen", in: .english, bundle: .main) == "4 other people")
    }

    @Test func assigneeTexts_inEnglish() {
        func english(_ key: String.LocalizationValue) -> String { Localized.string(key, in: .english, bundle: .main) }
        #expect(english("Zugewiesen") == "Assignees")
        #expect(english("Niemand") == "No one")
        #expect(english("Vergeben") == "Assigned")
        #expect(english("Abgeben") == "Hand over")
        #expect(english("Du bist danach nicht mehr zugewiesen.") == "You will no longer be assigned.")
        #expect(english("#\(151) angelegt, aber \("lea-m") konnte nicht zugewiesen werden.") == "#151 created, but lea-m could not be assigned.")
        #expect(english("\("#151") an \("lea-m")") == "#151 to lea-m")
        #expect(english("\("lea-m") ist in \("beispiel/app") nicht zuweisbar.") == "lea-m cannot be assigned in beispiel/app.")
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

    /// Phase 5 design §5.10: every line of the table has its English text.
    @Test func shoppingTexts_haveEnglish() {
        let expected: [(String.LocalizationValue, String)] = [
            ("Einkaufsliste", "Shopping List"), ("Notizen", "Notes"), ("Einkaufsliste einrichten", "Set up shopping list"),
            ("Liste „\("Einkauf")“ als Einkaufsliste verwenden?", "Use the list “Einkauf” as your shopping list?"),
            ("Verwenden", "Use"), ("Andere Liste …", "Another List …"), ("Nicht jetzt", "Not now"),
            ("\(7) offen", "7 open"), ("Artikel hinzufügen", "Add item"), ("Erledigt · \(3)", "Completed · 3"),
            ("Erledigte entfernen", "Remove Completed"), ("Sonstiges", "Other"), ("Kategorien verwalten", "Manage Categories"),
            ("Mit ChatGPT sortieren", "Sort with ChatGPT"), ("Vorschlag von ChatGPT", "Suggestion from ChatGPT"),
            ("Vorschlag übernehmen", "Apply"), ("Verwerfen", "Discard"), ("Neue Notiz", "New note"),
            ("Tagesstart", "Morning start"), ("Tagesabschluss", "Evening wrap-up"), ("Auf die Einkaufsliste", "Add to Shopping List"),
            ("Einkaufsliste zeigen", "Show Shopping List"), ("Einkaufsliste ändern", "Change shopping list"),
        ]
        for (key, english) in expected {
            #expect(Localized.string(key, in: .english, bundle: .main) == english)
        }
        // The key differs from the German text, because "Übernehmen" elsewhere means "Accept".
        #expect(Localized.string("Vorschlag übernehmen", in: .german, bundle: .main) == "Übernehmen")
    }

    @Test func shoppingPlurals_followTheCount() {
        func english(_ key: String.LocalizationValue) -> String { Localized.string(key, in: .english, bundle: .main) }
        #expect(english("\(1) Artikel hinzugefügt:") == "1 item added:")
        #expect(english("\(3) Artikel hinzugefügt:") == "3 items added:")
        #expect(english("\(1) erledigte Artikel endgültig löschen?") == "Permanently delete 1 completed item?")
        #expect(Localized.string("\(1) erledigte Artikel endgültig löschen?", in: .german, bundle: .main)
                == "1 erledigten Artikel endgültig löschen?")
        #expect(Localized.string("und \(1) weitere", in: .german, bundle: .main) == "und 1 weiterer")
    }
}
