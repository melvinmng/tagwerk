import Foundation

/// Pages pushed onto the navigation stack of the "Einstellungen" tab. Every page of the settings has a case, so that something other
/// than a tap on its row can open it: the settings search, the global search and the UI test mode (`UITestScreen`) set the path.
enum SettingsDestination: Hashable, CaseIterable {
    case languages
    case ai
    case aiVoice
    case aiPrivacy
    case capture
    case shopping
    case siri
    case workSchedule
    case deadlineCalendars
    case travel
    case mergeRules
    case calendarDiagnostics
    case calendars
    case reminderLists
    case githubProjects
    case routines
    case bibleStudy
    case habits
    case notes
    case backup
    case focus
    case reminderDefaults
    case quietHours

    /// The page that holds the row of this page; `nil` for a page that is a row of the settings list itself.
    var parent: SettingsDestination? {
        switch self {
        case .aiVoice, .aiPrivacy: .ai
        case .bibleStudy, .habits: .routines
        default: nil
        }
    }

    /// The pages to push, outermost first, to show this page.
    var path: [SettingsDestination] {
        (parent.map { $0.path } ?? []) + [self]
    }

    /// The title of the page, as in its navigation bar.
    var title: LocalizedStringResource {
        switch self {
        case .languages: "Sprachen"
        case .ai: "KI"
        case .aiVoice: "Spracheingabe und Vorlesen"
        case .aiPrivacy: "Datenschutzhinweis"
        case .capture: "Erfassen"
        case .shopping: "Einkaufsliste"
        case .siri: "Siri & Kurzbefehle"
        case .workSchedule: "Arbeitszeit"
        case .deadlineCalendars: "Deadline-Kalender"
        case .travel: "Fahrzeit"
        case .mergeRules: "Zusammenfassen-Regeln"
        case .calendarDiagnostics: "Kalender-Diagnose"
        case .calendars: "Kalender"
        case .reminderLists: "Erinnerungslisten"
        case .githubProjects: "Projekte"
        case .routines: "Routinen"
        case .bibleStudy: "Bible Study"
        case .habits: "Gewohnheiten"
        case .notes: "Notizen"
        case .backup: "Datensicherung"
        case .focus: "Fokus-Timer"
        case .reminderDefaults: "Standard-Erinnerungen"
        case .quietHours: "Ruhezeiten"
        }
    }
}
