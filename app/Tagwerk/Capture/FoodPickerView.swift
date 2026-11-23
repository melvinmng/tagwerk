import SwiftUI
import TagwerkCore

/// What the food list of a sheet can open: the amount sheet of a food, the edit sheet. It lives above the lists, so the sheets hang
/// off the navigation stack and not off a row (a sheet on a row of a `Form` is dropped by SwiftUI).
@MainActor
@Observable
final class FoodPickerCoordinator {
    /// A food whose amount is being entered.
    var amountFood: FoodValue?
    /// The edit sheet: a new food, an existing one or a prefilled draft.
    var edit: FoodEditSheet.Seed?
    /// The online search sheet (decision LM1d); opened by a tap on "Online suchen", never by typing.
    var onlineSearch: OnlineSearchRequest?
    /// Counts changes of the list, so the list redraws after a save or a delete.
    private(set) var revision = 0
    /// Called with the item of a chosen food and amount.
    let onItem: (MealItem) -> Void

    init(onItem: @escaping (MealItem) -> Void) {
        self.onItem = onItem
    }

    func listChanged() { revision += 1 }

    func startNewFood(withLabelPhoto: Bool = false) { edit = FoodEditSheet.Seed(startsWithLabelPhoto: withLabelPhoto) }

    func startEditing(_ food: FoodValue) { edit = FoodEditSheet.Seed(food: food, isExisting: true) }
}

extension View {
    /// The sheets of the food list: amount and edit.
    func foodSheets(_ coordinator: FoodPickerCoordinator) -> some View {
        modifier(FoodSheetsModifier(coordinator: coordinator))
    }
}

private struct FoodSheetsModifier: ViewModifier {
    @Bindable var coordinator: FoodPickerCoordinator

    func body(content: Content) -> some View {
        content
            .sheet(item: $coordinator.amountFood) { food in
                FoodAmountSheet(food: food) { item in
                    coordinator.amountFood = nil
                    coordinator.onItem(item)
                }
            }
            .sheet(item: $coordinator.edit) { seed in
                FoodEditSheet(seed: seed) { _ in coordinator.listChanged() }
            }
            .sheet(item: $coordinator.onlineSearch) { request in
                ProductSearchSheet(request: request) { coordinator.listChanged() }
            }
    }
}

/// The rows of "Meine Lebensmittel" in a form: the foods that match `query`, a button for a new food.
struct FoodPickerSection: View {
    let query: String
    let coordinator: FoodPickerCoordinator

    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        // Reading the revision makes the list follow a save or a delete.
        let _ = coordinator.revision
        let foods = environment.foods
        let results = foods.search(query)
        Section {
            if results.isEmpty {
                Text(foods.isEmpty ? "Hier erscheinen Lebensmittel, die du anlegst: mit Werten je 100 g, je 100 ml oder je Stück."
                                   : "Kein Lebensmittel passt zu deiner Suche.")
                    .font(.subheadline).foregroundStyle(.secondaryText)
            }
            ForEach(results) { food in
                Button { coordinator.amountFood = food } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(food.name).lineLimit(2)
                            Text(food.summary()).font(.caption).foregroundStyle(.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondaryText)
                    }
                }
                .tint(.primary)
                .accessibilityIdentifier(AccessibilityID.Food.row)
                .swipeActions {
                    Button(role: .destructive) {
                        foods.delete(food.id)
                        coordinator.listChanged()
                    } label: { Label("Löschen", systemImage: "trash") }
                    Button { coordinator.startEditing(food) } label: { Label("Bearbeiten", systemImage: "pencil") }
                        .tint(.accentColor)
                }
            }
            onlineSearchRow
            Button("Neues Lebensmittel", systemImage: "plus") { coordinator.startNewFood() }
                .accessibilityIdentifier(AccessibilityID.Food.newButton)
            if environment.ai.isSignedIn {
                Button("Etikett fotografieren", systemImage: "camera") { coordinator.startNewFood(withLabelPhoto: true) }
            }
        } footer: {
            Text("Tippe auf ein Lebensmittel und gib die Menge ein. Wische nach links, um es zu bearbeiten oder zu löschen.")
        }
    }
}

extension FoodPickerSection {
    /// "Online suchen: ‚…‘" below the own hits: a tap opens the search (and, without consent, the consent first). Nothing is sent while
    /// the words are typed. Without a connection or with fewer than three characters the row is greyed out and says why.
    @ViewBuilder
    var onlineSearchRow: some View {
        let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !words.isEmpty {
            let offline = !environment.connectivity.isOnline
            let tooShort = words.count < ProductSearchRules.minimumQueryLength
            VStack(alignment: .leading, spacing: 2) {
                Button { coordinator.onlineSearch = OnlineSearchRequest(query: words) } label: {
                    Label("Online suchen: „\(words)“", systemImage: "globe")
                }
                .disabled(offline || tooShort)
                .accessibilityIdentifier(AccessibilityID.FoodLookup.searchRow)
                if offline {
                    Text("Keine Verbindung").font(.caption).foregroundStyle(.secondaryText)
                } else if tooShort {
                    Text("Gib mindestens \(ProductSearchRules.minimumQueryLength) Zeichen ein.").font(.caption).foregroundStyle(.secondaryText)
                }
            }
            .onAppear { environment.connectivity.start() }
        }
    }
}

/// The amount of a chosen food: grams, millilitres or pieces, with the energy it gives.
struct FoodAmountSheet: View {
    let food: FoodValue
    let onAdd: (MealItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amount: Double?

    init(food: FoodValue, onAdd: @escaping (MealItem) -> Void) {
        self.food = food
        self.onAdd = onAdd
        // The field reads its value once when it appears, so the amount is set before the first render.
        _amount = State(initialValue: food.reference.defaultAmount)
    }

    /// A sanity limit for a typed amount.
    private static let maximumAmount = 10_000.0

    private var item: MealItem? {
        guard let amount, amount > 0, amount <= Self.maximumAmount else { return nil }
        return food.item(amount: amount)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(food.name)
                        Text(food.summary()).font(.caption).foregroundStyle(.secondaryText)
                    }
                    HStack {
                        Text("Menge")
                        Spacer()
                        DecimalField(value: $amount).accessibilityLabel("Menge")
                            .accessibilityIdentifier(AccessibilityID.Food.amountField)
                        Text(verbatim: food.reference.amountUnit).foregroundStyle(.secondaryText)
                            .frame(width: 44, alignment: .leading)
                    }
                } footer: {
                    if let item {
                        Text(IntakeFormat.kcal(item.kcal, estimated: false))
                    } else {
                        Text("Gib eine Menge größer als 0 ein.")
                    }
                }
                if food.hasGaps {
                    Section {
                        Text("Nicht alle Werte sind bekannt. Unbekannte Werte zählen nicht als 0.")
                            .font(.footnote).foregroundStyle(.secondaryText)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Menge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") {
                        if let item { onAdd(item) }
                    }
                    .disabled(item == nil)
                    .accessibilityIdentifier(AccessibilityID.Food.addButton)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// "Lebensmittel hinzufügen" in the editing view of a meal: a search field and the list, as a sheet of its own.
struct FoodPickerSheet: View {
    let onItem: (MealItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var coordinator: FoodPickerCoordinator

    init(onItem: @escaping (MealItem) -> Void) {
        self.onItem = onItem
        _coordinator = State(initialValue: FoodPickerCoordinator(onItem: onItem))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Suchen: Lebensmittel", text: $query)
                        .accessibilityIdentifier(AccessibilityID.Food.searchField)
                }
                FoodPickerSection(query: query, coordinator: coordinator)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Meine Lebensmittel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
            }
            .foodSheets(coordinator)
        }
        .presentationDetents([.large])
    }
}
