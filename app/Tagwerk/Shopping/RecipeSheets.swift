import PhotosUI
import SwiftUI
import TagwerkCore

/// "Rezept hinzufügen": one sheet with its own navigation. First the input (text, photo, link or a note), and with the last
/// tap the purpose: "Zutaten auf die Einkaufsliste" shows the ingredients found, to select and put on the list, "Nur als Rezept
/// speichern" saves the recipe as a note (EK3b). Nothing is sent before one of these taps; the consent (once) is asked at that
/// tap, and only when the chosen source needs ChatGPT.
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
    /// The sheet ends in two buttons, "Zutaten auf die Einkaufsliste" and "Nur als Rezept speichern". Without it only the
    /// first one is there and the recipe always goes to the shopping list.
    var offersSaveOnly = true

    @State private var result: RecipeResult?

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

    /// Whether a recipe read with this button is only saved: the button exists and it is "Nur als Rezept speichern".
    static func savesOnly(offersSaveOnly: Bool, purpose: RecipePurpose) -> Bool {
        offersSaveOnly && purpose == .saveOnly
    }

    var body: some View {
        NavigationStack {
            RecipeInputView(purpose: .shopping, model: model, start: start,
                            choice: RecipeInputView.Choice(offersSaveOnly: offersSaveOnly)) { recipe, fromNote, purpose in
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
                point("hand.tap", "**Nur auf dein Tippen:** Ohne dein Tippen auf „Zutaten auf die Einkaufsliste“, „Nur als Rezept speichern“, „Rezept holen“ oder „Übersetzen“ verlässt nichts das iPhone. Auch ein Link wird erst dann geladen.")
                ConsentFollowUpPoint()
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
                    .font(.footnote).foregroundStyle(.secondaryText)
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
///
/// Without `choice` there is one button for the fixed `purpose` ("Rezept holen" of "Rezept mit ChatGPT anlegen"). With it the
/// source comes first and the purpose is chosen by the last tap (EK3b): one button per purpose. The purpose of a read is the
/// one of the tapped button, also when the consent sheet comes in between.
struct RecipeInputView: View {
    @Environment(AppEnvironment.self) private var environment
    /// The fixed purpose without `choice`; with it the sources of the shopping list are offered.
    let purpose: RecipePurpose
    /// The shopping list, to mark the ingredients that are on it already; `nil` when the recipe is only saved.
    let model: ShoppingModel?
    var start: RecipeStart?
    var choice: Choice?
    /// Called with the recipe, whether it came from a note of the user, and the purpose of the button that was tapped.
    let onResult: (RecipeImporter.Result, Bool, RecipePurpose) -> Void

    /// The input ends in one button per purpose instead of one button.
    struct Choice {
        /// "Nur als Rezept speichern" next to "Zutaten auf die Einkaufsliste".
        var offersSaveOnly = true
    }

    init(purpose: RecipePurpose, model: ShoppingModel?, start: RecipeStart? = nil, choice: Choice? = nil,
         onResult: @escaping (RecipeImporter.Result, Bool, RecipePurpose) -> Void) {
        self.purpose = purpose
        self.model = model
        self.start = start
        self.choice = choice
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
    /// The purpose of the button that started the read; the consent sheet and the read itself use it.
    @State private var requestedPurpose: RecipePurpose = .shopping

    private var sources: [Source] { choice != nil || purpose == .shopping ? Source.allCases : [.text, .photo, .link] }

    /// The source is set already (shared item, recipe note): only the buttons stay.
    private var hasPresetSource: Bool { !RecipeInputRules.showsSourceInput(hasStart: start != nil, hasChoice: choice != nil) }

    private var purposeButtons: [RecipeInputRules.PurposeButton] {
        RecipeInputRules.purposeButtons(offersSaveOnly: choice?.offersSaveOnly ?? false, sourceIsNote: source == .note,
                                        hasInput: canRead, isReading: reading != nil)
    }

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
            if hasPresetSource {
                presetSourceSection
            } else {
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
            }
            if let errorText {
                Section { Text(errorText).foregroundStyle(.redText) }
            }
            readSection
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
                read(for: requestedPurpose)
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

    /// The buttons that end the input: one per purpose, or the single "Rezept holen" of the fixed purpose. Both are greyed out
    /// until there is an input; the text of a button never changes.
    private var readSection: some View {
        Section {
            if choice != nil {
                VStack(spacing: 12) {
                    ForEach(purposeButtons) { button in
                        purposeButton(button)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } else {
                Button { tapRead(purpose) } label: {
                    Text("Rezept holen").fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .disabled(!canRead || reading != nil)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if choice != nil, purposeButtons.contains(where: { $0.purpose == .saveOnly }) {
                    Text("Beides legt auf Wunsch eine Notiz im Ordner „Rezepte“ an.")
                }
                if !readsLocally, !environment.ai.isSignedIn { Text("Anmeldung unter Einstellungen › KI") }
            }
        }
    }

    @ViewBuilder private func purposeButton(_ button: RecipeInputRules.PurposeButton) -> some View {
        switch button.purpose {
        case .shopping:
            Button { tapRead(.shopping) } label: {
                Text("Zutaten auf die Einkaufsliste").fontWeight(.semibold).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!button.isEnabled)
            .accessibilityIdentifier(AccessibilityID.Shopping.recipeToList)
        case .saveOnly:
            Button { tapRead(.saveOnly) } label: {
                Text("Nur als Rezept speichern").fontWeight(.semibold).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!button.isEnabled)
            .accessibilityIdentifier(AccessibilityID.Shopping.recipeSaveOnly)
        }
    }

    /// The line that names the source when it is set already: a shared link, text or photos, or a recipe note.
    private var presetSourceSection: some View {
        Section {
            Label(presetSourceText, systemImage: presetSourceSymbol)
        }
    }

    private var presetSourceSymbol: String {
        switch source {
        case .text: "text.alignleft"
        case .photo: "photo.on.rectangle"
        case .link: "link"
        case .note: "note.text"
        }
    }

    private var presetSourceText: String {
        switch source {
        case .text: String(localized: "Quelle: geteilter Text")
        case .photo: String(localized: "Quelle: Fotos (\(photos.count))")
        case .link:
            if let host = RecipeImporter.url(from: linkText)?.host { String(localized: "Quelle: Link, \(host)") } else { String(localized: "Quelle: Link") }
        case .note:
            if let noteID, let note = environment.notes.note(id: noteID) { String(localized: "Quelle: Notiz „\(NoteText.title(note.text))“") } else { String(localized: "Quelle: Notiz") }
        }
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
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondaryText)
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
            if choice != nil {
                Text("Tagwerk lädt die Seite erst beim Tippen auf einen der Knöpfe und sendet nur den gelesenen Text, nicht die Adresse.")
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
    private func tapRead(_ tapped: RecipePurpose) {
        guard reading == nil, canRead else { return }
        // The purpose is the one of this button, kept for the consent sheet: it decides what the request sends.
        requestedPurpose = tapped
        if !readsLocally, !environment.settings.shoppingRecipeConsent {
            showsConsent = true
            return
        }
        read(for: tapped)
    }

    private func read(for purpose: RecipePurpose) {
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
        // Only the shopping list knows categories and open items; a recipe that is only saved sends neither. The list's own
        // language only matters when ingredients go onto the list, and only when it differs from the recipe's.
        let context = RecipeInputRules.requestContext(
            for: purpose, openItemKeys: Set((model?.openItems ?? []).map { ShoppingName.key($0.name) }),
            categoryNames: environment.shoppingCategories.categories().map(\.name),
            shoppingLanguage: environment.settings.contentLanguages.shoppingLanguageIfDifferent())
        let openKeys = context.openItemKeys, names = context.categoryNames, shoppingLanguage = context.shoppingLanguage
        let classifier = RecipeImporter.localClassifier(assignments: environment.shoppingCategories.assignments(),
                                                        categories: environment.shoppingCategories.categories())
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
                onResult(found, fromNote, purpose)
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

/// The ingredients found: a checkmark per row. New items come first and start selected; items that are on the list already stand
/// in their own section, start unselected and say what checking them does (EK4b). At the top the question for how many servings
/// to buy; the amounts follow it, and each amount can be changed with a tap.
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
    /// Amounts the user typed instead of the scaled ones, by candidate id. They stay when the servings change afterwards.
    @State private var quantityOverrides: [String: String] = [:]
    /// The ingredient whose amount the small field changes, and the text in it.
    @State private var quantityEditID: String?
    @State private var quantityDraft = ""

    init(result: RecipeImporter.Result, fromNote: Bool, model: ShoppingModel, onAdded: @escaping (String) -> Void,
         onDiscard: @escaping () -> Void) {
        self.result = result
        self.fromNote = fromNote
        self.model = model
        self.onAdded = onAdded
        self.onDiscard = onDiscard
        _deselected = State(initialValue: Self.initiallyDeselected(result.candidates))
        _baseServings = State(initialValue: result.servings)
        _savesNote = State(initialValue: Self.defaultSavesNote(fromNote: fromNote))
    }

    private var candidates: [RecipeImporter.Candidate] { result.candidates }
    private var selected: [RecipeImporter.Candidate] { Self.selection(candidates, deselected: deselected) }
    private var target: Int? { Self.targetServings(base: baseServings, cooking: cookingServings) }
    private var locale: Locale { result.language.locale }
    /// The language the items go on the list in: the second language of the import, else the recipe's.
    private var listLocale: Locale { (result.shoppingLanguage ?? result.language).locale }

    /// Items that are on the list already start unselected: checking one is a decision (raise or second entry), not a default.
    static func initiallyDeselected(_ candidates: [RecipeImporter.Candidate]) -> Set<String> {
        Set(candidates.filter(\.alreadyOnList).map(\.id))
    }

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

    /// The candidates as they go on the list: scaled for the servings, with the amounts the user typed instead (a typed amount
    /// is free text: the amount in numbers and the unit of the shopping language are dropped, so it goes on the list as typed).
    static func effective(_ candidates: [RecipeImporter.Candidate], base: Int?, target: Int?, locale: Locale,
                          overrides: [String: String]) -> [RecipeImporter.Candidate] {
        scaled(candidates: candidates, base: base, target: target, locale: locale).map { candidate in
            guard let typed = overrides[candidate.id] else { return candidate }
            var changed = candidate
            let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            changed.quantity = text.isEmpty ? nil : text
            changed.line = nil
            changed.shoppingUnit = nil
            return changed
        }
    }

    // MARK: Items that are on the list

    /// The line under an item that is on the list already: what is there and what checking it does.
    static func existingLine(listed: ShoppingItem?, added: String?, locale: Locale) -> String {
        guard let listed else { return String(localized: "schon auf der Liste") }
        let current = listed.quantity
        let merge = ShoppingQuantity.merge(existing: current, added: added, hasLongNotes: listed.hasLongNotes, locale: locale)
        switch (merge, current) {
        case (.raise(let total), let current?): return String(localized: "auf der Liste: \(current) · anhaken erhöht auf \(total)")
        case (.raise(let total), nil): return String(localized: "auf der Liste: ohne Menge · anhaken setzt \(total)")
        case (.secondEntry, let current?): return String(localized: "auf der Liste: \(current) · anhaken legt einen zweiten Eintrag an")
        case (.secondEntry, nil): return String(localized: "auf der Liste: ohne Menge · anhaken legt einen zweiten Eintrag an")
        case (.keep, let current?): return String(localized: "auf der Liste: \(current) · bleibt unverändert")
        case (.keep, nil): return String(localized: "schon auf der Liste · bleibt unverändert")
        }
    }

    /// "Neu · 3" and "Schon auf der Liste · 1": the headers of the two sections.
    static func newHeader(count: Int) -> String { String(localized: "Neu · \(count)") }
    static func listedHeader(count: Int) -> String { String(localized: "Schon auf der Liste · \(count)") }

    /// "Portionen · 4 im Rezept": the header of the servings, which names the number the recipe is written for.
    static func servingsHeader(recipeServings: Int?) -> String {
        recipeServings.map { String(localized: "Portionen · \($0) im Rezept") } ?? String(localized: "Portionen")
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
        let shown = Self.effective(candidates, base: baseServings, target: target, locale: locale, overrides: quantityOverrides)
        let fresh = shown.filter { !$0.alreadyOnList }
        let listed = shown.filter(\.alreadyOnList)
        List {
            servingsSection
            if !fresh.isEmpty {
                Section {
                    ForEach(fresh) { candidate in row(candidate) }
                } header: {
                    Text(Self.newHeader(count: fresh.count))
                } footer: {
                    if listed.isEmpty { categoryFooter }
                }
            }
            if !listed.isEmpty {
                Section {
                    ForEach(listed) { candidate in row(candidate) }
                } header: {
                    Text(Self.listedHeader(count: listed.count))
                } footer: {
                    categoryFooter
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
        .alert(quantityEditTitle, isPresented: Binding(get: { quantityEditID != nil }, set: { if !$0 { quantityEditID = nil } })) {
            TextField("Menge", text: $quantityDraft)
            Button("Übernehmen") {
                if let id = quantityEditID { quantityOverrides[id] = quantityDraft }
                quantityEditID = nil
            }
            Button("Abbrechen", role: .cancel) { quantityEditID = nil }
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

    /// One row for the servings when the recipe names them: "Ich koche für" with the recipe's number in the header. Without a
    /// number in the recipe there are two rows, because "Rezept für" has to be set first.
    private var servingsSection: some View {
        Section {
            if result.servings == nil {
                ValueStepper("Rezept für", value: $baseServings, start: Self.startServings, in: Self.servingsRange)
            }
            ValueStepper("Ich koche für", value: Binding(get: { target }, set: { cookingServings = $0 }),
                         start: Self.startServings, in: Self.servingsRange)
        } header: {
            Text(Self.servingsHeader(recipeServings: result.servings))
        } footer: {
            if baseServings == nil {
                Text("Im Rezept steht keine Portionszahl.").foregroundStyle(.redText)
            }
        }
    }

    @ViewBuilder private var categoryFooter: some View {
        if result.readLocally {
            Text("Die Kategorien kommen aus deiner Einkaufsliste.")
            if result.keepsNoteLanguage, let noteLanguage = result.noteLanguage {
                Text("Die Zutaten stehen in der Sprache der Notiz (\(LanguageSettingsText.name(noteLanguage))). Neue Artikel aus dieser Notiz kommen so auf die Liste. Über „•••“ › „Artikel übersetzen …“ kannst du sie danach übersetzen.")
            }
        } else {
            Text("Die Kategorien kommen von ChatGPT und lassen sich später in der Liste ändern.")
        }
    }

    /// The row: a checkmark and the name with its second line, and the amount as a button of its own that opens the small field.
    private func row(_ candidate: RecipeImporter.Candidate) -> some View {
        let isOn = !deselected.contains(candidate.id)
        let quantity = RecipeImporter.listItem(for: candidate, locale: listLocale).quantity
        return HStack(spacing: 0) {
            Button {
                if isOn { deselected.insert(candidate.id) } else { deselected.remove(candidate.id) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isOn ? Color.accentColor : Color.secondaryText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidate.listName).foregroundStyle(.primary)
                        if candidate.shoppingName != nil, candidate.shoppingName != candidate.name {
                            Text("Rezept: \(candidate.name)").font(.footnote).foregroundStyle(Color.secondaryText)
                        }
                        // A fixed grey: the hierarchical `.secondary` takes the tint of the button around the row and fails the contrast audit.
                        Text(secondLine(candidate, quantity: quantity)).font(.subheadline).foregroundStyle(Color.secondaryText)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)  // inside a list row, default buttons all fire together
            .accessibilityAddTraits(isOn ? .isSelected : [])
            Button {
                quantityDraft = quantity ?? ""
                quantityEditID = candidate.id
            } label: {
                Text(quantity ?? String(localized: "Menge"))
                    .foregroundStyle(quantity == nil ? AnyShapeStyle(Color.secondaryText) : AnyShapeStyle(.tint))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(String(localized: "Menge ändern, \(candidate.listName)"))
            .accessibilityValue(quantity ?? String(localized: "ohne Menge"))
        }
    }

    /// Under the name: the category, or for an item on the list what is there and what checking it does.
    private func secondLine(_ candidate: RecipeImporter.Candidate, quantity: String?) -> String {
        guard candidate.alreadyOnList else { return candidate.category }
        let listed = model.openItems.first { ShoppingName.key($0.name) == candidate.id }
        return Self.existingLine(listed: listed, added: quantity, locale: listLocale)
    }

    private var quantityEditTitle: String {
        let name = candidates.first { $0.id == quantityEditID }?.listName ?? ""
        return String(localized: "Menge von \(name)")
    }

    static func addTitle(count: Int) -> String {
        String(localized: "\(count) Artikel hinzufügen")
    }

    private func add() {
        guard Self.canAdd(base: baseServings, selectedCount: selected.count) else { return }
        isAdding = true
        let chosen = Self.effective(selected, base: baseServings, target: target, locale: locale, overrides: quantityOverrides)
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
        let count = report.added.count + report.reopened.count + report.raised.count
        if let error = report.errorMessage, count == 0 { return error }
        return String(localized: "\(count) Artikel aus dem Rezept hinzugefügt.")
    }
}
