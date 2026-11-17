import SwiftUI
import TagwerkCore

/// The "Aufgaben" tab (mockup 2).
struct TaskListView: View {
    @Bindable var model: TaskListModel
    @State private var isCreating = false
    @State private var reschedulingItem: TaskItem?
    @State private var pickingDateFor: TaskItem?
    @State private var editing: TaskItem?
    @State private var editingContainers: [TaskContainer] = []
    @Environment(\.openURL) private var openURL

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
                    SourceProblemRow(source: source, state: model.sourceStates[source]) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
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
                    ContentUnavailableView("Keine Aufgaben", systemImage: "checkmark.circle")
                }
            }
            .safeAreaInset(edge: .bottom) { undoBar }
            .navigationTitle("Aufgaben")
            .toolbar {
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
                                   containers: editingContainers) { saved in
                        model.didSave(saved)
                    }
                }
            }
            .sheet(item: $pickingDateFor) { item in
                RescheduleDateSheet(item: item, calendar: model.calendar, now: model.now()) { day in
                    Task { await model.reschedule(item.id, option: .date(day)) }
                }
            }
            .confirmationDialog("Verschieben", isPresented: isRescheduling, presenting: reschedulingItem) { item in
                Button("Morgen") { Task { await model.reschedule(item.id, option: .tomorrow) } }
                Button("Nächste Woche (Mo)") { Task { await model.reschedule(item.id, option: .nextMonday) } }
                Button("Datum wählen …") { pickingDateFor = item }
            }
            .alert("Hinweis", isPresented: hasError) {
                Button("OK") { model.clearError() }
            } message: {
                Text(model.lastError ?? "")
            }
        }
    }

    private func row(_ item: TaskItem, section: TaskSection) -> some View {
        TaskRow(item: item, section: section, now: model.now(), calendar: model.calendar) {
            Task { await model.complete(item.id) }
        }
        .onTapGesture {
            Task {
                editingContainers = item.editableFields.contains(.container)
                    ? await model.containers(for: item.id.source) : []
                editing = item
            }
        }
        .swipeActions(edge: .leading) {
            Button { Task { await model.complete(item.id) } } label: {
                Label("Erledigt", systemImage: "checkmark")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button { reschedulingItem = item } label: {
                Label("Verschieben", systemImage: "calendar")
            }
            .tint(.orange)
        }
    }

    @ViewBuilder private var undoBar: some View {
        if let completed = model.lastCompleted {
            HStack {
                Text("Erledigt: \(completed.title)").lineLimit(1)
                Spacer()
                Button("Rückgängig") { Task { await model.undoComplete() } }
                    .fontWeight(.semibold)
            }
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .task(id: completed.id) {
                try? await Task.sleep(for: .seconds(4))
                if model.lastCompleted?.id == completed.id { model.dismissUndo() }
            }
        }
    }

    /// Sources in the current filter that could not be loaded.
    private var problemSources: [TaskSource] {
        TaskSource.allCases.filter { source in
            guard model.filter.sources.contains(source), let state = model.sourceStates[source] else { return false }
            return state != .loaded
        }
    }

    private var isRescheduling: Binding<Bool> {
        Binding(get: { reschedulingItem != nil }, set: { if !$0 { reschedulingItem = nil } })
    }

    private var hasError: Binding<Bool> {
        Binding(get: { model.lastError != nil }, set: { if !$0 { model.clearError() } })
    }
}

/// Hint for a source without access or with a load error.
private struct SourceProblemRow: View {
    let source: TaskSource
    let state: SourceState?
    let openSettings: () -> Void

    var body: some View {
        switch state {
        case .noAccess:
            VStack(alignment: .leading, spacing: 8) {
                Text("Kein Zugriff auf \(name)").font(.headline)
                Text("Erlaube den Vollzugriff in den Einstellungen, damit Tagwerk sie anzeigen kann.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Einstellungen öffnen", action: openSettings)
            }
        case .failed(let message):
            Label("\(name): \(message)", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .loaded, nil:
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
