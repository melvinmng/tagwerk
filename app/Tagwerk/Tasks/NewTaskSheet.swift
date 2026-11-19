import GitHubKit
import SwiftUI
import TagwerkCore

/// Creates a local task or a reminder.
struct NewTaskSheet: View {
    let model: TaskListModel
    @Environment(\.dismiss) private var dismiss

    @State private var target: TaskSource

    init(model: TaskListModel) {
        self.model = model
        let available = Set(Self.availableTargets(in: model))
        _target = State(initialValue: model.filter.creationTarget(available: available))
        _priority = State(initialValue: model.filter.creationTarget(available: available) == .reminders ? .p4 : nil)
    }
    @State private var title = ""
    @State private var notes = ""
    @State private var hasDue = false
    @State private var hasTime = false
    @State private var dueDate = Date()
    @State private var priority: Priority?
    @State private var listID: String?
    @State private var reminderLists: [TaskContainer] = []
    @State private var catalog: GitHubCatalog?
    @State private var repository: String?
    @State private var projectIDs: Set<String> = []
    @State private var projectsEdited = false
    @State private var gitHubError: String?
    @State private var recurrence: Recurrence?

    private var gitHub: GitHubTaskProvider? { model.provider(for: .github) as? GitHubTaskProvider }

    private var targets: [TaskSource] { Self.availableTargets(in: model) }

    /// Sources a task can be created in right now (registered and loaded; Local always).
    static func availableTargets(in model: TaskListModel) -> [TaskSource] {
        [.local, .reminders, .github].filter { source in
            guard model.provider(for: source) != nil, let state = model.sourceStates[source] else {
                return source == .local
            }
            return state == .loaded
        }
    }

    private var canSave: Bool {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return target != .github || (repository != nil && !projectIDs.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                if targets.count > 1 {
                    Picker("Anlegen als", selection: $target) {
                        ForEach(targets, id: \.self) { source in
                            Text(label(for: source)).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    TextField("Titel", text: $title)
                    TextField("Notiz", text: $notes, axis: .vertical)
                }

                if target == .github {
                    Section {
                        Picker("Repository", selection: $repository) {
                            Text("Wählen …").tag(String?.none)
                            ForEach(catalog?.repositories ?? [], id: \.self) { Text($0).tag(Optional($0)) }
                        }
                        ProjectSelectionRow(projects: (catalog?.projects ?? []).map { (id: $0.id, title: $0.title) },
                                            selection: $projectIDs, edited: $projectsEdited)
                    } footer: {
                        if let gitHubError {
                            Text(gitHubError)
                        } else if repository != nil, projectIDs.isEmpty, !(catalog?.projects.isEmpty ?? true) {
                            Text("Mindestens ein Projekt wählen. Das Issue wird dir zugewiesen.")
                        } else {
                            Text("Das Issue wird dir zugewiesen.")
                        }
                    }
                    .task(id: target) { await loadCatalog() }
                    .onChange(of: repository) { _, repo in
                        // Preselect the projects linked to the chosen repository.
                        guard let repo, let catalog else { return }
                        projectIDs = ProjectSelection.preselect(current: projectIDs, linked: Set(catalog.projectIDs(linkedTo: repo)),
                                                                edited: projectsEdited)
                    }
                }

                if target == .reminders, !reminderLists.isEmpty {
                    Picker("Liste", selection: $listID) {
                        Text("Standard").tag(String?.none)
                        ForEach(reminderLists, id: \.id) { list in
                            Text(list.name).tag(Optional(list.id))
                        }
                    }
                }

                Section {
                    Toggle("Fällig", isOn: $hasDue.animation())
                    if hasDue {
                        if target != .github { Toggle("Uhrzeit", isOn: $hasTime) }
                        DatePicker("Datum", selection: $dueDate,
                                   displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
                            .environment(\.calendar, model.calendar)
                            .environment(\.timeZone, model.calendar.timeZone)
                    }
                    recurrenceRow
                    PriorityPicker(priority: $priority, choices: TaskEditorModel.priorityChoices(for: target))
                } footer: {
                    if target == .reminders, recurrence != nil {
                        Text("Wird als Regel in Erinnerungen gespeichert und ist dort ebenfalls sichtbar.")
                    } else if target == .local, recurrence != nil {
                        Text("Nur in Tagwerk. Beim Abhaken rückt die Aufgabe auf den nächsten Termin.")
                    }
                }
                .onChange(of: hasDue) { _, isOn in
                    // A repeating task needs a due date (plan §6, rule 3).
                    if !isOn { recurrence = nil }
                }
            }
            .navigationTitle("Neue Aufgabe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
            .task { reminderLists = await model.containers(for: .reminders) }
            .onChange(of: target) { _, newTarget in
                // Keep the picker selection valid for the target's priority levels.
                if !TaskEditorModel.priorityChoices(for: newTarget).contains(priority) {
                    priority = newTarget == .reminders ? .p4 : nil
                }
                // A rule chosen before switching to a source that cannot repeat is not taken over (mockup RK3).
                if RecurrenceAvailability.forNewTask(newTarget) != .available { recurrence = nil }
            }
        }
    }

    private func save() async {
        let draft = TaskDraft(
            title: title.trimmingCharacters(in: .whitespaces),
            notes: notes.isEmpty ? nil : notes,
            due: hasDue ? DueDate(date: dueDate, includeTime: hasTime && target != .github, calendar: model.calendar) : nil,
            priority: priority,
            containerID: target == .reminders ? listID : target == .github ? repository : nil,
            subContainerIDs: target == .github ? (catalog?.projects ?? []).map(\.id).filter(projectIDs.contains) : [],
            recurrence: RecurrenceAvailability.draftRecurrence(
                recurrence, target: target,
                due: hasDue ? DueDate(date: dueDate, includeTime: false, calendar: model.calendar) : nil)
        )
        await model.create(draft, in: target)
        dismiss()
    }
}

extension NewTaskSheet {
    /// "Wiederholen": the recurrence page for reminders and local tasks; GitHub issues show why not.
    @ViewBuilder private var recurrenceRow: some View {
        let dueDay = PlanDay(date: dueDate, calendar: model.calendar)
        switch RecurrenceAvailability.forNewTask(target) {
        case .available:
            NavigationLink {
                RecurrenceEditorView(
                    original: recurrence, start: dueDay, dueDay: hasDue ? dueDay : nil, calendar: model.calendar,
                    onChange: { newRecurrence in
                        recurrence = newRecurrence
                        if newRecurrence != nil, !hasDue { hasDue = true }
                    },
                    onMoveDue: { day in
                        let time = model.calendar.dateComponents([.hour, .minute], from: dueDate)
                        dueDate = model.calendar.date(byAdding: time, to: day.startDate(in: model.calendar)) ?? dueDate
                    }
                )
            } label: {
                LabeledContent {
                    Text(RecurrenceAvailability.draftRecurrence(recurrence, target: target, due: DueDate(year: dueDay.year, month: dueDay.month, day: dueDay.day))
                        .map { RecurrenceText.summary($0, calendar: model.calendar) } ?? String(localized: "Nie"))
                } label: {
                    Label("Wiederholen", systemImage: "repeat")
                }
            }
        case .unavailable(let reason):
            LabeledContent {
                Text(reason)
            } label: {
                Label("Wiederholen", systemImage: "repeat")
            }
            .foregroundStyle(.secondary)
            .accessibilityHint(reason)
        }
    }

    private func label(for source: TaskSource) -> String {
        switch source {
        case .local: String(localized: "Lokal")
        case .reminders: String(localized: "Erinnerung")
        case .github: String(localized: "GitHub-Issue")
        }
    }

    private func loadCatalog() async {
        guard let gitHub else { return }
        catalog = await gitHub.catalog(maxAge: AppEnvironment.catalogMaxAge)
        if catalog == nil { gitHubError = String(localized: "Repositories konnten nicht geladen werden.") }
    }
}

/// Priority choice among the levels a source supports.
struct PriorityPicker: View {
    @Binding var priority: Priority?
    var choices: [Priority?] = [nil] + Priority.allCases.map { $0 }

    var body: some View {
        Picker("Priorität", selection: $priority) {
            ForEach(choices, id: \.self) { value in
                Text(value?.label ?? "Keine").tag(value)
            }
        }
    }
}
