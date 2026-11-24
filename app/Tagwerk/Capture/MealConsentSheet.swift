import SwiftUI

/// The one-time consent before the first meal estimate (mockup E3a, main design §7).
struct MealConsentSheet: View {
    /// What the user is about to do; the consent is the same for both, the text names the one that was tapped.
    enum Purpose { case estimate, label }

    var purpose: Purpose = .estimate
    let onAgree: () -> Void
    let onDecline: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Zum Schätzen sendet Tagwerk deine Beschreibung und, wenn du eines aufnimmst, das Foto der Mahlzeit an ChatGPT (OpenAI), über das Konto, mit dem du angemeldet bist. Zum Lesen eines Etiketts sendet Tagwerk das Foto der Nährwerttabelle.")
                    point("paperplane", "**Gesendet wird** nur der Text und das Foto dieser Mahlzeit, beim Etikett nur das Foto der Nährwerttabelle. Fotos gehen verkleinert und ohne Ortsangabe raus.")
                    point("heart.slash", "**Nicht gesendet werden** Daten aus Health, deine Ziele und frühere Einträge.")
                    point("hand.tap", "**Nur auf dein Tippen:** Ohne „Schätzen“ und ohne ein Foto, das du für ein Etikett aufnimmst oder auswählst, verlässt nichts das iPhone.")
                    ConsentFollowUpPoint()
                    Text("Wie OpenAI die gesendeten Daten behandelt, richtet sich nach den Einstellungen deines ChatGPT-Kontos.")
                        .font(.footnote).foregroundStyle(.secondaryText)
                    VStack(spacing: 10) {
                        Button(action: onAgree) {
                            Text(purpose == .estimate ? "Einverstanden und schätzen" : "Einverstanden und Etikett lesen")
                                .fontWeight(.semibold).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        Button("Nicht jetzt", action: onDecline)
                    }
                    .padding(.top, 4)
                    Text("Du kannst das in den Einstellungen unter „Erfassen“ widerrufen.")
                        .font(.footnote).foregroundStyle(.secondaryText)
                        .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle(purpose == .estimate ? "Mahlzeiten von ChatGPT schätzen lassen" : "Etikett von ChatGPT lesen lassen")
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
