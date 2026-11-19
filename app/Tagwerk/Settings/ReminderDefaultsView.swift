import SwiftUI
import TagwerkCore

/// "Standard-Erinnerungen" (plan P4): when Tagwerk reminds by default, for tasks, deadlines and events, each for entries
/// with and without a time of day. Opening the page writes nothing; only a change is stored.
struct ReminderDefaultsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model: ReminderDefaultsModel?

    var body: some View {
        Form {
            if let model {
                ForEach(ReminderDefaultsModel.slots) { slot in
                    Section {
                        ReminderListEditor(model: model.list(slot), defaultSwitchTitle: nil, calendar: .tagwerk)
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
        .onChange(of: model?.defaults) { _, defaults in
            if let defaults { environment.settings.reminderDefaults = defaults }
        }
    }

    private static func header(for slot: ReminderDefaultsModel.Slot) -> LocalizedStringKey {
        switch (slot.kind, slot.isAllDay) {
        case (.task, false): "Aufgaben mit Uhrzeit"
        case (.task, true): "Aufgaben ohne Uhrzeit"
        case (.deadline, false): "Deadlines mit Uhrzeit"
        case (.deadline, true): "Deadlines ganztägig"
        case (.event, false): "Termine mit Uhrzeit"
        case (.event, true): "Termine ganztägig"
        }
    }

    /// The explanation sits under the second list of each kind.
    private static func footer(for slot: ReminderDefaultsModel.Slot) -> LocalizedStringKey? {
        guard slot.isAllDay else { return nil }
        switch slot.kind {
        case .task: return "Gilt für alle Aufgaben ohne eigene Erinnerungen."
        case .deadline: return "Gilt für alle Deadline-Termine ohne eigene Erinnerungen."
        case .event: return "Wird beim Anlegen eines Termins in Tagwerk übernommen. Bestehende Termine bleiben unverändert."
        }
    }
}
