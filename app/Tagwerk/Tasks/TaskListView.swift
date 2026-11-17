import GitHubKit
import SwiftUI
import TagwerkCore

/// The "Aufgaben" tab (mockup 2).
struct TaskListView: View {
    @Bindable var model: TaskListModel
    /// Shows a planned day in the "Planen" tab (editor section "Geplant").
    var onShowDay: ((PlanDay) -> Void)?
    /// Opens the effort sheet of a recurring reminder.
    var onEditRecurring: ((RecurringItem, PlanDay) -> Void)?
    @State private var isCreating = false
    @State private var reschedulingItem: TaskItem?
    @State private var pickingDateFor: TaskItem?
    @State private var editing: TaskItem?
    @State private var editingContainers: [TaskContainer] = []
    @State private var gitHubLogin: GitHubLoginModel?
    @State private var deleting: TaskItem?
    @State private var showsOfflineInfo = false
    @State private var planningDateFor: TaskItem?
    @Environment(\.openURL) private var openURL
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        NavigationStack {
            List {
                if model.availableFilters.count > 2 {
                    Picker("Filter", selection: $model.filter) {
                        ForEach(model.availableFilters, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                ForEach(problemSources, id: \.self) { source in
                    SourceProblemRow(
                        source: source,
                        state: model.sourceStates[source],
                        canRequest: environment.accessState(for: source) == .notDetermined,
                        requestAccess: { Task { await environment.requestAccess(for: source) } },
                        signIn: { gitHubLogin = environment.makeGitHubLoginModel() },
                        openSettings: {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    )
                }

                ForEach(model.sections, id: \.0) { section, items in
                    Section(section.title) {
                        ForEach(items) { item in
                            row(item, section: section)
                        }
                    }
                }
            }
            .overlay {
                if model.sections.isEmpty && problemSources.isEmpty {
                    if !model.loadingSources.isDisjoint(with: model.filter.sources) {
                        ProgressView("Aufgaben werden geladen …")
                    } else if model.filter == .github {
                        ContentUnavailableView("Keine zugewiesenen Issues in offenen Projects", systemImage: "checkmark.circle")
                    } else {
                        ContentUnavailableView("Keine Aufgaben", systemImage: "checkmark.circle")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { undoBar }
            .animation(.spring(duration: 0.35), value: model.lastCompleted?.id)
            .onChange(of: gitHubOfflineSince == nil) { _, online in if online { showsOfflineInfo = false } }
            .navigationTitle("Aufgaben")
            .toolbar {
                if gitHubOfflineSince != nil {
                    ToolbarItem(placement: .topBarTrailing) { offlineIndicator }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { isCreating = true } label: { Label("Neue Aufgabe", systemImage: "plus") }
                }
            }
            .refreshable { await model.reload() }
            .task { await model.reload() }
            .sheet(isPresented: $isCreating) { NewTaskSheet(model: model) }
            .sheet(item: $editing) { item in
                if let provider = model.provider(for: item.id.source) {
                    TaskEditorView(item: item, provider: provider, calendar: model.calendar,
                                   containers: editingContainers,
                                   addComment: commentAction(for: provider),
                                   isReadOnly: model.sourceStates[item.id.source]?.isOffline == true,
                                   onDelete: { version in Task { await model.delete(item.id, version: version) } },
                                   planning: environment.planning,
                                   onShowDay: onShowDay) { saved in
                        model.didSave(saved)
                    }
                }
            }
            .sheet(isPresented: isSigningIn) {
                if let gitHubLogin {
                    NavigationStack {
                        Form { GitHubLoginView(model: gitHubLogin) { self.gitHubLogin = nil } }
                            .navigationTitle("GitHub")
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Schließen") { gitHubLogin.cancel(); self.gitHubLogin = nil }
                                }
                            }
                    }
                }
            }
            .sheet(item: $planningDateFor) { item in
                RescheduleDateSheet(item: item, calendar: model.calendar, now: model.now()) { day in
                    Task { await environment.planning.assign(item.id, to: PlanDay(day)) }
                }
            }
            .sheet(item: $pickingDateFor) { item in
                RescheduleDateSheet(item: item, calendar: model.calendar, now: model.now()) { day in
                    Task { await model.reschedule(item.id, option: .date(day)) }
                }
            }


            .alert("Hinweis", isPresented: hasError) {
                Button("OK") { model.clearError() }
            } message: {
                Text(model.lastError ?? "")
            }
        }
    }

    private func row(_ item: TaskItem, section: TaskSection) -> some View {
        TaskRow(item: item, section: section, now: model.now(), calendar: model.calendar, isReadOnly: !isWritable(item)) {
            if isWritable(item) { Task { await model.complete(item.id) } } else { showsOfflineInfo = true }
        }
        .onTapGesture {
            Task {
                editingContainers = item.editableFields.contains(.container)
                    ? await model.containers(for: item.id.source) : []
                editing = item
            }
        }
        .contextMenu {
            TaskContextMenu(item: item, actions: menuActions(for: item))
        }
        // Dialogs hang on the row, so iOS shows them next to the affected task (above or below it).
        .confirmationDialog("Verschieben", isPresented: dialogBinding($reschedulingItem, for: item)) {
            Button("Heute") { Task { await model.reschedule(item.id, option: .today) } }
            Button("Morgen") { Task { await model.reschedule(item.id, option: .tomorrow) } }
            Button("Wochenende (Sa)") { Task { await model.reschedule(item.id, option: .weekend) } }
            Button("Nächste Woche (Mo)") { Task { await model.reschedule(item.id, option: .nextMonday) } }
            Button("Datum wählen …") { pickingDateFor = item }
        }
        .confirmationDialog(Self.deleteQuestion(for: item), isPresented: dialogBinding($deleting, for: item),
                            titleVisibility: .visible) {
            Button(Self.deleteTitle(for: item), role: .destructive) { Task { await model.delete(item.id) } }
        }
        .swipeActions(edge: .leading) {
            if isWritable(item) {
                Button { Task { await model.complete(item.id) } } label: {
                    Label("Erledigt", systemImage: "checkmark")
                }
                .tint(.green)
            }
        }
        .swipeActions(edge: .trailing) {
            if isWritable(item) {
                Button { reschedulingItem = item } label: {
                    Label("Verschieben", systemImage: "calendar")
                }
                .tint(.orange)
                Button { deleting = item } label: {
                    Label(Self.deleteTitle(for: item), systemImage: "trash")
                }
                .tint(.red)
            }
        }
    }

    @ViewBuilder private var undoBar: some View {
        if let completed = model.lastCompleted {
            UndoCapsule(title: completed.title, duration: 5,
                        onUndo: { Task { await model.undoComplete() } },
                        onExpire: { if model.lastCompleted?.id == completed.id { model.dismissUndo() } })
                .id(completed.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// Time of the cached GitHub data while GitHub is offline.
    private var gitHubOfflineSince: Date? {
        if case .offline(let since, _) = model.sourceStates[.github] { return since }
        return nil
    }

    /// Reason when the cache is shown because of an error rather than a missing connection.
    private var gitHubOfflineReason: String? {
        if case .offline(_, let reason) = model.sourceStates[.github] { return reason }
        return nil
    }

    /// Mockup 4A: a quiet toolbar symbol; tapping it (or a read-only row) shows the details.
    @ViewBuilder private var offlineIndicator: some View {
        if let since = gitHubOfflineSince {
            Button { showsOfflineInfo = true } label: {
                Image(systemName: "icloud.slash")
                    .symbolEffect(.bounce, options: .nonRepeating, isActive: true)
            }
            .tint(.secondary)
            .accessibilityLabel("GitHub offline")
            .accessibilityValue("Stand \(since.formatted(.dateTime.day().month(.wide).hour().minute()))")
            .accessibilityHint("Zeigt Details")
            .popover(isPresented: $showsOfflineInfo) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(gitHubOfflineReason == nil ? "GitHub offline" : "GitHub nicht erreichbar",
                          systemImage: "icloud.slash").font(.headline)
                    Text("Stand \(since.formatted(.dateTime.day().month().hour().minute()))")
                    if let reason = gitHubOfflineReason {
                        Text(reason).font(.subheadline)
                    }
                    Text("GitHub-Aufgaben sind nur lesbar, bis GitHub wieder antwortet.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Erneut versuchen") {
                        showsOfflineInfo = false
                        Task { await model.reload(only: [.github]) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                // Popovers size to their first line; let every text wrap instead of truncating.
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .frame(width: 300, alignment: .leading)
                .presentationCompactAdaptation(.popover)
            }
        }
    }

    private func menuActions(for item: TaskItem) -> TaskMenuActions {
        TaskMenuActions(
            plan: { option in Task { await environment.planning.plan(item.id, option: option) } },
            planOnDate: { planningDateFor = item },
            moveDue: { option in Task { await model.reschedule(item.id, option: option) } },
            moveDueOnDate: { pickingDateFor = item },
            complete: { Task { await model.complete(item.id) } },
            delete: { deleting = item },
            editEffort: onEditRecurring.flatMap { open in
                let today = environment.planning.today
                return environment.planning.recurringItem(for: item, on: today).map { recurring in { open(recurring, today) } }
            },
            isWritable: isWritable(item)
        )
    }

    /// Offline sources (GitHub cache) are read-only.
    private func isWritable(_ item: TaskItem) -> Bool {
        model.sourceStates[item.id.source]?.isOffline != true
    }

    private func commentAction(for provider: any TaskProvider) -> TaskEditorModel.CommentAction? {
        guard let gitHub = provider as? GitHubTaskProvider else { return nil }
        return { id, text, version in try await gitHub.addComment(to: id, body: text, expectedVersion: version) }
    }

    /// Sources in the current filter that could not be loaded.
    private var problemSources: [TaskSource] {
        TaskSource.allCases.filter { source in
            guard model.filter.sources.contains(source), let state = model.sourceStates[source] else { return false }
            // Offline is a quiet state shown in the toolbar, not a row (mockup 4A).
            return state != .loaded && !state.isOffline
        }
    }

    /// True while `selection` holds `item`; closing the dialog clears the selection.
    private func dialogBinding(_ selection: Binding<TaskItem?>, for item: TaskItem) -> Binding<Bool> {
        Binding(get: { selection.wrappedValue?.id == item.id },
                set: { if !$0, selection.wrappedValue?.id == item.id { selection.wrappedValue = nil } })
    }

    private var isSigningIn: Binding<Bool> {
        Binding(get: { gitHubLogin != nil }, set: { if !$0 { gitHubLogin = nil } })
    }

    static func deleteTitle(for item: TaskItem) -> String {
        item.id.source == .github ? "Als nicht geplant schließen" : "Löschen"
    }

    static func deleteQuestion(for item: TaskItem) -> String {
        item.id.source == .github
            ? "„\(item.title)“ auf GitHub als nicht geplant schließen?"
            : "„\(item.title)“ endgültig löschen?"
    }

    private var hasError: Binding<Bool> {
        Binding(get: { model.lastError != nil }, set: { if !$0 { model.clearError() } })
    }
}

/// Hint for a source without access or with a load error.
private struct SourceProblemRow: View {
    let source: TaskSource
    let state: SourceState?
    let canRequest: Bool
    let requestAccess: () -> Void
    let signIn: () -> Void
    let openSettings: () -> Void

    var body: some View {
        switch state {
        case .noAccess:
            VStack(alignment: .leading, spacing: 8) {
                Text("Kein Zugriff auf \(name)").font(.headline)
                if canRequest {
                    Text("Erlaube den Zugriff, damit Tagwerk sie anzeigen kann.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Zugriff erlauben", action: requestAccess)
                } else {
                    Text("Erlaube den Vollzugriff in den Einstellungen, damit Tagwerk sie anzeigen kann.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Einstellungen öffnen", action: openSettings)
                }
            }
        case .failed(let message):
            Label("\(name): \(message)", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .signedOut:
            VStack(alignment: .leading, spacing: 8) {
                Text("\(name): Anmeldung abgelaufen").font(.headline)
                Text("Melde dich neu an, damit Tagwerk deine Issues wieder anzeigt.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Mit GitHub anmelden", action: signIn)
            }
        case .offline, .loaded, nil:
            EmptyView()
        }
    }

    private var name: String {
        switch source {
        case .reminders: "Erinnerungen"
        case .github: "GitHub"
        case .local: "lokale Aufgaben"
        }
    }
}
