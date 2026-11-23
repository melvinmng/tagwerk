import PhotosUI
import SwiftUI
import TagwerkCore

/// Creates or edits an entry of "Meine Lebensmittel": name, the amount the values refer to, energy, macros and the further
/// nutrients. An empty field is unknown, never 0. Values from a third-party source (Open Food Facts) arrive prefilled; changing
/// them turns the entry into a typed one (`FoodValue.afterEditing(from:)`).
struct FoodEditSheet: View {
    /// What the sheet starts with: an existing food, a prefilled draft (taken over from an item or a product) or nothing.
    struct Seed: Identifiable {
        let id = UUID()
        var food: FoodValue?
        /// The energy of a prefilled draft is unknown (a product without an energy value): the field starts empty.
        var energyUnknown = false
        /// A saved food that is edited; `false` for a new entry, also when it starts from a draft.
        var isExisting = false
        /// "Etikett fotografieren" in the list opens the sheet with the camera.
        var startsWithLabelPhoto = false
    }

    let seed: Seed
    /// Called after a food was saved or deleted, with that food.
    let onChanged: (FoodValue) -> Void

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    private enum ReferenceKind: String, CaseIterable, Identifiable {
        case per100g, per100ml, perPiece
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .per100g: "je 100 g"
            case .per100ml: "je 100 ml"
            case .perPiece: "je Stück"
            }
        }
    }

    @State private var name: String
    @State private var referenceKind: ReferenceKind
    @State private var pieceGrams: Double?
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var nutrients: NutrientValues
    @State private var showsFurtherNutrients: Bool
    @State private var confirmsDelete = false
    // Reading a nutrition label (decision LM3b).
    @State private var showsCamera = false
    @State private var showsConsent = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var pendingJPEG: Data?
    @State private var isReading = false
    @State private var readTask: Task<Void, Never>?
    @State private var labelError: String?
    /// The values were read from a label photo (and are still to be compared with the package).
    @State private var readFromLabel = false
    /// Bumped when the fields are filled from outside, so the number fields (which read their value once) are rebuilt.
    @State private var fieldRevision = 0
    @State private var startedWithCamera = false

    /// The fields start with the values of the seed. A `DecimalField` reads its value once when it appears, so they are set before
    /// the first render and not in `onAppear`.
    init(seed: Seed, onChanged: @escaping (FoodValue) -> Void) {
        self.seed = seed
        self.onChanged = onChanged
        let food = seed.food
        _name = State(initialValue: food?.name ?? "")
        switch food?.reference ?? .per100g {
        case .per100g: _referenceKind = State(initialValue: .per100g)
        case .per100ml: _referenceKind = State(initialValue: .per100ml)
        case .perPiece(let grams):
            _referenceKind = State(initialValue: .perPiece)
            _pieceGrams = State(initialValue: grams)
        }
        _kcal = State(initialValue: seed.energyUnknown ? nil : food?.kcal)
        _protein = State(initialValue: food?.protein)
        _carbs = State(initialValue: food?.carbs)
        _fat = State(initialValue: food?.fat)
        _nutrients = State(initialValue: food?.nutrients ?? NutrientValues())
        _showsFurtherNutrients = State(initialValue: food?.nutrients.hasAny ?? false)
    }

    private var original: FoodValue? { seed.food }

    private var reference: FoodReference {
        switch referenceKind {
        case .per100g: .per100g
        case .per100ml: .per100ml
        case .perPiece: .perPiece(grams: pieceGrams.flatMap { $0 > 0 ? $0 : nil })
        }
    }

    private var draft: FoodValue {
        var food = original ?? FoodValue(name: "", reference: .per100g, kcal: 0)
        food.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        food.reference = reference
        food.kcal = kcal ?? 0
        food.protein = protein
        food.carbs = carbs
        food.fat = fat
        food.nutrients = nutrients
        return food
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && kcal != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier(AccessibilityID.Food.nameField)
                    Picker("Werte", selection: $referenceKind) {
                        ForEach(ReferenceKind.allCases) { Text($0.title).tag($0) }
                    }
                    if referenceKind == .perPiece {
                        HStack {
                            Text("Gewicht je Stück")
                            Spacer()
                            DecimalField(value: $pieceGrams).id(fieldRevision).accessibilityLabel("Gewicht je Stück")
                            Text("g").foregroundStyle(.secondaryText).frame(width: 34, alignment: .leading)
                        }
                    }
                } footer: {
                    Text("Die Werte unten gelten für diese Menge. Beim Erfassen gibst du Gramm, Milliliter oder Stück ein.")
                }

                labelSection

                Section {
                    row("Kalorien", "kcal", $kcal)
                    row("Eiweiß", "g", $protein)
                    row("Kohlenhydrate", "g", $carbs)
                    row("Fett", "g", $fat)
                    DisclosureGroup(isExpanded: $showsFurtherNutrients) {
                        ForEach(Nutrient.allCases, id: \.self) { nutrient in
                            HStack {
                                Text(verbatim: nutrient.displayName)
                                Spacer()
                                DecimalField(value: Binding(get: { nutrients[nutrient] },
                                                            set: { nutrients[nutrient] = $0.map { max(0, $0) } }))
                                    .id(fieldRevision)
                                    .accessibilityLabel(Text(verbatim: nutrient.displayName))
                                Text("g").foregroundStyle(.secondaryText).frame(width: 34, alignment: .leading)
                            }
                        }
                    } label: {
                        HStack {
                            Text("Weitere Nährwerte")
                            Spacer()
                            Text("\(Nutrient.allCases.filter { nutrients[$0] != nil }.count) von \(Nutrient.allCases.count)")
                                .foregroundStyle(.secondaryText).monospacedDigit()
                        }
                    }
                } header: {
                    Text("Werte")
                } footer: {
                    if readFromLabel {
                        Text("Vom Etikett gelesen. Bitte vergleiche die Werte mit der Verpackung, bevor du sicherst. Ein leeres Feld ist unbekannt, nicht 0.")
                    } else {
                        Text("Nur Kalorien sind nötig. Ein leeres Feld ist unbekannt, nicht 0, und wird nicht nach Health geschrieben.")
                    }
                }

                if let note = original?.sourceNote {
                    Section {
                        Text(note).font(.footnote).foregroundStyle(.secondaryText)
                    }
                }

                if seed.isExisting {
                    Section {
                        Button("Lebensmittel löschen", role: .destructive) { confirmsDelete = true }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(seed.isExisting ? "Lebensmittel" : "Neues Lebensmittel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(!canSave)
                        .accessibilityIdentifier(AccessibilityID.Food.saveButton)
                }
            }
            .sheet(isPresented: $showsConsent) {
                MealConsentSheet(purpose: .label) {
                    environment.settings.mealEstimationConsent = true
                    showsConsent = false
                    startReading()
                } onDecline: {
                    showsConsent = false
                }
            }
            .fullScreenCover(isPresented: $showsCamera) {
                CameraPicker { image in
                    showsCamera = false
                    if let image { process(image) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { process(image) }
                    pickerItem = nil
                }
            }
            .onAppear {
                // "Etikett fotografieren" in the list opens the camera at once (once, and only where there is one).
                guard seed.startsWithLabelPhoto, !startedWithCamera else { return }
                startedWithCamera = true
                if UIImagePickerController.isSourceTypeAvailable(.camera), environment.ai.isSignedIn { showsCamera = true }
            }
            .onDisappear { readTask?.cancel() }
            .confirmationDialog("Lebensmittel löschen?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    if let id = original?.id { environment.foods.delete(id) }
                    if let food = original { onChanged(food) }
                    dismiss()
                }
            } message: {
                Text("Bereits erfasste Mahlzeiten ändern sich nicht.")
            }
        }
        .presentationDetents([.large])
    }

    private func row(_ title: LocalizedStringKey, _ unit: String, _ value: Binding<Double?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            DecimalField(value: value).id(fieldRevision).accessibilityLabel(Text(title))
            Text(unit).foregroundStyle(.secondaryText).frame(width: 34, alignment: .leading)
        }
    }

    // MARK: Label photo

    /// "Etikett fotografieren": only with a ChatGPT sign-in; the photo is read on a tap, the result fills the fields.
    @ViewBuilder
    private var labelSection: some View {
        if environment.ai.isSignedIn {
            Section {
                if isReading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Lese Etikett …").foregroundStyle(.secondaryText)
                        Spacer()
                        Button("Stopp") {
                            readTask?.cancel()
                            isReading = false
                        }
                        .buttonStyle(.borderless)
                    }
                } else {
                    if let labelError {
                        Text(labelError).foregroundStyle(.orangeText).font(.subheadline)
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Etikett fotografieren", systemImage: "camera") { showsCamera = true }
                            .accessibilityIdentifier(AccessibilityID.Food.labelCamera)
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Foto vom Etikett auswählen", systemImage: "photo")
                    }
                }
            } footer: {
                Text("Das Foto wird verkleinert und ohne Ortsangabe an ChatGPT gesendet und nicht in Tagwerk gespeichert. Die gelesenen Werte füllen die Felder; gesichert wird erst, wenn du auf „Sichern“ tippst.")
            }
        }
    }

    private func process(_ image: UIImage) {
        guard let jpeg = ImageDownscaler.jpeg(from: image) else {
            labelError = LabelReader.Failure.failed.message
            return
        }
        pendingJPEG = jpeg
        if environment.settings.mealEstimationConsent {
            startReading()
        } else {
            showsConsent = true
        }
    }

    private func startReading() {
        guard let jpeg = pendingJPEG else { return }
        labelError = nil
        isReading = true
        readTask = Task {
            do {
                let reading = try await environment.labelReader.read(jpeg: jpeg)
                guard !Task.isCancelled else { return }
                apply(reading)
                isReading = false
            } catch {
                // "Stopp" or closing the sheet: the user already moved on.
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                labelError = (error as? LabelReader.Failure ?? .failed).message
                isReading = false
            }
        }
    }

    /// Puts the values read from the label into the fields; the values of a photo replace what stood there.
    private func apply(_ reading: NutritionLabelReading) {
        let food = reading.food
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { name = food.name }
        switch food.reference {
        case .per100g:
            referenceKind = .per100g
            pieceGrams = nil
        case .per100ml:
            referenceKind = .per100ml
            pieceGrams = nil
        case .perPiece(let grams):
            referenceKind = .perPiece
            pieceGrams = grams
        }
        kcal = reading.energyUnknown ? nil : food.kcal
        protein = food.protein
        carbs = food.carbs
        fat = food.fat
        nutrients = food.nutrients
        showsFurtherNutrients = nutrients.hasAny
        readFromLabel = true
        fieldRevision += 1
        pendingJPEG = nil
    }

    private func save() {
        var food = draft
        if let original { food = food.afterEditing(from: original) }
        if readFromLabel {
            // Values read from a photo and confirmed by the user are the user's own table values, not those of a third party.
            food.origin = .label
            food.sourceNote = nil
        }
        guard environment.foods.save(food) else { return }
        onChanged(food)
        dismiss()
    }
}
