import AIKit
import Foundation
import Observation
import TagwerkCore

/// "Tag/Woche/Monat planen" with ChatGPT (design §8.2, §11.10).
///
/// The model gets the selected tasks and the days as JSON and answers in a strict JSON schema.
/// Every suggestion is checked locally; violations are sent back once, whatever still fails goes to
/// "Nicht eingeplant". Nothing is written to a calendar or a source before the user accepts.
@MainActor
@Observable
final class AIPlanner {
    enum State: Equatable {
        case idle
        case planning
        case failed(String)
    }

    static let invalidAnswerMessage = "Die Antwort von ChatGPT ließ sich nicht lesen. Versuche es erneut."
    static let nothingToPlanMessage = "Keine offenen Aufgaben zum Planen."
    static let modelFallbackMessage = "Das gewählte Modell gibt es nicht mehr. Tagwerk plant mit „Automatisch“."

    private(set) var state: State = .idle
    /// A one-line note after planning or accepting; the view clears it when shown.
    var notice: String?

    @ObservationIgnored private let responder: ResponseStreaming
    @ObservationIgnored private let model: @MainActor () async throws -> String
    @ObservationIgnored private let consumeModelFallback: @MainActor () -> Bool
    @ObservationIgnored private let planning: PlanningModel
    @ObservationIgnored private let store: SuggestionStore
    /// The last planning request, for "Erneut versuchen".
    @ObservationIgnored private var lastRequest: (scope: PlanScope, anchor: PlanDay, taskID: TaskID?)?

    init(responder: ResponseStreaming, model: @escaping @MainActor () async throws -> String, planning: PlanningModel,
         store: SuggestionStore, consumeModelFallback: @escaping @MainActor () -> Bool = { false }) {
        self.responder = responder
        self.model = model
        self.planning = planning
        self.store = store
        self.consumeModelFallback = consumeModelFallback
    }

    var isPlanning: Bool { state == .planning }

    // MARK: Planning

    /// Plans the period of `scope` around `anchor`; with `taskID` only that task ("Mit KI planen").
    func plan(scope: PlanScope, anchor: PlanDay, taskID: TaskID? = nil) async {
        guard !isPlanning else { return }
        lastRequest = (scope, anchor, taskID)
        notice = nil
        if planning.scope != scope || planning.anchor != anchor {
            planning.scope = scope
            planning.anchor = anchor
        }
        await planning.reload()
        let input = makeInput(scope: scope, only: taskID.map { [$0] })
        guard !input.tasks.isEmpty, !input.days.isEmpty else {
            notice = Self.nothingToPlanMessage
            return
        }
        state = .planning
        do {
            let model = try await model()
            if consumeModelFallback() { notice = Self.modelFallbackMessage }
            let inputText = String(decoding: try input.modelJSON(), as: UTF8.self)
            let firstText = try await answer(model: model, scope: scope, input: [.user(inputText)])
            var (accepted, violations) = validate(try decode(firstText, scope: scope), input: input)
            if !violations.isEmpty {
                // One follow-up with the violations; what still fails goes to "Nicht eingeplant".
                let retryText = try await answer(model: model, scope: scope, input: [
                    .user(inputText), .assistant(firstText), .user(Self.violationMessage(violations)),
                ])
                (accepted, violations) = validate(try decode(retryText, scope: scope), input: input)
            }
            store.replace(with: makeBatch(scope: scope, input: input, output: accepted, violations: violations))
            await planning.reload()
            state = .idle
        } catch let error as ChatGPTError {
            state = .failed(error.userMessage)
        } catch is DecodingError {
            state = .failed(Self.invalidAnswerMessage)
        } catch {
            state = .failed(Self.invalidAnswerMessage)
        }
    }

    func retry() async {
        guard case .failed = state, let request = lastRequest else { return }
        state = .idle
        await plan(scope: request.scope, anchor: request.anchor, taskID: request.taskID)
    }

    // MARK: Accepting

    /// Accepts one suggestion after checking it against fresh data.
    func accept(_ suggestion: PlanSuggestion) async {
        await planning.reload()
        let result = await apply([suggestion])
        if let failure = result.failures.first {
            notice = "Der Vorschlag passt nicht mehr: \(failure.reason)"
        } else if let error = result.errors.first {
            notice = error
        }
        await planning.reload()
    }

    /// Accepts every open suggestion of the shown range; failed ones stay or move to "Nicht eingeplant".
    func acceptAll() async {
        await planning.reload()
        let open = planning.suggestionBatches.flatMap(\.suggestions)
        guard !open.isEmpty else { return }
        let result = await apply(open)
        let failed = result.failures.count + result.errors.count
        notice = failed == 0 ? nil : "\(Self.count(result.applied, "Vorschlag", "Vorschläge")) übernommen, \(failed) \(failed == 1 ? "passt" : "passen") nicht mehr."
        if let error = result.errors.first, result.applied == 0 { notice = error }
        await planning.reload()
    }

    func dismiss(_ suggestion: PlanSuggestion) async {
        for var batch in planning.suggestionBatches where batch.suggestions.contains(suggestion) {
            batch.suggestions.removeAll { $0.id == suggestion.id }
            store.update(batch)
        }
        await planning.reload()
    }

    /// "Verwerfen": drops all open suggestions, notes and risks of the shown range.
    func dismissAll() async {
        for batch in planning.suggestionBatches { store.remove(batch.id) }
        await planning.reload()
    }

    // MARK: Applying

    private struct ApplyResult {
        var applied = 0
        var failures: [UnscheduledTask] = []
        var errors: [String] = []
    }

    /// Validates `suggestions` together against fresh data, applies the valid ones and updates the batches.
    private func apply(_ suggestions: [PlanSuggestion]) async -> ApplyResult {
        var result = ApplyResult()
        var resolved: Set<UUID> = []
        var failed: [UUID: UnscheduledTask] = [:]

        for (day, daySuggestions) in Dictionary(grouping: suggestions, by: \.day) {
            let byKind = Dictionary(grouping: daySuggestions, by: \.kind)
            if let dayBlocks = byKind[.block] {
                let (valid, invalid) = recheck(dayBlocks, scope: .day, day: day)
                failed.merge(invalid) { first, _ in first }
                for suggestion in valid {
                    if let error = applyBlock(suggestion) { result.errors.append(error) } else {
                        resolved.insert(suggestion.id)
                        result.applied += 1
                    }
                }
            }
            if let assignments = byKind[.assignment] {
                let (valid, invalid) = recheck(assignments, scope: .week, day: day)
                failed.merge(invalid) { first, _ in first }
                for suggestion in valid {
                    if let error = applyAssignment(suggestion) { result.errors.append(error) } else {
                        resolved.insert(suggestion.id)
                        result.applied += 1
                    }
                }
            }
        }
        result.failures = Array(failed.values)
        await saveEstimates(for: suggestions.filter { resolved.contains($0.id) })

        // Accepted ones leave the batch; failed ones move to "Nicht eingeplant" with their reason.
        // Suggestions that hit a write error (e.g. no plan calendar) stay for another try.
        for var batch in planning.suggestionBatches {
            let touched = Set(batch.suggestions.map(\.id)).filter { resolved.contains($0) || failed[$0] != nil }
            guard !touched.isEmpty else { continue }
            for id in touched {
                guard let entry = failed[id], !batch.unscheduled.contains(where: { $0.taskKey == entry.taskKey }) else { continue }
                batch.unscheduled.append(entry)
            }
            batch.suggestions.removeAll { touched.contains($0.id) }
            store.update(batch)
        }
        return result
    }

    /// Checks suggestions of one day again with fresh data, independent of the selection rules.
    private func recheck(_ suggestions: [PlanSuggestion], scope: PlanScope,
                         day: PlanDay) -> (valid: [PlanSuggestion], invalid: [UUID: UnscheduledTask]) {
        let ids = Set(suggestions.compactMap(\.taskID))
        let days = planning.days.compactMap(\.planInput).filter { scope == .day ? $0.day == day : true }
        var input = makeInput(scope: scope, only: ids)
        input.days = days
        var invalid: [UUID: UnscheduledTask] = [:]
        let output: PlanOutput = scope == .day
            ? .day(DayPlanOutput(blocks: suggestions.map {
                PlanBlock(taskId: $0.taskKey, start: Self.time($0.startMinutes ?? 0), minutes: $0.minutes ?? 0, reason: $0.reason)
            }, unscheduled: [], risks: [], estimates: []))
            : .period(PeriodPlanOutput(assignments: suggestions.map {
                PlanAssignment(taskId: $0.taskKey, day: Self.dayString($0.day), reason: $0.reason)
            }, unscheduled: [], risks: [], estimates: []))
        let (_, violations) = validate(output, input: input)
        for violation in violations {
            guard let suggestion = suggestions.first(where: { $0.taskKey == violation.taskId }) else { continue }
            invalid[suggestion.id] = UnscheduledTask(taskKey: suggestion.taskKey, title: suggestion.title,
                                                     reason: violation.reason.rawValue)
        }
        return (suggestions.filter { invalid[$0.id] == nil }, invalid)
    }

    private func applyBlock(_ suggestion: PlanSuggestion) -> String? {
        guard let task = task(for: suggestion), let startMinutes = suggestion.startMinutes, let minutes = suggestion.minutes else {
            return "Die Aufgabe gibt es nicht mehr."
        }
        // Built from calendar fields, so days with a clock change keep the suggested time.
        var components = DateComponents(year: suggestion.day.year, month: suggestion.day.month, day: suggestion.day.day)
        components.hour = startMinutes / 60
        components.minute = startMinutes % 60
        guard let start = planning.calendar.date(from: components) else { return "Die Uhrzeit ist ungültig." }
        do {
            try planning.blocks.createBlock(for: task, start: start, minutes: minutes)
            return nil
        } catch {
            return TaskListModel.message(for: error)
        }
    }

    /// Sets the work day; future blocks move along, as when planning by hand (accepting is the user's decision).
    private func applyAssignment(_ suggestion: PlanSuggestion) -> String? {
        guard let id = suggestion.taskID else { return "Die Aufgabe gibt es nicht mehr." }
        do {
            try planning.blocks.moveFutureBlocks(of: id, to: suggestion.day, after: planning.now())
        } catch {
            return TaskListModel.message(for: error)
        }
        planning.planStore.assign(id, to: suggestion.day)
        return nil
    }

    /// Stores the model's estimates locally for accepted tasks without effort; GitHub estimates would be a
    /// Project field (a source) and are left out.
    private func saveEstimates(for accepted: [PlanSuggestion]) async {
        let estimates = planning.suggestionBatches.reduce(into: [String: Int]()) { $0.merge($1.estimates) { first, _ in first } }
        for suggestion in accepted {
            guard let minutes = estimates[suggestion.taskKey], let task = task(for: suggestion),
                  task.estimateMinutes == nil, task.id.source != .github,
                  let provider = planning.taskList.provider(for: task.id.source) else { continue }
            var edit = TaskEdit()
            edit.estimateMinutes = .set(minutes)
            if let saved = try? await provider.apply(edit, to: task.id, expectedVersion: task.version) {
                planning.taskList.didSave(saved)
            }
        }
    }

    // MARK: Model call

    private func answer(model: String, scope: PlanScope, input: [InputItem]) async throws -> String {
        let schema = scope == .day ? (name: "day_plan", schema: AIPlanSchemas.dayPlanSchema)
                                   : (name: "period_plan", schema: AIPlanSchemas.periodPlanSchema)
        var text = ""
        for try await event in responder.respond(model: model, instructions: Self.instructions(scope), input: input,
                                                  tools: [], jsonSchema: schema) {
            if case .textDelta(let delta) = event { text += delta }
        }
        return text
    }

    private func decode(_ text: String, scope: PlanScope) throws -> PlanOutput {
        try PlanOutput.decode(Data(text.utf8), scope: scope)
    }

    static func instructions(_ scope: PlanScope) -> String {
        let common = """
        Du planst die Arbeit einer Person in der App Tagwerk. Die Eingabe ist JSON mit Tagen (Arbeitszeit, \
        Mittagspause, Puffer, Termine, freie Minuten) und offenen Aufgaben. Antworte nur im vorgegebenen Format, \
        Begründungen kurz und auf Deutsch.
        Regeln: nichts in die Vergangenheit, nichts an freien Tagen (dayOff), nichts nach der Fälligkeit (due) \
        oder nach der zugehörigen Deadline (deadline) einer Aufgabe; die freien Minuten eines Tages nicht \
        überschreiten. Wichtige Aufgaben (important) und solche mit naher Fälligkeit zuerst. Termine mit \
        busy=false belegen keine Zeit. Aufgaben ohne minutes schätzt du und nennst die Schätzung in estimates. \
        Was nicht passt, steht in unscheduled mit Grund; drohende Probleme in risks. taskId ist immer die id der Aufgabe.
        """
        switch scope {
        case .day:
            return common + "\nPlane Zeitblöcke für den Tag: Start (HH:mm) und Dauer, innerhalb der Arbeitszeit, ohne Überschneidung mit belegten Terminen samt Puffer, der Mittagspause oder bestehenden Blöcken (existingBlocks)."
        case .week, .month:
            return common + "\nOrdne Aufgaben Arbeitstagen zu (day im Format YYYY-MM-DD), nur Tagen aus der Eingabe. Aufgaben mit plannedDay sind schon zugeordnet; ändere sie nicht."
        }
    }

    static func violationMessage(_ violations: [PlanViolation]) -> String {
        let lines = violations.map { "- \($0.taskId): \($0.reason.rawValue)" }.joined(separator: "\n")
        return "Diese Vorschläge verletzen die Regeln:\n\(lines)\nKorrigiere den Plan und antworte wieder vollständig im vorgegebenen Format."
    }

    // MARK: Input and batches

    private func makeInput(scope: PlanScope, only: Set<TaskID>?) -> PlanInput {
        let today = planning.today
        let days = planning.days.compactMap(\.planInput).filter { day in
            switch scope {
            case .day: day.day == planning.anchor
            case .week: day.day >= today
            case .month: day.day >= today && day.day.month == planning.anchor.month && day.day.year == planning.anchor.year
            }
        }
        let everything = PlanDay(year: 1, month: 1, day: 1)...PlanDay(year: 9999, month: 12, day: 31)
        let now = planning.now()
        let dayStart = today.startDate(in: planning.calendar)
        return makePlanInput(
            scope: scope, days: days, tasks: planning.taskList.items,
            assignments: planning.planStore.assignments(in: everything), anchors: deadlineAnchors(),
            today: today, nowMinutes: Int(now.timeIntervalSince(dayStart) / 60),
            timeZoneID: planning.calendar.timeZone.identifier, defaultTaskMinutes: planning.defaultTaskMinutes,
            only: only,
            excluding: Set(planning.recurringReminderIDs.map { TaskID(source: .reminders, rawValue: $0) })
        )
    }

    /// Deadline-calendar events linked to a task are that task's anchor (§11.7).
    private func deadlineAnchors() -> [TaskID: DueDate] {
        var anchors: [TaskID: DueDate] = [:]
        for deadline in planning.days.flatMap(\.deadlines) where deadline.kind == .deadlineCalendar {
            guard let eventID = deadline.eventID, let task = planning.linkedTask(eventID: eventID) else { continue }
            let due = deadline.time.map { DueDate(date: $0, includeTime: true, calendar: planning.calendar) }
                ?? DueDate(year: deadline.day.year, month: deadline.day.month, day: deadline.day.day)
            if let existing = anchors[task.id],
               existing.startDate(in: planning.calendar) <= due.startDate(in: planning.calendar) { continue }
            anchors[task.id] = due
        }
        return anchors
    }

    private func makeBatch(scope: PlanScope, input: PlanInput, output: PlanOutput, violations: [PlanViolation]) -> SuggestionBatch {
        let titles = Dictionary(input.tasks.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        func title(_ key: String) -> String { titles[key] ?? key }
        var suggestions: [PlanSuggestion] = []
        var unscheduled: [UnscheduledTask] = []
        var risks: [String] = []
        var estimates: [PlanEstimate] = []
        switch output {
        case .day(let plan):
            let day = input.days.first?.day ?? planning.anchor
            suggestions = plan.blocks.compactMap { block in
                guard let start = Self.minutes(block.start) else { return nil }
                return PlanSuggestion(id: UUID(), kind: .block, taskKey: block.taskId, title: title(block.taskId), day: day,
                                      startMinutes: start, minutes: block.minutes, reason: block.reason)
            }
            unscheduled = plan.unscheduled.map { UnscheduledTask(taskKey: $0.taskId, title: title($0.taskId), reason: $0.reason) }
            risks = plan.risks
            estimates = plan.estimates
        case .period(let plan):
            suggestions = plan.assignments.compactMap { assignment in
                guard let day = Self.planDay(assignment.day) else { return nil }
                return PlanSuggestion(id: UUID(), kind: .assignment, taskKey: assignment.taskId, title: title(assignment.taskId),
                                      day: day, startMinutes: nil, minutes: nil, reason: assignment.reason)
            }
            unscheduled = plan.unscheduled.map { UnscheduledTask(taskKey: $0.taskId, title: title($0.taskId), reason: $0.reason) }
            risks = plan.risks
            estimates = plan.estimates
        }
        for violation in violations where titles[violation.taskId] != nil
            && !unscheduled.contains(where: { $0.taskKey == violation.taskId })
            && !suggestions.contains(where: { $0.taskKey == violation.taskId }) {
            unscheduled.append(UnscheduledTask(taskKey: violation.taskId, title: title(violation.taskId),
                                               reason: violation.reason.rawValue))
        }
        return SuggestionBatch(id: UUID(), scope: scope, days: input.days.map(\.day), createdAt: planning.now(),
                               suggestions: suggestions, unscheduled: unscheduled, risks: risks,
                               estimates: Dictionary(estimates.map { ($0.taskId, $0.minutes) }, uniquingKeysWith: { first, _ in first }))
    }

    private func task(for suggestion: PlanSuggestion) -> TaskItem? {
        planning.taskList.items.first { $0.id.key == suggestion.taskKey }
    }

    // MARK: Formats

    static func minutes(_ time: String) -> Int? {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return hour * 60 + minute
    }

    static func time(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    static func dayString(_ day: PlanDay) -> String { String(format: "%04d-%02d-%02d", day.year, day.month, day.day) }

    static func planDay(_ text: String) -> PlanDay? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return PlanDay(year: parts[0], month: parts[1], day: parts[2])
    }

    private static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(value) \(value == 1 ? singular : plural)"
    }
}
