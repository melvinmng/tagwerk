import SwiftUI

/// The one-time consent before the first meal estimate (mockup E3a, main design §7).
struct MealConsentSheet: View {
    let onAgree: () -> Void
    let onDecline: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Zum Schätzen sendet Tagwerk deine Beschreibung und, wenn du eines aufnimmst, das Foto der Mahlzeit an ChatGPT (OpenAI), über das Konto, mit dem du angemeldet bist.")
                    point("paperplane", "**Gesendet wird** nur der Text und das Foto dieser Mahlzeit. Fotos gehen verkleinert und ohne Ortsangabe raus.")
                    point("heart.slash", "**Nicht gesendet werden** Daten aus Health, deine Ziele und frühere Einträge.")
                    point("hand.tap", "**Nur auf dein Tippen:** Ohne „Schätzen“ verlässt nichts das iPhone.")
                    ConsentFollowUpPoint()
                    Text("Wie OpenAI die gesendeten Daten behandelt, richtet sich nach den Einstellungen deines ChatGPT-Kontos.")
                        .font(.footnote).foregroundStyle(.secondary)
                    VStack(spacing: 10) {
                        Button(action: onAgree) {
                            Text("Einverstanden und schätzen").fontWeight(.semibold).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        Button("Nicht jetzt", action: onDecline)
                    }
                    .padding(.top, 4)
                    Text("Du kannst das in den Einstellungen unter „Erfassen“ widerrufen.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle("Mahlzeiten von ChatGPT schätzen lassen")
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
