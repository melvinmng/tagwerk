import PhotosUI
import SwiftUI
import TagwerkCore

/// "Rezept hinzufügen": one sheet with its own navigation. First the input (text, photo, link or a note), then the
/// ingredients found, to select and put on the list. Nothing is sent before the user taps "Zutaten holen"; the consent
/// (once) is asked at that tap, and only when the chosen source needs ChatGPT.
struct RecipeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var environment
    let model: ShoppingModel
    /// Called after the ingredients were added, with the line for the page's notice.
    let onFinished: (String) -> Void
    /// Shared content (plan P6) or a recipe note: the input starts with this link, text, photo or note.
    var start: RecipeStart?
    /// Offered by shared items: "Verwerfen" removes the item instead of only closing the sheet.
    var onDiscard: (() -> Void)?
    /// Shared items: the sheet first asks what happens with the recipe, "Zutaten auf die Einkaufsliste" or "Nur als Rezept
    /// speichern". Without it the recipe always goes to the shopping list (the "Rezept hinzufügen" button).
    var offersSaveOnly = false

    @State private var result: RecipeResult?
    @State private var purpose: RecipePurpose = .shopping

    /// The recipe found, identifiable for the navigation.
    struct RecipeResult: Identifiable, Hashable {
        let id = UUID()
        let recipe: RecipeImporter.Result
        /// The recipe came from a note of the user: it is not saved as a second recipe note.
        let fromNote: Bool
        /// The user chose "Nur als Rezept speichern": the result is saved as a note, the shopping list stays untouched.
        var savesOnly = false
        static func == (lhs: RecipeResult, rhs: RecipeResult) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    /// Whether a recipe read now is only saved: the choice exists and "Nur als Rezept speichern" is on.
    static func savesOnly(offersSaveOnly: Bool, purpose: RecipePurpose) -> Bool {
        offersSaveOnly && purpose == .saveOnly
    }

    var body: some View {
        NavigationStack {
            RecipeInputView(purpose: Self.savesOnly(offersSaveOnly: offersSaveOnly, purpose: purpose) ? .saveOnly : .shopping,
                            model: model, start: start, purposeChoice: offersSaveOnly ? $purpose : nil) { recipe, fromNote in
                result = RecipeResult(recipe: recipe, fromNote: fromNote,
                                      savesOnly: Self.savesOnly(offersSaveOnly: offersSaveOnly, purpose: purpose))
            }
            .navigationTitle("Rezept hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                if let onDiscard {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Verwerfen", role: .destructive) {
                            onDiscard()
                            dismiss()
                        }
                    }
                }
            }
            .navigationDestination(item: $result) { found in
                if found.savesOnly {
                    // The same confirmation as "Rezept mit ChatGPT anlegen"; the shopping list is not touched.
                    RecipeNoteSaveView(result: found.recipe, store: environment.notes) { _ in
                        onFinished(String(localized: "Das Rezept liegt als Notiz im Ordner „Rezepte“."))
                        dismiss()
                    } onDiscard: {
                        dismiss()
                    }
                } else {
                    RecipeResultView(result: found.recipe, fromNote: found.fromNote, model: model) { line in
                        onFinished(line)
                        dismiss()
                    } onDiscard: {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        // A sheet does not take the forced text size of the UI test mode from the window; no effect outside that mode.
        .modifier(UITestAppearance())
    }
}

// MARK: Consent

/// The one-time consent before the first recipe is read by ChatGPT.
struct RecipeConsentView: View {
    let onAgree: () -> Void
    let onDecline: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Um ein Rezept zu lesen oder zu übersetzen, sendet Tagwerk den Rezepttext oder die Fotos und die Namen deiner Kategorien an ChatGPT (OpenAI), über das Konto, mit dem du angemeldet bist.")
                point("paperplane", "**Gesendet wird:** der Rezepttext oder die Fotos und die Kategorienamen, oder der Text einer Notiz, die du ausdrücklich als Quelle wählst. Bei einem Link nur der gelesene Text der Seite, nicht die Adresse. Beim Übersetzen der Text der einen Rezept-Notiz, ohne Anhänge.")
                point("eye.slash", "**Nicht gesendet werden:** deine Einkaufsliste, Mengen auf der Liste, Aufgaben, Termine, andere Notizen, Daten aus Health. Eine Notiz mit Zutaten und Zubereitung liest Tagwerk auf dem iPhone, und private Notizen stehen nie zur Auswahl.")
                point("hand.tap", "**Nur auf dein Tippen:** Ohne „Zutaten holen“, „Rezept holen“ oder „Übersetzen“ verlässt nichts das iPhone. Auch ein Link wird erst dann geladen.")
                VStack(spacing: 10) {
                    Button(action: onAgree) {
                        Text("Einverstanden").fontWeight(.semibold).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Button("Nicht jetzt", action: onDecline)
                }
                .padding(.top, 4)
                Text("Du kannst das in den Einstellungen unter „Einkaufsliste“ widerrufen.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .interactiveDismissDisabled()
        .modifier(UITestAppearance())
    }

    private func point(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 24)
            Text(text)
        }
    }
}

// MARK: Input

/// What a shared item or a recipe note puts into the input of the recipe sheet.
enum RecipeStart {
    case link(String)
    case text(String)
    /// The pictures of a shared item, in order; at most `RecipePhotos.maximumCount` are taken.
    case photos([UIImage])
    /// A recipe note: "Zutaten auf die Einkaufsliste" in the note.
    case note(UUID)
}

/// A photo of the recipe, scaled down once when it is added (long edge 1,024 px, re-encoded, no metadata).
private struct PickedPhoto: Identifiable {
    let id = UUID()
    let jpeg: Data
    let image: UIImage

    init?(image: UIImage) {
        guard let jpeg = ImageDownscaler.jpeg(from: image, maxEdge: 1024), let scaled = UIImage(data: jpeg) else { return nil }
        self.jpeg = jpeg
        self.image = scaled
    }
}

/// An image from the clipboard; the data is kept as it is and decoded where it is added.
private struct PastedImage: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { PastedImage(data: $0) }
    }
}

/// What the recipe is read for.
enum RecipePurpose {
    /// "Rezept hinzufügen": the ingredients go on the shopping list.
    case shopping
    /// "Rezept mit ChatGPT anlegen": the recipe is only saved as a note; the shopping list is not touched.
    case saveOnly
}

/// Text, photo, link or note, and the button that reads the recipe. Both ways to a recipe (the shopping list and the recipe
/// note) read through this one view and `RecipeImporter.read`; only what follows the result differs.
struct RecipeInputView: View {
    @Environment(AppEnvironment.self) private var environment
    let purpose: RecipePurpose
    /// The shopping list, to mark the ingredients that are on it already; `nil` when the recipe is only saved.
    let model: ShoppingModel?
    var start: RecipeStart?
    /// Shared items: shows the choice between the shopping list and "Nur als Rezept speichern" above the source. The caller
    /// passes the same value as `purpose`, so the request, the button and the consent text follow the choice.
    var purposeChoice: Binding<RecipePurpose>?
    /// Called with the recipe and whether it came from a note of the user.
    let onResult: (RecipeImporter.Result, Bool) -> Void

    init(purpose: RecipePurpose, model: ShoppingModel?, start: RecipeStart? = nil, purposeChoice: Binding<RecipePurpose>? = nil,
         onResult: @escaping (RecipeImporter.Result, Bool) -> Void) {
        self.purpose = purpose
        self.model = model
        self.start = start
        self.purposeChoice = purposeChoice
        self.onResult = onResult
        switch start {
        case .link(let text): _source = State(initialValue: .link); _linkText = State(initialValue: text)
        case .text(let text): _recipeText = State(initialValue: text)
        case .photos(let images):
            _source = State(initialValue: .photo)
            _photos = State(initialValue: images.prefix(RecipePhotos.maximumCount).compactMap(PickedPhoto.init(image:)))
        case .note(let id): _source = State(initialValue: .note); _noteID = State(initialValue: id)
        case nil: break
        }
    }

    private enum Source: String, CaseIterable, Identifiable {
        case text, photo, link, note
        var id: String { rawValue }
    }

    @State private var source: Source = .text
    @State private var recipeText = ""
    @State private var linkText = ""
    @State private var photos: [PickedPhoto] = []
    @State private var noteID: UUID?
    @State private var showsOtherNotes = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showsPhotoLimit = false
    @State private var showsCamera = false
    @State private var showsConsent = false
    @State private var reading: Task<Void, Never>?
    @State private var readingID: UUID?
    @State private var errorText: String?

    private var sources: [Source] { purpose == .shopping ? Source.allCases : [.text, .photo, .link] }

    private var canRead: Bool {
        switch source {
        case .text: !recipeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .photo: !photos.isEmpty
        case .link: !linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .note: selectedNoteText != nil
        }
    }

    /// The text of the chosen note, if it may be used at all (not private, not empty).
    private var selectedNoteText: String? {
        guard let noteID, let note = environment.notes.note(id: noteID),
              RecipeNoteSource.isOffered(note, store: environment.notes) else { return nil }
        return note.text
    }

    /// A structured recipe note is read on the device: no consent, no sign-in, nothing sent.
    private var readsLocally: Bool {
        source == .note && selectedNoteText.map { RecipeNote.parse($0) != nil } == true
    }

    var body: some View {
        Form {
            if let purposeChoice { purposeSection(purposeChoice) }
            Section {
                Picker("Quelle", selection: $source) {
                    ForEach(sources) { source in
                        switch source {
                        case .text: Text("Text").tag(source)
                        case .photo: Text("Foto").tag(source)
                        case .link: Text("Link").tag(source)
                        case .note: Text("Notiz").tag(source)
                        }
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            switch source {
            case .text: textSection
            case .photo: photoSection
            case .link: linkSection
            case .note: RecipeNoteSection(store: environment.notes, selectedID: $noteID, showsOthers: $showsOtherNotes)
            }
            if let errorText {
                Section { Text(errorText).foregroundStyle(.red) }
            }
            Section {
                Button(action: tapRead) {
                    Text(readTitle).fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .disabled(!canRead || reading != nil)
            } footer: {
                if !readsLocally, !environment.ai.isSignedIn { Text("Anmeldung unter Einstellungen › KI") }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .overlay {
            if reading != nil { readingOverlay }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker { image in
                showsCamera = false
                if let image { add([image]) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showsConsent) {
            RecipeConsentView {
                environment.settings.shoppingRecipeConsent = true
                showsConsent = false
                read()
            } onDecline: {
                showsConsent = false
            }
        }
        .sheet(isPresented: $showsOtherNotes) {
            RecipeOtherNotesSheet(store: environment.notes, selectedID: $noteID)
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                // In the order of the selection; a photo that cannot be read is skipped.
                var images: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { images.append(image) }
                }
                pickerItems = []
                add(images)
            }
        }
        .onDisappear { cancel() }
    }

    /// "Was soll mit dem Rezept geschehen?" for shared items. Both ways read once; the shopping way can also keep the recipe
    /// as a note ("Auch als Rezept-Notiz sichern" on the next page), so both together are possible there.
    private func purposeSection(_ choice: Binding<RecipePurpose>) -> some View {
        Section {
            Picker("Was soll mit dem Rezept geschehen?", selection: choice) {
                Text("Zutaten auf die Einkaufsliste").tag(RecipePurpose.shopping)
                Text("Nur als Rezept speichern").tag(RecipePurpose.saveOnly)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("Was soll mit dem Rezept geschehen?")
        } footer: {
            switch choice.wrappedValue {
            case .shopping: Text("Du wählst die Zutaten aus und kannst das Rezept zusätzlich als Notiz im Ordner „Rezepte“ sichern.")
            case .saveOnly: Text("Das Rezept wird als Notiz im Ordner „Rezepte“ gespeichert. Die Einkaufsliste bleibt unverändert.")
            }
        }
    }

    private var readTitle: LocalizedStringKey {
        if purpose == .saveOnly { return "Rezept holen" }
        return readsLocally ? "Zutaten übernehmen" : "Zutaten holen"
    }

    // MARK: Sources

    private var textSection: some View {
        Section {
            TextEditor(text: $recipeText)
                .frame(minHeight: 220)
                .accessibilityLabel("Rezepttext")
                .keyboardDoneButton()
        } header: {
            Text("Rezepttext")
        } footer: {
            Text("Füge die Zutatenliste oder das ganze Rezept ein. Es werden höchstens \(RecipeText.maximumLength) Zeichen gelesen.")
        }
    }

    private var photoSection: some View {
        Section {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                HStack(spacing: 12) {
                    Image(uiImage: photo.image).resizable().scaledToFill().frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .accessibilityHidden(true)
                    Text("Foto \(index + 1)")
                    Spacer()
                    Button { photos.removeAll { $0.id == photo.id } } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Foto \(index + 1) entfernen")
                }
            }
            .onDelete { photos.remove(atOffsets: $0) }
            if RecipePhotos.remainingSlots(current: photos.count) > 0 {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: RecipePhotos.remainingSlots(current: photos.count),
                             selectionBehavior: .ordered, matching: .images) {
                    Label(photos.isEmpty ? "Fotos auswählen" : "Weitere Fotos auswählen", systemImage: "photo.on.rectangle")
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showsCamera = true } label: { Label("Foto aufnehmen", systemImage: "camera") }
                }
                PasteButton(payloadType: PastedImage.self) { pasted in
                    add(pasted.compactMap { UIImage(data: $0.data) })
                }
            }
        } header: {
            Text("Fotos des Rezepts")
        } footer: {
            if showsPhotoLimit || RecipePhotos.remainingSlots(current: photos.count) == 0 {
                Text("Höchstens \(RecipePhotos.maximumCount) Fotos pro Rezept.")
            } else {
                Text("Zum Beispiel die Seiten aus einem Kochbuch oder mehrere Screenshots: bis zu \(RecipePhotos.maximumCount) Fotos, die zusammen als ein Rezept gelesen werden. Die Fotos werden verkleinert und nicht gespeichert.")
            }
        }
    }

    /// Adds photos in order, up to the limit; the rest is dropped and the limit is named.
    private func add(_ images: [UIImage]) {
        let take = RecipePhotos.accepted(current: photos.count, incoming: images.count)
        showsPhotoLimit = take < images.count
        photos.append(contentsOf: images.prefix(take).compactMap(PickedPhoto.init(image:)))
    }

    private var linkSection: some View {
        Section {
            TextField("https://…", text: $linkText)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            PasteButton(payloadType: String.self) { strings in
                if let first = strings.first { linkText = first }
            }
        } header: {
            Text("Link zum Rezept")
        } footer: {
            if purpose == .shopping {
                Text("Tagwerk lädt die Seite erst, wenn du „Zutaten holen“ tippst, und sendet nur den gelesenen Text, nicht die Adresse.")
            } else {
                Text("Tagwerk lädt die Seite erst, wenn du „Rezept holen“ tippst, und sendet nur den gelesenen Text, nicht die Adresse.")
            }
        }
    }

    private var readingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView("ChatGPT liest das Rezept …")
            Button("Abbrechen", action: cancel)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Reading

    /// The tap on the button: a source that needs ChatGPT asks for the consent first (once); a recipe note on the device
    /// needs none.
    private func tapRead() {
        guard reading == nil, canRead else { return }
        if !readsLocally, !environment.settings.shoppingRecipeConsent {
            showsConsent = true
            return
        }
        read()
    }

    private func read() {
        guard reading == nil, let input = makeInput() else {
            if source == .link, reading == nil { errorText = RecipeImporter.Failure.linkUnreadable.message }
            return
        }
        guard readsLocally || environment.ai.isSignedIn else {
            errorText = RecipeImporter.Failure.signedOut.message
            return
        }
        errorText = nil
        let language = environment.settings.resolvedRecipeLanguage
        // Only the shopping list knows categories and open items; a recipe that is only saved sends neither.
        let openKeys = purpose == .shopping ? Set((model?.openItems ?? []).map { ShoppingName.key($0.name) }) : []
        let names = purpose == .shopping ? environment.shoppingCategories.categories().map(\.name) : []
        let classifier = RecipeImporter.localClassifier(assignments: environment.shoppingCategories.assignments(),
                                                        categories: environment.shoppingCategories.categories())
        // The list's own language only matters when ingredients go onto the list, and only when it differs from the recipe's.
        let shoppingLanguage = purpose == .shopping ? environment.settings.contentLanguages.shoppingLanguageIfDifferent() : nil
        let fromNote = source == .note
        let id = UUID()
        readingID = id
        reading = Task {
            defer { if readingID == id { reading = nil } }
            do {
                let found = try await environment.recipeImporter.read(input, language: language, shoppingLanguage: shoppingLanguage,
                                                                      categoryNames: names, openItemKeys: openKeys,
                                                                      localClassifier: classifier)
                // A cancelled request must not show a late answer.
                guard !Task.isCancelled else { return }
                onResult(found, fromNote)
            } catch let failure as RecipeImporter.Failure {
                if !Task.isCancelled { errorText = failure.message }
            } catch {
                // Cancelled by the user: nothing to report.
            }
        }
    }

    private func makeInput() -> RecipeImporter.Input? {
        switch source {
        case .text: return .text(recipeText)
        case .photo: return photos.isEmpty ? nil : .photos(photos.map(\.jpeg))
        case .link: return RecipeImporter.url(from: linkText).map { .link($0) }
        case .note: return noteID.flatMap { id in selectedNoteText.map { .note(id, text: $0) } }
        }
    }

    private func cancel() {
        reading?.cancel()
        reading = nil
        readingID = nil
    }
}

// MARK: Result

/// The ingredients found: a checkmark per row, items that are on the list already start unselected. At the top the question
/// for how many servings to buy; the amounts follow it.
struct RecipeResultView: View {
    @Environment(AppEnvironment.self) private var environment
    let result: RecipeImporter.Result
    let fromNote: Bool
    let model: ShoppingModel
    let onAdded: (String) -> Void
    let onDiscard: () -> Void

    @State private var deselected: Set<String>
    /// "Rezept für": the servings the recipe is written for; `nil` when the recipe names none, then it has to be set.
    @State private var baseServings: Int?
    /// "Ich koche für"; `nil` follows "Rezept für".
    @State private var cookingServings: Int?
    @State private var savesNote: Bool
    @State private var isAdding = false

    init(result: RecipeImporter.Result, fromNote: Bool, model: ShoppingModel, onAdded: @escaping (String) -> Void,
         onDiscard: @escaping () -> Void) {
        self.result = result
        self.fromNote = fromNote
        self.model = model
        self.onAdded = onAdded
        self.onDiscard = onDiscard
        _deselected = State(initialValue: Set(result.candidates.filter(\.alreadyOnList).map(\.id)))
        _baseServings = State(initialValue: result.servings)
        _savesNote = State(initialValue: Self.defaultSavesNote(fromNote: fromNote))
    }

    private var candidates: [RecipeImporter.Candidate] { result.candidates }
    private var selected: [RecipeImporter.Candidate] { Self.selection(candidates, deselected: deselected) }
    private var target: Int? { Self.targetServings(base: baseServings, cooking: cookingServings) }
    private var locale: Locale { result.language.locale }
    /// The language the items go on the list in: the second language of the import, else the recipe's.
    private var listLocale: Locale { (result.shoppingLanguage ?? result.language).locale }

    /// What "hinzufügen" puts on the list.
    static func selection(_ candidates: [RecipeImporter.Candidate], deselected: Set<String>) -> [RecipeImporter.Candidate] {
        candidates.filter { !deselected.contains($0.id) }
    }

    // MARK: Servings

    static let servingsRange = RecipeImporter.servingsRange
    /// The number a stepper starts from when it has none yet.
    static let startServings = 4

    /// "Ich koche für": the number the user chose, otherwise the one of the recipe.
    static func targetServings(base: Int?, cooking: Int?) -> Int? { cooking ?? base }

    /// Whether "hinzufügen" is possible: at least one item is chosen, and the recipe's servings are known (the amounts cannot
    /// be scaled without them).
    static func canAdd(base: Int?, selectedCount: Int) -> Bool { base != nil && selectedCount > 0 }

    /// The candidates with their amounts for `target` servings of a recipe written for `base`. Names and ids stay (a name on
    /// the list is not put into the plural). Without a number for both, or with equal numbers, nothing changes; a free
    /// quantity that cannot be read stays as it is.
    static func scaled(candidates: [RecipeImporter.Candidate], base: Int?, target: Int?, locale: Locale) -> [RecipeImporter.Candidate] {
        guard let base, let target, base != target else { return candidates }
        return candidates.map { candidate in
            var scaled = candidate
            if let line = candidate.line {
                let changed = RecipeScaler.scale(line, from: base, to: target, adjustsName: false)
                scaled.line = changed
                scaled.quantity = RecipeImporter.quantityText(of: changed, locale: locale) ?? candidate.quantity
            } else {
                scaled.quantity = RecipeScaler.scale(candidate.quantity, from: base, to: target, locale: locale)
            }
            return scaled
        }
    }

    // MARK: Recipe note

    /// Whether "Auch als Rezept-Notiz sichern" starts on: not for a recipe that came from a note.
    static func defaultSavesNote(fromNote: Bool) -> Bool { !fromNote }

    /// The recipe note "hinzufügen" saves along with the items; `nil` when the switch is off or the recipe came from a note
    /// already. It holds the recipe as it was read, with the servings it is written for.
    static func noteToSave(_ result: RecipeImporter.Result, fromNote: Bool, savesNote: Bool, servings: Int?) -> RecipeNote? {
        guard savesNote, !fromNote else { return nil }
        return RecipeNoteWriter.recipeNote(from: result, title: result.title, servings: servings)
    }

    // MARK: Body

    var body: some View {
        let shown = Self.scaled(candidates: candidates, base: baseServings, target: target, locale: locale)
        List {
            Section {
                ValueStepper("Rezept für", value: $baseServings, start: Self.startServings, in: Self.servingsRange)
                ValueStepper("Ich koche für", value: Binding(get: { target }, set: { cookingServings = $0 }),
                             start: Self.startServings, in: Self.servingsRange)
            } header: {
                Text("Portionen")
            } footer: {
                if baseServings == nil {
                    Text("Im Rezept steht keine Portionszahl.").foregroundStyle(.red)
                }
            }
            Section {
                ForEach(shown) { candidate in
                    Button {
                        if deselected.contains(candidate.id) { deselected.remove(candidate.id) } else { deselected.insert(candidate.id) }
                    } label: {
                        row(candidate, isOn: !deselected.contains(candidate.id))
                    }
                    .accessibilityAddTraits(deselected.contains(candidate.id) ? [] : .isSelected)
                }
            } footer: {
                if result.readLocally {
                    Text("Die Kategorien kommen aus deiner Einkaufsliste.")
                    if result.keepsNoteLanguage, let noteLanguage = result.noteLanguage {
                        Text("Die Zutaten stehen in der Sprache der Notiz (\(LanguageSettingsText.name(noteLanguage))). Neue Artikel aus dieser Notiz kommen so auf die Liste.")
                    }
                } else {
                    Text("Die Kategorien kommen von ChatGPT und lassen sich später in der Liste ändern.")
                }
            }
            if !fromNote {
                Section {
                    Toggle("Auch als Rezept-Notiz sichern", isOn: $savesNote)
                } footer: {
                    Text("Legt eine Notiz im Ordner „Rezepte“ an, mit den Zutaten in den Mengen des Rezepts.")
                }
            }
        }
        .navigationTitle("Zutaten")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Verwerfen", action: onDiscard) }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: add) {
                Text(Self.addTitle(count: selected.count)).fontWeight(.semibold).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!Self.canAdd(base: baseServings, selectedCount: selected.count) || isAdding)
            .padding()
            .background(.bar)
        }
    }

    private func row(_ candidate: RecipeImporter.Candidate, isOn: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(candidate.listName).foregroundStyle(.primary)
                    // A fixed grey: the hierarchical `.secondary` takes the tint of the button around the row and fails the contrast audit.
                    if let quantity = RecipeImporter.listItem(for: candidate, locale: listLocale).quantity {
                        Text(quantity).foregroundStyle(Color.secondary)
                    }
                }
                if candidate.shoppingName != nil, candidate.shoppingName != candidate.name {
                    Text("Rezept: \(candidate.name)").font(.footnote).foregroundStyle(Color.secondary)
                }
                Text(candidate.alreadyOnList ? candidate.category + " · " + String(localized: "schon auf der Liste") : candidate.category)
                    .font(.subheadline).foregroundStyle(Color.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    static func addTitle(count: Int) -> String {
        String(localized: "\(count) Artikel hinzufügen")
    }

    private func add() {
        guard Self.canAdd(base: baseServings, selectedCount: selected.count) else { return }
        isAdding = true
        let chosen = Self.scaled(candidates: selected, base: baseServings, target: target, locale: locale)
        // The note keeps the title, the servings and the amounts of the recipe, not the scaled ones.
        let note = Self.noteToSave(result, fromNote: fromNote, savesNote: savesNote, servings: baseServings)
        Task {
            let report = await RecipeImporter.apply(chosen, model: model, categories: environment.shoppingCategories, locale: listLocale)
            var line = Self.resultLine(report)
            if let note, RecipeNoteWriter.save(note, language: result.language, store: environment.notes) != nil {
                line += " " + String(localized: "Das Rezept liegt als Notiz im Ordner „Rezepte“.")
            }
            onAdded(line)
        }
    }

    /// The line on the shopping page afterwards: how many went on the list, or the first error.
    static func resultLine(_ report: ShoppingModel.AddReport) -> String {
        let count = report.added.count + report.reopened.count
        if let error = report.errorMessage, count == 0 { return error }
        return String(localized: "\(count) Artikel aus dem Rezept hinzugefügt.")
    }
}
