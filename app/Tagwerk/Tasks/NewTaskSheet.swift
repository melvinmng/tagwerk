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

    private var targets: [TaskSource] {
        [.local, .reminders].filter { source in
            model.provider(for: source) != nil && model.sourceStates[source] != .noAccess
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if targets.count > 1 {
                    Picker("Anlegen als", selection: $target) {
                        ForEach(targets, id: \.self) { source in
                            Text(source == .local ? "Lokal" : "Erinnerung").tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    TextField("Titel", text: $title)
                    TextField("Notiz", text: $notes, axis: .vertical)
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
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
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
            containerID: target == .reminders ? listID : nil
        )
        await model.create(draft, in: target)
        dismiss()
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
