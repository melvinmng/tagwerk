import SwiftUI
import TagwerkCore

/// The shopping page: open items in category sections, checking off, the folded "Erledigt" section and the
/// input bar. It has no navigation stack of its own, so it can be pushed or shown in a sheet.
struct ShoppingListView: View {
    @Environment(AppEnvironment.self) private var environment
    let model: ShoppingModel

    @State private var editing: ShoppingItem?
    @State private var showsCompleted = false
    @State private var confirmsRemoveCompleted = false
    @State private var confirmsClearList = false
    /// Completed items of the whole list (not only those of the last seven days), loaded when the page appears and when a
    /// confirmation opens.
    @State private var completedTotal = 0
    @State private var clearListTotal = 0
    @State private var showsCategories = false
    /// The line above the input field: feedback after adding or the text of a write error.
    @State private var notice: String?
    /// The item that gets the category typed into the "Neue Kategorie" dialog.
    @State private var newCategoryItem: ShoppingItem?
    @State private var newCategoryName = ""
    @State private var showsSortConsent = false
    @State private var showsRecipe = false
    /// The running request to ChatGPT; cancelling it discards the answer.
    @State private var sorting: Task<Void, Never>?
    /// Identifies the running request, so a cancelled one cannot clear the state of its successor.
    @State private var sortingID: UUID?
    @State private var proposal: SortProposal?
    /// The card, preview and undo of "Artikel übersetzen"; created with the page, because it needs the environment.
    @State private var translation: ShoppingTranslationModel?
    @State private var showsTranslateConsent = false
    @Environment(\.scenePhase) private var scenePhase

    /// The proposal of one request, identifiable for the result sheet.
    private struct SortProposal: Identifiable {
        let id = UUID()
        let draft: ShoppingSortDraft
    }

    init(model: ShoppingModel) {
        self.model = model
    }

    private var categories: [ShoppingCategoryInfo] { environment.shoppingCategories.categories() }

    private var siriTipDone: Binding<Bool> {
        let settings = environment.settings
        return Binding(get: { settings.siriTipShoppingDone }, set: { settings.siriTipShoppingDone = $0 })
    }

    var body: some View {
        translationLayer
            .alert("Neue Kategorie", isPresented: newCategoryBinding) {
                TextField("Name", text: $newCategoryName)
                Button("Anlegen", action: createCategory)
                Button("Abbrechen", role: .cancel) {}
            }
            .confirmationDialog(Self.removeCompletedQuestion(count: completedTotal), isPresented: $confirmsRemoveCompleted,
                                titleVisibility: .visible) {
                Button("Alle erledigten löschen", role: .destructive) {
                    Task {
                        await model.removeAllCompleted()
                        completedTotal = await model.allCompletedCount()
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text(Self.remindersNotice)
            }
            .confirmationDialog(Self.clearListQuestion(count: clearListTotal), isPresented: $confirmsClearList, titleVisibility: .visible) {
                Button("Liste leeren", role: .destructive) {
                    Task {
                        await model.clearList()
                        completedTotal = await model.allCompletedCount()
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text(Self.remindersNotice)
            }
            .task {
                if translation == nil {
                    translation = ShoppingTranslationModel(shopping: model, settings: environment.settings,
                                                           translator: environment.shoppingTranslator)
                }
                environment.shoppingCategories.seedIfNeeded()
                await model.reload()
                translation?.refreshOffer()
                completedTotal = await model.allCompletedCount()
            }
    }

    /// The page with the sheets and hooks of "Artikel übersetzen"; split from `body` to keep the modifier chains type-checkable.
    private var translationLayer: some View {
        pageWithSheets
            .sheet(isPresented: $showsTranslateConsent) {
                ShoppingSortConsentSheet(purpose: .translate) {
                    environment.settings.hasShoppingSortConsent = true
                    showsTranslateConsent = false
                    translate()
                } onDecline: {
                    showsTranslateConsent = false
                }
            }
            .sheet(item: Binding(get: { translation?.preview }, set: { if $0 == nil { translation?.discard() } })) { preview in
                ShoppingTranslationResultSheet(preview: preview, language: environment.settings.contentLanguages.shoppingLanguage()) { selected in
                    Task {
                        if let line = await translation?.apply(selected) { notice = line }
                    }
                } onDiscard: {
                    translation?.discard()
                }
            }
            .overlay {
                if sorting != nil {
                    busyOverlay(title: "ChatGPT sortiert …", cancel: cancelSorting)
                } else if translation?.isTranslating == true {
                    busyOverlay(title: "ChatGPT übersetzt …") { translation?.cancel() }
                }
            }
            .onDisappear {
                cancelSorting()
                translation?.cancel()
            }
            .onChange(of: model.openItems.count) { translation?.refreshOffer() }
            .onChange(of: model.state) { translation?.refreshOffer() }
            .onChange(of: environment.settings.contentLanguages.shoppingLanguage()) { translation?.refreshOffer() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { translation?.refreshOffer() } }
            .onChange(of: translation?.notice) { _, line in
                guard let line else { return }
                notice = line
                translation?.notice = nil
            }
    }

    private var pageWithSheets: some View {
        content
            .navigationTitle("Einkaufsliste")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if model.state == .ready {
                    ToolbarItem(placement: .topBarTrailing) { menu }
                }
                AssistantToolbarItems { .tasks }
            }
            .navigationDestination(isPresented: $showsCategories) {
                ShoppingCategoriesView(store: environment.shoppingCategories, model: model)
            }
            .sheet(item: $editing) { item in
                ShoppingItemSheet(model: model, item: item) { notice = $0 }
            }
            .sheet(isPresented: $showsSortConsent) {
                ShoppingSortConsentSheet {
                    environment.settings.hasShoppingSortConsent = true
                    showsSortConsent = false
                    sort()
                } onDecline: {
                    showsSortConsent = false
                }
            }
            .sheet(isPresented: $showsRecipe) {
                RecipeSheet(model: model) { notice = $0 }
            }
            .sheet(item: $proposal) { proposal in
                ShoppingSortResultSheet(draft: proposal.draft) { selected in
                    ShoppingSorter.apply(selected, categories: environment.shoppingCategories, model: model)
                    self.proposal = nil
                } onDiscard: {
                    self.proposal = nil
                }
            }
    }

    // MARK: States

    @ViewBuilder private var content: some View {
        switch model.state {
        case .ready:
            list
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        translationCard
                        undoCapsule
                        ShoppingInputBar(model: model, notice: $notice)
                    }
                }
        case .accessDenied:
            ContentUnavailableView {
                Label("Kein Zugriff auf Erinnerungen", systemImage: "lock")
            } description: {
                Text("Erlaube Tagwerk in den iOS-Einstellungen den vollen Zugriff auf Erinnerungen.")
            } actions: {
                Button("Einstellungen öffnen") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        case .listMissing:
            ContentUnavailableView {
                Label("Liste verschwunden", systemImage: "questionmark.folder")
            } description: {
                Text("Die bisherige Liste gibt es nicht mehr.")
            } actions: {
                Button("Andere Liste wählen") { environment.tasksPath.append(.shoppingSettings) }
            }
        case .noList:
            ContentUnavailableView {
                Label("Keine Einkaufsliste", systemImage: "cart")
            } description: {
                Text("Wähle eine Erinnerungsliste als Einkaufsliste.")
            } actions: {
                Button("Liste wählen") { environment.tasksPath.append(.shoppingSettings) }
            }
        }
    }

    private var list: some View {
        List {
            Section {
                // SI3: shown once; renders nothing, and takes no height, when the shortcuts are not registered.
                if SiriTipPolicy.isVisible(done: environment.settings.siriTipShoppingDone) {
                    SiriTip(intent: AddShoppingArticleIntent(), isDone: siriTipDone)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .environment(\.defaultMinListRowHeight, 0)
                }
                Text("\(model.openItems.count) offen · Liste „\(model.listTitle ?? "")“ in Erinnerungen")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
            }
            if model.openItems.isEmpty && model.completedItems.isEmpty {
                Section {
                    Text("Die Liste ist leer. Füge unten Artikel hinzu.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                }
            }
            ForEach(model.sections) { section in
                Section {
                    ForEach(section.items) { row($0) }
                } header: {
                    sectionHeader(section)
                }
            }
            if !model.completedItems.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showsCompleted) {
                        ForEach(model.completedItems) { row($0) }
                    } label: {
                        Text("Erledigt · \(model.completedItems.count)").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .listStyle(.insetGrouped)
        .refreshable { await model.reload() }
    }

    private func sectionHeader(_ section: ShoppingSection) -> some View {
        HStack {
            Text(title(of: section.categoryID))
            Spacer()
            if section.categoryID == nil, environment.ai.isSignedIn {
                Button("✦ Sortieren") { startSorting() }
                    .font(.footnote)
                    .textCase(nil)
            }
        }
    }

    private func title(of categoryID: UUID?) -> String {
        guard let categoryID else { return String(localized: "Sonstiges") }
        return categories.first { $0.id == categoryID }?.name ?? String(localized: "Sonstiges")
    }

    // MARK: Rows

    private func row(_ item: ShoppingItem) -> some View {
        HStack(spacing: 12) {
            Button {
                toggle(item)
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isCompleted ? Color.secondary : Color.accentColor)
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                if let quantity = item.quantity {
                    Text(quantity).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = item }
        .contextMenu { rowMenu(item) }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { delete(item) } label: { Label("Löschen", systemImage: "trash") }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ShoppingInput.accessibilityLabel(item))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: item.isCompleted ? Text("Wieder öffnen") : Text("Abhaken")) { toggle(item) }
        .accessibilityAction(named: Text("Bearbeiten")) { editing = item }
        .accessibilityAction(named: Text("Löschen")) { delete(item) }
    }

    @ViewBuilder private func rowMenu(_ item: ShoppingItem) -> some View {
        let current = model.categoryID(of: item)
        Menu("Kategorie") {
            ForEach(categories) { category in
                Button {
                    model.setCategory(category.id, forItemID: item.id)
                } label: {
                    if category.id == current { Label(category.name, systemImage: "checkmark") } else { Text(category.name) }
                }
            }
            Button {
                model.setCategory(nil, forItemID: item.id)
            } label: {
                if current == nil { Label("Sonstiges", systemImage: "checkmark") } else { Text("Sonstiges") }
            }
            Divider()
            Button("Neue Kategorie …") {
                newCategoryName = ""
                newCategoryItem = item
            }
        }
        Button { editing = item } label: { Label("Bearbeiten", systemImage: "pencil") }
        Button(role: .destructive) { delete(item) } label: { Label("Löschen", systemImage: "trash") }
    }

    // MARK: Menu

    private var menu: some View {
        Menu {
            Button(action: startSorting) {
                Label("Mit ChatGPT sortieren", systemImage: "sparkles")
                if !environment.ai.isSignedIn { Text("Anmeldung unter Einstellungen › KI") }
            }
            .disabled(!environment.ai.isSignedIn || sorting != nil || translation?.isTranslating == true)
            Button(action: startTranslating) {
                Label("Artikel übersetzen …", systemImage: "globe")
                Text(environment.ai.isSignedIn ? Self.translateSubtitle(environment.settings.contentLanguages.shoppingLanguage())
                                               : String(localized: "Anmeldung unter Einstellungen › KI"))
            }
            .disabled(!environment.ai.isSignedIn || model.openItems.isEmpty || sorting != nil || translation?.isTranslating == true)
            Button { showsRecipe = true } label: {
                Label("Rezept hinzufügen …", systemImage: "fork.knife")
                if !environment.ai.isSignedIn { Text("Anmeldung unter Einstellungen › KI") }
            }
            .disabled(!environment.ai.isSignedIn)
            Button { showsCategories = true } label: { Label("Kategorien verwalten", systemImage: "list.bullet.indent") }
            Button(role: .destructive) {
                askRemoveCompleted()
            } label: {
                Label("Alle erledigten löschen", systemImage: "trash")
            }
            .disabled(model.completedItems.isEmpty && completedTotal == 0)
            Button(role: .destructive) {
                askClearList()
            } label: {
                Label("Liste leeren", systemImage: "trash.slash")
            }
            .disabled(model.openItems.isEmpty && model.completedItems.isEmpty && completedTotal == 0)
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Mehr")
    }

    // MARK: Clearing

    /// "12 erledigte Artikel löschen?"
    static func removeCompletedQuestion(count: Int) -> String {
        String(localized: "\(count) erledigte Artikel löschen?")
    }

    /// "Gesamte Liste leeren? 20 Artikel werden gelöscht."
    static func clearListQuestion(count: Int) -> String {
        String(localized: "Gesamte Liste leeren? \(count) Artikel werden gelöscht.")
    }

    static var remindersNotice: String { String(localized: "Sie verschwinden auch aus Apple Erinnerungen.") }

    /// Reads the number first, so the question names what is really deleted, including items older than seven days.
    private func askRemoveCompleted() {
        Task {
            completedTotal = await model.allCompletedCount()
            if completedTotal > 0 { confirmsRemoveCompleted = true } else { notice = String(localized: "Es gibt keine erledigten Artikel.") }
        }
    }

    private func askClearList() {
        Task {
            completedTotal = await model.allCompletedCount()
            clearListTotal = model.openItems.count + completedTotal
            if clearListTotal > 0 { confirmsClearList = true } else { notice = String(localized: "Die Liste ist schon leer.") }
        }
    }

    // MARK: Actions

    private func toggle(_ item: ShoppingItem) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        perform {
            if item.isCompleted { try await model.reopen(id: item.id) } else { try await model.checkOff(id: item.id) }
        }
    }

    private func delete(_ item: ShoppingItem) {
        perform { try await model.delete(id: item.id) }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        Task {
            do {
                try await operation()
            } catch {
                notice = TaskListModel.message(for: error)
            }
        }
    }

    private var newCategoryBinding: Binding<Bool> {
        Binding(get: { newCategoryItem != nil }, set: { if !$0 { newCategoryItem = nil } })
    }

    /// Creates the typed category at the end and puts the item into it at once.
    private func createCategory() {
        guard let item = newCategoryItem else { return }
        do {
            let category = try environment.shoppingCategories.add(name: newCategoryName)
            model.setCategory(category.id, forItemID: item.id)
        } catch let error as ShoppingCategoryRules.NameError {
            notice = ShoppingCategoriesView.message(for: error)
        } catch {
            notice = TaskListModel.message(for: error)
        }
    }

    // MARK: Sorting with ChatGPT

    private func busyOverlay(title: LocalizedStringKey, cancel: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            ProgressView(title)
            Button("Abbrechen", action: cancel)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    /// The first tap asks for consent; nothing is sent before the user agreed.
    private func startSorting() {
        guard environment.ai.isSignedIn, sorting == nil, translation?.isTranslating != true else { return }
        if environment.settings.hasShoppingSortConsent { sort() } else { showsSortConsent = true }
    }

    private func sort() {
        let categories = categories
        let request = ShoppingSorter.request(sections: model.sections, assignments: environment.shoppingCategories.assignments(),
                                             categories: categories)
        guard !request.itemNames.isEmpty else {
            notice = String(localized: "Es gibt keine Artikel zum Sortieren.")
            return
        }
        let current = ShoppingSorter.currentCategories(sections: model.sections, categories: categories)
        let id = UUID()
        sortingID = id
        sorting = Task {
            defer { if sortingID == id { sorting = nil } }
            do {
                let result = try await environment.shoppingSorter.sort(request, current: current)
                // A cancelled request must not show a late answer.
                guard !Task.isCancelled else { return }
                // The follow-up sends the same names again and checks every answer against them.
                let sorter = environment.shoppingSorter
                let draft = ShoppingSortDraft(proposal: result, request: request, current: current) { request, current, proposal, pinned, focus, comment in
                    try await sorter.revise(request, current: current, proposal: proposal, pinned: pinned, focus: focus, comment: comment)
                }
                proposal = SortProposal(draft: draft)
            } catch let failure as ShoppingSorter.Failure {
                if !Task.isCancelled { notice = failure.message }
            } catch {
                // Cancelled by the user: nothing to report.
            }
        }
    }

    // MARK: Translating with ChatGPT

    /// "ins Englische, mit ChatGPT"
    static func translateSubtitle(_ language: VoiceLanguage) -> String {
        language == .english ? String(localized: "ins Englische, mit ChatGPT") : String(localized: "ins Deutsche, mit ChatGPT")
    }

    @ViewBuilder private var translationCard: some View {
        if let translation, let offer = translation.offer, translation.preview == nil {
            ShoppingTranslationCard(offer: offer, isSignedIn: environment.ai.isSignedIn, onTranslate: startTranslating,
                                    onKeep: { translation.keepAsIs() })
        }
    }

    @ViewBuilder private var undoCapsule: some View {
        if let translation, !translation.undo.isEmpty {
            let caption: LocalizedStringResource = environment.settings.contentLanguages.shoppingLanguage() == .english ? "Englisch" : "Deutsch"
            UndoCapsule(title: String(localized: "\(translation.undo.count) Artikel übersetzt"), caption: caption, duration: 8,
                        actionHint: "Stellt die alten Namen wieder her",
                        onUndo: { Task { await translation.undoLast() } },
                        onExpire: { translation.capsuleExpired() })
                .id(translation.undo.map(\.id))
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// The first tap asks for the consent; nothing is sent before the user agreed.
    private func startTranslating() {
        guard environment.ai.isSignedIn, sorting == nil, translation?.isTranslating != true else { return }
        if environment.settings.hasShoppingSortConsent { translate() } else { showsTranslateConsent = true }
    }

    private func translate() {
        Task { await translation?.translate() }
    }

    private func cancelSorting() {
        sorting?.cancel()
        sorting = nil
        sortingID = nil
    }
}
