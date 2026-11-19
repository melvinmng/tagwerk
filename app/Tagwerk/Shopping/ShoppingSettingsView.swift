import RemindersKit
import SwiftUI
import TagwerkCore

/// The settings page "Einkaufsliste": which reminder list serves as the shopping list, the categories and
/// the consent for sorting with ChatGPT. It has no navigation stack of its own.
struct ShoppingSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var settings = environment.settings
        let hasAccess = environment.reminderStore.accessState == .fullAccess
        // Only writable lists can be the shopping list.
        let lists = hasAccess ? environment.reminderStore.lists().filter(\.isWritable) : []
        List {
            Section {
                ForEach(lists) { list in
                    choiceRow(title: Text(list.title), color: Color(hex: list.colorHex) ?? .accentColor,
                              isSelected: settings.shoppingListID == list.id) {
                        Task { await environment.setShoppingList(list.id) }
                    }
                }
                choiceRow(title: Text("Keine"), color: nil, isSelected: settings.shoppingListID == nil) {
                    Task { await environment.setShoppingList(nil) }
                }
            } header: {
                Text("Liste")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if !hasAccess { Text("Tagwerk hat keinen Zugriff auf Erinnerungen.") }
                    Text("Die gewählte Liste erscheint als Einkaufsliste. Ihre Einträge stehen nicht mehr unter „Aufgaben“, werden nicht eingeplant, zählen nicht im Wochenrückblick und lösen keine Tagwerk-Mitteilungen aus. In der App „Erinnerungen“ ändert sich nichts.")
                }
            }
            Section("Kategorien") {
                NavigationLink {
                    ShoppingCategoriesView(store: environment.shoppingCategories, model: environment.shopping)
                } label: {
                    LabeledContent("Kategorien verwalten", value: "\(environment.shoppingCategories.categories().count)")
                }
            }
            Section {
                Toggle("Mit ChatGPT sortieren", isOn: $settings.shoppingSortConsent)
            } header: {
                Text("ChatGPT")
            } footer: {
                Text("Sendet auf dein Tippen die Namen der offenen Artikel und deiner Kategorien an ChatGPT. Fragst du den Assistenten nach der Einkaufsliste, gehen die Artikelnamen ebenfalls an ChatGPT.")
            }
        }
        .navigationTitle("Einkaufsliste")
        .navigationBarTitleDisplayMode(.inline)
        .task { environment.shoppingCategories.seedIfNeeded() }
    }

    private func choiceRow(title: Text, color: Color?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if let color { Circle().fill(color).frame(width: 10, height: 10) }
                title.foregroundStyle(.primary)
                Spacer()
                if isSelected { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
