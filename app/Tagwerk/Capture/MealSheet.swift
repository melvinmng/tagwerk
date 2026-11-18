import PhotosUI
import SwiftUI
import TagwerkCore

/// "Essen" (mockup E2a, E3a, E7a): text and/or photo → ChatGPT estimate → editable preview → save.
/// Without sign-in or with "Ohne Schätzung eintragen" the same sheet takes typed values.
struct MealSheet: View {
    let model: CaptureModel
    let estimator: MealEstimator
    let existing: MealValue?

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
    @State private var editingItem: EditedItem?
    @State private var prepared = false
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
                            Task {
                                await save()
                                dismiss()
                            }
                        }
                        .disabled(!draft.canSave)
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
                MealItemEditor(item: edited.item) { updated in
                    if let index = edited.index { draft.items[index] = updated } else { draft.items.append(updated) }
                }
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
                HStack(alignment: .top) {
                    TextField(photo == nil ? "Was hast du gegessen?" : "Hinweis, z. B. „halbe Portion“", text: $text, axis: .vertical)
                        .focused($textFocused)
                        .lineLimit(1...4)
                        .disabled(phase == .estimating)
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
                        .foregroundStyle(.secondary)
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
                        Text("Schätze …").foregroundStyle(.secondary)
                        Spacer()
                        Button("Stopp") {
                            estimateTask?.cancel()
                            phase = .input
                        }
                        .buttonStyle(.borderless)
                    }
                } else if isSignedIn {
                    if let errorText {
                        Text(errorText).foregroundStyle(.orange).font(.subheadline)
                    }
                    Button(errorText == nil ? "Schätzen" : "Erneut versuchen") { requestEstimate() }
                        .disabled(!hasInput)
                        .fontWeight(.semibold)
                    Button("Ohne Schätzung eintragen") { startManual() }
                } else {
                    Text("Für Schätzungen aus Text oder Foto melde dich unter Einstellungen › KI bei ChatGPT an.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Weiter") { startManual() }.fontWeight(.semibold)
                    Button("Zu den KI-Einstellungen") {
                        environment.requestedTab = 2
                        dismiss()
                    }
                }
            }

            repeatSection
        }
        .onAppear { textFocused = existing == nil }
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
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(suggestions) { meal in
                HStack {
                    Button { startEditing(copyOf: meal) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meal.title).lineLimit(1)
                            Text("zuletzt \(CaptureText.relativeDay(PlanDay(date: meal.date, calendar: model.calendar), today: model.today, calendar: model.calendar).lowercasedFirst)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tint(.primary)
                    Spacer()
                    Text(IntakeFormat.kcal(meal.kcal, estimated: meal.hasEstimate)).font(.subheadline).foregroundStyle(.secondary)
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
                    ForEach(MealKind.allCases, id: \.self) { Text($0.germanName).tag($0) }
                }
                DatePicker("Zeit", selection: $draft.date)
            }

            if draft.isManualSingle {
                manualValues
            } else {
                estimateSummary
                itemsSection
            }

            if let existing {
                Section {
                    Text(provenance).font(.footnote).foregroundStyle(.secondary)
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
    }

    private var provenance: String {
        var lines: [String] = []
        if let estimatedAt = existing.flatMap({ model.estimatedAt(meal: $0.id) }) {
            let date = CaptureText.date(PlanDay(date: estimatedAt, calendar: model.calendar), calendar: model.calendar)
            lines.append("Geschätzt von ChatGPT am \(date) um \(CaptureText.time(estimatedAt, calendar: model.calendar)).")
        } else if existing?.origin == .manual {
            lines.append("Von dir eingetragen.")
        }
        if let existing, model.access.wasAsked {
            lines.append(model.isInHealth(existing.id) ? "In Health gespeichert." : "Noch nicht in Health gespeichert. Tagwerk versucht es erneut.")
        }
        return lines.joined(separator: " ")
    }

    private var manualValues: some View {
        Section {
            numberRow("Kalorien", unit: "kcal", value: $draft.manualKcal)
            numberRow("Eiweiß", unit: "g", value: $draft.manualProtein)
            numberRow("Kohlenhydrate", unit: "g", value: $draft.manualCarbs)
            numberRow("Fett", unit: "g", value: $draft.manualFat)
        } header: {
            Text("Werte")
        } footer: {
            Text("Nur Kalorien sind nötig. Leere Felder werden nicht nach Health geschrieben.")
        }
    }

    private func numberRow(_ title: String, unit: String, value: Binding<Double?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("–", value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
            Text(unit).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
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
                Text(range).font(.subheadline).foregroundStyle(.secondary)
            }
            Text([IntakeFormat.grams(meal.protein, estimated: estimated) + " Eiweiß",
                  IntakeFormat.grams(meal.carbs, estimated: estimated) + " Kohlenhydrate",
                  IntakeFormat.grams(meal.fat, estimated: estimated) + " Fett"].joined(separator: " · "))
                .font(.subheadline).foregroundStyle(.secondary)
        } header: {
            Text(draft.origin == .estimated ? "Schätzung von ChatGPT" : "Werte")
        }
    }

    private var itemsSection: some View {
        Section {
            ForEach(Array(draft.items.enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: 6) {
                    Button { editingItem = EditedItem(index: index, item: item) } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                if !item.amount.isEmpty {
                                    Text(item.amount).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(IntakeFormat.kcal(item.totalKcal, estimated: item.isEstimated)).monospacedDigit()
                        }
                    }
                    .tint(.primary)
                    Stepper(value: $draft.items[index].factor, in: MealItem.factorRange, step: MealItem.factorStep) {
                        Text("Menge \(IntakeFormat.factor(item.factor))").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) { draft.items.remove(at: index) } label: { Label("Entfernen", systemImage: "trash") }
                }
            }
            Button("Posten hinzufügen", systemImage: "plus") {
                editingItem = EditedItem(index: nil, item: MealItem(name: "", amount: "", kcalMin: 0, kcal: 0, kcalMax: 0,
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
            } catch is CancellationError {
                phase = .input
            } catch let failure as MealEstimator.Failure {
                if failure == .consentMissing {
                    showsConsent = true
                } else {
                    errorText = failure.message
                }
                phase = .input
            } catch {
                errorText = MealEstimator.Failure.failed.message
                phase = .input
            }
        }
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

    private func save() async {
        await model.saveMeal(draft.value, estimatedAt: draft.estimatedAt, isNew: existing == nil)
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

    private func manualValue(_ keyPath: KeyPath<MealItem, Double>) -> Double? {
        guard let value = items.first?[keyPath: keyPath], value > 0 else { return nil }
        return value
    }

    private mutating func setManual(_ value: Double?, _ apply: (inout MealItem, Double) -> Void) {
        if items.isEmpty {
            items = [MealItem(name: title, amount: "", kcalMin: 0, kcal: 0, kcalMax: 0, protein: 0, carbs: 0, fat: 0)]
        }
        apply(&items[0], max(0, value ?? 0))
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
    let id = UUID()
    let index: Int?
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
    @State private var prepared = false

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
                } footer: {
                    Text("Werte je Menge ×1. Eigene Werte gelten als genau und stehen ohne „~“.")
                }
            }
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
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ title: String, _ unit: String, _ value: Binding<Double?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("–", value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
            Text(unit).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
        }
    }
}

private extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
