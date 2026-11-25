import Foundation
import TagwerkCore

/// A row of the main settings list that has no page of its own (a section or a single row). The settings search opens the list
/// and scrolls to it.
enum SettingsAnchor: String, CaseIterable {
    case planning
    case lunch
    case buffer
    case github
    case notifications
    case access
    case setup

    var title: LocalizedStringResource {
        switch self {
        case .planning: "Planen"
        case .lunch: "Mittagspause"
        case .buffer: "Puffer"
        case .github: "GitHub"
        case .notifications: "Benachrichtigungen"
        case .access: "Zugriff"
        case .setup: "Einrichtung erneut starten"
        }
    }
}

/// Where a search hit leads: the pages to push (empty for the main list) and the row of the main list to scroll to.
struct SettingsTarget: Equatable {
    var path: [SettingsDestination]
    var anchor: SettingsAnchor?
}

/// One entry of the settings search: a page, a single setting on a page, or a row of the main list. Titles are the labels shown in the
/// settings; the keywords are comma separated words that find the entry without being its title. Both are in the language of the app,
/// and so is the search.
struct SettingsSearchEntry: Identifiable {
    let id: String
    let title: LocalizedStringResource
    let keywords: LocalizedStringResource?
    /// The page the setting is on, or the page itself when `isPage`.
    let destination: SettingsDestination?
    /// The row of the main list, for an entry without a page.
    let anchor: SettingsAnchor?
    let isPage: Bool

    /// A page of the settings.
    init(page destination: SettingsDestination, keywords: LocalizedStringResource) {
        id = "page.\(destination)"
        title = destination.title
        self.keywords = keywords
        self.destination = destination
        anchor = nil
        isPage = true
    }

    /// A single setting on `destination`.
    init(_ id: String, _ title: LocalizedStringResource, on destination: SettingsDestination, keywords: LocalizedStringResource? = nil) {
        self.id = id
        self.title = title
        self.keywords = keywords
        self.destination = destination
        anchor = nil
        isPage = false
    }

    /// A row of the main list.
    init(_ id: String, _ title: LocalizedStringResource, anchor: SettingsAnchor, keywords: LocalizedStringResource? = nil) {
        self.id = id
        self.title = title
        self.keywords = keywords
        destination = nil
        self.anchor = anchor
        isPage = false
    }

    var target: SettingsTarget {
        SettingsTarget(path: destination?.path ?? [], anchor: anchor)
    }

    /// The pages (or the section) that lead to the entry, for the line under the title: "Erfassen", "KI › Spracheingabe und Vorlesen".
    var pathTitles: [LocalizedStringResource] {
        guard let destination else { return anchor.map { [$0.title] } ?? [] }
        let pages = destination.path.map(\.title)
        // A page is listed with the pages above it, not with itself.
        return isPage ? Array(pages.dropLast()) : pages
    }
}

/// A hit of the search with its texts resolved.
struct SettingsSearchHit: Identifiable, Equatable {
    let id: String
    let title: String
    /// "Erfassen", "KI › Spracheingabe und Vorlesen"; empty for a page of the main list.
    let pathText: String
    let target: SettingsTarget
}

/// The maintained list of everything that can be found in the settings. A page has an entry because a test requires one for every
/// `SettingsDestination`; single settings are listed by hand and only the ones people look for.
enum SettingsSearchIndex {
    static let entries: [SettingsSearchEntry] = pages + settings

    /// The entries that match `query`, best first (title and word starts before other hits), at most `limit`. A blank query has no hits.
    static func hits(for query: String, limit: Int? = nil, in entries: [SettingsSearchEntry] = SettingsSearchIndex.entries) -> [SettingsSearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let matching = ChoiceFilter.matching(entries, query: trimmed) { entry in
            [String(localized: entry.title)] + keywordList(of: entry) + entry.pathTitles.map { String(localized: $0) }
        }
        let capped = limit.map { Array(matching.prefix($0)) } ?? matching
        return capped.map { entry in
            SettingsSearchHit(id: entry.id, title: String(localized: entry.title),
                              pathText: entry.pathTitles.map { String(localized: $0) }.joined(separator: " › "), target: entry.target)
        }
    }

    private static func keywordList(of entry: SettingsSearchEntry) -> [String] {
        guard let keywords = entry.keywords else { return [] }
        return String(localized: keywords).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: Pages

    private static let pages: [SettingsSearchEntry] = [
        .init(page: .languages, keywords: "Diktat, Deutsch, Englisch, Sprache, Rezepte, Sprachchat"),
        .init(page: .ai, keywords: "ChatGPT, Anmelden, Modell, Denkaufwand, Planungsvorgaben, Assistent, künstliche Intelligenz"),
        .init(page: .aiVoice, keywords: "Stimme, Mikrofon, Vorlesen, Sprachpaket, Sprechen, Diktieren"),
        .init(page: .aiPrivacy, keywords: "Datenschutz, Daten, ChatGPT, Privatsphäre"),
        .init(page: .capture, keywords: "Ernährung, Kalorien, Wasser, Schritte, Gewicht, Health, Ziele, Lebensmittel"),
        .init(page: .shopping, keywords: "Einkauf, Kategorien, Rezepte, Übersetzen, Sortieren"),
        .init(page: .siri, keywords: "Kurzbefehle, Sprachbefehl, Shortcuts, Siri"),
        .init(page: .workSchedule, keywords: "Arbeitszeit, Wochentage, Arbeitsbeginn, Feierabend, Wochenplan"),
        .init(page: .deadlineCalendars, keywords: "Fristen, Klausuren, Termine, Kalender"),
        .init(page: .travel, keywords: "Verkehrsmittel, Rückweg, Zuhause, Auto, Fahrrad, Anfahrt"),
        .init(page: .mergeRules, keywords: "Doppelte Termine, Duplikate, Zusammenfassen, Termine"),
        .init(page: .calendarDiagnostics, keywords: "Prüfen, Fehler, Termine, Kalender, Problem"),
        .init(page: .calendars, keywords: "Quellen, Termine, Kalender auswählen"),
        .init(page: .reminderLists, keywords: "Quellen, Erinnerungen, Listen, Aufgaben"),
        .init(page: .githubProjects, keywords: "GitHub, Issues, Repositories, Aufgaben, Quellen"),
        .init(page: .routines, keywords: "Schlaf, Schlafenszeit, Tagesstart, Tagesabschluss, Abend, Morgen, Gewohnheiten"),
        .init(page: .bibleStudy, keywords: "Bibel, Andacht, Zeit mit Gott, Erinnerung, Tagebuch"),
        .init(page: .habits, keywords: "Routinen, Gewohnheit, Tracker, Erinnerung"),
        .init(page: .notes, keywords: "Sortieren, Gruppieren, Notion, Sperre, Ordner"),
        .init(page: .backup, keywords: "Backup, Sicherung, Passwort, Verschlüsseln, Wiederherstellen, Export"),
        .init(page: .focus, keywords: "Pomodoro, Pause, Runden, Konzentration, Timer, Sammlung"),
        .init(page: .reminderDefaults, keywords: "Erinnerungen, Benachrichtigungen, Standard, Vorlauf"),
        .init(page: .quietHours, keywords: "Nicht stören, Stille, Nacht, Fokus-Filter, Benachrichtigungen"),
    ]

    // MARK: Single settings

    private static let settings: [SettingsSearchEntry] = [
        // Erfassen
        .init("capture.kilocalories", "Kalorien (Grundziel)", on: .capture, keywords: "Kalorienziel, kcal, Energie, Budget"),
        .init("capture.water", "Wasser", on: .capture, keywords: "Trinken, Wasserziel, Liter"),
        .init("capture.workout", "Training pro Woche", on: .capture, keywords: "Sport, Workout, Minuten"),
        .init("capture.steps", "Schritte pro Tag", on: .capture, keywords: "Schrittziel, Gehen"),
        .init("capture.protein", "Eiweiß-Ziel", on: .capture, keywords: "Protein"),
        .init("capture.activityCredit", "Aktivität anrechnen", on: .capture, keywords: "Aktive Energie, Budget, Prozent"),
        .init("capture.foreignNutrition", "Einträge anderer Apps mitzählen", on: .capture, keywords: "Health, Fremde Einträge, Ernährung"),
        .init("capture.bodyFat", "Körperfett erfassen", on: .capture, keywords: "Gewicht, Körper, Waage"),
        .init("capture.estimateMeals", "Mahlzeiten von ChatGPT schätzen", on: .capture, keywords: "Foto, Schätzung, KI"),
        .init("capture.openFoodFacts", "Online-Suche in Open Food Facts", on: .capture, keywords: "Strichcode, Lebensmittel, Produktsuche, Einwilligung"),
        .init("capture.widget", "Ernährung im Widget zeigen", on: .capture, keywords: "Widget, Sperrbildschirm, Startbildschirm"),
        // KI
        .init("ai.mailSummary", "Mails von ChatGPT zusammenfassen", on: .ai, keywords: "Mail, Teilen, Aufgabenvorschlag"),
        .init("ai.noteAssistant", "Notizen mit ChatGPT", on: .ai, keywords: "Notizen, Assistent, Zugriff"),
        .init("ai.model", "Modell", on: .ai, keywords: "ChatGPT, Version"),
        .init("ai.reasoning", "Denkaufwand", on: .ai, keywords: "Reasoning, Geschwindigkeit, Gründlichkeit"),
        .init("ai.workAhead", "Vorarbeiten, wenn Luft ist", on: .ai, keywords: "Planen, Nächste Tage"),
        .init("ai.longerDays", "Längere Tage vorschlagen", on: .ai, keywords: "Planen, Überstunden, Fristen"),
        // Sprachen und Sprache
        .init("languages.dictation", "Diktat", on: .languages, keywords: "Sprache, Spracheingabe"),
        .init("languages.recipes", "Rezepte", on: .languages, keywords: "Übersetzen, Sprache"),
        .init("languages.voiceReply", "Sprachchat-Antwort", on: .languages, keywords: "Antwort, Sprache, Vorlesen"),
        .init("voice.microphone", "Mikrofon in Gesprächen", on: .aiVoice, keywords: "Spracheingabe, Mikrofonzugriff"),
        .init("voice.readAloud", "Antworten vorlesen", on: .aiVoice, keywords: "Stimme, Sprachausgabe"),
        .init("voice.announceChanges", "Änderungen ansagen", on: .aiVoice, keywords: "Ansagen, Stimme"),
        // Planen
        .init("workSchedule.weekdays", "Arbeitszeit je Wochentag", on: .workSchedule, keywords: "Beginn, Ende, Freie Tage"),
        .init("planning.planCalendar", "Plan-Kalender", anchor: .planning, keywords: "Kalender, Zeitblöcke, Tagwerk-Kalender"),
        .init("planning.defaultDuration", "Standarddauer", anchor: .planning, keywords: "Aufwand, Aufgaben ohne Aufwand, Minuten"),
        .init("planning.mergeEvents", "Termine zusammenfassen (mit Rückfrage)", anchor: .planning, keywords: "Doppelte Termine, Duplikate"),
        .init("travel.enabled", "Fahrzeit berücksichtigen", on: .travel, keywords: "Anfahrt, Termine, Route"),
        .init("travel.transport", "Verkehrsmittel", on: .travel, keywords: "Auto, Fahrrad, Zu Fuß, Bahn"),
        .init("lunch.break", "Mittagspause", anchor: .lunch, keywords: "Pause, Mittag, Beginn, Dauer"),
        .init("buffer.gap", "Puffer", anchor: .buffer, keywords: "Abstand, Termine, Aufgaben, Minuten"),
        // Routinen
        .init("routines.bedtime", "Zielschlafzeit", on: .routines, keywords: "Schlaf, Schlafenszeit, Abendroutine"),
        .init("routines.eveningReminder", "Erinnerungen am Abend", on: .routines, keywords: "Tagesabschluss, Abend"),
        .init("routines.askWeight", "Gewicht abfragen", on: .routines, keywords: "Wiegen, Morgen, Tagesstart"),
        .init("routines.noteSuggestions", "Notizen an ChatGPT senden", on: .routines, keywords: "Gedanken, Aufgabenvorschläge"),
        // Notizen
        .init("notes.groupByDate", "Nach Datum gruppieren", on: .notes, keywords: "Sortierung, Liste"),
        .init("notes.notionImport", "Aus Notion importieren", on: .notes, keywords: "Import, Notion"),
        .init("notes.lockFolders", "Private Ordner sperren", on: .notes, keywords: "Face ID, Code, Sperre, Privat"),
        // Datensicherung
        .init("backup.folder", "Sicherungsordner", on: .backup, keywords: "iCloud, Speicherort, Backup"),
        .init("backup.encrypt", "Mit Passwort verschlüsseln", on: .backup, keywords: "Passwort, Verschlüsselung, Backup"),
        .init("backup.diary", "Tagebuch und Bible Study einschließen", on: .backup, keywords: "Tagebuch, Privat, Backup"),
        // Fokus
        .init("focus.pomodoro", "Pomodoro (Runden mit Pausen)", on: .focus, keywords: "Runden, Pause, Konzentration"),
        .init("focus.askDuration", "Dauer beim Start fragen", on: .focus, keywords: "Timer, Dauer"),
        .init("focus.useExperience", "Erfahrungswerte in der Planung nutzen", on: .focus, keywords: "Planen, Dauer, Messung"),
        // Benachrichtigungen und Zugriff
        .init("quietHours.respectFocus", "Bei iOS-Fokus zurückhalten", on: .quietHours, keywords: "Nicht stören, Fokus-Filter"),
        .init("notifications.github", "GitHub-Issues", anchor: .notifications, keywords: "Benachrichtigungen, Aufgaben, Fristen"),
        .init("notifications.reminders", "Erinnerungen", anchor: .notifications, keywords: "Benachrichtigungen, Aufgaben"),
        .init("notifications.local", "Lokale Aufgaben", anchor: .notifications, keywords: "Benachrichtigungen, Aufgaben"),
        .init("notifications.deadlines", "Deadline-Termine", anchor: .notifications, keywords: "Benachrichtigungen, Fristen, Klausuren"),
        .init("access.permissions", "Zugriff", anchor: .access, keywords: "Health, Kalender, Erinnerungen, Benachrichtigungen, Berechtigungen, Erlauben"),
        .init("github.account", "GitHub", anchor: .github, keywords: "Anmelden, Abmelden, Konto, Issues, Login"),
        .init("setup.restart", "Einrichtung erneut starten", anchor: .setup, keywords: "Einrichtung, Willkommen, Neu starten"),
        // Einkaufsliste
        .init("shopping.categories", "Kategorien verwalten", on: .shopping, keywords: "Sortierung, Einkauf"),
        .init("shopping.sortWithAI", "Mit ChatGPT sortieren und übersetzen", on: .shopping, keywords: "KI, Einkauf, Übersetzen"),
    ]
}
