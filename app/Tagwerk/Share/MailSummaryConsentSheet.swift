import SwiftUI

/// The one-time consent before the first mail summary (pattern of `MealConsentSheet`).
struct MailSummaryConsentSheet: View {
    let onAgree: () -> Void
    let onDecline: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Für die Zusammenfassung sendet Tagwerk Betreff, Absendername und Text der Mail an ChatGPT (OpenAI), nur wenn du auf „Mit ChatGPT zusammenfassen“ tippst. Anhänge, Adressen und Empfänger werden nie gesendet.")
                    point("paperplane", "**Gesendet wird** der Betreff, der Name des Absenders und der Text der Mail, höchstens 12 000 Zeichen.")
                    point("eye.slash", "**Nicht gesendet werden** Anhänge, E-Mail-Adressen (auch im Text), Empfänger und der Link zur Mail.")
                    point("hand.tap", "**Nur auf dein Tippen:** Ohne „Mit ChatGPT zusammenfassen“ verlässt nichts das iPhone. Die Vorschläge übernimmst du erst, wenn du sie bestätigst.")
                    Text("Wie OpenAI die gesendeten Daten behandelt, richtet sich nach den Einstellungen deines ChatGPT-Kontos.")
                        .font(.footnote).foregroundStyle(.secondary)
                    VStack(spacing: 10) {
                        Button(action: onAgree) {
                            Text("Einverstanden und zusammenfassen").fontWeight(.semibold).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        Button("Nicht jetzt", action: onDecline)
                    }
                    .padding(.top, 4)
                    Text("Du kannst das in den Einstellungen unter „KI“ widerrufen.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle("Mails von ChatGPT zusammenfassen")
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
