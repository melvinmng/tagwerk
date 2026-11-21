import SwiftUI
import TagwerkCore

/// Einstellungen › Erfassen (mockup E6a, ST1): goals and the meal-estimate consent.
struct CaptureSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var settings = environment.settings
        Form {
            Section {
                ValueStepper("Kalorien", value: $settings.goalKilocalories, in: 1000...6000, step: 50, unit: "kcal") {
                    IntakeFormat.kcal(Double($0), estimated: false)
                }
                ValueStepper("Wasser", value: $settings.goalWaterMilliliters, in: 500...6000, step: 250,
                             kind: .decimal(fractionDigits: 2), scale: 1000, unit: "l") { IntakeFormat.liters($0) }
                ValueStepper("Training pro Woche", value: $settings.goalWorkoutMinutesPerWeek, in: 0...1200, step: 15,
                             kind: .durationMinutes, display: workoutGoalText)
                ValueStepper("Schritte pro Tag", value: $settings.goalStepsPerDay, in: 0...30000, step: 500,
                             unit: "Schritte", display: stepGoalText)
                Toggle("Eiweiß-Ziel", isOn: $settings.proteinGoalEnabled)
                if settings.proteinGoalEnabled {
                    ValueStepper("Eiweiß", value: $settings.goalProteinGrams, in: 20...400, step: 5, unit: "g") {
                        IntakeFormat.grams(Double($0), estimated: false)
                    }
                }
            } header: {
                Text("Ziele")
            } footer: {
                Text("Die Vorgaben sind Platzhalter, keine Empfehlung. Trag deine eigenen Ziele ein. Zur Trainingszeit zählen Trainings aus Tagwerk und aus Health. Schritte liest Tagwerk aus Health; 0 blendet ein Ziel aus.")
            }

            Section {
                ForEach(0..<DrinkPresets.defaults.count, id: \.self) { index in
                    ValueStepper("Portion \(index + 1)", value: presetBinding(index), in: DrinkPresets.range,
                                 step: DrinkPresets.step, unit: "ml") { "\($0) ml" }
                        .accessibilityIdentifier("drinkPreset\(index + 1)")
                }
                Button("Zurücksetzen") { settings.drinkPresets = DrinkPresets.defaults }
                    .accessibilityIdentifier("drinkPresetsReset")
            } header: {
                Text("Trinkportionen")
            } footer: {
                Text("Die drei Schnellknöpfe im Tab „Erfassen“ tragen diese Mengen ein, in dieser Reihenfolge.")
            }

            Section {
                Toggle("Mahlzeiten von ChatGPT schätzen", isOn: $settings.mealEstimationConsent)
                    .disabled(!environment.ai.isSignedIn)
            } header: {
                Text("Schätzung")
            } footer: {
                if environment.ai.isSignedIn {
                    Text("Zum Schätzen sendet Tagwerk nur Text und Foto der jeweiligen Mahlzeit an ChatGPT (OpenAI), und nur, wenn du auf „Schätzen“ tippst. Daten aus Health, Ziele und frühere Einträge werden nie gesendet. Ausgeschaltet trägst du Werte selbst ein.")
                } else {
                    Text("Melde dich unter Einstellungen › KI bei ChatGPT an, um Mahlzeiten schätzen zu lassen.")
                }
            }

            Section {
                Toggle("In Planen anzeigen", isOn: $settings.showsIntakeInPlan)
                Toggle("Ernährung im Widget zeigen", isOn: $settings.widgetShowsNutrition)
            } header: {
                Text("Anzeige")
            } footer: {
                Text("„In Planen anzeigen“ zeigt Kalorien, Wasser und Schritte von heute unter dem Datum im Tab „Planen“, sobald du etwas erfasst hast. Ist „Ernährung im Widget zeigen“ aus, stehen die Werte und die Schritte nicht im Widget. Auf dem Sperrbildschirm erscheinen sie nie.")
            }
        }
        .navigationTitle("Erfassen")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// One portion of the quick buttons; every write goes through the rules, so the three values stay inside the range.
    private func presetBinding(_ index: Int) -> Binding<Int> {
        let settings = environment.settings
        return Binding(get: { settings.drinkPresets[index] },
                       set: { newValue in
                           var presets = settings.drinkPresets
                           presets[index] = newValue
                           settings.drinkPresets = presets
                       })
    }

    /// "2 h 30 min"; "aus" when the goal is off.
    private func workoutGoalText(_ minutes: Int) -> String {
        minutes > 0 ? IntakeFormat.duration(minutes: minutes) : String(localized: "aus")
    }

    /// "8.000"; "ohne Ziel" at 0.
    private func stepGoalText(_ steps: Int) -> String {
        steps > 0 ? IntakeFormat.grouped(steps) : String(localized: "ohne Ziel")
    }
}
