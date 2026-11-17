import SwiftUI
import TagwerkCore

/// A calendar event in Tagwerk with its linked task (mockup h): jump to the task, link or unlink.
struct EventDetailView: View {
    let event: CalendarEvent
    let model: PlanningModel
    let onOpenTask: (TaskItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var search = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(event.title).font(.headline)
                    Text(timeText).foregroundStyle(.secondary)
                }

                if !event.mergedCalendarIDs.isEmpty {
                    Section {
                        Button("Getrennt anzeigen") {
                            Task { await model.showDuplicatesSeparately() }
                            dismiss()
                        }
                    } header: {
                        Text("In \(event.mergedCalendarIDs.count + 1) Kalendern")
                    } footer: {
                        Text("Gleiche Termine aus mehreren Kalendern stehen als eine Zeile im Ablauf. Das lässt sich in den Einstellungen wieder einschalten.")
                    }
                }

                Section("Verknüpfte Aufgabe") {
                    if let task = model.linkedTask(eventID: event.id) {
                        LabeledContent(task.title, value: originText)
                        Button("Aufgabe öffnen") {
                            dismiss()
                            onOpenTask(task)
                        }
                        if model.linkOrigin(eventID: event.id) == .manual {
                            Button("Verknüpfung lösen", role: .destructive) { Task { await model.unlink(eventID: event.id) } }
                        }
                    } else {
                        NavigationLink("Mit Aufgabe verknüpfen …") { taskPicker }
                    }
                }

                Section {
                    Button("Im Kalender öffnen") {
                        if let url = URL(string: "calshow:\(Int(event.start.timeIntervalSinceReferenceDate))") { openURL(url) }
                    }
                }
            }
            .navigationTitle("Termin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
    }

    private var taskPicker: some View {
        List(filteredTasks) { task in
            Button(task.title) {
                Task {
                    await model.link(eventID: event.id, to: task.id)
                    dismiss()
                }
            }
            .foregroundStyle(.primary)
        }
        .searchable(text: $search, prompt: "Aufgabe suchen")
        .navigationTitle("Aufgabe wählen")
    }

    private var filteredTasks: [TaskItem] {
        let open = model.taskList.items.filter { !$0.isCompleted }
        guard !search.isEmpty else { return open }
        return open.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    private var timeText: String {
        if event.isAllDay { return event.start.formatted(date: .complete, time: .omitted) + " · ganztägig" }
        return event.start.formatted(date: .complete, time: .shortened) + " – " + event.end.formatted(date: .omitted, time: .shortened)
    }

    private var originText: String {
        switch model.linkOrigin(eventID: event.id) {
        case .url?: "Tagwerk-Block"
        case .manual?: "manuell verknüpft"
        case .automatic?: "automatisch erkannt"
        case nil: ""
        }
    }
}
