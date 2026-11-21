import GitHubKit
import SwiftUI
import TagwerkCore

/// Creates a local task or a reminder.
struct NewTaskSheet: View {
    let model: TaskListModel
    /// Called after the task was created (the thoughts note counts it as derived).
    let onCreated: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var environment

    @State private var target: TaskSource

    /// Offered by shared items: "Verwerfen" removes the item instead of only closing the sheet.
    private let onDiscard: (() -> Void)?

    /// `prefilledTitle` only fills the title; source and the other fields stay as in any new task. Shared content and mails
    /// also fill the notes (the link goes on its own last line) and the due date; a date without a time sets no time.
    init(model: TaskListModel, prefilledTitle: String? = nil, onCreated: (() -> Void)? = nil,
         prefilledNotes: String? = nil, prefilledURL: URL? = nil, prefilledDue: DueDate? = nil, onDiscard: (() -> Void)? = nil) {
        self.model = model
        self.onCreated = onCreated
        self.onDiscard = onDiscard
        _title = State(initialValue: prefilledTitle ?? "")
        _notes = State(initialValue: NewTaskPrefill.notes(text: prefilledNotes, url: prefilledURL) ?? "")
        let dueFields = NewTaskPrefill.dueFields(prefilledDue, calendar: model.calendar, fallback: Date())
        _hasDue = State(initialValue: dueFields.hasDue)
        _dueDate = State(initialValue: dueFields.date)
        _hasTime = State(initialValue: dueFields.hasTime)
        let available = Set(Self.availableTargets(in: model))
        _target = State(initialValue: model.filter.creationTarget(available: available))
        _priority = State(initialValue: model.filter.creationTarget(available: available) == .reminders ? .p4 : nil)
        // The default is always the signed-in user, never a remembered choice.
        let login = (model.provider(for: .github) as? GitHubTaskProvider)?.login
        _assignees = State(initialValue: Set([login].compactMap { $0 }))
    }
    @State private var title: String
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
    @State private var startStatus: String?
    @State private var gitHubError: String?
    @State private var assignees: Set<String>
    /// The user changed the people; until then the draft keeps the default "Ich" (`nil`).
    @State private var assigneesChosen = false
    @State private var assigneeLoad: AssigneeLoad = .idle
    @State private var recurrence: Recurrence?
    /// The reminders of the new task; created when the sheet appears, because the defaults come from the settings.
    @State private var reminders: NewTaskReminders?
    /// Set when the task was created but its reminders could not be written: the sheet then only offers to close.
    @State private var remindersError: String?

    private var gitHub: GitHubTaskProvider? { model.provider(for: .github) as? GitHubTaskProvider }

    private var targets: [TaskSource] { Self.availableTargets(in: model) }

    /// People offered for the chosen repository: the signed-in user first, also while loading or after a failed load.
    private var assigneeCandidates: [String] {
        AssigneeSelection.ordered(candidates: assigneeLoad.logins(for: repository), me: gitHub?.login)
    }

    /// The chosen people in menu order.
    private var selectedAssignees: [String] { assigneeCandidates.filter(assignees.contains) }

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
        // A GitHub issue needs a repository; a project is optional (#153).
        return target != .github || repository != nil
    }

    /// Projects of the catalog that are selected, in catalog order.
    private var selectedProjects: [ProjectInfo] { (catalog?.projects ?? []).filter { projectIDs.contains($0.id) } }

    /// Start stages that all selected projects have; empty without a project.
    private var startStatusOptions: [String] {
        ProjectSelection.commonStatusOptions(selectedProjects.map(GitHubMapping.statusOptions(in:)))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let remindersError {
                    Section {
                        Label(remindersError, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    } footer: {
                        Text("Die Aufgabe ist angelegt. Die Erinnerungen kannst du im Editor setzen.")
                    }
                }
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
                        .keyboardDoneButton()
                }

                if target == .github {
                    Section {
                        Picker("Repository", selection: $repository) {
                            Text("Wählen …").tag(String?.none)
                            ForEach(catalog?.repositories ?? [], id: \.self) { Text($0).tag(Optional($0)) }
                        }
                        ProjectSelectionRow(projects: (catalog?.projects ?? []).map { (id: $0.id, title: $0.title) },
                                            selection: $projectIDs, edited: $projectsEdited)
                        if !startStatusOptions.isEmpty {
                            Picker("Status", selection: $startStatus) {
                                ForEach(startStatusOptions, id: \.self) { Text($0).tag(Optional($0)) }
                            }
                        }
                        AssigneeSelectionRow(candidates: assigneeCandidates, me: gitHub?.login, load: assigneeLoad,
                                             selection: Binding(get: { assignees },
                                                                set: { assignees = $0; assigneesChosen = true }),
                                             isEnabled: repository != nil, showsDefaultMe: !assigneesChosen)
                    } footer: {
                        if let gitHubError {
                            Text(gitHubError)
                        } else {
                            Text(gitHubFooter)
                        }
                    }
                    .task(id: target) { await loadCatalog() }
                    .onChange(of: startStatusOptions, initial: true) { _, options in
                        startStatus = ProjectSelection.startStatus(current: startStatus, options: options)
                    }
                    .task(id: repository) { await loadAssignees() }
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
                    if hasDue, let reminders { remindersRow(reminders) }
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
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Neue Aufgabe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if remindersError != nil {
                        Button("Fertig") { dismiss() }
                    } else {
                        Button("Hinzufügen") { Task { await save() } }
                            .disabled(!canSave)
                    }
                }
                if let onDiscard {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Verwerfen", role: .destructive) {
                            onDiscard()
                            dismiss()
                        }
                    }
                }
            }
            .task { reminderLists = await model.containers(for: .reminders) }
            .task {
                if reminders == nil {
                    reminders = NewTaskReminders(defaults: environment.settings.reminderDefaults, source: target, hasTime: hasTime && target != .github)
                }
            }
            .onChange(of: hasTime) { _, _ in configureReminders() }
            .onChange(of: target) { _, newTarget in
                configureReminders(source: newTarget)
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
            subContainerIDs: target == .github ? selectedProjects.map(\.id) : [],
            recurrence: RecurrenceAvailability.draftRecurrence(
                recurrence, target: target,
                due: hasDue ? DueDate(date: dueDate, includeTime: false, calendar: model.calendar) : nil),
            assignees: target == .github ? AssigneeSelection.draftAssignees(selected: selectedAssignees, chosen: assigneesChosen) : nil,
            startStatus: target == .github && !projectIDs.isEmpty ? startStatus : nil
        )
        guard let created = await model.create(draft, in: target) else {
            dismiss()
            return
        }
        onCreated?()
        do {
            try reminders?.save(for: created, overrides: environment.reminderOverrides, reminderStore: environment.reminderStore)
            if reminders?.ownList != nil && created.due != nil {
                environment.notifications.scheduleSoon()
                environment.taskList.refreshReminderMarks()
            }
            dismiss()
        } catch {
            remindersError = TaskListModel.message(for: error)
        }
    }

    /// The reminders follow the source and the time of day of the new task.
    private func configureReminders(source: TaskSource? = nil) {
        let source = source ?? target
        reminders?.configure(source: source, hasTime: hasTime && source != .github)
    }

    /// "Erinnerungen" in the section of the due date, shown once a due date is set: "Standard" until the user picks an own list.
    private func remindersRow(_ reminders: NewTaskReminders) -> some View {
        NavigationLink {
            ReminderSelectionPage(model: reminders.list, subject: .task, calendar: model.calendar,
                                  footer: target == .reminders
                                      ? String(localized: "Eigene Erinnerungen werden in der Erinnerungen-App gespeichert. Ruhezeiten gelten dafür nicht.") : nil)
        } label: {
            LabeledContent("Erinnerungen", value: reminders.list.rowSummary(subject: .task, calendar: model.calendar))
        }
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

    /// Stands for the signed-in user in the footer while nothing was chosen (the login may not be known yet).
    private static let defaultAssigneeMarker = "me"

    /// Says before saving who gets the issue; before that it says what the project choice means (no project, no shared stage).
    private var gitHubFooter: String {
        let assignment = assigneesChosen ? AssigneeSelection.footer(selected: selectedAssignees, me: gitHub?.login)
            : AssigneeSelection.footer(selected: [Self.defaultAssigneeMarker], me: Self.defaultAssigneeMarker)
        return ProjectSelection.footer(repositoryChosen: repository != nil, hasProject: !projectIDs.isEmpty,
                                       optionLists: selectedProjects.map(GitHubMapping.statusOptions(in:)), assignment: assignment)
    }

    /// Loads the assignable people of the chosen repository. Every repository change resets the choice to
    /// the signed-in user, also after an own choice, so an issue never goes to the people of another repository.
    private func loadAssignees() async {
        assignees = Set([gitHub?.login].compactMap { $0 })
        assigneesChosen = false
        guard let repository, let gitHub else {
            assigneeLoad = .idle
            return
        }
        assigneeLoad = .loading(repository: repository)
        let logins = await gitHub.assignableUsers(in: repository, maxAge: AppEnvironment.catalogMaxAge)
        assigneeLoad = assigneeLoad.adopting(logins, for: repository, selected: self.repository)
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
