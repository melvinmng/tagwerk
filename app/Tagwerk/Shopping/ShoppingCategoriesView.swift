import SwiftUI
import TagwerkCore

/// The page "Kategorien": reorder, rename, delete and add the categories of the shopping list.
/// It has no navigation stack of its own.
struct ShoppingCategoriesView: View {
    let store: ShoppingCategoryStore
    let model: ShoppingModel

    @State private var renaming: ShoppingCategoryInfo?
    @State private var isAdding = false
    @State private var nameText = ""
    @State private var deleting: ShoppingCategoryInfo?
    @State private var errorText: String?

    init(store: ShoppingCategoryStore, model: ShoppingModel) {
        self.store = store
        self.model = model
    }

    var body: some View {
        let categories = store.categories()
        List {
            Section {
                ForEach(categories) { category in
                    Button {
                        nameText = category.name
                        renaming = category
                    } label: {
                        HStack {
                            Text(category.name).foregroundStyle(.primary)
                            Spacer()
                            Text("\(openCount(category.id))").monospacedDigit().foregroundStyle(.secondaryText)
                        }
                        .contentShape(Rectangle())
                    }
                    // Without this the whole row takes the accent colour of a button (#173).
                    .buttonStyle(.plain)
                    .accessibilityHint("Umbenennen")
                }
                .onMove { offsets, target in
                    store.move(fromOffsets: offsets, toOffset: target)
                    model.refreshSections()
                }
                .onDelete { offsets in
                    deleting = offsets.first.flatMap { categories.indices.contains($0) ? categories[$0] : nil }
                }
                Button {
                    nameText = ""
                    isAdding = true
                } label: {
                    Label("Kategorie hinzufügen", systemImage: "plus")
                }
                .moveDisabled(true)
                .deleteDisabled(true)
            } footer: {
                Text("Die Zahl nennt die offenen Artikel. Tippe auf einen Namen, um ihn zu ändern.")
            }
            Section {
                HStack {
                    Text("Sonstiges")
                    Spacer()
                    Text("für alles ohne Kategorie")
                }
                .foregroundStyle(.secondaryText)
                .moveDisabled(true)
                .deleteDisabled(true)
            }
            Section {
                Button("Standardkategorien wiederherstellen") {
                    store.restoreBuiltins()
                    model.refreshSections()
                }
                .moveDisabled(true)
                .deleteDisabled(true)
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Kategorien")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            store.seedIfNeeded()
            model.refreshSections()
        }
        .alert("Kategorie umbenennen", isPresented: renamingBinding) {
            TextField("Name", text: $nameText)
            Button("Sichern", action: rename)
            Button("Abbrechen", role: .cancel) {}
        }
        .alert("Neue Kategorie", isPresented: $isAdding) {
            TextField("Name", text: $nameText)
            Button("Anlegen", action: add)
            Button("Abbrechen", role: .cancel) {}
        }
        .alert(errorText ?? "", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        }
        .confirmationDialog(deleting.map { Self.deleteQuestion(name: $0.name, openCount: openCount($0.id)) } ?? "",
                            isPresented: deletingBinding, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                if let deleting { store.delete(deleting.id) }
                model.refreshSections()
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    // MARK: Texts

    /// Names how many open items get sorted again when the category goes.
    static func deleteQuestion(name: String, openCount: Int) -> String {
        let question = String(localized: "„\(name)“ löschen?")
        guard openCount > 0 else { return question }
        return question + " " + String(localized: "\(openCount) Artikel werden neu einsortiert, meist unter „Sonstiges“.")
    }

    static func message(for error: ShoppingCategoryRules.NameError) -> String {
        switch error {
        case .empty: String(localized: "Gib einen Namen ein.")
        case .tooLong: String(localized: "Der Name darf höchstens 30 Zeichen haben.")
        case .duplicate: String(localized: "Diese Kategorie gibt es schon.")
        case .reserved: String(localized: "„Sonstiges“ ist fest vergeben und kann nicht als Name dienen.")
        case .limitReached: String(localized: "Mehr als 30 Kategorien sind nicht möglich.")
        }
    }

    // MARK: Actions

    private func openCount(_ id: UUID) -> Int {
        model.sections.first { $0.categoryID == id }?.items.count ?? 0
    }

    private func rename() {
        guard let renaming else { return }
        run { try store.rename(renaming.id, to: nameText) }
    }

    private func add() {
        run { try store.add(name: nameText) }
    }

    private func run(_ change: () throws -> Void) {
        do {
            try change()
            model.refreshSections()
        } catch let error as ShoppingCategoryRules.NameError {
            errorText = Self.message(for: error)
        } catch {
            errorText = TaskListModel.message(for: error)
        }
    }

    private var renamingBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var deletingBinding: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })
    }
}
