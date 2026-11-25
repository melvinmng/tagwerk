import SwiftUI

/// The small sheet "Zutat" of the result sheet (plan ki-vorschlaege-anpassen, task D2, AN9a): name and category of one
/// ingredient. The amount is changed with the amount button of the row, not here. The categories are those of the shopping list and the fixed section; nothing else can be chosen, so the list
/// never gets a category from here. "Übernehmen" only changes the proposal.
struct RecipeRowEditor: View {
    let row: RecipeRow
    let categories: [String]
    let onSave: (RecipeRow) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var category: String

    init(row: RecipeRow, categories: [String], onSave: @escaping (RecipeRow) -> Void) {
        self.row = row
        self.categories = categories
        self.onSave = onSave
        _name = State(initialValue: row.candidate.listName)
        _category = State(initialValue: row.candidate.category)
    }

    /// The categories to choose from: the ones of the list, and the current one when it is not among them.
    static func choices(_ categories: [String], current: String) -> [String] {
        categories.contains(current) ? categories : categories + [current]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                }
                Section {
                    Picker("Kategorie", selection: $category) {
                        ForEach(Self.choices(categories, current: row.candidate.category), id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Kategorie")
                        .foregroundStyle(.secondaryText)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Zutat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") {
                        onSave(row.edited(name: name, category: category))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
