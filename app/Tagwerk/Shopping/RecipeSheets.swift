import PhotosUI
import SwiftUI
import TagwerkCore

/// "Rezept hinzufügen": one sheet with its own navigation. First the consent (once), then the input (text, photo or
/// link), then the ingredients found, to select and put on the list. Nothing is sent before the user taps
/// "Zutaten holen".
struct RecipeSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let model: ShoppingModel
    /// Called after the ingredients were added, with the line for the page's notice.
    let onFinished: (String) -> Void

    @State private var hasConsent = false
    @State private var result: RecipeResult?

    /// The ingredients found, identifiable for the navigation.
    struct RecipeResult: Identifiable, Hashable {
        let id = UUID()
        let candidates: [RecipeImporter.Candidate]
        static func == (lhs: RecipeResult, rhs: RecipeResult) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if hasConsent {
                    RecipeInputView(model: model) { result = RecipeResult(candidates: $0) }
                } else {
                    RecipeConsentView {
                        environment.settings.shoppingRecipeConsent = true
                        hasConsent = true
                    } onDecline: {
                        dismiss()
                    }
                }
            }
            .navigationTitle("Rezept hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if hasConsent {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                }
            }
            .navigationDestination(item: $result) { found in
                RecipeResultView(candidates: found.candidates, model: model) { line in
                    onFinished(line)
                    dismiss()
                } onDiscard: {
                    dismiss()
                }
            }
        }
        .presentationDetents([.large])
        .onAppear { hasConsent = environment.settings.shoppingRecipeConsent }
    }
}

// MARK: Consent

/// The one-time consent before the first recipe is read.
struct RecipeConsentView: View {
    let onAgree: () -> Void
    let onDecline: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Um ein Rezept zu lesen, sendet Tagwerk den Rezepttext oder das Foto und die Namen deiner Kategorien an ChatGPT (OpenAI), über das Konto, mit dem du angemeldet bist.")
                point("paperplane", "**Gesendet wird:** der Rezepttext oder das Foto und die Kategorienamen. Bei einem Link nur der gelesene Text der Seite, nicht die Adresse.")
                point("eye.slash", "**Nicht gesendet werden:** deine Einkaufsliste, Mengen auf der Liste, Aufgaben, Termine, Notizen, Daten aus Health.")
                point("hand.tap", "**Nur auf dein Tippen:** Ohne „Zutaten holen“ verlässt nichts das iPhone. Auch ein Link wird erst dann geladen.")
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
    }

    private func point(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 24)
            Text(text)
        }
    }
}

// MARK: Input

/// Text, photo or link, and the button that reads the recipe.
struct RecipeInputView: View {
    @Environment(AppEnvironment.self) private var environment
    let model: ShoppingModel
    let onResult: ([RecipeImporter.Candidate]) -> Void

    private enum Source: String, CaseIterable, Identifiable {
        case text, photo, link
        var id: String { rawValue }
    }

    @State private var source: Source = .text
    @State private var recipeText = ""
    @State private var linkText = ""
    @State private var photo: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showsCamera = false
    @State private var reading: Task<Void, Never>?
    @State private var readingID: UUID?
    @State private var errorText: String?

    private var canRead: Bool {
        switch source {
        case .text: !recipeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .photo: photo != nil
        case .link: !linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Quelle", selection: $source) {
                    Text("Text").tag(Source.text)
                    Text("Foto").tag(Source.photo)
                    Text("Link").tag(Source.link)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            switch source {
            case .text: textSection
            case .photo: photoSection
            case .link: linkSection
            }
            if let errorText {
                Section { Text(errorText).foregroundStyle(.red) }
            }
            Section {
                Button(action: read) {
                    Text("Zutaten holen").fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .disabled(!canRead || reading != nil)
            } footer: {
                if !environment.ai.isSignedIn { Text("Anmeldung unter Einstellungen › KI") }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .overlay {
            if reading != nil { readingOverlay }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker { image in
                showsCamera = false
                if let image { photo = image }
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { photo = image }
                pickerItem = nil
            }
        }
        .onDisappear { cancel() }
    }

    // MARK: Sources

    private var textSection: some View {
        Section {
            TextEditor(text: $recipeText)
                .frame(minHeight: 220)
                .keyboardDoneButton()
        } header: {
            Text("Rezepttext")
        } footer: {
            Text("Füge die Zutatenliste oder das ganze Rezept ein. Es werden höchstens \(RecipeText.maximumLength) Zeichen gelesen.")
        }
    }

    private var photoSection: some View {
        Section {
            if let photo {
                Image(uiImage: photo).resizable().scaledToFit().frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 8)).frame(maxWidth: .infinity)
                Button("Foto entfernen", systemImage: "xmark.circle.fill", role: .destructive) { self.photo = nil }
            }
            PhotosPicker(selection: $pickerItem, matching: .images) { Label("Foto auswählen", systemImage: "photo") }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showsCamera = true } label: { Label("Foto aufnehmen", systemImage: "camera") }
            }
        } header: {
            Text("Foto des Rezepts")
        } footer: {
            Text("Zum Beispiel die Seite aus einem Kochbuch. Das Foto wird verkleinert und nicht gespeichert.")
        }
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
            Text("Tagwerk lädt die Seite erst, wenn du „Zutaten holen“ tippst, und sendet nur den gelesenen Text, nicht die Adresse.")
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

    private func read() {
        guard reading == nil, let input = makeInput() else {
            if source == .link, reading == nil { errorText = RecipeImporter.Failure.linkUnreadable.message }
            return
        }
        guard environment.ai.isSignedIn else {
            errorText = RecipeImporter.Failure.signedOut.message
            return
        }
        errorText = nil
        let openKeys = Set(model.openItems.map { ShoppingName.key($0.name) })
        let names = environment.shoppingCategories.categories().map(\.name)
        let id = UUID()
        readingID = id
        reading = Task {
            defer { if readingID == id { reading = nil } }
            do {
                let found = try await environment.recipeImporter.read(input, categoryNames: names, openItemKeys: openKeys)
                // A cancelled request must not show a late answer.
                guard !Task.isCancelled else { return }
                onResult(found)
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
        case .photo: return photo.flatMap { ImageDownscaler.jpeg(from: $0, maxEdge: 1024) }.map { .photo(jpeg: $0) }
        case .link: return RecipeImporter.url(from: linkText).map { .link($0) }
        }
    }

    private func cancel() {
        reading?.cancel()
        reading = nil
        readingID = nil
    }
}

// MARK: Result

/// The ingredients found: a checkmark per row, items that are on the list already start unselected.
struct RecipeResultView: View {
    @Environment(AppEnvironment.self) private var environment
    let candidates: [RecipeImporter.Candidate]
    let model: ShoppingModel
    let onAdded: (String) -> Void
    let onDiscard: () -> Void

    @State private var deselected: Set<String>
    @State private var isAdding = false

    init(candidates: [RecipeImporter.Candidate], model: ShoppingModel, onAdded: @escaping (String) -> Void, onDiscard: @escaping () -> Void) {
        self.candidates = candidates
        self.model = model
        self.onAdded = onAdded
        self.onDiscard = onDiscard
        _deselected = State(initialValue: Set(candidates.filter(\.alreadyOnList).map(\.id)))
    }

    private var selected: [RecipeImporter.Candidate] { Self.selection(candidates, deselected: deselected) }

    /// What "hinzufügen" puts on the list.
    static func selection(_ candidates: [RecipeImporter.Candidate], deselected: Set<String>) -> [RecipeImporter.Candidate] {
        candidates.filter { !deselected.contains($0.id) }
    }

    var body: some View {
        List {
            Section {
                ForEach(candidates) { candidate in
                    Button {
                        if deselected.contains(candidate.id) { deselected.remove(candidate.id) } else { deselected.insert(candidate.id) }
                    } label: {
                        row(candidate, isOn: !deselected.contains(candidate.id))
                    }
                    .accessibilityAddTraits(deselected.contains(candidate.id) ? [] : .isSelected)
                }
            } footer: {
                Text("Die Kategorien kommen von ChatGPT und lassen sich später in der Liste ändern.")
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
            .disabled(selected.isEmpty || isAdding)
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
                    Text(candidate.name).foregroundStyle(.primary)
                    if let quantity = candidate.quantity { Text(quantity).foregroundStyle(.secondary) }
                }
                Text(candidate.alreadyOnList ? candidate.category + " · " + String(localized: "schon auf der Liste") : candidate.category)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    static func addTitle(count: Int) -> String {
        String(localized: "\(count) Artikel hinzufügen")
    }

    private func add() {
        isAdding = true
        let chosen = selected
        Task {
            let report = await RecipeImporter.apply(chosen, model: model, categories: environment.shoppingCategories)
            onAdded(Self.resultLine(report))
        }
    }

    /// The line on the shopping page afterwards: how many went on the list, or the first error.
    static func resultLine(_ report: ShoppingModel.AddReport) -> String {
        let count = report.added.count + report.reopened.count
        if let error = report.errorMessage, count == 0 { return error }
        return String(localized: "\(count) Artikel aus dem Rezept hinzugefügt.")
    }
}
