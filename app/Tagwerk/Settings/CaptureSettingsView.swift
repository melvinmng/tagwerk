import SwiftUI
import TagwerkCore

/// Einstellungen › Erfassen (mockup E6a): goals and the meal-estimate consent.
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
                Stepper("Trainings pro Woche: \(settings.goalWorkoutsPerWeek)", value: $settings.goalWorkoutsPerWeek, in: 0...14)
                Toggle("Eiweiß-Ziel", isOn: $settings.proteinGoalEnabled)
                if settings.proteinGoalEnabled {
                    Stepper("Eiweiß: \(settings.goalProteinGrams) g", value: $settings.goalProteinGrams, in: 20...400, step: 5)
                }
            } header: {
                Text("Ziele")
            } footer: {
                Text("Die Vorgaben sind Platzhalter, keine Empfehlung. Trag deine eigenen Ziele ein. Als Training zählt jede Einheit ab 10 min, aus Tagwerk oder aus Health.")
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
                Text("„In Planen anzeigen“ zeigt Kalorien und Wasser von heute unter dem Datum im Tab „Planen“, sobald du etwas erfasst hast. Ist „Ernährung im Widget zeigen“ aus, stehen die Werte nicht im Widget. Auf dem Sperrbildschirm erscheinen sie nie.")
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

    private func phrase(_ text: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("„\(text)“")
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}
