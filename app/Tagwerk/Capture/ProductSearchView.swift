import SwiftUI
import TagwerkCore

/// What opens the online search: the words from the list, and an identity so the sheet starts fresh for each tap.
struct OnlineSearchRequest: Identifiable {
    let id = UUID()
    let query: String
}

/// The sheet of the online search. Without consent and a contact address it shows the consent first; after "Einverstanden" the search
/// runs once. Nothing is sent before that, and never while typing.
struct ProductSearchSheet: View {
    let request: OnlineSearchRequest
    /// Called after a product was taken over as a food, so the list can show it.
    let onFoodSaved: () -> Void

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if environment.settings.isFoodLookupEnabled {
                ProductSearchView(request: request, onFoodSaved: onFoodSaved, close: { dismiss() })
            } else {
                FoodLookupConsentSheet(startsSearch: true) {
                    // The sheet now shows the search (the consent switched `isFoodLookupEnabled` on).
                } onDecline: {
                    dismiss()
                }
            }
        }
        .onDisappear { environment.productLookup.clearMemory() }
    }
}

struct ProductSearchView: View {
    let request: OnlineSearchRequest
    let onFoodSaved: () -> Void
    let close: () -> Void

    @Environment(AppEnvironment.self) private var environment
    @State private var model: ProductSearchModel?
    @State private var started = false
    @FocusState private var queryFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                if let model {
                    searchSection(model)
                    resultsSection(model)
                }
                attributionSection
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Online suchen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen", action: close) }
            }
            .navigationDestination(for: ProductCandidate.self) { candidate in
                ProductPreviewView(candidate: candidate, onFoodSaved: {
                    onFoodSaved()
                    close()
                })
            }
            .task {
                environment.connectivity.start()
                if model == nil {
                    model = ProductSearchModel(query: request.query, lookup: environment.productLookup,
                                               isOnline: { environment.connectivity.isOnline })
                }
                // The tap on "Online suchen" (or on "Einverstanden und suchen") was the tap: the first search starts here, once.
                guard !started, let model else { return }
                started = true
                await model.submit()
            }
        }
        .presentationDetents([.large])
    }

    private func searchSection(_ model: ProductSearchModel) -> some View {
        @Bindable var model = model
        return Section {
            TextField("Lebensmittel suchen", text: $model.query)
                .focused($queryFocused)
                .submitLabel(.search)
                .onSubmit { Task { await model.submit() } }
            Button("Suchen") {
                queryFocused = false
                Task { await model.submit() }
            }
            .disabled(!model.canSubmit)
            .accessibilityIdentifier(AccessibilityID.FoodLookup.searchButton)
        } footer: {
            if let blocker = model.blocker, blocker != .queryTooShort || !model.trimmedQuery.isEmpty {
                Text(blocker.message)
            } else {
                Text("Gesucht wird nur, wenn du auf „Suchen“ tippst.")
            }
        }
    }

    @ViewBuilder
    private func resultsSection(_ model: ProductSearchModel) -> some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .loading:
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Suche …").foregroundStyle(.secondaryText)
                }
            }
        case .failed(let message):
            Section { Text(message).foregroundStyle(.orangeText).font(.subheadline) }
        case .empty:
            Section {
                Text("Nichts gefunden. Versuch andere Wörter oder lege das Lebensmittel selbst an.")
                    .font(.subheadline).foregroundStyle(.secondaryText)
            }
        case .results:
            Section {
                ForEach(model.candidates) { candidate in
                    NavigationLink(value: candidate) { ProductRow(candidate: candidate) }
                        .accessibilityIdentifier(AccessibilityID.FoodLookup.results)
                }
                if model.hasMore {
                    Button("Weitere laden") { Task { await model.loadMore() } }
                }
            }
        }
    }

    private var attributionSection: some View {
        Section {
            ProductAttribution()
        }
    }
}

/// "Daten: Open Food Facts (ODbL)" with a link to the source; shown under every list of hits and every preview.
struct ProductAttribution: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Link("Daten: Open Food Facts (ODbL)", destination: URL(string: "https://world.openfoodfacts.org")!)
            Text("Die Daten stammen von Freiwilligen und können fehlen oder falsch sein.")
                .font(.footnote).foregroundStyle(.secondaryText)
        }
    }
}

/// A hit in the list: name, brand and package size, and the values per 100 g or "Angaben unvollständig".
struct ProductRow: View {
    let candidate: ProductCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(candidate.name).lineLimit(2)
            let detail = [candidate.brand, candidate.quantity].compactMap { $0 }.joined(separator: " · ")
            if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondaryText) }
            Text(valuesLine).font(.caption).foregroundStyle(candidate.isIncomplete ? .orangeText : .secondaryText)
        }
    }

    private var valuesLine: String {
        if candidate.energyUnknown { return String(localized: "Angaben unvollständig") }
        let base = "\(candidate.food.reference.text()) · \(IntakeFormat.kcal(candidate.food.kcal, estimated: false))"
        return candidate.isIncomplete ? "\(base) · \(String(localized: "Angaben unvollständig"))" : base
    }
}

/// The values of a hit, each with its source named; a missing one reads "keine Angabe". Taking the product over is a separate tap.
struct ProductPreviewView: View {
    let candidate: ProductCandidate
    /// Called after the food was saved.
    let onFoodSaved: () -> Void

    @Environment(AppEnvironment.self) private var environment
    @State private var edit: FoodEditSheet.Seed?

    private var preview: ProductPreviewModel { ProductPreviewModel(candidate: candidate, isSignedIn: environment.ai.isSignedIn) }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.name)
                    let detail = [candidate.brand, candidate.quantity].compactMap { $0 }.joined(separator: " · ")
                    if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondaryText) }
                }
            }
            Section {
                row("Kalorien", candidate.energyUnknown ? nil : IntakeFormat.kcal(candidate.food.kcal, estimated: false))
                row("Eiweiß", candidate.food.protein.map { IntakeFormat.grams($0, estimated: false) })
                row("Kohlenhydrate", candidate.food.carbs.map { IntakeFormat.grams($0, estimated: false) })
                row("Fett", candidate.food.fat.map { IntakeFormat.grams($0, estimated: false) })
                ForEach(Nutrient.allCases, id: \.self) { nutrient in
                    let value = candidate.food.nutrients[nutrient]
                    row(verbatim: nutrient.displayName,
                        value.map { IntakeFormat.nutrient(nutrient, sum: NutrientSum(value: $0, known: 1, total: 1)) })
                }
            } header: {
                Text(verbatim: candidate.food.reference.text())
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if candidate.valuesPerServingOnly {
                        Text("Die Packung nennt nur Werte je Portion, nicht je 100 g.")
                    }
                    Text("Bitte mit der Verpackung vergleichen: Die Werte stammen aus einer offenen Datenbank und können fehlen oder falsch sein.")
                }
            }
            Section {
                Button("Als Lebensmittel speichern") { edit = preview.takeOverSeed(retrievedOn: Date()) }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier(AccessibilityID.FoodLookup.saveFood)
                if preview.offersLabelPhoto {
                    Button("Stattdessen Etikett fotografieren", systemImage: "camera") { edit = preview.labelPhotoSeed(retrievedOn: Date()) }
                }
            } footer: {
                Text("Das Produkt kommt als eigener Eintrag in „Meine Lebensmittel“, mit Hinweis auf die Quelle. Erst dort wählst du eine Menge.")
            }
            Section { ProductAttribution() }
        }
        .navigationTitle("Produkt")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $edit) { seed in
            FoodEditSheet(seed: seed) { _ in onFoodSaved() }
        }
    }

    private func row(_ title: LocalizedStringKey, _ value: String?) -> some View {
        LabeledContent {
            valueText(value)
        } label: {
            Text(title)
        }
    }

    /// A row whose title is already localized (the name of a nutrient).
    private func row(verbatim title: String, _ value: String?) -> some View {
        LabeledContent {
            valueText(value)
        } label: {
            Text(verbatim: title)
        }
    }

    private func valueText(_ value: String?) -> some View {
        Text(value ?? String(localized: "keine Angabe")).foregroundStyle(value == nil ? .secondaryText : .primary)
    }
}
