import PhotosUI
import SwiftUI
import TagwerkCore

/// "Essen" (mockup E2a, E3a, E7a): text and/or photo → ChatGPT estimate → editable preview → save.
/// Without sign-in or with "Ohne Schätzung eintragen" the same sheet takes typed values.
struct MealSheet: View {
    let model: CaptureModel
    let estimator: MealEstimator
    let existing: MealValue?
    /// Text from Siri ("Mahlzeit erfassen"); only prefilled, never estimated without a tap.
    var initialText: String? = nil

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    private enum Phase { case input, estimating, editing }

    @State private var phase: Phase = .input
    @State private var text = ""
    @State private var photo: UIImage?
    @State private var photoJPEG: Data?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showsCamera = false
    @State private var showsConsent = false
    @State private var errorText: String?
    @State private var estimateTask: Task<Void, Never>?
    @State private var draft = MealDraft()
    @State private var showsFurtherNutrients = false
    @State private var editingItem: EditedItem?
    @State private var prepared = false
    @State private var saving = false
    @State private var voice: VoiceInputModel?
    @FocusState private var textFocused: Bool

    private var isSignedIn: Bool { environment.ai.isSignedIn }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .input, .estimating: inputForm
                case .editing: editForm
                }
            }
            .navigationTitle("Essen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        estimateTask?.cancel()
                        dismiss()
                    }
                }
                if phase == .editing {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Sichern") {
                            guard !saving else { return }
                            saving = true
                            let meal = draft.value
                            let estimatedAt = draft.estimatedAt
                            let isNew = existing == nil
                            Task { await model.saveMeal(meal, estimatedAt: estimatedAt, isNew: isNew) }
                            dismiss()
                        }
                        .disabled(!draft.canSave || saving)
                    }
                }
            }
            .onAppear(perform: prepare)
            .sheet(isPresented: $showsConsent) {
                MealConsentSheet {
                    environment.settings.mealEstimationConsent = true
                    showsConsent = false
                    startEstimate()
                } onDecline: {
                    showsConsent = false
                }
            }
            .fullScreenCover(isPresented: $showsCamera) {
                CameraPicker { image in
                    showsCamera = false
                    if let image { setPhoto(image) }
                }
                .ignoresSafeArea()
            }
            .sheet(item: $editingItem) { edited in
                MealItemEditor(item: edited.item, onSave: { updated in
                    if let index = draft.items.firstIndex(where: { $0.id == updated.id }) {
                        draft.items[index] = updated
                    } else {
                        draft.items.append(updated)
                    }
                }, visibleNutrients: model.settings.visibleNutrients)
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        setPhoto(image)
                    }
                    pickerItem = nil
                }
            }
        }
    }

    // MARK: Input

    private var inputForm: some View {
        Form {
            Section {
                if let voice { VoiceNoticeRow(voice: voice) }
                if let voice, voice.isRecording {
                    // ↑ estimates right away when signed in; a tap on the text only fills the field.
                    VoiceRecordingBar(voice: voice, compact: true, canSend: isSignedIn)
                } else {
                    HStack(alignment: .top) {
                        TextField(photo == nil ? "Was hast du gegessen?" : "Hinweis, z. B. „halbe Portion“", text: $text, axis: .vertical)
                            .focused($textFocused)
                            .keyboardDoneButton(focus: $textFocused)
                            .lineLimit(1...4)
                            .disabled(phase == .estimating)
                        if environment.settings.voiceInputEnabled, let voice, phase != .estimating {
                            VoiceMicrophoneButton(voice: voice, isEnabled: true,
                                                  language: environment.settings.dictationLanguage(at: .meal))
                        }
                        if isSignedIn {
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                Button { showsCamera = true } label: { Image(systemName: "camera") }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Foto aufnehmen")
                            }
                            PhotosPicker(selection: $pickerItem, matching: .images) { Image(systemName: "photo") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Foto auswählen")
                        }
                    }
                }
                if let photo {
                    HStack {
                        Image(uiImage: photo).resizable().scaledToFill().frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Spacer()
                        Button("Foto entfernen", systemImage: "xmark.circle.fill") {
                            self.photo = nil
                            photoJPEG = nil
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondaryText)
                    }
                }
            } footer: {
                if photo != nil {
                    Text("Das Foto wird verkleinert und ohne Ortsangabe gesendet und nicht in Tagwerk gespeichert.")
                }
            }

            Section {
                if phase == .estimating {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Schätze …").foregroundStyle(.secondaryText)
                        Spacer()
                        Button("Stopp") {
                            estimateTask?.cancel()
                            phase = .input
                        }
                        .buttonStyle(.borderless)
                    }
                } else if isSignedIn {
                    if let errorText {
                        Text(errorText).foregroundStyle(.orangeText).font(.subheadline)
                    }
                    Button(errorText == nil ? "Schätzen" : "Erneut versuchen") { requestEstimate() }
                        .disabled(!hasInput)
                        .fontWeight(.semibold)
                    Button("Ohne Schätzung eintragen") { startManual() }
                } else {
                    Text("Für Schätzungen aus Text oder Foto melde dich unter Einstellungen › KI bei ChatGPT an.")
                        .font(.subheadline).foregroundStyle(.secondaryText)
                    Button("Weiter") { startManual() }.fontWeight(.semibold)
                    Button("Zu den KI-Einstellungen") {
                        environment.requestedTab = 2
                        dismiss()
                    }
                }
            }

            repeatSection
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            textFocused = existing == nil
            if voice == nil {
                let model = VoiceInputFactory.make(environment, place: .meal)
                model.readDraft = { text }
                model.writeDraft = { text = $0 }
                model.onSend = { spoken in
                    text = spoken
                    // Estimating sends the text to ChatGPT; it only follows the tap on ↑ (§8.4).
                    if isSignedIn { requestEstimate() }
                }
                voice = model
            }
        }
        .onDisappear { voice?.cancel() }
    }

    private var hasInput: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || photoJPEG != nil
    }

    @ViewBuilder
    private var repeatSection: some View {
        let suggestions = model.repeatSuggestions(filter: photo == nil ? text : "")
        Section {
            if suggestions.isEmpty {
                Text("Hier erscheinen Mahlzeiten, die du schon einmal erfasst hast.")
                    .font(.subheadline).foregroundStyle(.secondaryText)
            }
            ForEach(suggestions) { meal in
                HStack {
                    Button { startEditing(copyOf: meal) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meal.title).lineLimit(1)
                            Text(String(localized: "zuletzt \(CaptureText.lastUsedDay(PlanDay(date: meal.date, calendar: model.calendar), today: model.today, calendar: model.calendar))"))
                                .font(.caption).foregroundStyle(.secondaryText)
                        }
                    }
                    .tint(.primary)
                    Spacer()
                    Text(IntakeFormat.kcal(meal.kcal, estimated: meal.hasEstimate)).font(.subheadline).foregroundStyle(.secondaryText)
                    Button {
                        Task {
                            await model.repeatMeal(meal)
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(meal.title) jetzt erfassen")
                }
            }
        } header: {
            Text("Zuletzt und häufig")
        } footer: {
            if !suggestions.isEmpty {
                Text("„＋“ erfasst die Mahlzeit sofort für jetzt. Tippe auf die Zeile, um sie vorher anzupassen.")
            }
        }
    }

    // MARK: Editing

    private var editForm: some View {
        Form {
            Section {
                TextField("Name der Mahlzeit", text: $draft.title)
                Picker("Mahlzeit", selection: $draft.kind) {
                    ForEach(MealKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                DatePicker("Zeit", selection: $draft.date, in: ...Date())
            }

            if draft.isManualSingle {
                manualValues
            } else {
                estimateSummary
                itemsSection
            }

            if let existing {
                Section {
                    Text(provenance).font(.footnote).foregroundStyle(.secondaryText)
                    Button("Mahlzeit löschen", role: .destructive) {
                        Task {
                            await model.delete(existing.id)
                            dismiss()
                        }
                    }
                }
            } else if isSignedIn {
                Section {
                    Button("Neu schätzen") {
                        if text.isEmpty { text = draft.title }
                        phase = .input
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var provenance: String {
        var lines: [String] = []
        if let estimatedAt = existing.flatMap({ model.estimatedAt(meal: $0.id) }) {
            let date = CaptureText.date(PlanDay(date: estimatedAt, calendar: model.calendar), calendar: model.calendar)
            let time = CaptureText.time(estimatedAt, calendar: model.calendar)
            lines.append(String(localized: "Geschätzt von ChatGPT am \(date) um \(time)."))
        } else if existing?.origin == .manual {
            lines.append(String(localized: "Von dir eingetragen."))
        }
        if let existing, model.access?.wasAsked == true {
            lines.append(model.isInHealth(existing.id) ? String(localized: "In Health gespeichert.")
                : String(localized: "Noch nicht in Health gespeichert. Tagwerk versucht es erneut."))
        }
        return lines.joined(separator: " ")
    }

    private var manualValues: some View {
        Section {
            numberRow("Kalorien", unit: "kcal", value: $draft.manualKcal)
            numberRow("Eiweiß", unit: "g", value: $draft.manualProtein)
            numberRow("Kohlenhydrate", unit: "g", value: $draft.manualCarbs)
            numberRow("Fett", unit: "g", value: $draft.manualFat)
            furtherNutrients
        } header: {
            Text("Werte")
        } footer: {
            Text("Nur Kalorien sind nötig. Leere Felder sind unbekannt und werden nicht nach Health geschrieben.")
        }
    }

    /// "Weitere Nährwerte 2 von 4": the further nutrients fold out (decision NU3b); an empty field is unknown, not 0.
    private var furtherNutrients: some View {
        let visible = model.settings.visibleNutrients
        return DisclosureGroup(isExpanded: $showsFurtherNutrients) {
            ForEach(visible, id: \.self) { nutrient in
                nutrientRow(nutrient, value: Binding(get: { draft.manualNutrient(nutrient) },
                                                     set: { draft.setManualNutrient(nutrient, $0) }))
            }
        } label: {
            HStack {
                Text("Weitere Nährwerte")
                Spacer()
                Text("\(draft.knownManualNutrients(in: visible)) von \(visible.count)")
                    .foregroundStyle(.secondaryText).monospacedDigit()
            }
        }
        .accessibilityIdentifier("meal.furtherNutrients")
    }

    private func numberRow(_ title: LocalizedStringResource, unit: String, value: Binding<Double?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            DecimalField(value: value).accessibilityLabel(Text(title))
            Text(unit).foregroundStyle(.secondaryText).frame(width: 34, alignment: .leading)
        }
    }

    /// A row of a further nutrient; its name is already localized by `Nutrient.displayName`.
    private func nutrientRow(_ nutrient: Nutrient, value: Binding<Double?>) -> some View {
        HStack {
            Text(verbatim: nutrient.displayName)
            Spacer()
            DecimalField(value: value)
                .accessibilityLabel(Text(verbatim: nutrient.displayName))
                .accessibilityIdentifier("meal.nutrient.\(nutrient.rawValue)")
            Text("g").foregroundStyle(.secondaryText).frame(width: 34, alignment: .leading)
        }
    }

    private var estimateSummary: some View {
        let meal = draft.value
        let estimated = meal.hasEstimate
        return Section {
            HStack {
                Text("Gesamt").fontWeight(.semibold)
                Spacer()
                Text(IntakeFormat.kcal(meal.kcal, estimated: estimated)).fontWeight(.semibold).monospacedDigit()
            }
            if estimated, let range = IntakeFormat.rangeIfEstimated(min: meal.kcalMin, max: meal.kcalMax) {
                Text(range).font(.subheadline).foregroundStyle(.secondaryText)
            }
            let protein = IntakeFormat.grams(meal.protein, estimated: estimated)
            let carbs = IntakeFormat.grams(meal.carbs, estimated: estimated)
            let fat = IntakeFormat.grams(meal.fat, estimated: estimated)
            Text([String(localized: "\(protein) Eiweiß"), String(localized: "\(carbs) Kohlenhydrate"),
                  String(localized: "\(fat) Fett")].joined(separator: " · "))
                .font(.subheadline).foregroundStyle(.secondaryText)
            let known = IntakeRules.dayIntake(meals: [meal], drinks: [])
            let further = model.settings.visibleNutrients.compactMap { nutrient -> String? in
                known[nutrient].value == nil ? nil : "\(nutrient.displayName) \(IntakeFormat.nutrient(nutrient, sum: known[nutrient]))"
            }
            if !further.isEmpty {
                Text(further.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondaryText)
            }
        } header: {
            Text(draft.origin == .estimated ? "Schätzung von ChatGPT" : "Werte")
        }
    }

    private var itemsSection: some View {
        Section {
            ForEach($draft.items) { $item in
                VStack(alignment: .leading, spacing: 6) {
                    Button { editingItem = EditedItem(item: item) } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                if !item.amount.isEmpty {
                                    Text(item.amount).font(.caption).foregroundStyle(.secondaryText)
                                }
                            }
                            Spacer()
                            Text(IntakeFormat.kcal(item.totalKcal, estimated: item.isEstimated)).monospacedDigit()
                        }
                    }
                    .tint(.primary)
                    ValueStepper("Menge", value: $item.factor, in: MealItem.factorRange, step: MealItem.factorStep,
                                 kind: .decimal(fractionDigits: 2)) { IntakeFormat.factor($0) }
                        .font(.subheadline)
                }
                .swipeActions {
                    let id = item.id
                    Button(role: .destructive) { draft.items.removeAll { $0.id == id } } label: {
                        Label("Entfernen", systemImage: "trash")
                    }
                }
            }
            Button("Posten hinzufügen", systemImage: "plus") {
                editingItem = EditedItem(item: MealItem(name: "", amount: "", kcalMin: 0, kcal: 0, kcalMax: 0,
                                                                    protein: 0, carbs: 0, fat: 0))
            }
        } header: {
            Text("Posten")
        } footer: {
            Text("Schätzung, keine Messung. Passe Mengen und Werte an, bevor du sicherst. Tippe auf einen Posten, um seine Werte zu ändern; wische, um ihn zu entfernen.")
        }
    }

    // MARK: Actions

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        if let existing {
            draft = MealDraft(meal: existing, estimatedAt: model.estimatedAt(meal: existing.id))
            phase = .editing
        } else if let initialText {
            text = initialText
        }
    }

    private func setPhoto(_ image: UIImage) {
        photoJPEG = ImageDownscaler.jpeg(from: image)
        photo = photoJPEG.flatMap(UIImage.init(data:))
        errorText = nil
    }

    private func requestEstimate() {
        if environment.settings.mealEstimationConsent {
            startEstimate()
        } else {
            showsConsent = true
        }
    }

    private func startEstimate() {
        errorText = nil
        phase = .estimating
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let jpeg = photoJPEG
        estimateTask = Task {
            do {
                let estimate = try await estimator.estimate(text: input, jpeg: jpeg)
                guard !Task.isCancelled else { return }
                let date = model.entryDate
                draft = MealDraft(title: estimate.title, kind: MealKind.forTime(date, calendar: model.calendar), date: date,
                                  items: estimate.items, origin: .estimated, estimatedAt: Date())
                phase = .editing
            } catch {
                // "Stopp" or closing the sheet: the user already moved on; change nothing.
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                handle(error)
            }
        }
    }

    private func handle(_ error: Error) {
        let failure = error as? MealEstimator.Failure ?? .failed
        if failure == .consentMissing {
            showsConsent = true
        } else {
            errorText = failure.message
        }
        phase = .input
    }

    private func startManual() {
        let date = model.entryDate
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = MealDraft(title: title, kind: MealKind.forTime(date, calendar: model.calendar), date: date,
                          items: [MealItem(name: title, amount: "", kcalMin: 0, kcal: 0, kcalMax: 0, protein: 0, carbs: 0, fat: 0)],
                          origin: .manual, estimatedAt: nil)
        phase = .editing
    }

    private func startEditing(copyOf meal: MealValue) {
        let date = model.entryDate
        draft = MealDraft(title: meal.title, kind: MealKind.forTime(date, calendar: model.calendar), date: date,
                          items: meal.items, origin: meal.origin, estimatedAt: nil)
        phase = .editing
    }

}

// MARK: - Draft

/// The editable meal of the sheet.
struct MealDraft {
    var id = UUID()
    var title = ""
    var kind: MealKind = .snack
    var date = Date()
    var items: [MealItem] = []
    var origin: MealOrigin = .manual
    var estimatedAt: Date?

    init() {}

    init(title: String, kind: MealKind, date: Date, items: [MealItem], origin: MealOrigin, estimatedAt: Date?) {
        self.title = title
        self.kind = kind
        self.date = date
        self.items = items
        self.origin = origin
        self.estimatedAt = estimatedAt
    }

    init(meal: MealValue, estimatedAt: Date?) {
        self.init(title: meal.title, kind: meal.kind, date: meal.date, items: meal.items, origin: meal.origin,
                  estimatedAt: estimatedAt)
        id = meal.id
    }

    /// Typed meals with one item show the four value fields instead of the item list (mockup E2a, manual form).
    var isManualSingle: Bool { origin == .manual && items.count <= 1 && !(items.first?.isEstimated ?? false) }

    var value: MealValue {
        var finalItems = items
        if isManualSingle, !finalItems.isEmpty { finalItems[0].name = title }
        return MealValue(id: id, date: date, kind: kind, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                         items: finalItems, origin: origin)
    }

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.kcal > 0
    }

    /// The shown value includes the quantity factor, so what is shown is what gets saved.
    private func manualValue(_ keyPath: KeyPath<MealItem, Double>) -> Double? {
        guard let item = items.first else { return nil }
        let value = item[keyPath: keyPath] * item.factor
        return value > 0 ? value : nil
    }

    /// Makes sure there is one item and that its values are what is shown (the quantity factor folded in, nutrients included).
    private mutating func prepareManualItem() {
        if items.isEmpty {
            items = [MealItem(name: title, amount: "", kcalMin: 0, kcal: 0, kcalMax: 0, protein: 0, carbs: 0, fat: 0)]
        }
        if items[0].factor != 1 {
            let factor = items[0].factor
            let nutrients = items[0].nutrients.scaled(by: factor)
            items[0] = items[0].overridden(kcal: items[0].kcal * factor, protein: items[0].protein * factor,
                                           carbs: items[0].carbs * factor, fat: items[0].fat * factor)
            items[0].nutrients = nutrients
            items[0].factor = 1
        }
    }

    private mutating func setManual(_ value: Double?, _ apply: (inout MealItem, Double) -> Void) {
        prepareManualItem()
        apply(&items[0], max(0, value ?? 0))
    }

    /// A further nutrient of the typed item as shown. A stated 0 stays 0; only an empty field is unknown (`nil`).
    func manualNutrient(_ nutrient: Nutrient) -> Double? {
        guard let item = items.first else { return nil }
        return item.totalNutrient(nutrient)
    }

    /// Sets or clears a further nutrient: `nil` (an empty field) makes it unknown, never 0.
    mutating func setManualNutrient(_ nutrient: Nutrient, _ value: Double?) {
        if items.isEmpty && value == nil { return }
        prepareManualItem()
        items[0].nutrients[nutrient] = value.map { max(0, $0) }
    }

    /// How many of `nutrients` the typed item knows ("2 von 4").
    func knownManualNutrients(in nutrients: [Nutrient]) -> Int {
        nutrients.filter { manualNutrient($0) != nil }.count
    }

    var manualKcal: Double? {
        get { manualValue(\.kcal) }
        set { setManual(newValue) { item, value in item.kcal = value; item.kcalMin = value; item.kcalMax = value } }
    }
    var manualProtein: Double? {
        get { manualValue(\.protein) }
        set { setManual(newValue) { $0.protein = $1 } }
    }
    var manualCarbs: Double? {
        get { manualValue(\.carbs) }
        set { setManual(newValue) { $0.carbs = $1 } }
    }
    var manualFat: Double? {
        get { manualValue(\.fat) }
        set { setManual(newValue) { $0.fat = $1 } }
    }
}

struct EditedItem: Identifiable {
    var id: UUID { item.id }
    let item: MealItem
}

/// Values of one item. Saving typed values makes the item exact (no "~").
private struct MealItemEditor: View {
    let item: MealItem
    let onSave: (MealItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount = ""
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    /// The further nutrients per portion; an empty field is unknown.
    @State private var nutrients = NutrientValues()
    @State private var showsFurtherNutrients = false
    @State private var prepared = false
    /// The nutrients the user has switched on (fiber and sugar are always there).
    let visibleNutrients: [Nutrient]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Menge, z. B. „2 Stück“", text: $amount)
                }
                Section {
                    row("Kalorien", "kcal", $kcal)
                    row("Eiweiß", "g", $protein)
                    row("Kohlenhydrate", "g", $carbs)
                    row("Fett", "g", $fat)
                    DisclosureGroup(isExpanded: $showsFurtherNutrients) {
                        ForEach(visibleNutrients, id: \.self) { nutrient in
                            HStack {
                                Text(verbatim: nutrient.displayName)
                                Spacer()
                                DecimalField(value: Binding(get: { nutrients[nutrient] }, set: { nutrients[nutrient] = $0.map { max(0, $0) } }))
                                    .accessibilityLabel(Text(verbatim: nutrient.displayName))
                                Text("g").foregroundStyle(.secondaryText).frame(width: 34, alignment: .leading)
                            }
                        }
                    } label: {
                        HStack {
                            Text("Weitere Nährwerte")
                            Spacer()
                            Text("\(visibleNutrients.filter { nutrients[$0] != nil }.count) von \(visibleNutrients.count)")
                                .foregroundStyle(.secondaryText).monospacedDigit()
                        }
                    }
                } footer: {
                    Text("Werte je Menge ×1. Eigene Werte gelten als genau und stehen ohne „~“. Ein leeres Feld ist unbekannt, nicht 0.")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(item.name.isEmpty ? "Posten" : item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") {
                        var updated = item
                        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.amount = amount.trimmingCharacters(in: .whitespacesAndNewlines)
                        let changedValues = kcal != item.kcal || protein != item.protein || carbs != item.carbs || fat != item.fat
                        if changedValues || !item.isEstimated {
                            updated = updated.overridden(kcal: kcal ?? 0, protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0)
                        }
                        // The nutrients come from the fields; changing only them does not turn an estimate into typed values.
                        updated.nutrients = nutrients
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (kcal ?? 0) <= 0)
                }
            }
            .onAppear {
                guard !prepared else { return }
                prepared = true
                name = item.name
                amount = item.amount
                kcal = item.kcal > 0 ? item.kcal : nil
                protein = item.protein
                carbs = item.carbs
                fat = item.fat
                nutrients = item.nutrients
                showsFurtherNutrients = visibleNutrients.contains { nutrients[$0] != nil }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ title: LocalizedStringResource, _ unit: String, _ value: Binding<Double?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            DecimalField(value: value).accessibilityLabel(Text(title))
            Text(unit).foregroundStyle(.secondaryText).frame(width: 34, alignment: .leading)
        }
    }
}

/// A number field that updates its value on every keystroke (a `value:` text field only commits on return,
/// and the decimal pad has none). Accepts comma or point.
struct DecimalField: View {
    @Binding var value: Double?
    @State private var text = ""
    @State private var loaded = false

    var body: some View {
        TextField("–", text: $text)
            .keyboardType(.decimalPad)
            .keyboardDoneButton()
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 100)
            .onAppear {
                guard !loaded else { return }
                loaded = true
                text = value.map { Self.format($0) } ?? ""
            }
            .onChange(of: text) { _, newText in
                value = Double(newText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
            }
    }

    /// "5" or "1,5" in German, "1.5" in English: the decimal separator follows the locale; typing accepts both.
    static func format(_ value: Double, locale: Locale = .current) -> String {
        value.rounded() == value ? String(Int(value))
            : value.formatted(.number.precision(.fractionLength(1)).grouping(.never).locale(locale))
    }
}
