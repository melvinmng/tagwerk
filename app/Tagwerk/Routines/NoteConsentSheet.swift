import SwiftUI

/// The one-time consent before the first "Vorschläge holen" (mockup GZ1, design §9.1); built like `MealConsentSheet`.
struct NoteConsentSheet: View {
    let onAgree: () -> Void
    let onDecline: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Für Vorschläge sendet Tagwerk den Text dieser Notiz an ChatGPT (OpenAI), über das Konto, mit dem du angemeldet bist.")
                    point("paperplane", "**Gesendet wird** der Text dieser einen Notiz, dazu deine offenen Aufgaben und Termine der nächsten 7 Tage (Titel, Fälligkeit, Zeit).")
                    point("heart.slash", "**Nicht gesendet werden** Dankbarkeit, Gewohnheiten, Wochenreflexion, Daten aus Health und frühere Notizen.")
                    point("hand.tap", "**Nur auf dein Tippen:** Ohne „Vorschläge holen“ verlässt keine Notiz das iPhone.")
                    Text("Wie OpenAI die gesendeten Daten behandelt, richtet sich nach den Einstellungen deines ChatGPT-Kontos.")
                        .font(.footnote).foregroundStyle(.secondaryText)
                    VStack(spacing: 10) {
                        Button(action: onAgree) {
                            Text("Einverstanden und Vorschläge holen").fontWeight(.semibold).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        Button("Nicht jetzt", action: onDecline)
                    }
                    .padding(.top, 4)
                    Text("Du kannst das in den Einstellungen unter „Routinen“ widerrufen.")
                        .font(.footnote).foregroundStyle(.secondaryText)
                        .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle("Notizen von ChatGPT auswerten lassen")
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
