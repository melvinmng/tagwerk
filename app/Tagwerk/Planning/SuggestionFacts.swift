import Foundation
import TagwerkCore

/// What a suggestion shows about its task at first glance (mockups VC1, VL1, VE1, VU1): priority mark,
/// due date with urgency, and effort as "this block of the total". Without a task only the duration remains.
struct SuggestionFacts: Equatable {
    /// Colour of a capsule: red for overdue and P1, orange for today and P2 (mockup VU1).
    enum Urgency: Equatable { case none, medium, high }

    struct Mark: Equatable {
        var text: String
        var urgency: Urgency
    }

    /// Effort bar of the sheet (mockup VT1): already planned (green), this suggestion (purple), open (grey).
    struct Bar: Equatable {
        var total: Int
        var planned: Int
        var suggested: Int
        var open: Int { max(0, total - planned - suggested) }
    }

    var priority: Mark?
    var due: Mark?
    /// Short form for narrow blocks: "seit 16.11.", "heute", "20.11.".
    var dueShort: String?
    /// "in 2 Tagen" for the sheet.
    var dueDistance: String?
    var effort: String?
    /// Short form for narrow blocks: "von 3 h".
    var effortShort: String?
    var bar: Bar?
    /// Moves: "nach Mo 23.", red when the target day lies after the due date.
    var moveTarget: Mark?

    var dueIsUrgent: Bool { due.map { $0.urgency != .none } ?? false }

    init(suggestion: PlanSuggestion, task: TaskItem?, effort: Int?, blocked: Int, today: PlanDay, now: Date, calendar: Calendar) {
        self.init(task: task, today: today, now: now, calendar: calendar)
        let total = task == nil ? nil : effort.flatMap { $0 > 0 ? $0 : nil }
        switch suggestion.kind {
        case .move:
            self.effort = total.map(CapacityText.duration)
            let late = task?.due.map { PlanDay(year: $0.year, month: $0.month, day: $0.day) < suggestion.day } ?? false
            let target = Self.weekdayDay(suggestion.day, calendar: calendar)
            moveTarget = Mark(text: String(localized: "nach \(target)"), urgency: late ? .high : .none)
        case .block, .assignment, .dayChange:
            let minutes = suggestion.minutes
            if let total, let minutes {
                self.effort = String(localized: "\(CapacityText.duration(minutes)) von \(CapacityText.duration(total))")
                effortShort = String(localized: "von \(CapacityText.duration(total))")
                bar = Bar(total: total, planned: blocked, suggested: minutes)
            } else if let total {
                self.effort = CapacityText.duration(total)
            } else {
                self.effort = minutes.map(CapacityText.duration)
            }
        }
    }

    init(unscheduled: UnscheduledTask, task: TaskItem?, effort: Int?, blocked: Int, today: PlanDay, now: Date, calendar: Calendar) {
        self.init(task: task, today: today, now: now, calendar: calendar)
        if let effort, effort > 0 {
            self.effort = String(localized: "\(CapacityText.duration(max(0, effort - blocked))) offen")
        }
    }

    private init(task: TaskItem?, today: PlanDay, now: Date, calendar: Calendar) {
        if let priority = task?.priority {
            let urgency: Urgency = priority == .p1 ? .high : priority == .p2 ? .medium : .none
            self.priority = Mark(text: priority.label, urgency: urgency)
        }
        guard let due = task?.due else { return }
        let day = PlanDay(year: due.year, month: due.month, day: due.day)
        let date = day.startDate(in: calendar)
        let short = DateText.numericDay(day, calendar: calendar)
        let offset = calendar.dateComponents([.day], from: today.startDate(in: calendar), to: date).day ?? 0
        switch offset {
        case ..<0:
            self.due = Mark(text: String(localized: "überfällig seit \(short)"), urgency: .high)
            dueShort = String(localized: "seit \(short)")
            dueDistance = offset == -1 ? String(localized: "seit gestern") : String(localized: "seit \(-offset) Tagen")
        case 0:
            self.due = Mark(text: DueText.text(due, now: now, calendar: calendar), urgency: .medium)
            dueShort = String(localized: "heute")
            dueDistance = String(localized: "heute")
        case 1:
            self.due = Mark(text: String(localized: "morgen"), urgency: .none)
            dueShort = String(localized: "morgen")
            dueDistance = String(localized: "morgen")
        default:
            self.due = Mark(text: String(localized: "fällig \(Self.weekday(day, calendar: calendar)) \(short)"), urgency: .none)
            dueShort = short
            dueDistance = String(localized: "in \(offset) Tagen")
        }
    }
}

extension SuggestionFacts {
    /// "Mo 23.": weekday and day of the month, in the order of the language.
    static func weekdayDay(_ day: PlanDay, calendar: Calendar) -> String {
        String(localized: "\(weekday(day, calendar: calendar)) \(day.day).")
    }

    /// "Mo", "Fr": the short weekday without a dot.
    static func weekday(_ day: PlanDay, calendar: Calendar) -> String {
        day.startDate(in: calendar).formatted(.dateTime.weekday(.abbreviated).locale(calendar.locale ?? .current))
            .replacingOccurrences(of: ".", with: "")
    }
}

extension PlanningModel {
    /// The facts of a suggestion's task from the loaded task list; effort and planned minutes for the
    /// suggestion's day.
    func facts(for suggestion: PlanSuggestion) -> SuggestionFacts {
        let task = taskList.items.first { $0.id.key == suggestion.taskKey }
        return SuggestionFacts(suggestion: suggestion, task: task, effort: task.flatMap { effortMinutes(of: $0, on: suggestion.day) },
                               blocked: task.map { blockedMinutes(of: $0.id, on: suggestion.day) } ?? 0,
                               today: today, now: now(), calendar: calendar)
    }

    func facts(for entry: UnscheduledTask) -> SuggestionFacts {
        let task = taskList.items.first { $0.id.key == entry.taskKey }
        return SuggestionFacts(unscheduled: entry, task: task, effort: task.flatMap { effortMinutes(of: $0) },
                               blocked: task.map { blockedMinutes(of: $0.id) } ?? 0,
                               today: today, now: now(), calendar: calendar)
    }
}
