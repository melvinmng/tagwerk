import SwiftUI
import TagwerkCore

/// Editor sheet with source-specific fields and the conflict banner.
struct TaskEditorView: View {
    @State private var model: TaskEditorModel
    let calendar: Calendar
    let containers: [TaskContainer]
    let onSaved: (TaskItem) -> Void
    @Environment(\.dismiss) private var dismiss

    let isReadOnly: Bool
    let onDelete: ((String) -> Void)?
    @State private var labelText = ""
    @State private var confirmsDelete = false

    init(item: TaskItem, provider: any TaskProvider, calendar: Calendar, containers: [TaskContainer],
         addComment: TaskEditorModel.CommentAction? = nil, isReadOnly: Bool = false,
         onDelete: ((String) -> Void)? = nil, onSaved: @escaping (TaskItem) -> Void) {
        self.onDelete = onDelete
        _model = State(initialValue: TaskEditorModel(item: item, provider: provider, addComment: addComment))
        self.calendar = calendar
        self.containers = containers
        self.isReadOnly = isReadOnly
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                if model.conflict != nil {
                    ConflictBanner(
                        sourceName: sourceName,
                        changes: model.conflictChanges,
                        onReload: {
                            Task {
                                await model.reloadFromSource()
                                AccessibilityNotification.Announcement("Stand von \(sourceName) geladen").post()
                            }
                        },
                        onSaveAnyway: { Task { await finish(model.saveAnyway()) } }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if isReadOnly {
                    Label("Offline: Änderungen sind gerade nicht möglich.", systemImage: "wifi.slash")
                        .foregroundStyle(.secondary)
                }
                if let message = model.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }

                Section {
                    TextField("Titel", text: $model.draft.title, axis: .vertical)
                    if model.original.id.source == .github {
                        LabeledContent("Repo", value: model.original.container.name)
                    }
                    if model.isVisible(.labels) {
                        TextField("Labels (kommagetrennt)", text: $labelText)
                            .textInputAutocapitalization(.never)
                            .onChange(of: labelText) { _, text in
                                model.draft.labels = text.split(separator: ",")
                                    .map { $0.trimmingCharacters(in: .whitespaces) }
                                    .filter { !$0.isEmpty }
                            }
                    }
                    if model.isVisible(.container), !containers.isEmpty {
                        Picker("Liste", selection: containerID) {
                            ForEach(containers, id: \.id) { Text($0.name).tag($0.id) }
                        }
                    }
                }

                Section {
                    if model.original.subContainers.count > 1 {
                        Picker("Ändern in", selection: projectTarget) {
                            Text("Alle Projects").tag(String?.none)
                            ForEach(model.original.subContainers, id: \.id) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                    if model.isVisible(.due) { dueFields }
                    if model.isVisible(.priority) { PriorityPicker(priority: $model.draft.priority, choices: model.priorityChoices) }
                    if model.isVisible(.estimate) {
                        EstimateField(minutes: $model.draft.estimateMinutes)
                    }
                }

                if model.isVisible(.notes) {
                    Section(model.original.id.source == .github ? "Beschreibung (Markdown)" : "Notiz") {
                        TextField("Notiz", text: notes, axis: .vertical).lineLimit(3...10)
                    }
                }

                Section {
                    Toggle("Erledigt", isOn: $model.draft.isCompleted)
                }

                if model.canComment {
                    Section("Kommentar") {
                        TextField("Kommentar schreiben", text: $model.comment, axis: .vertical).lineLimit(2...6)
                        Button("Senden") { Task { await model.postComment() } }
                            .disabled(isReadOnly || model.isPostingComment || model.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if let url = model.original.url {
                    Section {
                        Link("Auf GitHub öffnen", destination: url)
                    }
                }

                if onDelete != nil, !isReadOnly {
                    Section {
                        Button(TaskListView.deleteTitle(for: model.original), role: .destructive) { confirmsDelete = true }
                    }
                }
            }
            .animation(.default, value: model.conflict == nil)
            .navigationTitle(title)
            .confirmationDialog(TaskListView.deleteQuestion(for: model.original), isPresented: $confirmsDelete,
                                titleVisibility: .visible) {
                Button(TaskListView.deleteTitle(for: model.original), role: .destructive) {
                    onDelete?(model.original.version)
                    dismiss()
                }
            }
            .onAppear { labelText = (model.draft.labels ?? []).joined(separator: ", ") }
            .onChange(of: model.original.version) { _, _ in
                labelText = (model.draft.labels ?? []).joined(separator: ", ")
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        if let refreshed = model.refreshed { onSaved(refreshed) }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { Task { await finish(model.save()) } }
                        .disabled(isReadOnly || model.isSaving || model.draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    @ViewBuilder private var dueFields: some View {
        Toggle("Fällig", isOn: hasDue.animation())
        if let due = model.draft.due {
            if model.supportsDueTime { Toggle("Uhrzeit", isOn: hasTime) }
            DatePicker("Datum", selection: dueDate, displayedComponents: due.hasTime ? [.date, .hourAndMinute] : [.date])
                .environment(\.calendar, calendar)
                .environment(\.timeZone, calendar.timeZone)
        }
    }

    private var sourceName: String {
        switch model.original.id.source {
        case .github: "GitHub"
        case .reminders: "Erinnerungen"
        case .local: "diesem Gerät"
        }
    }

    private var title: String {
        if model.original.id.source == .github, let number = model.original.url?.lastPathComponent, Int(number) != nil {
            return "Issue #\(number)"
        }
        return model.original.title
    }

    private func finish(_ success: Bool) {
        guard success else { return }
        if let saved = model.saved { onSaved(saved) }
        dismiss()
    }

    // MARK: Bindings for optional fields

    private var hasDue: Binding<Bool> {
        Binding(
            get: { model.draft.due != nil },
            set: { model.draft.due = $0 ? DueDate(date: .now, includeTime: false, calendar: calendar) : nil }
        )
    }

    private var hasTime: Binding<Bool> {
        Binding(
            get: { model.draft.due?.hasTime ?? false },
            set: { on in
                guard var due = model.draft.due else { return }
                due.hour = on ? 9 : nil
                due.minute = on ? 0 : nil
                model.draft.due = due
            }
        )
    }

    private var dueDate: Binding<Date> {
        Binding(
            get: { model.draft.due?.startDate(in: calendar) ?? .now },
            set: { date in
                let includeTime = model.draft.due?.hasTime ?? false
                model.draft.due = DueDate(date: date, includeTime: includeTime, calendar: calendar)
            }
        )
    }

    private var notes: Binding<String> {
        Binding(
            get: { model.draft.notes ?? "" },
            set: { model.draft.notes = $0.isEmpty ? nil : $0 }
        )
    }

    /// `nil` = all projects, otherwise exactly one project.
    private var projectTarget: Binding<String?> {
        Binding(
            get: {
                let all = Set(model.original.subContainers.map(\.id))
                return model.targetProjects == all ? nil : model.targetProjects.first
            },
            set: { id in
                model.targetProjects = id.map { [$0] } ?? Set(model.original.subContainers.map(\.id))
            }
        )
    }

    private var containerID: Binding<String> {
        Binding(
            get: { model.draft.container.id },
            set: { id in
                if let container = containers.first(where: { $0.id == id }) { model.draft.container = container }
            }
        )
    }
}
