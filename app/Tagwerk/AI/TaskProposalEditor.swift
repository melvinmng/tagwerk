import AIKit
import GitHubKit
import Observation
import SwiftUI
import TagwerkCore

/// A due date of a proposal: a day and, where the source has it, a time of day (minutes since midnight).
struct ProposalDue: Equatable {
    var day: PlanDay
    var minutes: Int?
}

/// Editor for `create_task`, `update_task`, `reschedule_task` and `assign_to_day` (plan ki-vorschlaege-anpassen, task B1).
///
/// The fields are those of "Neue Aufgabe": title, note, due date, priority, effort, and for a GitHub issue repository,
/// projects and people (the rows of the sheet "Ziel wählen"). `create_task` has no list argument, so there is no list
/// field. A field the user leaves as it was keeps the value of the call, so a `null` of `update_task` ("unchanged")
/// never turns into the current value of the task.
@MainActor
@Observable
final class TaskProposalEditor: ProposalEditor {
    nonisolated static let toolNames: Set<String> = ["create_task", "update_task", "reschedule_task", "assign_to_day"]

    enum Kind {
        case create, update, reschedule, assignToDay
    }

    /// The values of the plain fields; `initial` is the state the editor started from.
    private struct Draft: Equatable {
        var title = ""
        var notes = ""
        var due: ProposalDue?
        var priority: Priority?
        var minutes: Int?
        var day = PlanDay(year: 1970, month: 1, day: 1)
    }

    let kind: Kind
    let call: ToolCall
    let context: ProposalEditorContext

    var title = ""
    var notes = ""
    var due: ProposalDue?
    var priority: Priority?
    var minutes: Int?
    var day: PlanDay

    /// Repository, projects and people of a GitHub issue; `nil` for every other call, and without a stored catalog.
    private(set) var issueTarget: IssueTargetSheetModel?
    /// The call is an issue but no catalog is stored: the target is shown as it is and cannot be changed.
    private(set) var targetLocked = false

    @ObservationIgnored private let base: [String: Any]
    @ObservationIgnored private let initial: Draft
    @ObservationIgnored private let initialTarget: TargetState?

    private struct TargetState: Equatable {
        var repository: String?
        var projectIDs: Set<String>
        var assigneesChosen: Bool
        var assignees: Set<String>
    }

    required init?(call: ToolCall, context: ProposalEditorContext) {
        guard Self.toolNames.contains(call.name), let base = ProposalArguments.decode(call.arguments) else { return nil }
        self.call = call
        self.context = context
        self.base = base
        switch call.name {
        case "create_task": kind = .create
        case "update_task": kind = .update
        case "reschedule_task": kind = .reschedule
        default: kind = .assignToDay
        }
        func text(_ key: String) -> String { (base[key] as? String) ?? "" }
        var draft = Draft()
        draft.title = text("title")
        draft.notes = text("notes")
        draft.due = ProposalArguments.dayAndTime(text("due")).map { ProposalDue(day: $0.day, minutes: $0.minutes) }
        draft.priority = (base["priority"] as? String).flatMap(AppTools.priority)
        draft.minutes = (base["minutes"] as? NSNumber)?.intValue
        draft.day = ProposalArguments.dayAndTime(text("day"))?.day ?? PlanDay(date: context.now(), calendar: context.calendar)
        initial = draft
        title = draft.title
        notes = draft.notes
        due = draft.due
        priority = draft.priority
        minutes = draft.minutes
        day = draft.day

        var target: TargetState?
        if kind == .create, base["source"] as? String == "github" {
            if let directory = context.gitHubDirectory(), let catalog = directory.storedCatalog {
                let model = IssueTargetSheetModel(
                    catalog: catalog, me: directory.login, repository: base["repository"] as? String,
                    projectIDs: base["project_ids"] as? [String] ?? [],
                    loadAssignable: { await directory.assignableUsers(in: $0, maxAge: AppEnvironment.catalogMaxAge) })
                if let people = base["assignees"] as? [String] { model.choose(Set(people)) }
                issueTarget = model
                target = TargetState(repository: model.repository, projectIDs: model.projectIDs,
                                     assigneesChosen: model.assigneesChosen, assignees: model.assignees)
            } else {
                targetLocked = true
            }
        }
        initialTarget = target
    }

    // MARK: Offered values

    /// The priorities the function accepts for this source; reminders know P1 to P4 only. A value the call already has
    /// stays selectable.
    var priorityChoices: [Priority?] {
        var choices: [Priority?]
        if kind == .create, let source = base["source"] as? String, let task = TaskSource(rawValue: source) {
            choices = TaskEditorModel.priorityChoices(for: task)
        } else {
            choices = [nil] + Priority.allCases.map { $0 }
        }
        if let priority, !choices.contains(priority) { choices.append(priority) }
        return choices
    }

    /// GitHub's due date holds a day only.
    var supportsDueTime: Bool { base["source"] as? String != "github" }

    // MARK: ProposalEditor

    var isValid: Bool {
        switch kind {
        case .create:
            let hasTitle = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return hasTitle && (issueTarget?.canApply ?? true)
        case .update, .reschedule, .assignToDay: return true
        }
    }

    func arguments() -> Data {
        var result = base
        func set(_ key: String, _ value: Any?) { result[key] = value ?? NSNull() }
        func trimmed(_ text: String) -> String? {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        func dueText() -> String? { due.map { ProposalArguments.dueString(day: $0.day, minutes: $0.minutes) } }
        switch kind {
        case .create, .update:
            if title != initial.title { set("title", trimmed(title)) }
            if notes != initial.notes { set("notes", trimmed(notes)) }
            if due != initial.due { set("due", dueText()) }
            if priority != initial.priority { set("priority", priority?.label) }
            if minutes != initial.minutes { set("minutes", minutes) }
        case .reschedule:
            if due != initial.due { set("due", dueText()) }
        case .assignToDay:
            if day != initial.day { set("day", AIPlanner.dayString(day)) }
        }
        if let issueTarget, let initialTarget, let target = issueTarget.result {
            let now = TargetState(repository: issueTarget.repository, projectIDs: issueTarget.projectIDs,
                                  assigneesChosen: issueTarget.assigneesChosen, assignees: issueTarget.assignees)
            if now.repository != initialTarget.repository || now.projectIDs != initialTarget.projectIDs {
                set("repository", target.repository)
                set("project_ids", target.projectIDs)
            }
            // Untouched people survive, also while the list of assignable people has not loaded.
            if now.assigneesChosen != initialTarget.assigneesChosen || now.assignees != initialTarget.assignees {
                set("assignees", target.assignees)
            }
        }
        return ProposalArguments.encode(result)
    }

    var fields: AnyView { AnyView(TaskProposalFields(editor: self)) }

    func load() async { await issueTarget?.loadAssignees() }
}

/// The fields of `TaskProposalEditor`. A `Form` section per group; nothing here hangs a sheet on a row.
private struct TaskProposalFields: View {
    @Bindable var editor: TaskProposalEditor

    private var calendar: Calendar { editor.context.calendar }

    var body: some View {
        switch editor.kind {
        case .create, .update:
            textSection
            if editor.targetLocked {
                Section { Text("Ziel und Personen lassen sich nur ändern, solange GitHub verbunden ist.").foregroundStyle(.secondary) }
            }
            if let target = editor.issueTarget { TaskProposalTargetSection(model: target) }
            Section {
                dueRows
                priorityRow
                effortRows
            } footer: {
                if editor.kind == .update { Text("Felder, die du nicht änderst, bleiben unverändert.") }
            }
        case .reschedule:
            Section {
                dueRows
            } footer: {
                Text("Ohne Datum wird die Frist entfernt.")
            }
        case .assignToDay:
            Section {
                DatePicker("Tag", selection: dayBinding, displayedComponents: .date)
                    .environment(\.calendar, calendar)
                    .environment(\.timeZone, calendar.timeZone)
            }
        }
    }

    private var textSection: some View {
        Section {
            TextField("Titel", text: $editor.title)
            TextField("Notiz", text: $editor.notes, axis: .vertical).keyboardDoneButton()
        }
    }

    // MARK: Due date

    private var dueLabel: LocalizedStringKey { editor.kind == .update ? "Frist ändern" : "Fällig" }

    @ViewBuilder
    private var dueRows: some View {
        Toggle(dueLabel, isOn: Binding(
            get: { editor.due != nil },
            set: { isOn in
                editor.due = isOn ? ProposalDue(day: PlanDay(date: editor.context.now(), calendar: calendar), minutes: nil) : nil
            }))
        if let due = editor.due {
            if editor.supportsDueTime {
                Toggle("Uhrzeit", isOn: Binding(
                    get: { due.minutes != nil },
                    set: { isOn in editor.due?.minutes = isOn ? 9 * 60 : nil }))
            }
            DatePicker("Datum", selection: dueBinding, displayedComponents: due.minutes != nil ? [.date, .hourAndMinute] : [.date])
                .environment(\.calendar, calendar)
                .environment(\.timeZone, calendar.timeZone)
        }
    }

    private var dueBinding: Binding<Date> {
        Binding(
            get: {
                guard let due = editor.due else { return editor.context.now() }
                return due.day.startDate(in: calendar).addingTimeInterval(TimeInterval((due.minutes ?? 0) * 60))
            },
            set: { date in
                let hasTime = editor.due?.minutes != nil
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                editor.due = ProposalDue(day: PlanDay(date: date, calendar: calendar),
                                         minutes: hasTime ? (parts.hour ?? 0) * 60 + (parts.minute ?? 0) : nil)
            })
    }

    private var dayBinding: Binding<Date> {
        Binding(get: { editor.day.startDate(in: calendar) },
                set: { editor.day = PlanDay(date: $0, calendar: calendar) })
    }

    // MARK: Priority and effort

    private var priorityRow: some View {
        Picker("Priorität", selection: $editor.priority) {
            ForEach(editor.priorityChoices, id: \.self) { value in
                Text(value?.label ?? (editor.kind == .update ? String(localized: "Unverändert") : String(localized: "Keine"))).tag(value)
            }
        }
    }

    @ViewBuilder
    private var effortRows: some View {
        let label: LocalizedStringKey = editor.kind == .update ? "Aufwand ändern" : "Aufwand"
        Toggle(label, isOn: Binding(
            get: { editor.minutes != nil },
            set: { editor.minutes = $0 ? 30 : nil }))
        if editor.minutes != nil {
            ValueStepper("Aufwand", value: Binding(get: { editor.minutes ?? 30 }, set: { editor.minutes = $0 }),
                         in: 5...960, step: 5, kind: .durationMinutes, display: { CapacityText.duration($0) })
        }
    }
}

/// Repository, projects and people of an issue: the rows of the sheet "Ziel wählen".
private struct TaskProposalTargetSection: View {
    @Bindable var model: IssueTargetSheetModel

    var body: some View {
        Section {
            Picker("Repository", selection: $model.repository) {
                Text("Wählen …").tag(String?.none)
                ForEach(model.catalog.repositories, id: \.self) { Text($0).tag(Optional($0)) }
            }
            ProjectSelectionRow(projects: model.catalog.projects.map { (id: $0.id, title: $0.title) },
                                selection: $model.projectIDs, edited: $model.projectsEdited)
            AssigneeSelectionRow(candidates: model.assigneeCandidates, me: model.me, load: model.assigneeLoad,
                                 selection: Binding(get: { model.assignees }, set: { model.choose($0) }),
                                 isEnabled: model.repository != nil, showsDefaultMe: !model.assigneesChosen)
        } footer: {
            Text("Ohne Projekt erscheint das Issue nicht in deinen Aufgaben.")
        }
    }
}
