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
    @State private var editing = false
    @State private var movingDay = false
    @State private var askingDelete = false
    @State private var pendingSeriesChange: SeriesChange?

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
            Form {
                switch current {
                case .lunch(let day, let range): lunchContent(day: day, range: range)
                case .event(let event, let taskID): eventContent(event, taskID: taskID)
                }
            }
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
        Section {
            Text(event.title).font(.headline)
            Text(timeText(event)).foregroundStyle(.secondary)
            if let calendar = model.calendarTitle(event.calendarID) {
                LabeledContent("Kalender", value: calendar + (event.isEditable ? "" : " 🔒"))
            }
            if event.isRecurring { Label("Wiederholt sich", systemImage: "arrow.trianglehead.2.clockwise").foregroundStyle(.secondary) }
            if let location = event.location, !location.isEmpty { LabeledContent("Ort", value: location) }
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
        .sheet(isPresented: $editing) {
            EventEditSheet(model: model, existing: event, day: PlanDay(date: event.start, calendar: model.calendar))
        }
        .sheet(isPresented: $movingDay) { BlockDaySheet(block: event, model: model) }
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
            stepRow("Beginn", value: clock(range.lowerBound, day: day), enabled: true) { step in
                Task { await model.setLunch(startMinutes: range.lowerBound + step, minutes: range.count, on: day) }
            }
            stepRow("Dauer", value: CapacityText.duration(range.count), enabled: true) { step in
                Task { await model.setLunch(startMinutes: range.lowerBound, minutes: max(15, range.count + step), on: day) }
            }
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

    private func clock(_ minutes: Int, day: PlanDay) -> String {
        day.startDate(in: model.calendar).addingTimeInterval(TimeInterval(minutes * 60)).formatted(date: .omitted, time: .shortened)
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
        .searchable(text: $search, prompt: "Aufgabe suchen")
        .navigationTitle("Aufgabe wählen")
    }

    private var filtered: [TaskItem] {
        let open = sortedTasks(model.taskList.items.filter { !$0.isCompleted }, calendar: model.calendar)
        guard !search.isEmpty else { return open }
        return open.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }
}
