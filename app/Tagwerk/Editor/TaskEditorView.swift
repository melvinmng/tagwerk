import SwiftUI
import TagwerkCore

/// Editor sheet with source-specific fields and the conflict banner.
struct TaskEditorView: View {
    @State private var model: TaskEditorModel
    let calendar: Calendar
    let containers: [TaskContainer]
    let onSaved: (TaskItem) -> Void
    @Environment(\.dismiss) private var dismiss

    init(item: TaskItem, provider: any TaskProvider, calendar: Calendar, containers: [TaskContainer],
         onSaved: @escaping (TaskItem) -> Void) {
        _model = State(initialValue: TaskEditorModel(item: item, provider: provider))
        self.calendar = calendar
        self.containers = containers
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                if model.conflict != nil {
                    ConflictBanner(
                        onReload: { Task { await model.reloadFromSource() } },
                        onSaveAnyway: { Task { await finish(model.saveAnyway()) } }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                if let message = model.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }

                Section {
                    TextField("Titel", text: $model.draft.title, axis: .vertical)
                    if model.isVisible(.container), !containers.isEmpty {
                        Picker("Liste", selection: containerID) {
                            ForEach(containers, id: \.id) { Text($0.name).tag($0.id) }
                        }
                    }
                }

                Section {
                    if model.isVisible(.due) { dueFields }
                    if model.isVisible(.priority) { PriorityPicker(priority: $model.draft.priority) }
                    if model.isVisible(.estimate) {
                        Stepper(value: estimate, in: 0...1440, step: 15) {
                            LabeledContent("Geschätzt", value: model.draft.estimateMinutes.map { "\($0) min" } ?? "–")
                        }
                    }
                }

                if model.isVisible(.notes) {
                    Section("Notiz") {
                        TextField("Notiz", text: notes, axis: .vertical).lineLimit(3...10)
                    }
                }

                Section {
                    Toggle("Erledigt", isOn: $model.draft.isCompleted)
                }
            }
            .navigationTitle(model.original.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { Task { await finish(model.save()) } }
                        .disabled(model.isSaving || model.draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    @ViewBuilder private var dueFields: some View {
        Toggle("Fällig", isOn: hasDue.animation())
        if let due = model.draft.due {
            Toggle("Uhrzeit", isOn: hasTime)
            DatePicker("Datum", selection: dueDate, displayedComponents: due.hasTime ? [.date, .hourAndMinute] : [.date])
                .environment(\.calendar, calendar)
        }
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

    private var estimate: Binding<Int> {
        Binding(
            get: { model.draft.estimateMinutes ?? 0 },
            set: { model.draft.estimateMinutes = $0 == 0 ? nil : $0 }
        )
    }

    private var notes: Binding<String> {
        Binding(
            get: { model.draft.notes ?? "" },
            set: { model.draft.notes = $0.isEmpty ? nil : $0 }
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
