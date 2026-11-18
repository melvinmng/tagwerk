import SwiftUI

/// The assistant button (mockup AK2): in every tab top right, outermost, its own purple glass circle of
/// 44 pt, never inside the ＋ capsule. Opens the chat with the context of that tab.
struct AssistantButton: View {
    @Environment(AppEnvironment.self) private var environment
    let context: () -> AssistantModel.Context

    var body: some View {
        Button {
            environment.assistant.open(context: context())
        } label: {
            Image(systemName: "sparkles")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(.purple.opacity(0.75)).interactive(), in: .circle)
        .contentShape(Circle())
        .accessibilityLabel("Assistent")
        .accessibilityHint("Öffnet ChatGPT mit dem Kontext dieses Bildschirms")
    }
}

/// The assistant button as the outermost trailing toolbar item, kept apart from other items (mockup AK2).
/// Put it last in the toolbar block so it ends up outermost.
struct AssistantToolbarItems: ToolbarContent {
    let context: () -> AssistantModel.Context

    var body: some ToolbarContent {
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) { AssistantButton(context: context) }
            .sharedBackgroundVisibility(.hidden)
    }
}

extension View {
    /// For screens without other trailing items.
    func assistantToolbarButton(_ context: @escaping () -> AssistantModel.Context) -> some View {
        toolbar { AssistantToolbarItems(context: context) }
    }
}
