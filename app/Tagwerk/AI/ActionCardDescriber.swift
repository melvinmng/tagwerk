import AIKit
import Foundation
import GitHubKit
import TagwerkCore

/// The texts of action cards: what an AI function call would change, in words (mockup e). The assistant chat and the
/// suggestions of a thoughts note (phase 7) show the same cards, so the wording lives here once.
@MainActor
struct ActionCardDescriber {
    let planning: PlanningModel
    /// GitHub catalog and login for the issue card; `nil` while GitHub is not signed in.
    var gitHubDirectory: () -> (any GitHubDirectory)? = { nil }
    /// Name of an open shopping item by its id, for the card of `update_shopping`.
    var shoppingItemName: (String) -> String? = { _ in nil }
    /// An issue of the last GitHub search by task key, for the card of `assign_task` on an issue outside the user's tasks.
    var foundIssue: (String) -> OnlineIssue? = { _ in nil }
    /// Names repository and projects of an issue in the card text. The suggestions of a note show the target in a row of
    /// their own (it can be changed there), so their text leaves it out.
    var showsIssueTarget = true
    /// The notes the assistant may see, for the cards of the note tools; `nil` where there are none.
    var noteAccess: NoteToolAccess?
    /// The folder the notes chat was opened from; a new note goes there when the model names no folder.
    var noteDefaultFolderID: () -> UUID? = { nil }
    /// False for a card that was answered: it then carries no `detail` and no summary of the text (the note holds it already).
    var isOpen = true

    /// `spoken`: the card is read aloud; texts then avoid symbols that speech drops (the screen keeps them).
    func describe(_ call: ToolCall, language: VoiceLanguage = .app, spoken: Bool = false) -> AssistantModel.ActionCard {
        let args = (try? JSONSerialization.jsonObject(with: call.arguments) as? [String: Any]) ?? [:]
        func string(_ key: String) -> String? { (args[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        func text(_ key: String.LocalizationValue) -> String { Localized.string(key, in: language, bundle: .main) }
        let task = string("id").flatMap { id in planning.taskList.items.first { $0.id.key == id } }
        let title = task?.title ?? string("title") ?? text("Änderung")
        func dayText(_ value: String?) -> String {
            guard let value, let day = AIPlanner.planDay(String(value.prefix(10))) else { return text("keine") }
            return day.startDate(in: planning.calendar)
                .formatted(Date.FormatStyle(locale: AssistantModel.formatLocale(language)).weekday(.abbreviated).day().month())
        }
        func duration(_ minutes: Int) -> String { CapacityText.duration(minutes) }
        switch call.name {
        case "create_task" where string("source") == "github":
            var parts = [text("Issue anlegen")] + (showsIssueTarget ? issueTarget(args, text: text) : [])
            if let due = string("due") { parts.append(text("fällig \(dayText(due))")) }
            if let priority = string("priority") { parts.append(priority) }
            // Everyone the issue goes to is named in full before the user confirms.
            let people = issueAssignment(args["assignees"] as? [String], language: language, text: text)
            let notes = string("notes").map { "\n" + text("Notizen: „\($0)“") } ?? ""
            if !showsIssueTarget { return AssistantModel.ActionCard(title: title, change: (parts + [people]).joined(separator: " · ") + notes) }
            return AssistantModel.ActionCard(title: title, change: parts.joined(separator: " · ") + "\n" + people + notes)
        case "create_task":
            var parts = [text("Neue Aufgabe")]
            if let source = string("source") { parts.append(source == "github" ? text("als GitHub-Issue") : source) }
            if let due = string("due") { parts.append(text("fällig \(dayText(due))")) }
            if let priority = string("priority") { parts.append(priority) }
            // Everything that is written is shown in full before the user confirms.
            let notes = string("notes").map { "\n" + text("Notizen: „\($0)“") } ?? ""
            return AssistantModel.ActionCard(title: title, change: parts.joined(separator: " · ") + notes)
        case "update_task":
            var changes: [String] = []
            if let newTitle = string("title") { changes.append(text("Titel → \(newTitle)")) }
            if let due = string("due") {
                changes.append(text("Fälligkeit: \(dayText(task?.due.map { AppTools.dueString($0) })) → \(dayText(due))"))
            }
            if let priority = string("priority") { changes.append(text("Priorität: \(task?.priority?.label ?? "–") → \(priority)")) }
            if let minutes = args["minutes"] as? Int { changes.append(text("Aufwand → \(duration(minutes))")) }
            if let notes = string("notes") { changes.append(text("Notizen → „\(notes)“")) }
            return AssistantModel.ActionCard(title: title, change: changes.isEmpty ? text("Ändern") : changes.joined(separator: " · "))
        case "reschedule_task":
            return AssistantModel.ActionCard(title: title,
                              change: text("Fälligkeit: \(dayText(task?.due.map { AppTools.dueString($0) })) → \(dayText(string("due")))"))
        case "complete_task":
            return AssistantModel.ActionCard(title: title, change: text("Als erledigt markieren"))
        case "assign_to_day":
            let current = task.flatMap { planning.planStore.assignment(for: $0.id) }.map(AIPlanner.dayString)
            return AssistantModel.ActionCard(title: title, change: text("Verschieben: \(dayText(current)) → \(dayText(string("day")))"))
        case "create_time_block":
            let start = string("start") ?? ""
            if let minutes = args["minutes"] as? Int {
                return AssistantModel.ActionCard(title: title, change: text("Zeitblock \(dayText(string("day"))) · \(start) · \(duration(minutes))"))
            }
            return AssistantModel.ActionCard(title: title, change: text("Zeitblock \(dayText(string("day"))) · \(start)"))
        case "link_event_to_task":
            let linked = string("task_id").flatMap { id in planning.taskList.items.first { $0.id.key == id }?.title } ?? text("Aufgabe")
            return AssistantModel.ActionCard(title: linked, change: text("Termin mit dieser Aufgabe verknüpfen"))
        case "set_day_hours":
            let day = string("day")
            if args["off"] as? Bool == true { return AssistantModel.ActionCard(title: text("Arbeitszeit"), change: text("\(dayText(day)): frei")) }
            let current = day.flatMap { AIPlanner.planDay($0) }.flatMap { planning.workHours(on: $0) }
                .map { "\(AIPlanner.time($0.startMinutes))–\(AIPlanner.time($0.endMinutes))" } ?? text("frei")
            return AssistantModel.ActionCard(title: text("Arbeitszeit \(dayText(day))"), change: "\(current) → \(string("start") ?? "")–\(string("end") ?? "")")
        case "set_lunch":
            let minutes = args["minutes"] as? Int ?? 0
            return AssistantModel.ActionCard(title: text("Mittagspause \(dayText(string("day")))"),
                              change: minutes > 0 ? "\(string("start") ?? "") · \(duration(minutes))" : text("Keine Pause"))
        case "mark_events_free":
            let count = (args["event_ids"] as? [String])?.count ?? 0
            let free = args["free"] as? Bool ?? true
            let change = free ? text("Auf Frei setzen") : text("Auf Belegt setzen")
            let series = args["series"] as? Bool == true ? " · " + text("auch alle künftigen") : ""
            return AssistantModel.ActionCard(title: text("\(count) Termine"), change: change + series)
        case "plan_period":
            let scope = string("scope").flatMap(PlanScope.init(rawValue:)) ?? .day
            let action = switch scope {
            case .day: text("Tag planen")
            case .week: text("Woche planen")
            case .month: text("Monat planen")
            }
            return AssistantModel.ActionCard(title: action, change: text("Vorschläge in der Planen-Ansicht anlegen"))
        case "add_comment":
            return AssistantModel.ActionCard(title: title, change: text("Kommentar: „\(string("body") ?? "")“"))
        case "update_shopping":
            // One card for every change of the call: what is added (with quantity) and what is checked off.
            let additions = (args["add"] as? [[String: Any]] ?? []).compactMap { entry -> String? in
                guard let name = entry["name"] as? String, !name.isEmpty else { return nil }
                return [entry["quantity"] as? String, name].compactMap { $0 }.joined(separator: " ")
            }
            let checks = (args["check_off"] as? [String] ?? []).map { shoppingItemName($0) ?? $0 }
            guard spoken else {
                let marks = additions.map { "＋ " + $0 } + checks.map { "✓ " + $0 }
                return AssistantModel.ActionCard(title: text("Einkaufsliste ändern"), change: marks.joined(separator: " · "))
            }
            // Announced cards lose decorative symbols when spoken, so adding and checking off are named in words.
            var parts: [String] = []
            if !additions.isEmpty { parts.append(text("Hinzufügen: \(additions.joined(separator: ", "))")) }
            if !checks.isEmpty { parts.append(text("Abhaken: \(checks.joined(separator: ", "))")) }
            return AssistantModel.ActionCard(title: text("Einkaufsliste ändern"), change: parts.joined(separator: " · "))
        case "assign_task":
            // An issue outside the user's tasks comes from the last GitHub search.
            let found = task == nil ? string("id").flatMap(foundIssue) : nil
            return describeAssignment(task: task, found: found, args: args, title: found?.title ?? title, language: language, spoken: spoken)
        case "create_note", "update_note", "delete_note":
            return describeNote(call.name, args: args, language: language, spoken: spoken)
        case "create_event", "update_event", "delete_event":
            return describeEvent(call.name, series: args["series"] as? Bool == true, language: language, string: string)
        default:
            return AssistantModel.ActionCard(title: title, change: call.name)
        }
    }

    /// Cards for calendar events (issue #118): what is written, in which calendar, and whether it fits.
    /// Repository and projects of an issue card. `null` arguments resolve like the execution does, from the
    /// stored catalog; what cannot be resolved is named as missing (the execution then reports the error).
    private func issueTarget(_ args: [String: Any], text: (String.LocalizationValue) -> String) -> [String] {
        let repository = (args["repository"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let projectIDs = args["project_ids"] as? [String]
        // An explicitly empty list is a choice ("Kein Projekt"), not a gap.
        let missingProject = projectIDs?.isEmpty == true ? text("Kein Projekt") : text("Projekt fehlt")
        guard let catalog = gitHubDirectory()?.storedCatalog else {
            return [repository ?? text("Repository fehlt"), missingProject]
        }
        func titles(_ ids: [String]) -> String? {
            let found = ids.compactMap { id in catalog.projects.first { $0.id == id }?.title }
            return found.count == ids.count && !found.isEmpty ? text("Projekt \(found.joined(separator: ", "))") : nil
        }
        switch AppTools.gitHubTarget(repository: repository, projectIDs: projectIDs, catalog: catalog) {
        case .success(let target):
            return [target.repository, titles(target.projectIDs) ?? missingProject]
        case .failure(.repositoryMissing), .failure(.repositoryUnknown):
            return [text("Repository fehlt"), projectIDs.flatMap(titles) ?? missingProject]
        case .failure(.projectMissing), .failure(.projectUnknown):
            let known = repository.flatMap { name in catalog.repositories.first { $0.lowercased() == name.lowercased() } }
            return [known ?? catalog.repositories.first ?? text("Repository fehlt"), missingProject]
        }
    }

    /// "Zugewiesen: dir", "Zugewiesen: dir und lea-m", "Zugewiesen: lea-m (nicht dir)", "Niemandem zugewiesen".
    /// Always every login, never a count.
    private func issueAssignment(_ assignees: [String]?, language: VoiceLanguage,
                                 text: (String.LocalizationValue) -> String) -> String {
        guard let assignees else { return text("Zugewiesen: \(text("dir"))") }
        if assignees.isEmpty { return text("Niemandem zugewiesen") }
        let me = gitHubDirectory()?.login
        let names = AssigneeSelection.names(selected: assignees, me: me, summarize: false, language: language)
        let includesMe = assignees.contains { AssigneeSelection.isMe($0, me: me) }
        return includesMe ? text("Zugewiesen: \(names)") : text("Zugewiesen: \(names) (nicht dir)")
    }

    /// Card of `assign_task` (mockups ZU1a, ZU2): who is assigned before and after, and for a hand-over what it costs.
    /// The plan comes from the same function as the execution; when the issue is not loaded any more (or the change
    /// cannot be resolved) the card lists the requested change and the execution reports what is wrong.
    private func describeAssignment(task: TaskItem?, found: OnlineIssue?, args: [String: Any], title: String, language: VoiceLanguage,
                                    spoken: Bool) -> AssistantModel.ActionCard {
        func text(_ key: String.LocalizationValue) -> String { Localized.string(key, in: language, bundle: .main) }
        let me = gitHubDirectory()?.login
        let add = args["add"] as? [String] ?? [], remove = args["remove"] as? [String] ?? []
        func names(_ logins: [String]) -> String { AssigneeSelection.names(selected: logins, me: me, summarize: false, language: language) }
        func spokenNames(_ logins: [String]) -> String {
            let parts = logins.map { AssigneeSelection.isMe($0, me: me) ? text("du") : $0 }
            return parts.formatted(.list(type: .and).locale(AssistantModel.formatLocale(language)))
        }
        func requested() -> String {
            guard spoken else {
                var parts: [String] = []
                if !add.isEmpty { parts.append("＋ " + names(add)) }
                if !remove.isEmpty { parts.append("− " + names(remove)) }
                return text("Zuweisung ändern: \(parts.joined(separator: " · "))")
            }
            var parts: [String] = []
            if !add.isEmpty { parts.append(text("\(spokenNames(add)) dazu")) }
            if !remove.isEmpty { parts.append(text("\(spokenNames(remove)) nicht mehr")) }
            return text("Zuweisung ändern: \(parts.joined(separator: ", "))")
        }

        // An issue outside the lists is named by repository and number; nothing is planned for it, so no consequences.
        let location = found.map { "\($0.repository) #\($0.number)" }
        func prefixed(_ line: String) -> String {
            guard let location else { return line }
            return spoken ? location + ". " + line : location + "\n" + line
        }
        guard let current = task?.assignees ?? found?.assignees ?? (task == nil ? nil : [String]()),
              case .success(let plan) = AppTools.assignmentPlan(current: current, add: add, remove: remove, me: me) else {
            return AssistantModel.ActionCard(title: title, change: prefixed(requested()))
        }
        // Only an issue of the user's lists is handed over; an issue found by the search was never in them.
        let handsOver = task != nil && plan.handsOver
        let warning = handsOver
            ? task.flatMap { task in
                TaskEditorModel.handOverMessage(number: task.issueNumber, futureBlocks: planning.futureBlockCount(for: task.id),
                                                leavesUnassigned: plan.after.isEmpty)
            }
            : nil
        let before = plan.before.isEmpty ? text("niemand") : names(plan.before)
        let after: String
        if plan.after.isEmpty {
            after = text("niemand")
        } else if handsOver {
            after = text("\(names(plan.after)) (nicht mehr dir)")
        } else {
            after = names(plan.after)
        }
        var change = spoken ? requested() : text("Zugewiesen: \(before) → \(after)")
        // By voice the card is the only place that names the consequences, so they are read out as well.
        if spoken, let warning { change += ". " + warning }
        return AssistantModel.ActionCard(title: title, change: prefixed(change), warning: spoken ? nil : warning,
                                         confirmTitle: handsOver ? text("Abgeben") : nil, isDestructive: handsOver)
    }

    private func describeEvent(_ name: String, series: Bool, language: VoiceLanguage,
                                   string: (String) -> String?) -> AssistantModel.ActionCard {
        func text(_ key: String.LocalizationValue) -> String { Localized.string(key, in: language, bundle: .main) }
        let calendar = planning.calendar
        let existing = string("event_id").flatMap { planning.event(id: $0) }
        let seriesText = series ? " · " + text("auch alle künftigen") : ""
        let dayStyle = Date.FormatStyle(locale: AssistantModel.formatLocale(language)).weekday(.abbreviated).day().month()
        let timeStyle = Date.FormatStyle(locale: AssistantModel.formatLocale(language)).hour().minute()
        func parse(_ value: String?) -> (date: Date, timed: Bool)? {
            guard let value, let day = AIPlanner.planDay(String(value.prefix(10))) else { return nil }
            var components = DateComponents(year: day.year, month: day.month, day: day.day)
            let timed = value.count > 10
            if timed, let minutes = AIPlanner.minutes(String(value.dropFirst(11))) {
                components.hour = minutes / 60
                components.minute = minutes % 60
            }
            return calendar.date(from: components).map { ($0, timed) }
        }
        func when(start: Date, end: Date, allDay: Bool) -> String {
            let day = start.formatted(dayStyle)
            if allDay {
                let last = calendar.date(byAdding: .day, value: -1, to: end) ?? end
                if calendar.isDate(start, inSameDayAs: last) { return text("\(day) · ganztägig") }
                return text("\(day) bis \(last.formatted(dayStyle)) · ganztägig")
            }
            return text("\(day) · \(start.formatted(timeStyle)) bis \(end.formatted(timeStyle))")
        }
        func calendarName(_ id: String?) -> String {
            let id = id ?? planning.defaultEventCalendarID ?? ""
            return planning.calendarTitle(id).map { text("Kalender \($0)") } ?? text("Kalender")
        }
        func fit(_ start: Date, _ end: Date, excluding id: String?) -> String {
            switch planning.overlap(start: start, end: end, excluding: id) {
            case .none: text("passt in die freie Zeit")
            case .one(let title): text("überschneidet „\(title)“")
            case .several(let count): text("überschneidet \(count) Termine")
            }
        }
        switch name {
        case "create_event":
            guard let start = parse(string("start")), let endValue = parse(string("end")) else {
                return AssistantModel.ActionCard(title: string("title") ?? text("Termin"), change: text("Termin anlegen"))
            }
            let allDay = !start.timed
            let end = allDay ? (calendar.date(byAdding: .day, value: 1, to: endValue.date) ?? endValue.date) : endValue.date
            var parts = [text("Termin anlegen"), when(start: start.date, end: end, allDay: allDay), calendarName(string("calendar_id"))]
            if !allDay { parts.append(fit(start.date, end, excluding: nil)) }
            if let location = string("location") { parts.append(location) }
            let notes = string("notes").map { "\n" + text("Notizen: „\($0)“") } ?? ""
            return AssistantModel.ActionCard(title: string("title") ?? text("Termin"), change: parts.joined(separator: " · ") + notes)
        case "update_event":
            guard let existing else { return AssistantModel.ActionCard(title: text("Termin"), change: text("Termin ändern")) }
            var changes: [String] = []
            if let title = string("title") { changes.append(text("Titel → \(title)")) }
            if string("start") != nil || string("end") != nil {
                let length = existing.end.timeIntervalSince(existing.start)
                let start = parse(string("start"))?.date ?? existing.start
                var end = parse(string("end"))?.date ?? start.addingTimeInterval(length)
                if existing.isAllDay, string("end") != nil { end = calendar.date(byAdding: .day, value: 1, to: end) ?? end }
                changes.append("\(when(start: existing.start, end: existing.end, allDay: existing.isAllDay)) → \(when(start: start, end: end, allDay: existing.isAllDay))")
                if !existing.isAllDay { changes.append(fit(start, end, excluding: existing.id)) }
            }
            if let id = string("calendar_id") { changes.append("\(calendarName(existing.calendarID)) → \(calendarName(id))") }
            if let location = string("location") { changes.append(text("Ort → \(location)")) }
            if let notes = string("notes") { changes.append(text("Notizen → „\(notes)“")) }
            return AssistantModel.ActionCard(title: existing.title, change: ([text("Termin ändern")] + changes).joined(separator: " · ") + seriesText)
        default:
            guard let existing else { return AssistantModel.ActionCard(title: text("Termin"), change: text("Termin löschen")) }
            return AssistantModel.ActionCard(title: existing.title,
                              change: text("Termin löschen · \(when(start: existing.start, end: existing.end, allDay: existing.isAllDay))") + seriesText)
        }
    }
}
