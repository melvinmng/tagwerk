import SwiftUI

/// The goal planning in Einstellungen › Erfassen: the switch of the consent "Ziele mit ChatGPT planen" (decision PV1b). Switching it off
/// ends a running conversation and drops the data package of its session.
struct GoalPlanningSettingsSection: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var settings = environment.settings
        Section {
            Button {
                Task { await environment.goalPlanning.start(.plan) }
            } label: {
                Label("Ziele planen", systemImage: "sparkles")
            }
            .disabled(!environment.ai.isSignedIn || environment.goalPlanning.isPreparing)
            .accessibilityIdentifier(AccessibilityID.GoalPlanning.planEntry)
            // Withdrawing stays possible without a sign-in; only giving the consent needs one.
            Toggle("Ziele mit ChatGPT planen", isOn: $settings.goalPlanningConsent)
                .disabled(!environment.ai.isSignedIn && !settings.goalPlanningConsent)
                .accessibilityIdentifier(AccessibilityID.GoalPlanning.consentSwitch)
        } header: {
            Text("Zielplanung")
        } footer: {
            if environment.ai.isSignedIn {
                Text("Zum Planen deiner Ziele sendet Tagwerk auf dein Tippen die Angaben, die du vor jedem Gespräch auswählst, an ChatGPT (OpenAI): Größe, Alter, Geschlecht, Gewicht, Durchschnittswerte der letzten Wochen und deine geltenden Ziele. Einzelne Mahlzeiten, Fotos, Notizen, Aufgaben und Termine werden nie gesendet. Ausschalten beendet ein laufendes Gespräch. Tagwerk gibt keine medizinische Beratung.")
            } else {
                Text("Melde dich unter Einstellungen › KI bei ChatGPT an, um Ziele planen zu lassen.")
            }
        }
    }
}
