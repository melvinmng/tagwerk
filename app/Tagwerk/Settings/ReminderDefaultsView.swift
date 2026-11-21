import SwiftUI
import TagwerkCore

/// "Standard-Erinnerungen" (plan P4): when Tagwerk reminds by default, separately for calendar events, Apple reminders,
/// GitHub issues, local tasks and deadlines, each for entries with and without a time of day. Opening the page writes nothing; only a change is stored.
struct ReminderDefaultsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model: ReminderDefaultsModel?

    var body: some View {
        Form {
            if let model {
                ForEach(ReminderDefaultsModel.slots) { slot in
                    Section {
                        ReminderSelectionRows(model: model.list(slot), subject: slot.kind.subject, defaultSwitchTitle: nil, calendar: .tagwerk)
                    } header: {
                        Text(Self.header(for: slot))
                    } footer: {
                        if let footer = Self.footer(for: slot) { Text(footer) }
                    }
                }
            }
        }
        .navigationTitle("Standard-Erinnerungen")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil { model = ReminderDefaultsModel(defaults: environment.settings.reminderDefaults) }
        }
        .onChange(of: model?.defaults) { old, defaults in
            // The first value, when the model is created, is not a change.
            if old != nil, let defaults { environment.settings.reminderDefaults = defaults }
        }
    }

    private static func header(for slot: ReminderDefaultsModel.Slot) -> LocalizedStringKey {
        switch (slot.kind, slot.isAllDay) {
        case (.event, false): "Kalendertermine mit Uhrzeit"
        case (.event, true): "Kalendertermine ganztägig"
        case (.appleReminder, false): "Apple Erinnerungen mit Uhrzeit"
        case (.appleReminder, true): "Apple Erinnerungen ohne Uhrzeit"
        case (.githubIssue, false): "GitHub-Issues mit Uhrzeit"
        case (.githubIssue, true): "GitHub-Issues ohne Uhrzeit"
        case (.localTask, false): "Lokale Aufgaben mit Uhrzeit"
        case (.localTask, true): "Lokale Aufgaben ohne Uhrzeit"
        case (.deadline, false): "Deadline-Termine mit Uhrzeit"
        case (.deadline, true): "Deadline-Termine ganztägig"
        }
    }

    /// The explanation sits under the second list of each kind.
    private static func footer(for slot: ReminderDefaultsModel.Slot) -> LocalizedStringKey? {
        guard slot.isAllDay else { return nil }
        switch slot.kind {
        case .event: return "Wird beim Anlegen eines Termins in Tagwerk übernommen. Bestehende Termine bleiben unverändert."
        case .appleReminder: return "Gilt für alle Apple Erinnerungen ohne eigene Erinnerungen."
        case .githubIssue: return "Gilt für alle GitHub-Issues ohne eigene Erinnerungen."
        case .localTask: return "Gilt für alle lokalen Aufgaben ohne eigene Erinnerungen."
        case .deadline: return "Gilt für alle Deadline-Termine ohne eigene Erinnerungen."
        }
    }
}
