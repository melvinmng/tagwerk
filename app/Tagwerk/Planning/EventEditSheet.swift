import EventKit
import EventKitUI
import RemindersKit
import SwiftUI
import TagwerkCore

/// Short form to create or change an event in any writable calendar (mockup J2). New events default to
/// the plan calendar; series ask "Nur diesen Termin" / "Diesen und alle folgenden" on saving (J6).
struct EventEditSheet: View {
    let model: PlanningModel
    let existing: CalendarEvent?
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var environment
    @State private var draft: EventDraft
    @State private var askingSpan = false
    @State private var systemEditor: SystemEditorRequest?
    /// The alarms of the event (plan P4). A new event starts with the default for events.
    @State private var reminderList: ReminderListModel
    /// The list when the sheet opened; alarms are written only when it changed, so alarms Tagwerk cannot show stay as they are.
    @State private var initialReminders: [ReminderOffset]

    /// `existing == nil` creates a new event on `day` at the suggested start.
    init(model: PlanningModel, existing: CalendarEvent?, day: PlanDay) {
        self.model = model
        self.existing = existing
        if let existing {
            _draft = State(initialValue: EventDraft(existing))
            let list = ReminderListModel(list: model.alarms(ofEvent: existing.id), isAllDay: existing.isAllDay)
            _reminderList = State(initialValue: list)
            _initialReminders = State(initialValue: list.offsets)
        } else {
            let list = ReminderListModel(list: model.defaultEventReminders(isAllDay: false), isAllDay: false)
            _reminderList = State(initialValue: list)
            _initialReminders = State(initialValue: [])
            let start = suggestedBlockStart(on: day, hours: model.workHours(on: day), minutes: 60, now: model.now(),
                                            calendar: model.calendar)
            _draft = State(initialValue: EventDraft(title: "", start: start, end: start.addingTimeInterval(3600), isAllDay: false,
                                                    calendarID: model.defaultEventCalendarID ?? "", notes: nil, location: nil,
                                                    url: nil))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titel", text: $draft.title)
                    Toggle("Ganztägig", isOn: $draft.isAllDay)
                    DatePicker("Beginn", selection: $draft.start, displayedComponents: draft.isAllDay ? .date : [.date, .hourAndMinute])
                    DatePicker("Ende", selection: $draft.end, in: draft.start..., displayedComponents: draft.isAllDay ? .date : [.date, .hourAndMinute])
                } footer: {
                    if !draft.isAllDay {
                        Text(model.fitText(start: draft.start, end: draft.end, excluding: existing?.id))
                    }
                }
                Section {
                    Picker("Kalender", selection: $draft.calendarID) {
                        ForEach(model.writableCalendars) { calendar in Text(calendar.title).tag(calendar.id) }
                    }
                } footer: {
                    Text("Abonnierte Kalender, Feiertage und Geburtstage sind schreibgeschützt und fehlen hier.")
                }
                Section("Notiz") {
                    TextField("Notiz", text: notes, axis: .vertical).lineLimit(2...6).keyboardDoneButton()
                }
                Section {
                    ReminderSelectionRows(model: reminderList, subject: .event, defaultSwitchTitle: nil, customTitle: "Hinweis hinzufügen",
                                          calendar: model.calendar)
                } header: {
                    Text("Hinweise im Kalender")
                } footer: {
                    Text("iOS meldet diese Hinweise selbst, auch in Apple Kalender. Ruhezeiten gelten dafür nicht.")
                }
                Section {
                    Button("Weitere Optionen …") { openSystemEditor() }
                } footer: {
                    Text("Wiederholung, Teilnehmende und Hinweise stellst du in Apples Termin-Editor ein.")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: draft.isAllDay) { _, allDay in changeAllDay(to: allDay) }
            .navigationTitle(existing == nil ? "Neuer Termin" : "Termin bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        if existing?.isRecurring == true { askingSpan = true } else { save(span: .thisEvent) }
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty || draft.calendarID.isEmpty)
                }
            }
            .confirmationDialog("Dieser Termin wiederholt sich", isPresented: $askingSpan, titleVisibility: .visible) {
                Button("Nur diesen Termin") { save(span: .thisEvent) }
                Button("Diesen und alle folgenden") { save(span: .futureEvents) }
            }
            .sheet(item: $systemEditor) { request in
                SystemEventEditor(store: request.store, event: request.event) { saved in
                    systemEditor = nil
                    Task {
                        // A new event was saved only to open Apple's editor; cancelling there removes it again.
                        if !saved, let created = request.createdEvent { await model.deleteEvent(created, span: .thisEvent) }
                        await model.reload()
                    }
                    dismiss()
                }
                .ignoresSafeArea()
            }
        }
    }

    private var notes: Binding<String> {
        Binding(get: { draft.notes ?? "" }, set: { draft.notes = $0.isEmpty ? nil : $0 })
    }

    /// An all-day event has no hour distances. A new event that still has the default list gets the all-day default.
    private func changeAllDay(to allDay: Bool) {
        let untouchedDefault = existing == nil && reminderList.offsets == model.defaultEventReminders(isAllDay: !allDay)
        reminderList.configure(isAllDay: allDay, defaultOffsets: [])
        if untouchedDefault { reminderList.setList(model.defaultEventReminders(isAllDay: allDay)) }
    }

    /// The alarms to write: `nil` leaves them alone (nothing changed, or a new event without any).
    private func alarmsToWrite() -> [ReminderOffset]? {
        let list = reminderList.offsets
        if existing == nil { return list.isEmpty ? nil : list }
        return list == initialReminders && draft.isAllDay == existing?.isAllDay ? nil : list
    }

    private func save(span: EventSpan) {
        draft.alarms = alarmsToWrite()
        Task {
            if let existing {
                await model.updateEvent(existing, with: draft, span: span)
            } else {
                await model.createEvent(draft)
            }
            dismiss()
        }
    }

    /// New events are saved first, so Apple's editor opens the same event.
    private func openSystemEditor() {
        Task {
            var id = existing?.id
            var created: CalendarEvent?
            if id == nil, !draft.title.isEmpty {
                draft.alarms = alarmsToWrite()
                created = await model.createEvent(draft)
                id = created?.id
            }
            let pair = environment.gateway.eventForSystemEditor(id: id, calendarID: draft.calendarID)
            systemEditor = SystemEditorRequest(store: pair.store, event: pair.event, createdEvent: created)
        }
    }
}

struct SystemEditorRequest: Identifiable {
    let id = UUID()
    let store: EKEventStore
    let event: EKEvent
    /// Set when Tagwerk saved a new event just to open Apple's editor.
    var createdEvent: CalendarEvent?
}

/// Apple's full event editor (repeat rules, attendees, alerts).
struct SystemEventEditor: UIViewControllerRepresentable {
    let store: EKEventStore
    let event: EKEvent
    /// `true` when the user saved, `false` when cancelled.
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onFinish: (Bool) -> Void

        init(onFinish: @escaping (Bool) -> Void) {
            self.onFinish = onFinish
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onFinish(action != .canceled)
        }
    }
}
