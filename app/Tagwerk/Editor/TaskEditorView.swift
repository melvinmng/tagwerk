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
    let planning: PlanningModel?
    let onShowDay: ((PlanDay) -> Void)?
    @State private var plannedEdit: PlannedEdit?
    @State private var saveQuestion: TaskEditorModel.SaveQuestion?
    @State private var labelText = ""
    @State private var confirmsDelete = false

    init(item: TaskItem, provider: any TaskProvider, calendar: Calendar, containers: [TaskContainer],
         addComment: TaskEditorModel.CommentAction? = nil, isReadOnly: Bool = false,
         onDelete: ((String) -> Void)? = nil, planning: PlanningModel? = nil,
         onShowDay: ((PlanDay) -> Void)? = nil, onSaved: @escaping (TaskItem) -> Void) {
        self.onDelete = onDelete
        self.planning = planning
        _plannedEdit = State(initialValue: planning?.plannedEdit(for: item))
        self.onShowDay = onShowDay
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
                    if model.showsRecurrenceRow { recurrenceRow }
                    if model.removesRecurrenceWithDue {
                        Text("Ohne Fälligkeit entfällt die Wiederholung.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if model.isVisible(.priority) { PriorityPicker(priority: $model.draft.priority, choices: model.priorityChoices) }
                    if isRecurring {
                        // One effort for a recurring reminder: the value of this day (design §13.15 R1).
                        EstimateField(minutes: recurringMinutes)
                        Text(recurringEffortHint)
                            .font(.caption).foregroundStyle(.secondary)
                    } else if model.isVisible(.estimate) {
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
            .onDisappear {
                // After the user's own comment, the list needs the new version however the sheet closes.
                if let refreshed = model.refreshed { onSaved(refreshed) }
            }
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
                        Task { await finish(model.save()) }
                    }
                    Button("Für alle ab \(todayText)") {
                        plannedEdit?.recurringForAll = true
                        Task { await finish(model.save()) }
                    }
                case .keepBlocks(let blocks):
                    if blocks.count == 1 {
                        Button("Sichern, Block behalten") { Task { await finish(model.save()) } }
                    } else {
                        Button("Sichern, Blöcke behalten") { Task { await finish(model.save()) } }
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
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        // The reach question only comes when the effort of a recurring reminder changed (R1);
                        // a changed rule that leaves planned blocks off the series names them in the same step.
                        let effortChanged = isRecurring && plannedEdit.map { $0.recurringMinutes != $0.originalRecurringMinutes } == true
                        let offSeries = model.changedRecurrence.map { recurrence in
                            planning?.blocksOffSeries(for: model.original, recurrence: recurrence) ?? []
                        } ?? []
                        if let question = TaskEditorModel.saveQuestion(effortChanged: effortChanged, blocksOffSeries: offSeries) {
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
        if let saved = model.saved { onSaved(saved) }
        if let planning, let plannedEdit, plannedEdit != planning.plannedEdit(for: model.original) {
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

    private var askingSaveQuestion: Binding<Bool> {
        Binding(get: { saveQuestion != nil }, set: { if !$0 { saveQuestion = nil } })
    }

    private var saveQuestionTitle: String {
        switch saveQuestion {
        case .keepBlocks: String(localized: "Wiederholung geändert")
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
