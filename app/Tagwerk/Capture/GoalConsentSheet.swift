import SwiftUI

/// The one-time consent for the goal planning with ChatGPT (decision PV1b, mockup PV1b). It has its own purpose, its own promise and its
/// own switch; the promises of the meal and note sheets ("Nicht gesendet werden Daten aus Health, deine Ziele …") stay literally true,
/// because this consent covers only the chat "Ziele planen" and only the data package the user selects before every conversation.
struct GoalConsentSheet: View {
    let onAgree: () -> Void
    let onDecline: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Zum Planen deiner Ziele sendet Tagwerk Angaben über deinen Körper und deine Ernährung an ChatGPT (OpenAI), über das Konto, mit dem du angemeldet bist.")
                    point("paperplane", "**Gesendet werden** nur die Angaben, die du vor jedem Gespräch auswählst: Größe, Alter, Geschlecht, Gewicht, Durchschnittswerte der letzten Wochen und deine geltenden Ziele. Durchschnittswerte enthalten auch Einträge anderer Apps aus Health, wenn du sie mitzählen lässt.")
                    point("heart.slash", "**Nicht gesendet werden** einzelne Mahlzeiten, Fotos, Notizen, Aufgaben und Termine.")
                    point("hand.tap", "**Nur auf dein Tippen:** Ohne „Ziele planen“ verlässt nichts davon das iPhone.")
                    point("cross.case", "**Keine medizinische Beratung:** Vorschläge sind Schätzungen. Bei Erkrankungen, Schwangerschaft oder Essstörungen sprich mit einer Ärztin oder einem Arzt.")
                    Text("Wie OpenAI die gesendeten Daten behandelt, richtet sich nach den Einstellungen deines ChatGPT-Kontos.")
                        .font(.footnote).foregroundStyle(.secondaryText)
                    VStack(spacing: 10) {
                        Button(action: onAgree) {
                            Text("Einverstanden und weiter").fontWeight(.semibold).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityIdentifier(AccessibilityID.GoalPlanning.consentAgree)
                        Button("Nicht jetzt", action: onDecline)
                    }
                    .padding(.top, 4)
                    Text("Du kannst das in den Einstellungen unter „Erfassen“ widerrufen. Ein Widerruf beendet auch ein laufendes Gespräch.")
                        .font(.footnote).foregroundStyle(.secondaryText)
                        .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle("Ziele mit ChatGPT planen")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled()
    }

    private func point(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 24)
            Text(text)
        }
    }
}
