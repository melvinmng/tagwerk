import SwiftUI

/// The assistant button (fallback K2): ✦ top right next to ＋ in every tab, opening the chat with the
/// context of that tab.
struct AssistantButton: View {
    @Environment(AppEnvironment.self) private var environment
    let context: () -> AssistantModel.Context

    var body: some View {
        Button {
            environment.assistant.open(context: context())
        } label: {
            Image(systemName: "sparkles").frame(width: 22, height: 22)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .tint(.purple)
        .accessibilityLabel("Assistent")
        .accessibilityHint("Öffnet ChatGPT mit dem Kontext dieses Bildschirms")
    }
}
