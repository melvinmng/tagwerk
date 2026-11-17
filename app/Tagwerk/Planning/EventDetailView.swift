import RemindersKit
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
    @State private var editing = false
    @State private var askingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                if let notice {
                    Section {
                        Label(notice.title, systemImage: notice.symbol).font(.subheadline.weight(.semibold))
                        Text(notice.text).font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text(event.title).font(.headline)
                    Text(timeText).foregroundStyle(.secondary)
                    if let calendar = model.calendarTitle(event.calendarID) {
                        LabeledContent("Kalender", value: calendar + (event.isEditable ? "" : " 🔒"))
                    }
                    if let location = event.location, !location.isEmpty { LabeledContent("Ort", value: location) }
                    if let notes = event.notes, !notes.isEmpty, notes != CalendarBlockRules.blockNotes {
                        Text(notes).font(.subheadline).foregroundStyle(.secondary)
                    }
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
                        Button("Aufgabe zeigen") {
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

                if event.isEditable && !event.isInvitation {
                    Section {
                        Button("Bearbeiten") { editing = true }
                        Button("Termin löschen", role: .destructive) { askingDelete = true }
                    }
                }

                Section {
                    Button(event.isInvitation ? "In Kalender-App antworten" : "Im Kalender öffnen") {
                        if let url = URL(string: "calshow:\(Int(event.start.timeIntervalSinceReferenceDate))") { openURL(url) }
                    }
                }
            }
            .navigationTitle("Termin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
            .sheet(isPresented: $editing, onDismiss: { dismiss() }) {
                EventEditSheet(model: model, existing: event, day: PlanDay(date: event.start, calendar: model.calendar))
            }
            .confirmationDialog(event.isRecurring ? "Dieser Termin wiederholt sich" : "Termin löschen?",
                                isPresented: $askingDelete, titleVisibility: .visible) {
                if event.isRecurring {
                    Button("Nur diesen Termin löschen", role: .destructive) { delete(.thisEvent) }
                    Button("Diesen und alle folgenden löschen", role: .destructive) { delete(.futureEvents) }
                } else {
                    Button("Löschen", role: .destructive) { delete(.thisEvent) }
                }
            }
        }
    }

    private func delete(_ span: EventSpan) {
        Task {
            await model.deleteEvent(event, span: span)
            dismiss()
        }
    }

    /// Why an event cannot be changed in Tagwerk (mockups J4, J5).
    private var notice: (title: String, symbol: String, text: String)? {
        if event.isInvitation {
            return ("Einladung", "envelope",
                    "Titel und Zeit legt die einladende Person fest. Zusagen oder Absagen geht nur in der Kalender-App.")
        }
        if !event.isEditable {
            return ("Schreibgeschützt", "lock",
                    "Dieser Kalender ist abonniert oder schreibgeschützt. Ändern und Löschen sind hier nicht möglich; verknüpfen geht trotzdem.")
        }
        return nil
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
