import AIKit
import Observation
import SwiftUI
import TagwerkCore

/// Editor for `set_day_hours`, `set_lunch` and `plan_period` (plan ki-vorschlaege-anpassen, task B2): the day, the
/// time fields of the working hours or the lunch break, and the period of a planning request.
@MainActor
@Observable
final class DayHoursProposalEditor: ProposalEditor {
    nonisolated static let toolNames: Set<String> = ["set_day_hours", "set_lunch", "plan_period"]

    enum Kind {
        case dayHours, lunch, planPeriod
    }

    private struct Draft: Equatable {
        var day = PlanDay(year: 1970, month: 1, day: 1)
        var off = false
        var start: Int?
        var end: Int?
        var hasLunch = true
        var lunchMinutes = 30
        var scope = PlanScope.day
    }

    let kind: Kind
    let call: ToolCall
    let context: ProposalEditorContext

    var day: PlanDay
    /// `set_day_hours`: the day is marked off instead of getting hours.
    private(set) var off = false
    var start: Int?
    var end: Int?
    /// `set_lunch`: false removes the break (minutes 0).
    private(set) var hasLunch = true
    var lunchMinutes = 30
    var scope = PlanScope.day

    @ObservationIgnored private let base: [String: Any]
    @ObservationIgnored private let initial: Draft

    required init?(call: ToolCall, context: ProposalEditorContext) {
        guard Self.toolNames.contains(call.name), let base = ProposalArguments.decode(call.arguments) else { return nil }
        self.call = call
        self.context = context
        self.base = base
        switch call.name {
        case "set_day_hours": kind = .dayHours
        case "set_lunch": kind = .lunch
        default: kind = .planPeriod
        }
        var draft = Draft()
        draft.day = ProposalArguments.dayAndTime(base["day"] as? String)?.day ?? PlanDay(date: context.now(), calendar: context.calendar)
        draft.off = base["off"] as? Bool ?? false
        draft.start = (base["start"] as? String).flatMap(AIPlanner.minutes)
        draft.end = (base["end"] as? String).flatMap(AIPlanner.minutes)
        let minutes = (base["minutes"] as? NSNumber)?.intValue ?? 0
        draft.hasLunch = minutes > 0
        draft.lunchMinutes = minutes > 0 ? minutes : 30
        draft.scope = (base["scope"] as? String).flatMap(PlanScope.init(rawValue:)) ?? .day
        initial = draft
        day = draft.day
        off = draft.off
        start = draft.start
        end = draft.end
        hasLunch = draft.hasLunch
        lunchMinutes = draft.lunchMinutes
        scope = draft.scope
    }

    /// "Frei": the day gets no working hours. Turning it off again offers usual hours when the call has none.
    func setOff(_ isOn: Bool) {
        guard kind == .dayHours, isOn != off else { return }
        off = isOn
        if !isOn {
            if start == nil { start = 8 * 60 }
            if end == nil { end = 17 * 60 }
        }
    }

    /// Turning the break on again offers midday when the call names no start.
    func setLunch(_ isOn: Bool) {
        guard kind == .lunch, isOn != hasLunch else { return }
        hasLunch = isOn
        if isOn, start == nil { start = 12 * 60 }
    }

    // MARK: ProposalEditor

    var isValid: Bool {
        switch kind {
        case .dayHours:
            guard !off else { return true }
            guard let start, let end else { return false }
            return start < end
        case .lunch: return !hasLunch || (start != nil && lunchMinutes > 0)
        case .planPeriod: return true
        }
    }

    /// What the validity rule says is wrong, for the footer; `nil` when the values are fine.
    var problem: String? {
        guard kind == .dayHours, !off, let start, let end, start >= end else { return nil }
        return String(localized: "Beginn und Ende sind ungültig.")
    }

    func arguments() -> Data {
        var result = base
        func set(_ key: String, _ value: Any?) { result[key] = value ?? NSNull() }
        func time(_ minutes: Int?) -> String? { minutes.map(AIPlanner.time) }
        if day != initial.day { set("day", AIPlanner.dayString(day)) }
        switch kind {
        case .dayHours:
            if off != initial.off || start != initial.start || end != initial.end {
                set("off", off)
                set("start", off ? nil : time(start))
                set("end", off ? nil : time(end))
            }
        case .lunch:
            if hasLunch != initial.hasLunch || start != initial.start || lunchMinutes != initial.lunchMinutes {
                set("minutes", hasLunch ? lunchMinutes : 0)
                set("start", hasLunch ? time(start) : nil)
            }
        case .planPeriod:
            if scope != initial.scope { set("scope", scope.rawValue) }
        }
        return ProposalArguments.encode(result)
    }

    var fields: AnyView { AnyView(DayHoursProposalFields(editor: self)) }

    func load() async {}
}

private struct DayHoursProposalFields: View {
    @Bindable var editor: DayHoursProposalEditor

    private var calendar: Calendar { editor.context.calendar }

    var body: some View {
        switch editor.kind {
        case .dayHours:
            Section {
                ProposalDayRow(title: "Tag", day: $editor.day, calendar: calendar)
                Toggle("Frei", isOn: Binding(get: { editor.off }, set: { editor.setOff($0) }))
                if !editor.off {
                    ProposalTimeRow(title: "Beginn", minutes: Binding(get: { editor.start ?? 8 * 60 }, set: { editor.start = $0 }),
                                    calendar: calendar)
                    ProposalTimeRow(title: "Ende", minutes: Binding(get: { editor.end ?? 17 * 60 }, set: { editor.end = $0 }),
                                    calendar: calendar)
                }
            } footer: {
                if let problem = editor.problem { Text(problem).foregroundStyle(.redText) }
            }
        case .lunch:
            Section {
                ProposalDayRow(title: "Tag", day: $editor.day, calendar: calendar)
                Toggle("Mittagspause", isOn: Binding(get: { editor.hasLunch }, set: { editor.setLunch($0) }))
                if editor.hasLunch {
                    ProposalTimeRow(title: "Beginn", minutes: Binding(get: { editor.start ?? 12 * 60 }, set: { editor.start = $0 }),
                                    calendar: calendar)
                    ValueStepper("Dauer", value: $editor.lunchMinutes, in: 5...240, step: 5, kind: .durationMinutes,
                                 display: { CapacityText.duration($0) })
                }
            }
        case .planPeriod:
            Section {
                Picker("Zeitraum", selection: $editor.scope) {
                    Text("Tag").tag(PlanScope.day)
                    Text("Woche").tag(PlanScope.week)
                    Text("Monat").tag(PlanScope.month)
                }
                ProposalDayRow(title: "Tag", day: $editor.day, calendar: calendar)
            }
        }
    }
}
