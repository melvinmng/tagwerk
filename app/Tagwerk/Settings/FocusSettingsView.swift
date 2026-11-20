import SwiftUI

/// Einstellungen › Fokus-Timer (plan P3, #161, #162): durations, Pomodoro and the use of measured effort in the planning.
struct FocusSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var settings = environment.settings
        Form {
            Section {
                Toggle("Pomodoro", isOn: $settings.focusUsesPomodoro)
                Stepper("Fokus: \(settings.focusWorkMinutes) min", value: $settings.focusWorkMinutes, in: 5...120, step: 5)
                if settings.focusUsesPomodoro {
                    Stepper("Pause: \(settings.focusShortBreakMinutes) min", value: $settings.focusShortBreakMinutes, in: 1...30)
                    Stepper("Lange Pause: \(settings.focusLongBreakMinutes) min", value: $settings.focusLongBreakMinutes, in: 5...60, step: 5)
                    Stepper("Runden: \(settings.focusRounds)", value: $settings.focusRounds, in: 1...8)
                }
            } footer: {
                Text("Mit Pomodoro wechseln sich Fokus und Pause ab, nach der letzten Runde folgt die lange Pause. Ohne Pomodoro läuft eine einzelne Fokuszeit. Ein Zeitblock ohne Pomodoro setzt die Fokuszeit auf seine Restlänge.")
            }

            Section {
                Toggle("Erfahrungswerte in der Planung nutzen", isOn: $settings.effortHistoryInPlanning)
            } footer: {
                Text("Tagwerk misst den Aufwand beim Abhaken aus den Zeitblöcken der Aufgabe. Fokus-Timer-Zeit zählt nur, soweit sie außerhalb dieser Blöcke liegt, ohne Zeitblock zählt sie allein. Die Messwerte bleiben auf dem iPhone. Ist der Schalter an, geht bei der KI-Planung je Aufgabe nur eine erwartete Dauer in Minuten mit, keine Labels und keine Statistik.")
            }
        }
        .navigationTitle("Fokus-Timer")
        .navigationBarTitleDisplayMode(.inline)
    }
}
