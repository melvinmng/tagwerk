import SwiftUI
import TagwerkCore

/// Einstellungen › Benachrichtigungen › Ruhezeiten (plan quiet-hours, #169): task and deadline notifications that fall
/// into the window move to its end.
struct QuietHoursSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Right side of the row in the settings list: "Aus" or "23:00–07:00".
    static func summary(_ settings: AppSettings) -> String {
        guard let window = settings.quietHours else { return String(localized: "Aus") }
        let start = DateText.time(minutes: window.startMinutes, calendar: .tagwerk)
        let end = DateText.time(minutes: window.endMinutes, calendar: .tagwerk)
        return "\(start)–\(end)"
    }

    var body: some View {
        @Bindable var settings = environment.settings
        Form {
            Section {
                Toggle("Ruhezeiten", isOn: $settings.quietHoursEnabled)
                if settings.quietHoursEnabled {
                    Toggle("Beginn bei Zielschlafzeit", isOn: $settings.quietHoursStartsAtBedtime)
                    if settings.quietHoursStartsAtBedtime {
                        LabeledContent("Beginn", value: DateText.time(minutes: settings.bedtimeMinutes, calendar: .tagwerk))
                    } else {
                        DatePicker("Beginn", selection: $settings.quietStartMinutes.asTime(), displayedComponents: .hourAndMinute)
                    }
                    DatePicker("Ende", selection: $settings.quietEndMinutes.asTime(), displayedComponents: .hourAndMinute)
                }
            } footer: {
                Text("Mitteilungen zu Aufgaben und Deadline-Terminen, die in die Ruhezeit fallen, kommen erst am Ende der Ruhezeit. Sie entfallen nicht. Erinnerungen der Routinen bleiben davon ausgenommen. Die Zielschlafzeit stellst du unter Routinen ein.")
            }

            Section {
                Text("Zusätzlich kannst du in den iOS-Einstellungen unter Fokus einen Fokus-Filter für Tagwerk hinzufügen und „Aufgaben und Deadlines zurückhalten“ wählen. Solange dieser Fokus aktiv ist, hält Tagwerk die Mitteilungen zurück, bis der Fokus endet, spätestens nach 4 Stunden. Danach kommen Mitteilungen, die inzwischen fällig wurden.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Fokus")
            }
        }
        .navigationTitle("Ruhezeiten")
        .navigationBarTitleDisplayMode(.inline)
    }
}
