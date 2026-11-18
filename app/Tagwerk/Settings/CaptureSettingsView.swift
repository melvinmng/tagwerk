import SwiftUI
import TagwerkCore

/// Einstellungen › Erfassen (mockup E6a, ST1): goals and the meal-estimate consent.
struct CaptureSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var settings = environment.settings
        Form {
            Section {
                Stepper("Kalorien: \(IntakeFormat.grouped(settings.goalKilocalories)) kcal", value: $settings.goalKilocalories,
                        in: 1000...6000, step: 50)
                Stepper("Wasser: \(IntakeFormat.liters(settings.goalWaterMilliliters))", value: $settings.goalWaterMilliliters,
                        in: 500...6000, step: 250)
                Stepper("Training pro Woche: \(workoutGoalText(settings.goalWorkoutMinutesPerWeek))",
                        value: $settings.goalWorkoutMinutesPerWeek, in: 0...1200, step: 15)
                Stepper("Schritte pro Tag: \(stepGoalText(settings.goalStepsPerDay))", value: $settings.goalStepsPerDay,
                        in: 0...30000, step: 500)
                Toggle("Eiweiß-Ziel", isOn: $settings.proteinGoalEnabled)
                if settings.proteinGoalEnabled {
                    Stepper("Eiweiß: \(settings.goalProteinGrams) g", value: $settings.goalProteinGrams, in: 20...400, step: 5)
                }
            } header: {
                Text("Ziele")
            } footer: {
                Text("Die Vorgaben sind Platzhalter, keine Empfehlung. Trag deine eigenen Ziele ein. Zur Trainingszeit zählen Trainings aus Tagwerk und aus Health. Schritte liest Tagwerk aus Health; 0 blendet ein Ziel aus.")
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

            Section {
                phrase("Wasser in Tagwerk erfassen", "Trägt 250 ml ein, ohne Tagwerk zu öffnen")
                phrase("Mahlzeit in Tagwerk erfassen", "Öffnet das Blatt „Essen“")
                phrase("Training in Tagwerk erfassen", "Öffnet das Blatt „Training“")
                phrase("Was steht heute in Tagwerk an?", "Nennt Termine, Blöcke und Deadlines von heute")
            } header: {
                Text("Siri & Kurzbefehle")
            } footer: {
                Text("Sag einen der Sätze zu Siri oder füge ihn in der App „Kurzbefehle“ hinzu. „Wasser erfassen“ lässt sich dort auch auf die Aktionstaste oder den Home-Bildschirm legen.")
            }
        }
        .navigationTitle("Erfassen")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "2 h 30 min"; "aus" when the goal is off.
    private func workoutGoalText(_ minutes: Int) -> String {
        minutes > 0 ? IntakeFormat.duration(minutes: minutes) : String(localized: "aus")
    }

    /// "8.000"; "ohne Ziel" at 0.
    private func stepGoalText(_ steps: Int) -> String {
        steps > 0 ? IntakeFormat.grouped(steps) : String(localized: "ohne Ziel")
    }

    private func phrase(_ text: LocalizedStringResource, _ detail: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("„\(String(localized: text))“")
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}
