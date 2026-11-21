import SwiftUI
import TagwerkCore

/// Texts and symbol of the mark that tells who last changed a proposal (plan ki-vorschlaege-anpassen, AN2a).
/// The same mark is used by the action cards, the follow-up bar and the preview sheets.
extension ProposalMark {
    /// "von dir angepasst" / "von ChatGPT angepasst"; `language` is the language of the answer when a card is read aloud.
    func label(in language: VoiceLanguage = .app) -> String {
        switch self {
        case .byUser: Localized.string("von dir angepasst", in: language, bundle: .main)
        case .byAssistant: Localized.string("von ChatGPT angepasst", in: language, bundle: .main)
        }
    }

    var symbolName: String {
        switch self {
        case .byUser: "pencil"
        case .byAssistant: "sparkles"
        }
    }
}

/// The mark as a small capsule; read by VoiceOver as part of the card (the symbol is decoration).
struct ProposalMarkLabel: View {
    let mark: ProposalMark

    var body: some View {
        Label {
            Text(mark.label())
        } icon: {
            Image(systemName: mark.symbolName).accessibilityHidden(true)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.15), in: Capsule())
    }
}
