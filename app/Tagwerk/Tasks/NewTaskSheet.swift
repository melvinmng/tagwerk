import GitHubKit
import SwiftUI
import TagwerkCore

/// Creates a local task or a reminder.
struct NewTaskSheet: View {
    let model: TaskListModel
    @Environment(\.dismiss) private var dismiss

    @State private var target: TaskSource = .local
    @State private var title = ""
    @State private var notes = ""
    @State private var hasDue = false
    @State private var hasTime = false
    @State private var dueDate = Date()
    @State private var priority: Priority?
    @State private var listID: String?
    @State private var reminderLists: [TaskContainer] = []
    @State private var repositories: [String] = []
    @State private var repository: String?
    @State private var projectID: String?
    @State private var gitHubError: String?

    private var gitHub: GitHubTaskProvider? { model.provider(for: .github) as? GitHubTaskProvider }

    private var targets: [TaskSource] {
        [.local, .reminders, .github].filter { source in
            guard model.provider(for: source) != nil, let state = model.sourceStates[source] else {
                return source == .local
            }
            return state == .loaded
        }
    }

    private var canSave: Bool {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return target != .github || (repository != nil && projectID != nil)
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
                            ForEach(repositories, id: \.self) { Text($0).tag(Optional($0)) }
                        }
                        Picker("Project", selection: $projectID) {
                            Text("Wählen …").tag(String?.none)
                            ForEach(gitHub?.projects ?? []) { Text($0.title).tag(Optional($0.id)) }
                        }
                    } footer: {
                        Text(gitHubError ?? "Das Issue wird dir zugewiesen.")
                    }
                    .task(id: target) { await loadRepositories() }
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
                        Toggle("Uhrzeit", isOn: $hasTime)
                        DatePicker("Datum", selection: $dueDate,
                                   displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
                            .environment(\.calendar, model.calendar)
                            .environment(\.timeZone, model.calendar.timeZone)
                    }
                    PriorityPicker(priority: $priority)
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
        }
    }

    private func save() async {
        let draft = TaskDraft(
            title: title.trimmingCharacters(in: .whitespaces),
            notes: notes.isEmpty ? nil : notes,
            due: hasDue ? DueDate(date: dueDate, includeTime: hasTime, calendar: model.calendar) : nil,
            priority: priority,
            containerID: target == .reminders ? listID : target == .github ? repository : nil,
            subContainerID: target == .github ? projectID : nil
        )
        await model.create(draft, in: target)
        dismiss()
    }
}

extension NewTaskSheet {
    private func label(for source: TaskSource) -> String {
        switch source {
        case .local: "Lokal"
        case .reminders: "Erinnerung"
        case .github: "GitHub-Issue"
        }
    }

    private func loadRepositories() async {
        guard repositories.isEmpty, let gitHub else { return }
        do {
            repositories = try await gitHub.repositories()
        } catch {
            gitHubError = TaskListModel.message(for: error)
        }
    }
}

/// Priority choice "Keine", P1 … P5.
struct PriorityPicker: View {
    @Binding var priority: Priority?

    var body: some View {
        Picker("Priorität", selection: $priority) {
            Text("Keine").tag(Priority?.none)
            ForEach(Priority.allCases, id: \.self) { value in
                Text(value.label).tag(Optional(value))
            }
        }
    }
}
