import SwiftUI

/// The consent for the assistant to work with notes (mockup NC5b), shown by the entries in the notes (`NoteAssistantToolbarItems`)
/// while "Notizen mit ChatGPT" is off. "Einverstanden" sets the same setting as the switch under Einstellungen › KI.
/// Built like `NoteConsentSheet`. The wording has to agree with the footer of the switch and with `AIPrivacyView`.
struct NoteAssistantConsentSheet: View {
    /// Names of the folders that never leave the device, as the user sees them (`NoteToolAccess.privateFolderNames`).
    let privateFolderNames: [String]
    let onAgree: () -> Void
    let onDecline: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Damit der Assistent deine Notizen finden, lesen, überarbeiten, anlegen und löschen kann, sendet Tagwerk Notizen an ChatGPT (OpenAI), über das Konto, mit dem du angemeldet bist.")
                    point("paperplane", "**Gesendet wird:** die Titel deiner Notizen, kurze Ausschnitte zu Suchtreffern und der Text der Notizen, um die es im Gespräch geht, mit den Namen ihrer Anhänge.")
                    point("sparkles", "**Gilt überall beim Assistenten:** in diesem Notiz-Chat und für die Suche des Assistenten in allen anderen Gesprächen.")
                    point("lock", "**Nie gesendet werden:** \(NoteToolAccess.listText(privateFolderNames)), gelöschte Notizen und die Anhänge selbst.")
                    point("checkmark.circle", "**Nichts ändert sich ohne dich:** Jede Änderung, jede neue Notiz und jedes Löschen bestätigst du einzeln.")
                    point("hand.tap", "**Nur im Gespräch:** Ohne deine Nachricht an den Assistenten verlässt nichts das iPhone. Gelesene Notiztexte gelten nur für das laufende Gespräch und werden nicht im Verlauf gespeichert; die Antworten des Assistenten schon.")
                    VStack(spacing: 10) {
                        Button(action: onAgree) {
                            Text("Einverstanden").fontWeight(.semibold).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        Button("Nicht jetzt", action: onDecline)
                    }
                    .padding(.top, 4)
                    Text("Du kannst das in den Einstellungen unter „KI“ widerrufen.")
                        .font(.footnote).foregroundStyle(.secondaryText)
                        .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle("Notizen mit ChatGPT")
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
