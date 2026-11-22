import SwiftUI
import TagwerkCore

/// Shared text as shopping items: one item per line (commas and "und" also split), checked before anything is added.
struct ShareShoppingSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let item: ShareInboxItem
    let onFinished: () -> Void

    @State private var text: String
    @State private var isAdding = false
    @State private var errorText: String?

    init(item: ShareInboxItem, onFinished: @escaping () -> Void) {
        self.item = item
        self.onFinished = onFinished
        _text = State(initialValue: item.text ?? item.title)
    }

    private var parsed: ShoppingInputParser.ParseResult { ShoppingInputParser.parseAll(text) }
    private var hasList: Bool { environment.settings.shoppingListID != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                        .keyboardDoneButton()
                } header: {
                    Text("Artikel, einer pro Zeile")
                } footer: {
                    if !hasList {
                        Text("Richte zuerst unter Einstellungen › Einkaufsliste eine Liste ein.")
                    } else if parsed.droppedCount > 0 {
                        Text("Höchstens 20 Artikel auf einmal")
                    }
                }
                if !parsed.items.isEmpty {
                    Section("Wird hinzugefügt") {
                        ForEach(parsed.items, id: \.self) { parsedItem in
                            Text(ShoppingInput.chipTitle(parsedItem))
                        }
                    }
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(.redText) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Einkauf")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") { Task { await add() } }
                        .disabled(!hasList || parsed.items.isEmpty || isAdding)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Verwerfen", role: .destructive) {
                        onFinished()
                        dismiss()
                    }
                }
            }
        }
    }

    private func add() async {
        isAdding = true
        defer { isAdding = false }
        let report = await environment.shopping.add(parsed.items)
        if report.failed.isEmpty {
            onFinished()
            dismiss()
        } else {
            errorText = report.errorMessage
        }
    }
}
