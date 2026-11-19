import SwiftUI
import TagwerkCore

/// The sheet "Artikel": name, quantity, category and delete.
struct ShoppingItemSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let model: ShoppingModel
    let item: ShoppingItem
    /// Reports the text of a write error to the page.
    let onError: (String) -> Void

    @State private var name: String
    @State private var quantity: String
    @State private var categoryID: UUID?

    init(model: ShoppingModel, item: ShoppingItem, onError: @escaping (String) -> Void) {
        self.model = model
        self.item = item
        self.onError = onError
        _name = State(initialValue: item.name)
        _quantity = State(initialValue: item.quantity ?? "")
        _categoryID = State(initialValue: model.categoryID(of: item))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    if item.hasLongNotes {
                        LabeledContent("Menge", value: item.quantity ?? "")
                    } else {
                        TextField("Menge", text: $quantity)
                    }
                } footer: {
                    if item.hasLongNotes { Text("Längere Notiz, in Erinnerungen bearbeiten") }
                }
                Section {
                    Picker("Kategorie", selection: $categoryID) {
                        ForEach(environment.shoppingCategories.categories()) { category in
                            Text(category.name).tag(UUID?.some(category.id))
                        }
                        Text("Sonstiges").tag(UUID?.none)
                    }
                } footer: {
                    Text("Die Kategorie gilt für jeden Artikel mit diesem Namen.")
                }
                Section {
                    Button("Löschen", role: .destructive) {
                        perform { try await model.delete(id: item.id) }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Artikel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let newName = name, newQuantity = quantity, newCategory = categoryID
        let categoryChanged = newCategory != model.categoryID(of: item)
        perform {
            if newName != item.name || newQuantity != (item.quantity ?? "") {
                try await model.update(id: item.id, name: newName, quantity: newQuantity)
            }
            // After the rename, so the category is remembered for the new name.
            if categoryChanged { model.setCategory(newCategory, forItemID: item.id) }
        }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        Task {
            do {
                try await operation()
            } catch {
                onError(TaskListModel.message(for: error))
            }
        }
        dismiss()
    }
}
