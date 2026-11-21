import AIKit
import SwiftUI

/// The sheet "Vorschlag anpassen" (mockup AN2a): the fields of the function, "Zurück zum Vorschlag der KI" once the
/// card carries a mark, and "Fertig", which writes the values back into the card. Nothing is carried out here; the
/// card is confirmed with "Bestätigen" (AN2a). The sheet hangs on the chat view, never on the card (a sheet on a
/// row of a list or form does not open reliably).
struct ProposalAdjustSheet: View {
    let assistant: AssistantModel
    let call: ToolCall
    @Environment(\.dismiss) private var dismiss
    @State private var editor: (any ProposalEditor)?

    private var isMarked: Bool { assistant.conversation?.isAdjusted(call) == true }

    var body: some View {
        NavigationStack {
            Form {
                if let editor {
                    editor.fields
                }
                if isMarked {
                    Section {
                        Button("Zurück zum Vorschlag der KI", role: .destructive) {
                            assistant.resetAdjustment(call)
                            dismiss()
                        }
                    }
                }
                Section {
                } footer: {
                    Text("Geändert wird nur der Vorschlag. Ausgeführt wird erst mit „Bestätigen“ auf der Karte.")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Vorschlag anpassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        if let editor { assistant.adjust(call, arguments: editor.arguments()) }
                        dismiss()
                    }
                    .disabled(editor?.isValid != true)
                }
            }
            .task {
                if editor == nil { editor = assistant.proposalEditor(for: call) }
                await editor?.load()
            }
        }
        .presentationDetents([.large])
        .modifier(UITestAppearance())
    }
}
