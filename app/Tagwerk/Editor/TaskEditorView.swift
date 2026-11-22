import GitHubKit
import SwiftUI
import TagwerkCore

/// Editor sheet with source-specific fields and the conflict banner.
struct TaskEditorView: View {
    @State private var model: TaskEditorModel
    let calendar: Calendar
    let containers: [TaskContainer]
    /// Receives the saved item and the people this save added (for the warning when GitHub dropped one).
    let onSaved: (TaskItem, [String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var environment
    /// The reminders of the task (plan P4); created when the editor appears.
    @State private var reminders: TaskReminderModel?

    let isReadOnly: Bool
    let onDelete: ((String) -> Void)?
    let planning: PlanningModel?
    let onShowDay: ((PlanDay) -> Void)?
    @State private var plannedEdit: PlannedEdit?
    @State private var saveQuestion: TaskEditorModel.SaveQuestion?
    @State private var labelText = ""
    @State private var confirmsDelete = false
    /// Source of the assignable people; `nil` for tasks that are no GitHub issues.
    private let gitHub: GitHubTaskProvider?
    @State private var assignable: [String]?
    @State private var assigneeLoad: AssigneeLoad = .idle

    init(item: TaskItem, provider: any TaskProvider, calendar: Calendar, containers: [TaskContainer],
         addComment: TaskEditorModel.CommentAction? = nil, isReadOnly: Bool = false,
         onDelete: ((String) -> Void)? = nil, planning: PlanningModel? = nil,
         onShowDay: ((PlanDay) -> Void)? = nil, onSaved: @escaping (TaskItem, [String]) -> Void) {
        let gitHub = provider as? GitHubTaskProvider
        self.gitHub = gitHub
        self.onDelete = onDelete
        self.planning = planning
        _plannedEdit = State(initialValue: planning?.plannedEdit(for: item))
        self.onShowDay = onShowDay
        _model = State(initialValue: TaskEditorModel(item: item, provider: provider, addComment: addComment,
                                                         viewerLogin: gitHub?.login))
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
                                AccessibilityNotification.Announcement(String(localized: "Stand von \(sourceName) geladen")).post()
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
                        .foregroundStyle(.secondaryText)
                }
                if let message = model.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.redText)
                }

                Section {
                    TextField("Titel", text: $model.draft.title, axis: .vertical)
                        .keyboardDoneButton()
                        .accessibilityIdentifier(AccessibilityID.Tasks.editorTitle)
                    if model.original.id.source == .github {
                        LabeledContent("Repo", value: model.original.container.name)
                        assigneeRow
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
                            Text("Alle Projekte").tag(String?.none)
                            ForEach(model.original.subContainers, id: \.id) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                    if model.isVisible(.due) { dueFields }
                    if model.isVisible(.due) { remindersRow }
                    if model.showsRecurrenceRow { recurrenceRow }
                    if model.removesRecurrenceWithDue {
                        Text("Ohne Fälligkeit entfällt die Wiederholung.")
                            .font(.caption).foregroundStyle(.secondaryText)
                    }
                    if model.isVisible(.priority) { PriorityPicker(priority: $model.draft.priority, choices: model.priorityChoices) }
                    if isRecurring {
                        // One effort for a recurring reminder: the value of this day (design §13.15 R1).
                        EstimateField(minutes: recurringMinutes)
                        Text(recurringEffortHint)
                            .font(.caption).foregroundStyle(.secondaryText)
                    } else if model.isVisible(.estimate) {
                        EstimateField(minutes: $model.draft.estimateMinutes)
                    }
                }

                statusSection

                if model.isVisible(.notes) {
                    Section(model.original.id.source == .github ? "Beschreibung (Markdown)" : "Notiz") {
                        TextField("Notiz", text: notes, axis: .vertical).lineLimit(3...10).keyboardDoneButton()
                    }
                }

                Section {
                    Toggle("Erledigt", isOn: $model.draft.isCompleted)
                }

                if let planning, plannedEdit != nil {
                    PlannedSection(edit: plannedBinding, calendar: calendar,
                                   isRecurring: planning.recurringItem(for: model.original, on: planning.today) != nil,
                                   onShowDay: onShowDay.map { show in { day in
                                       dismiss()
                                       show(day)
                                   } },
                                   suggestedMinutes: planning.suggestedBlockMinutes(for: model.original),
                                   suggestedStart: { day in
                                       suggestedBlockStart(on: day, hours: planning.workHours(on: day),
                                                           minutes: planning.suggestedBlockMinutes(for: model.original),
                                                           now: planning.now(), calendar: calendar)
                                   })
                }

                if model.canComment {
                    Section("Kommentar") {
                        TextField("Kommentar schreiben", text: $model.comment, axis: .vertical).lineLimit(2...6).keyboardDoneButton()
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
            .scrollDismissesKeyboard(.interactively)
            .animation(.default, value: model.conflict == nil)
            .onDisappear {
                // After the user's own comment, the list needs the new version however the sheet closes.
                if let refreshed = model.refreshed { onSaved(refreshed, []) }
                // The task was written although its reminders were not: the list must know the new version.
                if model.reminderFailureAfterSave, let saved = model.saved { onSaved(saved, model.requestedAssignees) }
            }
            .task { await loadAssignable() }
            .task { prepareReminders() }
            .onChange(of: model.draft.due) { _, due in reminders?.dueChanged(to: due) }
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
            // One dialog for everything asked before saving (effort reach and blocks off the series).
            .confirmationDialog(saveQuestionTitle, isPresented: askingSaveQuestion, titleVisibility: .visible,
                                presenting: saveQuestion) { question in
                switch question {
                case .effortReach:
                    Button("Nur am \(todayText)") {
                        plannedEdit?.recurringForAll = false
                        reminders?.reach = .onlyThis
                        Task { await finish(model.save()) }
                    }
                    Button("Für alle ab \(todayText)") {
                        plannedEdit?.recurringForAll = true
                        reminders?.reach = .allFollowing
                        Task { await finish(model.save()) }
                    }
                case .keepBlocks(let blocks):
                    if blocks.count == 1 {
                        Button("Sichern, Block behalten") { Task { await finish(model.save()) } }
                    } else {
                        Button("Sichern, Blöcke behalten") { Task { await finish(model.save()) } }
                    }
                case .handOver:
                    Button("Abgeben", role: .destructive) { Task { await finish(model.save()) } }
                case .remindersReach:
                    Button(ReminderReachText.onlyThis(reachDay, calendar: calendar)) {
                        reminders?.reach = .onlyThis
                        Task { await finish(model.save()) }
                    }
                    Button(ReminderReachText.fromThis(reachDay, calendar: calendar)) {
                        reminders?.reach = .allFollowing
                        Task { await finish(model.save()) }
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: { question in
                switch question {
                case .effortReach(let blocks):
                    Text(String(localized: "Diese Aufgabe wiederholt sich. Titel, Fälligkeit und Priorität gelten für alle Tage.")
                         + (blocks.isEmpty ? "" : " " + blocksNotice(blocks)))
                case .keepBlocks(let blocks):
                    Text(blocksNotice(blocks))
                case .handOver(let futureBlocks):
                    Text(TaskEditorModel.handOverMessage(number: model.original.issueNumber, futureBlocks: futureBlocks,
                                                         leavesUnassigned: (model.draft.assignees ?? []).isEmpty))
                case .remindersReach:
                    Text("Diese Aufgabe wiederholt sich. Die Erinnerungen gelten nur für diese Fälligkeit oder für alle folgenden.")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                // Starting the timer closes the editor, so it is offered only while nothing would be lost.
                ToolbarItem(placement: .secondaryAction) {
                    if !model.original.isCompleted && !model.hasChanges { FocusStartButton(task: model.original) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        // The reach question only comes when the effort of a recurring reminder changed (R1);
                        // a changed rule that leaves planned blocks off the series names them in the same step.
                        let effortChanged = isRecurring && plannedEdit.map { $0.recurringMinutes != $0.originalRecurringMinutes } == true
                        let offSeries = model.changedRecurrence.map { recurrence in
                            planning?.blocksOffSeries(for: model.original, recurrence: recurrence) ?? []
                        } ?? []
                        // Removing myself is asked first, with the number of time blocks that will be deleted.
                        let handOverBlocks = model.handsOver ? (planning?.futureBlockCount(for: model.original.id) ?? 0) : nil
                        if let question = TaskEditorModel.saveQuestion(effortChanged: effortChanged, blocksOffSeries: offSeries,
                                                                       handOverFutureBlocks: handOverBlocks,
                                                                       remindersReach: model.asksReminderReach) {
                            saveQuestion = question
                        } else {
                            Task { await finish(model.save()) }
                        }
                    }
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

    // MARK: Reminders (plan P4)

    private func prepareReminders() {
        guard reminders == nil, model.isVisible(.due) else { return }
        let created = TaskReminderModel(item: model.original, overrides: environment.reminderOverrides,
                                        reminderStore: environment.reminderStore, defaults: environment.settings.reminderDefaults)
        created.dueChanged(to: model.draft.due)
        reminders = created
        model.reminders = created
    }

    /// One row under "Fällig" with the short form of the reminders; the list opens as a page of the navigation stack, so no
    /// sheet hangs on a row. Without a due date the row is grey, because the reminders count from it.
    @ViewBuilder private var remindersRow: some View {
        if let reminders {
            if model.draft.due == nil {
                LabeledContent("Erinnerungen", value: String(localized: "Braucht eine Fälligkeit"))
                    .foregroundStyle(.secondaryText)
                    .accessibilityElement(children: .combine)
            } else {
                NavigationLink {
                    ReminderSelectionPage(model: reminders.list, subject: .task, calendar: calendar,
                                          footer: remindersFooter(reminders))
                } label: {
                    LabeledContent("Erinnerungen",
                                   value: reminders.list.rowSummary(subject: .task, calendar: calendar))
                }
            }
        }
    }

    private func remindersFooter(_ reminders: TaskReminderModel) -> String? {
        guard model.original.id.source == .reminders else { return nil }
        let base = String(localized: "Eigene Erinnerungen werden in der Erinnerungen-App gespeichert. Ruhezeiten gelten dafür nicht.")
        return reminders.appliesToAllRepetitions(recurring: model.draft.recurrence != nil)
            ? base + " " + String(localized: "Gilt für alle Wiederholungen.") : base
    }

    private var sourceName: String {
        switch model.original.id.source {
        case .github: "GitHub"
        case .reminders: String(localized: "Erinnerungen")
        case .local: String(localized: "diesem Gerät")
        }
    }

    private var title: String {
        if model.original.id.source == .github, let number = model.original.url?.lastPathComponent, Int(number) != nil {
            return String(localized: "Issue #\(number)")
        }
        return model.original.title
    }

    private func finish(_ success: Bool) {
        guard success else { return }
        if reminders?.hasChanges == true {
            environment.notifications.scheduleSoon()
            environment.taskList.refreshReminderMarks()
        }
        if let saved = model.saved { onSaved(saved, model.requestedAssignees) }
        // A handed-over issue leaves the plan; its planning edits must not create a day or block again.
        if model.savedIsListed, let planning, let plannedEdit, plannedEdit != planning.plannedEdit(for: model.original) {
            let task = model.saved ?? model.original
            Task { await planning.applyPlanning(plannedEdit, for: task) }
        }
        dismiss()
    }

    private var isRecurring: Bool {
        planning.map { $0.recurringItem(for: model.original, on: $0.today) != nil } ?? false
    }

    private var recurringMinutes: Binding<Int?> {
        Binding(get: { plannedEdit?.recurringMinutes }, set: { plannedEdit?.recurringMinutes = $0 })
    }

    private var recurringEffortHint: String {
        if let previous = plannedEdit?.originalRecurringMinutes, previous > 0 {
            return String(localized: "Aufwand je Tag der Serie. Bisher \(CapacityText.duration(previous)).")
        }
        return String(localized: "Aufwand je Tag der Serie.")
    }

    private var todayText: String {
        guard let planning else { return String(localized: "heute") }
        return planning.today.startDate(in: calendar).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// The due date the reminder question names: the reminders of a repeating task count from it.
    private var reachDay: PlanDay {
        model.draft.due.map(PlanDay.init) ?? PlanDay(date: .now, calendar: calendar)
    }

    private var askingSaveQuestion: Binding<Bool> {
        Binding(get: { saveQuestion != nil }, set: { if !$0 { saveQuestion = nil } })
    }

    private var saveQuestionTitle: String {
        switch saveQuestion {
        case .keepBlocks: String(localized: "Wiederholung geändert")
        case .remindersReach: ReminderReachText.title(.task)
        case .handOver: String(localized: "Du bist danach nicht mehr zugewiesen.")
        case .effortReach, nil: effortQuestion
        }
    }

    /// "Gilt ab …. Geplante Blöcke … bleiben im Kalender: …" (decision 2026-11-18: blocks stay).
    private func blocksNotice(_ blocks: [CalendarEvent]) -> String {
        let start = model.changedRecurrence?.start ?? model.draft.due.map(PlanDay.init) ?? PlanDay(date: .now, calendar: calendar)
        return String(localized: "Gilt ab \(longDay(start)). Geplante Blöcke an Tagen ohne Termin der Serie bleiben im Kalender: \(BlockListText.text(blocks, calendar: calendar))")
    }

    private func longDay(_ day: PlanDay) -> String {
        day.startDate(in: calendar).formatted(
            Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated).day().month(.abbreviated))
    }

    // MARK: Assignees

    /// "Zugewiesen" for every issue: a menu of the assignable and the assigned people; a fixed value offline.
    @ViewBuilder private var assigneeRow: some View {
        let candidates = model.assigneeCandidates(assignable: assignable)
        if isReadOnly {
            LabeledContent("Zugewiesen", value: AssigneeSelection.value(selected: model.draft.assignees ?? [], me: model.viewerLogin))
        } else {
            AssigneeSelectionRow(candidates: candidates, me: model.viewerLogin, load: assigneeLoad,
                                 selection: Binding(get: { Set(model.draft.assignees ?? []) },
                                                    set: { model.setAssignees($0, candidates: candidates) }))
        }
    }

    /// Loads the assignable people of the issue's repository when the editor opens. Until then and after
    /// a failed load the menu offers only the assigned people (removing works, adding does not).
    private func loadAssignable() async {
        guard let gitHub, model.original.id.source == .github, !isReadOnly else { return }
        let repository = model.original.container.id
        assigneeLoad = .loading(repository: repository)
        assignable = await gitHub.assignableUsers(in: repository, maxAge: AppEnvironment.catalogMaxAge)
        assigneeLoad = assigneeLoad.adopting(assignable, for: repository, selected: repository)
    }

    // MARK: Recurrence

    private var draftDueDay: PlanDay? { model.draft.due.map(PlanDay.init) }

    private var recurrenceRow: some View {
        let today = PlanDay(date: .now, calendar: calendar)
        return NavigationLink {
            RecurrenceEditorView(
                original: model.draft.recurrence, previous: model.original.recurrence, start: draftDueDay ?? today,
                dueDay: draftDueDay, calendar: calendar,
                blocksOffSeries: planning.map { planning in
                    { recurrence in planning.blocksOffSeries(for: model.original, recurrence: recurrence) }
                },
                onChange: { model.setRecurrence($0, fallbackDue: draftDueDay ?? today) },
                onMoveDue: moveDue
            )
        } label: {
            LabeledContent {
                Text(model.draft.recurrence.map { RecurrenceText.summary($0, calendar: calendar) } ?? String(localized: "Nie"))
            } label: {
                Label("Wiederholen", systemImage: "repeat")
            }
        }
    }

    /// Takes the suggested day as due date and keeps the time.
    private func moveDue(_ day: PlanDay) {
        var due = model.draft.due ?? DueDate(year: day.year, month: day.month, day: day.day)
        due.year = day.year
        due.month = day.month
        due.day = day.day
        model.draft.due = due
        model.draft.recurrence?.start = day
    }

    private var effortQuestion: String {
        let old = plannedEdit?.originalRecurringMinutes.map(CapacityText.duration) ?? String(localized: "kein Aufwand")
        let new = plannedEdit?.recurringMinutes.map(CapacityText.duration) ?? String(localized: "kein Aufwand")
        return String(localized: "Aufwand geändert: \(old) → \(new)")
    }

    private var plannedBinding: Binding<PlannedEdit> {
        Binding(get: { plannedEdit ?? PlannedEdit(day: nil, blocks: [], originalDay: nil, originalRecurringMinutes: nil) },
                set: { plannedEdit = $0 })
    }

    // MARK: Bindings for optional fields

    private var hasDue: Binding<Bool> {
        Binding(
            get: { model.draft.due != nil },
            set: { model.setHasDue($0, today: PlanDay(date: .now, calendar: calendar)) }
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
                // The series starts at the due date (shown in the summary, e.g. "Jedes Jahr am …").
                model.draft.recurrence?.start = PlanDay(date: date, calendar: calendar)
            }
        )
    }

    private var notes: Binding<String> {
        Binding(
            get: { model.draft.notes ?? "" },
            set: { model.draft.notes = $0.isEmpty ? nil : $0 }
        )
    }

    /// One picker per Project (issue #154); only for issues whose Projects have a Status field.
    @ViewBuilder private var statusSection: some View {
        if model.isVisible(.status), !model.statusRows.isEmpty {
            Section {
                ForEach(model.statusRows, id: \.subContainerID) { row in
                    statusRow(row)
                }
            } header: {
                Text("Status")
            } footer: {
                if model.statusRows.count > 1 {
                    Text("Der Status gilt je Projekt, unabhängig von „Ändern in“.")
                }
            }
        }
    }

    @ViewBuilder private func statusRow(_ row: SubContainerStatus) -> some View {
        if row.isWritable {
            Picker(row.subContainerName, selection: statusBinding(row.subContainerID)) {
                if row.current == nil { Text("–").tag(String?.none) }
                ForEach(row.options, id: \.self) { Text($0).tag(Optional($0)) }
            }
        } else {
            LabeledContent(row.subContainerName, value: row.current ?? "–")
        }
    }

    private func statusBinding(_ subContainerID: String) -> Binding<String?> {
        Binding(
            get: { model.draft.statuses.first { $0.subContainerID == subContainerID }?.current },
            set: { if let status = $0 { model.setStatus(status, in: subContainerID) } }
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
