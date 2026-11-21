import RemindersKit
import SwiftUI
import TagwerkCore

/// One sheet for events, Tagwerk blocks and the lunch break (design §13.15 U1): head, time with ±15 min,
/// "Zählt als", task and actions in the same order; locked rows stay visible and say why.
struct EntrySheet: View {
    let entry: DayEntry
    let model: PlanningModel
    let onShowTask: (TaskID) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppEnvironment.self) private var environment
    @State private var editingReminders = false
    @State private var editing = false
    @State private var movingDay = false
    @State private var askingDelete = false
    @State private var pendingSeriesChange: SeriesChange?
    /// Deadline marking (DL2): series question and removal with preparation links.
    @State private var askingMarkSeries = false
    @State private var confirmingUnmark: CalendarEvent?

    /// A change of a series occurrence waiting for "Nur diesen / alle folgenden".
    private enum SeriesChange: Identifiable {
        case time(Range<Int>)
        case availability(free: Bool)
        var id: String {
            switch self {
            case .time(let range): "time-\(range)"
            case .availability(let free): "free-\(free)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            eventPresentations(Form {
                switch current {
                case .lunch(let day, let range): lunchContent(day: day, range: range)
                case .event(let event, let taskID): eventContent(event, taskID: taskID)
                }
            })
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    /// The entry as the model shows it now (times change while the sheet is open).
    private var current: DayEntry {
        switch entry {
        case .lunch(let day, let range):
            return .lunch(day: day, range: model.lunch(on: day) ?? range)
        case .event(let event, let taskID):
            let fresh = model.days.lazy.flatMap { $0.events + $0.blocks }.first { $0.id == event.id }
            return .event(fresh ?? event, taskID)
        }
    }

    private var navigationTitle: String {
        switch current {
        case .lunch: String(localized: "Mittagspause")
        case .event(let event, let taskID):
            taskID != nil && model.canEditAsBlock(event) ? String(localized: "Zeitblock") : String(localized: "Termin")
        }
    }

    // MARK: Event and block

    @ViewBuilder
    private func eventContent(_ event: CalendarEvent, taskID: TaskID?) -> some View {
        let isBlock = taskID != nil && model.canEditAsBlock(event)
        let deadline = model.importantDeadline(for: event)
        Section {
            Text((deadline != nil ? "⚑ " : "") + event.title).font(.headline)
            Text(timeText(event) + (deadline.map { " · " + DeadlineText(calendar: model.calendar).relative($0.day, today: model.today) } ?? ""))
                .foregroundStyle(.secondary)
            if let calendar = model.calendarTitle(event.calendarID) {
                LabeledContent("Kalender", value: calendar + (event.isEditable ? "" : " 🔒"))
            }
            if event.isRecurring { Label("Wiederholt sich", systemImage: "arrow.trianglehead.2.clockwise").foregroundStyle(.secondary) }
            if let location = event.location, !location.isEmpty { LabeledContent("Ort", value: location) }
            TravelInfoRow(event: event, model: model)
            if let notes = event.notes, !notes.isEmpty, !CalendarBlockRules.isBlockNote(notes) {
                Text(notes).font(.subheadline).foregroundStyle(.secondary)
            }
        }

        if !event.isAllDay {
            Section {
                stepRow("Beginn", value: event.start.formatted(date: .omitted, time: .shortened), enabled: model.canDrag(event)) { step in
                    let range = minutesRange(event)
                    change(event, to: (range.lowerBound + step)..<(range.upperBound + step))
                }
                stepRow("Dauer", value: CapacityText.duration(minutesRange(event).count), enabled: model.canDrag(event)) { step in
                    let range = minutesRange(event)
                    change(event, to: range.lowerBound..<max(range.lowerBound + 15, range.upperBound + step))
                }
            } footer: {
                if let reason = lockReason(event) { Text(reason) }
            }
        }

        Section {
            Picker("Zählt als", selection: Binding(get: { event.isBusy }, set: { busy in setAvailability(event, free: !busy) })) {
                Text("Belegt").tag(true)
                Text("Frei").tag(false)
            }
            .pickerStyle(.segmented)
        } footer: {
            Text("„Frei“ gilt nur in Tagwerk: Der Termin bleibt im Kalender, zählt aber nicht zur belegten Zeit.")
        }

        deadlineSection(event)
        // Its own section: the dialogs of the deadline section hang on it and would be presented once per row.
        if environment.settings.deadlineCalendarNotifications, model.isInDeadlineCalendar(event) || model.isMarkedDeadline(event) {
            Section { remindersRow(event) }
        }
        if let deadline {
            PreparationSection(deadline: deadline, model: model) { event in
                model.showDay(of: event)
                dismiss()
            }
        } else {
            preparationTargetSection(event)
        }

        Section("Aufgabe") {
            if let task = model.linkedTask(eventID: event.id) {
                LabeledContent(task.title, value: originText(event))
                if let progress = model.sessionProgress[task.id] {
                    // Mockup FS1: planned time against the effort.
                    Text("\(CapacityText.duration(progress.blocked)) von \(CapacityText.duration(progress.estimate)) eingeplant")
                        .font(.footnote).foregroundStyle(progress.remaining > 0 ? .orange : .secondary)
                }
                Button("Aufgabe zeigen") {
                    dismiss()
                    onShowTask(task.id)
                }
                Button("Erledigt") { Task { await model.taskList.complete(task.id); await model.reload() } }
                if model.linkOrigin(eventID: event.id) == .manual {
                    Button("Verknüpfung lösen", role: .destructive) { Task { await model.unlink(eventID: event.id) } }
                }
            } else {
                NavigationLink("Mit Aufgabe verknüpfen …") { TaskLinkPicker(model: model, eventID: event.id) { dismiss() } }
            }
        }

        if !event.mergedCalendarIDs.isEmpty {
            Section {
                Button("Getrennt anzeigen") {
                    Task { await model.showSeparately(event) }
                    dismiss()
                }
            } header: {
                Text("In \(event.mergedCalendarIDs.count + 1) Kalendern")
            } footer: {
                Text("Zusammengefasst auf deinen Wunsch; gezeigt wird die Kopie mit den meisten Angaben.")
            }
        }

        Section {
            if let linked = model.linkedTask(eventID: event.id) {
                // A linked calendar event starts the timer for its task; a time block also sizes the session to the block.
                if isBlock { FocusStartButton(block: event) } else { FocusStartButton(task: linked) }
            }
            if isBlock && model.linkedTask(eventID: event.id) != nil { duplicateRow(event) }
            if isBlock { Button("Auf anderen Tag …") { movingDay = true } }
            if event.isEditable && !event.isInvitation {
                Button("Bearbeiten …") { editing = true }
                Button(isBlock ? "Zeitblock löschen" : "Termin löschen", role: .destructive) { askingDelete = true }
            }
            Button(event.isInvitation ? "In Kalender-App antworten" : "Im Kalender öffnen") {
                if let url = URL(string: "calshow:\(Int(event.start.timeIntervalSinceReferenceDate))") { openURL(url) }
            }
        }
    }

    /// Sheets and dialogs of an event. They hang on the form, not on a section: inside a form a section passes
    /// its modifiers on to every row, so several rows presented the same sheet at once and SwiftUI closed the
    /// whole stack, including this sheet ("Auf anderen Tag …").
    @ViewBuilder
    private func eventPresentations(_ content: some View) -> some View {
        if case .event(let event, _) = current {
            content
                .sheet(isPresented: $editing) {
                    EventEditSheet(model: model, existing: event, day: PlanDay(date: event.start, calendar: model.calendar))
                }
                .sheet(isPresented: $movingDay) { BlockDaySheet(block: event, model: model) { dismiss() } }
                .sheet(isPresented: $editingReminders) { DeadlineReminderSheet(event: event, calendar: model.calendar) }
                .confirmationDialog(event.isRecurring ? "Dieser Termin wiederholt sich" : "Löschen?", isPresented: $askingDelete,
                                    titleVisibility: .visible) {
                    if event.isRecurring {
                        Button("Nur diesen Termin löschen", role: .destructive) { delete(event, .thisEvent) }
                        Button("Diesen und alle folgenden löschen", role: .destructive) { delete(event, .futureEvents) }
                    } else {
                        Button("Löschen", role: .destructive) { delete(event, .thisEvent) }
                    }
                }
                .confirmationDialog("Dieser Termin wiederholt sich", isPresented: hasSeriesChange, titleVisibility: .visible,
                                    presenting: pendingSeriesChange) { change in
                    Button("Nur diesen Termin") { apply(change, to: event, series: false) }
                    Button("Diesen und alle folgenden") { apply(change, to: event, series: true) }
                }
        } else {
            content
        }
    }

    // MARK: Deadline (DL2, DV1)

    /// "Als Deadline markieren" (Tagwerk only); for deadline calendar events only a note.
    @ViewBuilder
    private func deadlineSection(_ event: CalendarEvent) -> some View {
        let calendarName = model.calendarTitle(event.calendarID) ?? String(localized: "Kalender")
        Section {
            if model.isInDeadlineCalendar(event) {
                Label(String(localized: "Deadline · aus Kalender \(calendarName)"), systemImage: "flag.fill").foregroundStyle(.red)
            } else {
                Toggle("Als Deadline markieren", isOn: Binding(get: { model.isMarkedDeadline(event) }, set: { mark in
                    setMarked(event, mark)
                }))
                .tint(.red)
            }
        } header: {
            Text("Deadline")
        } footer: {
            if !model.isInDeadlineCalendar(event) {
                Text("Gilt nur in Tagwerk. Der Kalender „\(calendarName)“ bleibt unverändert.")
            }
        }
        .seriesMarkQuestion(isPresented: $askingMarkSeries, event: event, model: model)
        .unmarkConfirmation(event: $confirmingUnmark, model: model)
    }

    /// "Erinnerungen" of a deadline with their short form; opens `DeadlineReminderSheet` (plan P4).
    private func remindersRow(_ event: CalendarEvent) -> some View {
        let offsets = DeadlineReminderModel.offsets(for: event, overrides: environment.reminderOverrides,
                                                    defaults: environment.settings.reminderDefaults, calendar: model.calendar)
        return Button { editingReminders = true } label: {
            LabeledContent("Erinnerungen") {
                HStack(spacing: 4) {
                    Text(ReminderText.summary(offsets, subject: .deadline, isAllDay: event.isAllDay, locale: .current, calendar: model.calendar))
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
        }
        .foregroundStyle(.primary)
    }

    private func setMarked(_ event: CalendarEvent, _ mark: Bool) {
        if mark {
            if event.isRecurring { askingMarkSeries = true } else { Task { await model.markDeadline(event, series: false) } }
        } else if model.needsUnmarkConfirmation(event) {
            confirmingUnmark = event
        } else {
            Task { await model.unmarkDeadline(event) }
        }
    }

    /// For an ordinary event: the deadline it prepares for, or "Zu Deadline zuordnen …".
    @ViewBuilder
    private func preparationTargetSection(_ event: CalendarEvent) -> some View {
        Section("Vorbereitung") {
            if let target = model.preparationTarget(forEventID: event.id) ?? model.deadlineMarks.preparationTarget(for: event) {
                let text = DeadlineText(calendar: model.calendar)
                Label(text.preparationMark(target, today: model.today), systemImage: "link")
                if let deadline = model.deadline(for: target) {
                    NavigationLink("Deadline zeigen") {
                        Form {
                            PreparationSection(deadline: deadline, model: model) { event in
                                model.showDay(of: event)
                                dismiss()
                            }
                        }
                            .navigationTitle(deadline.title)
                    }
                    Button("Zuordnung lösen", role: .destructive) {
                        Task { await model.unlinkPreparation(event, from: deadline) }
                    }
                }
            } else {
                NavigationLink("Zu Deadline zuordnen …") { DeadlinePicker(event: event, model: model) {} }
            }
        }
    }

    private func change(_ event: CalendarEvent, to range: Range<Int>) {
        if event.isRecurring {
            pendingSeriesChange = .time(range)
        } else {
            Task { await model.setTime(of: event, startMinutes: range.lowerBound, endMinutes: range.upperBound, span: .thisEvent) }
        }
    }

    private func setAvailability(_ event: CalendarEvent, free: Bool) {
        if event.isRecurring {
            pendingSeriesChange = .availability(free: free)
        } else {
            Task { await model.setFree([event], free: free, series: false) }
        }
    }

    private func apply(_ change: SeriesChange, to event: CalendarEvent, series: Bool) {
        switch change {
        case .time(let range):
            Task { await model.setTime(of: event, startMinutes: range.lowerBound, endMinutes: range.upperBound,
                                       span: series ? .futureEvents : .thisEvent) }
        case .availability(let free):
            Task { await model.setFree([event], free: free, series: series) }
        }
    }

    private var hasSeriesChange: Binding<Bool> {
        Binding(get: { pendingSeriesChange != nil }, set: { if !$0 { pendingSeriesChange = nil } })
    }

    private func delete(_ event: CalendarEvent, _ span: EventSpan) {
        Task {
            await model.deleteEvent(event, span: span)
            dismiss()
        }
    }

    private func lockReason(_ event: CalendarEvent) -> String? {
        if event.isInvitation { return String(localized: "Einladung: Zeit und Titel legt die einladende Person fest.") }
        if !event.isEditable { return String(localized: "Abonnierter oder schreibgeschützter Kalender: Zeit und Titel sind hier nicht änderbar.") }
        return nil
    }

    // MARK: Lunch

    @ViewBuilder
    private func lunchContent(day: PlanDay, range: Range<Int>) -> some View {
        Section {
            Text("Mittagspause").font(.headline)
            Text(model.hasOwnLunch(on: day) ? "Nur an diesem Tag geändert" : "Standard aus den Einstellungen")
                .foregroundStyle(.secondary)
        }
        Section {
            DatePicker("Beginn", selection: lunchStart(range, on: day), displayedComponents: .hourAndMinute)
            ValueStepper("Dauer", value: lunchDuration(range, on: day), in: 15...max(15, 24 * 60 - range.lowerBound), step: 15,
                         kind: .durationMinutes, unit: "min", appliesWhileTyping: false, display: CapacityText.duration)
        } footer: {
            Text("Änderungen gelten nur für diesen Tag.")
        }
        Section {
            if model.hasOwnLunch(on: day) {
                Button("Für alle Tage übernehmen") { Task { await model.applyLunchToAllDays(from: day) } }
                Button("Standard wiederherstellen") { Task { await model.resetLunch(on: day) } }
            }
            Button("Heute keine Pause", role: .destructive) {
                Task { await model.removeLunch(on: day) }
                dismiss()
            }
        }
    }

    // MARK: Helpers

    private func stepRow(_ title: String, value: String, enabled: Bool, step: @escaping (Int) -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button { step(-15) } label: { Image(systemName: "minus") }
                .buttonStyle(.bordered).disabled(!enabled).accessibilityLabel("\(title) 15 Minuten früher oder kürzer")
            Text(value).monospacedDigit().frame(minWidth: 64)
            Button { step(15) } label: { Image(systemName: "plus") }
                .buttonStyle(.bordered).disabled(!enabled).accessibilityLabel("\(title) 15 Minuten später oder länger")
        }
    }

    private func minutesRange(_ event: CalendarEvent) -> Range<Int> {
        let dayStart = PlanDay(date: event.start, calendar: model.calendar).startDate(in: model.calendar)
        let start = Int(event.start.timeIntervalSince(dayStart) / 60)
        return start..<(start + max(15, Int(event.end.timeIntervalSince(event.start) / 60)))
    }

    /// The start of the lunch break as a time of day for the time picker; a change moves the break and keeps its length.
    private func lunchStart(_ range: Range<Int>, on day: PlanDay) -> Binding<Date> {
        let calendar = Calendar.tagwerk
        return Binding(
            get: { calendar.date(bySettingHour: range.lowerBound / 60, minute: range.lowerBound % 60, second: 0, of: .now) ?? .now },
            set: { date in
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                let start = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                Task { await model.setLunch(startMinutes: start, minutes: range.count, on: day) }
            }
        )
    }

    /// The length of the lunch break; a change keeps its start.
    private func lunchDuration(_ range: Range<Int>, on day: PlanDay) -> Binding<Int> {
        Binding(
            get: { range.count },
            set: { minutes in Task { await model.setLunch(startMinutes: range.lowerBound, minutes: minutes, on: day) } }
        )
    }

    private func timeText(_ event: CalendarEvent) -> String {
        if event.isAllDay { return String(localized: "\(event.start.formatted(date: .complete, time: .omitted)) · ganztägig") }
        return event.start.formatted(date: .complete, time: .shortened) + " – " + event.end.formatted(date: .omitted, time: .shortened)
    }

    /// "Duplizieren" with its target (mockup DU1); disabled with a reason when the day has no free stretch.
    @ViewBuilder
    private func duplicateRow(_ event: CalendarEvent) -> some View {
        if let target = model.duplicateTarget(for: event) {
            Button {
                Task { await model.duplicateBlock(event); dismiss() }
            } label: {
                LabeledContent("Duplizieren", value: "\(DateText.time(minutes: target.lowerBound, calendar: model.calendar)) · \(CapacityText.duration(target.count))")
            }
        } else {
            LabeledContent("Duplizieren", value: String(localized: "kein freier Platz mehr"))
                .foregroundStyle(.secondary)
        }
    }

    private func originText(_ event: CalendarEvent) -> String {
        switch model.linkOrigin(eventID: event.id) {
        case .url?: String(localized: "Tagwerk-Block")
        case .manual?: String(localized: "manuell verknüpft")
        case .automatic?: String(localized: "automatisch erkannt")
        case nil: ""
        }
    }
}

/// Picks a task to link an event to.
struct TaskLinkPicker: View {
    let model: PlanningModel
    let eventID: String
    let onDone: () -> Void
    @State private var search = ""

    var body: some View {
        List(filtered) { task in
            Button(task.title) {
                Task {
                    await model.link(eventID: eventID, to: task.id)
                    onDone()
                }
            }
            .foregroundStyle(.primary)
        }
        .scrollDismissesKeyboard(.interactively)
        .searchable(text: $search, prompt: "Aufgabe suchen")
        .navigationTitle("Aufgabe wählen")
    }

    private var filtered: [TaskItem] {
        let open = sortedTasks(model.taskList.items.filter { !$0.isCompleted }, calendar: model.calendar)
        guard !search.isEmpty else { return open }
        return open.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }
}
