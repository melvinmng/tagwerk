import SwiftUI
import TagwerkCore

/// The row every consent sheet of a function with AI proposals carries (plan ki-vorschlaege-anpassen, AN10a): a follow-up
/// message sends the same data again, plus the proposal with the user's changes and the message. The sentence is the
/// same on every sheet, so the consent covers it and nobody has to agree again.
struct ConsentFollowUpPoint: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.turn.down.right").foregroundStyle(.tint).frame(width: 24).accessibilityHidden(true)
            Text("Wenn du zu einem Vorschlag etwas zurückschreibst, sendet Tagwerk dieselben Angaben noch einmal, dazu den Vorschlag mit deinen Änderungen und deine Nachricht.")
        }
    }

    /// The sentence in a given language, for tests and for a card read aloud.
    static func sentence(in language: VoiceLanguage) -> String {
        Localized.string("Wenn du zu einem Vorschlag etwas zurückschreibst, sendet Tagwerk dieselben Angaben noch einmal, dazu den Vorschlag mit deinen Änderungen und deine Nachricht.",
                         in: language, bundle: .main)
    }
}
