import AIKit
import Observation
import RemindersKit
import SwiftUI
import TagwerkCore

/// Editor for `create_event`, `update_event` and `create_time_block` (plan ki-vorschlaege-anpassen, task B2).
///
/// The fields are those of the event sheet: title, all day, start, end, calendar, location and note. A time block has
/// day, start and duration; the task it belongs to is not editable and stays as it is. `update_event` writes `null` for
/// everything that stays unchanged, so a field the user did not touch keeps its `null`. The calendars offered are the
/// writable ones, the same list the function checks against, and the function still refuses an event that cannot be
/// changed (`editableEvent`), whatever the user wrote here.
@MainActor
@Observable
final class EventProposalEditor: ProposalEditor {
    nonisolated static let toolNames: Set<String> = ["create_event", "update_event", "create_time_block"]

    enum Kind {
        case createEvent, updateEvent, timeBlock
    }

    private struct Draft: Equatable {
        var title = ""
        var notes = ""
        var location = ""
        var calendarID: String?
        var allDay = false
        var start: ProposalDue?
        var end: ProposalDue?
        var blockDay = PlanDay(year: 1970, month: 1, day: 1)
        var blockStart = 9 * 60
        var blockMinutes = 30
    }

    let kind: Kind
    let call: ToolCall
    let context: ProposalEditorContext

    var title = ""
    var notes = ""
    var location = ""
    var calendarID: String?
    private(set) var allDay = false
    var start: ProposalDue?
    var end: ProposalDue?
    var blockDay: PlanDay
    var blockStart = 9 * 60
    var blockMinutes = 30

    @ObservationIgnored private let base: [String: Any]
    @ObservationIgnored private let initial: Draft

    required init?(call: ToolCall, context: ProposalEditorContext) {
        guard Self.toolNames.contains(call.name), let base = ProposalArguments.decode(call.arguments) else { return nil }
        self.call = call
        self.context = context
        self.base = base
        switch call.name {
        case "create_event": kind = .createEvent
        case "update_event": kind = .updateEvent
        default: kind = .timeBlock
        }
        func text(_ key: String) -> String? { (base[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        var draft = Draft()
        draft.title = text("title") ?? ""
        draft.notes = text("notes") ?? ""
        draft.location = text("location") ?? ""
        draft.calendarID = text("calendar_id")
        let today = PlanDay(date: context.now(), calendar: context.calendar)
        switch kind {
        case .createEvent:
            draft.allDay = base["all_day"] as? Bool ?? false
            let timed = !draft.allDay
            func moment(_ key: String, fallbackMinutes: Int) -> ProposalDue {
                let parsed = ProposalArguments.dayAndTime(text(key))
                return ProposalDue(day: parsed?.day ?? today, minutes: timed ? (parsed?.minutes ?? fallbackMinutes) : nil)
            }
            draft.start = moment("start", fallbackMinutes: 9 * 60)
            draft.end = moment("end", fallbackMinutes: 10 * 60)
        case .updateEvent:
            draft.allDay = base["all_day"] as? Bool ?? false
            func moment(_ key: String) -> ProposalDue? {
                ProposalArguments.dayAndTime(text(key)).map { ProposalDue(day: $0.day, minutes: draft.allDay ? nil : $0.minutes) }
            }
            draft.start = moment("start")
            draft.end = moment("end")
        case .timeBlock:
            draft.blockDay = ProposalArguments.dayAndTime(text("day"))?.day ?? today
            draft.blockStart = text("start").flatMap(AIPlanner.minutes) ?? 9 * 60
            draft.blockMinutes = (base["minutes"] as? NSNumber)?.intValue ?? 30
        }
        initial = draft
        title = draft.title
        notes = draft.notes
        location = draft.location
        calendarID = draft.calendarID
        allDay = draft.allDay
        start = draft.start
        end = draft.end
        blockDay = draft.blockDay
        blockStart = draft.blockStart
        blockMinutes = draft.blockMinutes
    }

    /// The calendars offered; a calendar the call already names stays selectable.
    var calendars: [ListInfo] {
        let writable = context.writableCalendars()
        guard let calendarID, !writable.contains(where: { $0.id == calendarID }) else { return writable }
        return writable + [ListInfo(id: calendarID, title: calendarID, colorHex: nil, kind: .other)]
    }

    /// Switching "Ganztägig" turns the moments into days or gives them a time again.
    func setAllDay(_ isOn: Bool) {
        guard kind == .createEvent, isOn != allDay else { return }
        allDay = isOn
        if allDay {
            start?.minutes = nil
            end?.minutes = nil
        } else {
            if start?.minutes == nil { start?.minutes = 9 * 60 }
            if end?.minutes == nil { end?.minutes = 10 * 60 }
        }
    }

    /// The end is not before the start (an all-day end is the last day, inclusive).
    var orderIsValid: Bool {
        guard let start, let end else { return true }
        return allDay ? end.orderingKey >= start.orderingKey : end.orderingKey > start.orderingKey
    }

    // MARK: ProposalEditor

    var isValid: Bool {
        switch kind {
        case .createEvent:
            return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && start != nil && end != nil && orderIsValid
        case .updateEvent: return orderIsValid
        case .timeBlock: return blockMinutes > 0
        }
    }

    func arguments() -> Data {
        var result = base
        func set(_ key: String, _ value: Any?) { result[key] = value ?? NSNull() }
        func trimmed(_ text: String) -> String? {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        func moment(_ due: ProposalDue?) -> String? { due.map { ProposalArguments.dueString(day: $0.day, minutes: $0.minutes) } }
        switch kind {
        case .createEvent, .updateEvent:
            if title != initial.title { set("title", trimmed(title)) }
            if notes != initial.notes { set("notes", trimmed(notes)) }
            if location != initial.location { set("location", trimmed(location)) }
            if calendarID != initial.calendarID { set("calendar_id", calendarID) }
            if kind == .createEvent, allDay != initial.allDay { set("all_day", allDay) }
            if start != initial.start { set("start", moment(start)) }
            if end != initial.end { set("end", moment(end)) }
        case .timeBlock:
            if blockDay != initial.blockDay { set("day", AIPlanner.dayString(blockDay)) }
            if blockStart != initial.blockStart { set("start", AIPlanner.time(blockStart)) }
            if blockMinutes != initial.blockMinutes { set("minutes", blockMinutes) }
        }
        return ProposalArguments.encode(result)
    }

    var fields: AnyView { AnyView(EventProposalFields(editor: self)) }

    func load() async {}
}

private struct EventProposalFields: View {
    @Bindable var editor: EventProposalEditor

    private var calendar: Calendar { editor.context.calendar }
    private var isUpdate: Bool { editor.kind == .updateEvent }

    var body: some View {
        switch editor.kind {
        case .createEvent, .updateEvent:
            Section {
                TextField("Titel", text: $editor.title)
                if editor.kind == .createEvent { Toggle("Ganztägig", isOn: Binding(get: { editor.allDay }, set: { editor.setAllDay($0) })) }
                momentRows(title: "Beginn", changeTitle: "Beginn ändern", moment: $editor.start, fallback: 9 * 60)
                momentRows(title: "Ende", changeTitle: "Ende ändern", moment: $editor.end, fallback: 10 * 60)
            } footer: {
                if !editor.orderIsValid { Text("Das Ende liegt nicht nach dem Beginn.").foregroundStyle(.redText) }
            }
            Section {
                Picker("Kalender", selection: $editor.calendarID) {
                    Text(isUpdate ? "Unverändert" : "Standard").tag(String?.none)
                    ForEach(editor.calendars) { Text($0.title).tag(Optional($0.id)) }
                }
            } footer: {
                Text("Abonnierte Kalender, Feiertage und Geburtstage sind schreibgeschützt und fehlen hier.")
            }
            Section {
                TextField("Ort", text: $editor.location)
                TextField("Notiz", text: $editor.notes, axis: .vertical).keyboardDoneButton()
            } footer: {
                if isUpdate { Text("Felder, die du nicht änderst, bleiben unverändert.") }
            }
        case .timeBlock:
            Section {
                ProposalDayRow(title: "Tag", day: $editor.blockDay, calendar: calendar)
                ProposalTimeRow(title: "Beginn", minutes: $editor.blockStart, calendar: calendar)
                ValueStepper("Dauer", value: $editor.blockMinutes, in: 5...720, step: 5, kind: .durationMinutes,
                             display: { CapacityText.duration($0) })
            }
        }
    }

    /// A start or end: always shown for a new event, behind a switch for a change (`nil` leaves it as it is).
    @ViewBuilder
    private func momentRows(title: LocalizedStringKey, changeTitle: LocalizedStringKey, moment: Binding<ProposalDue?>, fallback: Int) -> some View {
        if isUpdate {
            Toggle(changeTitle, isOn: Binding(
                get: { moment.wrappedValue != nil },
                set: { isOn in
                    moment.wrappedValue = isOn ? ProposalDue(day: PlanDay(date: editor.context.now(), calendar: calendar),
                                                             minutes: editor.allDay ? nil : fallback) : nil
                }))
        }
        if let value = moment.wrappedValue {
            ProposalMomentRow(title: title, moment: Binding(get: { value }, set: { moment.wrappedValue = $0 }), calendar: calendar)
        }
    }
}
