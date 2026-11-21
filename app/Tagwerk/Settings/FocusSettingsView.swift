import SwiftUI
import TagwerkCore

/// Einstellungen › Fokus-Timer (plan P3, #161, #162; FO12b): templates, durations, Pomodoro, the start sheet, the
/// collection and the use of measured effort in the planning.
struct FocusSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    /// "Eigene" stays selected while the user edits values that happen to match a template.
    @State private var isCustom: Bool?

    private var presetSelection: Binding<FocusPreset> {
        Binding(get: {
            (isCustom ?? (FocusPreset.matching(environment.settings.focusTimerSettings) == .custom)) ? .custom
                : FocusPreset.matching(environment.settings.focusTimerSettings)
        }, set: { preset in
            isCustom = preset == .custom
            environment.settings.focusTimerSettings = preset.applied(to: environment.settings.focusTimerSettings)
        })
    }

    var body: some View {
        @Bindable var settings = environment.settings
        Form {
            Section {
                Picker("Vorlage", selection: presetSelection) {
                    Text(verbatim: "25 / 5").tag(FocusPreset.classic)
                    Text(verbatim: "50 / 10").tag(FocusPreset.long)
                    Text("Eigene").tag(FocusPreset.custom)
                }
                .pickerStyle(.segmented)
                Toggle("Pomodoro (Runden mit Pausen)", isOn: $settings.focusUsesPomodoro)
                ValueStepper("Fokus", value: $settings.focusWorkMinutes, in: 5...120, step: 5, kind: .durationMinutes,
                             unit: "min", display: ValueStepper.minutesText)
                if settings.focusUsesPomodoro {
                    ValueStepper("Pause", value: $settings.focusShortBreakMinutes, in: 1...30, kind: .durationMinutes,
                                 unit: "min", display: ValueStepper.minutesText)
                    ValueStepper("Lange Pause", value: $settings.focusLongBreakMinutes, in: 5...60, step: 5, kind: .durationMinutes,
                                 unit: "min", display: ValueStepper.minutesText)
                    ValueStepper("Runden", value: $settings.focusRounds, in: 1...8) { "\($0)" }
                }
            } footer: {
                Text("Mit Pomodoro wechseln sich Fokus und Pause ab, nach der letzten Runde folgt die lange Pause. Ohne Pomodoro läuft eine einzelne Fokuszeit. Ein Zeitblock ohne Pomodoro setzt die Fokuszeit auf seine Restlänge.")
            }

            Section {
                Toggle("Dauer beim Start fragen", isOn: $settings.focusAsksDurationAtStart)
            } footer: {
                Text("Vor dem Start erscheint ein Blatt, in dem du die Dauer wählst. Siri, das Kontrollzentrum und Kurzbefehle starten immer ohne Blatt mit den Werten von oben.")
            }

            Section("Sammlung") {
                NavigationLink {
                    FocusCollectionView()
                } label: {
                    LabeledContent("Sammlung ansehen", value: FocusTimerText.collectionSummary(collectionSummary))
                }
            }

            Section {
                Toggle("Erfahrungswerte in der Planung nutzen", isOn: $settings.effortHistoryInPlanning)
            } header: {
                Text("Planung")
            } footer: {
                Text("Tagwerk misst den Aufwand beim Abhaken aus den Zeitblöcken der Aufgabe. Fokus-Timer-Zeit zählt nur, soweit sie außerhalb dieser Blöcke liegt, ohne Zeitblock zählt sie allein. Die Messwerte bleiben auf dem iPhone. Ist der Schalter an, geht bei der KI-Planung je Aufgabe nur eine erwartete Dauer in Minuten mit, keine Labels und keine Statistik.")
            }
        }
        .navigationTitle("Fokus-Timer")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var collectionSummary: FocusCollectionSummary {
        FocusReward.summary(of: environment.focusStore.finishedSessions().compactMap(\.piece))
    }
}
