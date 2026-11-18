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

    static var invalidAnswerMessage: String { String(localized: "Die Antwort von ChatGPT ließ sich nicht lesen. Versuche es erneut.") }
    static var nothingToPlanMessage: String { String(localized: "Keine offenen Aufgaben zum Planen.") }
    static var modelFallbackMessage: String { String(localized: "Das gewählte Modell gibt es nicht mehr. Tagwerk plant mit „Automatisch“.") }

    private(set) var state: State = .idle
    /// A one-line note after planning or accepting; the view clears it when shown.
    var notice: String?

    @ObservationIgnored let responder: ResponseStreaming
    @ObservationIgnored let model: @MainActor () async throws -> String
    @ObservationIgnored private let consumeModelFallback: @MainActor () -> Bool
    /// "Vorarbeiten, wenn Luft ist" (setting, default on).
    @ObservationIgnored var workAhead: @MainActor () -> Bool = { true }
    /// "Längere Tage vorschlagen": never, for deadlines and P1 (default), only in an emergency.
    @ObservationIgnored var longerDays: @MainActor () -> LongerDays = { .forDeadlines }
    /// "Planungsvorgaben" (mockup VR1): short sentences sent with every planning and conversation.
    @ObservationIgnored var preferences: @MainActor () -> [String] = { [] }
    /// The language of the reasons the model writes; they are shown and stored (plan english-app, decision 8).
    @ObservationIgnored var language: @MainActor () -> VoiceLanguage = { .app }

    /// The suggestion a conversation answer is awaited for (mockup VK1).
    var revisingID: UUID?
    /// Why the last conversation call failed.
    var revisionError: String?

    enum LongerDays: String, CaseIterable {
        case never, forDeadlines, emergencyOnly
    }
    @ObservationIgnored let planning: PlanningModel
    @ObservationIgnored let store: SuggestionStore
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
        // An undo from before would bring old suggestions back next to the new ones.
        clearDismissUndo()
        clearAcceptUndo()
        if planning.scope != scope || planning.anchor != anchor {
            planning.scope = scope
            planning.anchor = anchor
        }
        await planning.reload()
        // Day plan: the next two working days (within five calendar days) as move targets and for working ahead.
        let targets = scope == .day ? await laterDays(after: anchor) : []
        // Suggestions the user moved by hand stay where they are (mockup VM1): their tasks are not planned
        // again, and their time is taken.
        let pinned = pinnedSuggestions(replacedBy: scope, days: Set(planning.days.map(\.day)))
        var input = makeInput(scope: scope, only: taskID.map { [$0] }, lookahead: Set(targets.map(\.day)),
                              excluding: Set(pinned.compactMap(\.taskID)))
        input.laterDays = targets
        for suggestion in pinned where suggestion.kind == .block {
            guard let start = suggestion.startMinutes, let minutes = suggestion.minutes,
                  let index = input.days.firstIndex(where: { $0.day == suggestion.day }) else { continue }
            input.days[index].blocks.append(start..<(start + minutes))
        }
        guard !input.tasks.isEmpty, !input.days.isEmpty else {
            notice = Self.nothingToPlanMessage
            return
        }
        state = .planning
        let started = Date()
        do {
            let model = try await model()
            if consumeModelFallback() { notice = Self.modelFallbackMessage }
            let inputText = String(decoding: try input.modelJSON(), as: UTF8.self)
            let firstText = try await answer(model: model, scope: scope, input: [.user(inputText)])
            var (accepted, violations) = validate(try decode(firstText, scope: scope), input: input)
            let firstViolations = violations
            if !violations.isEmpty {
                // One follow-up with the violations; what still fails goes to "Nicht eingeplant".
                let retryText = try await answer(model: model, scope: scope, input: [
                    .user(inputText), .assistant(firstText), .user(Self.violationMessage(violations)),
                ])
                (accepted, violations) = validate(try decode(retryText, scope: scope), input: input)
            }
            let beforeP1 = Self.blockCount(accepted)
            accepted = ensureFittingP1(accepted, input: input)
            if longerDays() == .never { accepted = Self.withoutDayChanges(accepted) }
            log(scope: scope, input: input, inputText: inputText, model: model, started: started,
                retried: !firstViolations.isEmpty, output: accepted, addedP1: Self.blockCount(accepted) - beforeP1,
                violations: firstViolations + violations)
            var batch = makeBatch(scope: scope, input: input, output: accepted, violations: violations)
            batch.suggestions += pinned.map { var kept = $0; kept.dependsOn = nil; kept.previousPosition = nil; return kept }
            store.replace(with: batch)
            await planning.reload()
            state = .idle
        } catch is CancellationError {
            state = .idle
        } catch let error as ChatGPTError {
            guard !Task.isCancelled else { state = .idle; return }
            state = .failed(error.userMessage)
        } catch is DecodingError {
            state = .failed(Self.invalidAnswerMessage)
        } catch {
            state = .failed(Self.invalidAnswerMessage)
        }
    }

    static var addedLocallyReason: String { String(localized: "Von Tagwerk ergänzt: P1, passt in diese freie Lücke.") }

    /// Proposal §3: a P1 that fits into a free stretch gets a block even if the model left it out.
    private func ensureFittingP1(_ output: PlanOutput, input: PlanInput) -> PlanOutput {
        guard case .day(var plan) = output, var day = input.days.first else { return output }
        let handled = Set(plan.blocks.map(\.taskId) + plan.moves.map(\.taskId))
        day.blocks += plan.blocks.compactMap { block in Self.minutes(block.start).map { $0..<($0 + block.minutes) } }
        let from = day.day == input.today ? input.nowMinutes : nil
        for task in input.tasks where task.priority == .p1 && !handled.contains(task.id) {
            let length = max(15, min(task.sessionMinutes ?? .max, task.remainingMinutes ?? input.defaultTaskMinutes))
            guard let slot = nextFreeSlot(day, after: day.hours?.startMinutes ?? 0, minutes: length, fromMinutes: from),
                  slot.count >= length else { continue }
            plan.blocks.append(PlanBlock(taskId: task.id, start: Self.time(slot.lowerBound), minutes: length,
                                         reason: Self.addedLocallyReason))
            day.blocks.append(slot.lowerBound..<(slot.lowerBound + length))
        }
        return .day(plan)
    }

    private static func blockCount(_ output: PlanOutput) -> Int {
        if case .day(let plan) = output { return plan.blocks.count }
        return 0
    }

    /// Numbers only (proposal §6): no titles, no IDs.
    private func log(scope: PlanScope, input: PlanInput, inputText: String, model: String, started: Date, retried: Bool,
                     output: PlanOutput, addedP1: Int, violations: [PlanViolation]) {
        let (blocks, assignments, moves, changes): (Int, Int, Int, Int) = switch output {
        case .day(let plan): (plan.blocks.count, 0, plan.moves.count, plan.dayChanges.count)
        case .period(let plan): (0, plan.assignments.count, plan.moves.count, plan.dayChanges.count)
        }
        let reasons = Dictionary(grouping: violations, by: { String(describing: $0.reason) }).mapValues(\.count)
        let overbooked = input.days.reduce(0) { $0 + max(0, $1.plannedMinutes - $1.availableMinutes) }
        let free = input.days.reduce(0) { $0 + max(0, $1.availableMinutes - $1.plannedMinutes) }
        PlanningDiagnostics.shared.append(PlanningRunLog(
            date: started, scope: scope.rawValue, tasksSent: input.tasks.count, omitted: input.omittedCount,
            freeMinutes: free, inputCharacters: inputText.count, model: model, seconds: Date().timeIntervalSince(started),
            retried: retried, blocks: blocks, assignments: assignments, moves: moves, dayChanges: changes,
            addedP1: addedP1, violations: reasons, overbookedBefore: overbooked))
    }

    private static func withoutDayChanges(_ output: PlanOutput) -> PlanOutput {
        switch output {
        case .day(var plan):
            plan.dayChanges = []
            return .day(plan)
        case .period(var plan):
            plan.dayChanges = []
            return .period(plan)
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
        // A double tap must not run twice (the second run would fail and drop the first one's undo).
        guard !isAccepting else { return }
        isAccepting = true
        defer { isAccepting = false }
        await planning.reload()
        clearDismissUndo()  // its snapshot would bring this suggestion back after it is in the calendar
        let batches = planning.suggestionBatches
        let result = await apply([suggestion])
        // "Widerrufen" after a single ✓ as well (mockup VL1).
        var undo = result.undo
        undo.batches = batches
        undo.count = result.applied
        lastAcceptAll = result.applied > 0 ? undo : nil
        if let failure = result.failures.values.first {
            notice = String(localized: "Der Vorschlag passt nicht mehr: \(failure.reason)")
        } else if let error = result.errors.first {
            notice = error
        }
        await planning.reload()
    }

    /// What "Alle übernehmen" did, for "Widerrufen".
    struct AcceptUndo {
        var batches: [SuggestionBatch] = []
        var createdBlocks: [CalendarEvent] = []
        var assignments: [(TaskID, PlanDay?)] = []
        var overrides: [(PlanDay, DayOverride?)] = []
        var moves: [PlanningModel.DayMove] = []
        var count = 0
    }

    private(set) var lastAcceptAll: AcceptUndo?
    @ObservationIgnored private var isAccepting = false

    /// Accepts every open suggestion of the shown range: longer days first, then moves, then blocks and work days
    /// (mockup AB1). Failed ones stay or move to "Nicht eingeplant".
    func acceptAll() async {
        guard !isAccepting else { return }
        isAccepting = true
        defer { isAccepting = false }
        await planning.reload()
        let open = planning.suggestionBatches.flatMap(\.suggestions)
        guard !open.isEmpty else { return }
        clearDismissUndo()
        let batches = planning.suggestionBatches
        let result = await apply(open)
        var undo = result.undo
        undo.batches = batches
        undo.count = result.applied
        lastAcceptAll = result.applied > 0 ? undo : nil
        let failed = result.failures.count + result.errors.count
        notice = failed == 0 ? nil : Self.partialAcceptNotice(applied: result.applied, failed: failed)
        if let error = result.errors.first, result.applied == 0 { notice = error }
        await planning.reload()
    }

    /// "Widerrufen" after "Alle übernehmen": removes the new blocks, restores days, hours and moves and
    /// brings the suggestions back.
    func undoAcceptAll() async {
        guard let undo = lastAcceptAll else { return }
        lastAcceptAll = nil
        for block in undo.createdBlocks { await planning.deleteBlock(block) }
        for move in undo.moves.reversed() { await planning.undo(move) }
        for (id, previous) in undo.assignments {
            if let previous { planning.planStore.assign(id, to: previous) } else { planning.planStore.unassign(id) }
        }
        for (day, previous) in undo.overrides { planning.planStore.setOverride(previous, on: day) }
        for batch in planning.suggestionBatches { store.remove(batch.id) }
        for batch in undo.batches { store.update(batch) }
        await planning.reload()
    }

    func clearAcceptUndo() {
        lastAcceptAll = nil
    }

    func dismiss(_ suggestion: PlanSuggestion) async {
        // "Widerrufen" after a single ✕ (mockup VL1): keep the batches as they were.
        lastDismissed = planning.suggestionBatches.filter { $0.suggestions.contains(suggestion) }
        dismissedCount = lastDismissed.isEmpty ? 0 : 1
        clearAcceptUndo()
        for var batch in planning.suggestionBatches where batch.suggestions.contains(suggestion) {
            batch.suggestions.removeAll { $0.id == suggestion.id }
            batch.revisionUndo = nil
            if suggestion.kind == .dayChange {
                // Without the longer day the blocks that need it do not fit (mockup AB1).
                let dependent = batch.suggestions.filter { $0.dependsOn == suggestion.id }
                for block in dependent where !batch.unscheduled.contains(where: { $0.taskKey == block.taskKey }) {
                    batch.unscheduled.append(UnscheduledTask(taskKey: block.taskKey, title: block.title,
                                                             reason: PlanViolation.Reason.outsideWorkHours.text))
                }
                batch.suggestions.removeAll { $0.dependsOn == suggestion.id }
            }
            store.update(batch)
        }
        await planning.reload()
    }

    /// Batches dropped by the last "Verwerfen", for "Widerrufen".
    private(set) var lastDismissed: [SuggestionBatch] = []
    /// How many suggestions the last "Verwerfen" or ✕ dropped.
    private(set) var dismissedCount = 0

    /// "Verwerfen": drops all open suggestions, notes and risks of the shown range; "Widerrufen" restores them.
    func dismissAll() async {
        lastDismissed = planning.suggestionBatches
        dismissedCount = lastDismissed.reduce(0) { $0 + $1.suggestions.count }
        clearAcceptUndo()
        for batch in lastDismissed { store.remove(batch.id) }
        await planning.reload()
    }

    func undoDismissAll() async {
        for batch in lastDismissed { store.update(batch) }
        lastDismissed = []
        await planning.reload()
    }

    func clearDismissUndo() {
        lastDismissed = []
    }

    // MARK: Running in the background

    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var runningID: UUID?

    /// Starts planning without blocking the view; the result arrives even if the user switches views.
    func start(scope: PlanScope, anchor: PlanDay, taskID: TaskID? = nil) {
        guard !isPlanning, running == nil else { return }
        let id = UUID()
        runningID = id
        running = Task { [weak self] in
            await self?.plan(scope: scope, anchor: anchor, taskID: taskID)
            // A cancelled run must not clear a newer one.
            if self?.runningID == id {
                self?.running = nil
                self?.runningID = nil
            }
        }
    }

    /// "Abbrechen" while ChatGPT is still answering; nothing is stored.
    func cancel() {
        running?.cancel()
        running = nil
        runningID = nil
        if isPlanning { state = .idle }
    }

    // MARK: Applying

    private struct ApplyResult {
        var applied = 0
        var failures: [UUID: UnscheduledTask] = [:]
        var errors: [String] = []
        var undo = AcceptUndo()
    }

    static var needsLongerDayMessage: String { String(localized: "Übernimm zuerst die längere Arbeitszeit.") }

    /// Validates `suggestions` against fresh data, applies the valid ones and updates the batches.
    private func apply(_ suggestions: [PlanSuggestion]) async -> ApplyResult {
        var result = ApplyResult()
        var resolved: Set<UUID> = []
        let pendingChanges = Set(planning.suggestionBatches.flatMap(\.suggestions).filter { $0.kind == .dayChange }.map(\.id))

        // 1. Longer days and moves change the ground the other suggestions are checked on.
        for change in suggestions where change.kind == .dayChange {
            guard change.day >= planning.today, let start = change.startMinutes, let end = change.endMinutes else {
                result.failures[change.id] = UnscheduledTask(taskKey: change.taskKey, title: change.title,
                                                             reason: PlanViolation.Reason.inThePast.text)
                continue
            }
            result.undo.overrides.append((change.day, planning.planStore.override(on: change.day)))
            planning.planStore.setOverride(.hours(WorkHours(startMinutes: start, endMinutes: end)), on: change.day)
            resolved.insert(change.id)
            result.applied += 1
        }
        for move in suggestions where move.kind == .move {
            guard let id = move.taskID, task(for: move) != nil, move.day > planning.today else {
                result.failures[move.id] = UnscheduledTask(taskKey: move.taskKey, title: move.title,
                                                           reason: PlanViolation.Reason.inThePast.text)
                continue
            }
            await planning.moveTask(id, to: move.day)
            if let done = planning.lastMove { result.undo.moves.append(done) }
            planning.clearMoveUndo()
            resolved.insert(move.id)
            result.applied += 1
        }
        if !resolved.isEmpty { await planning.reload() }

        // 2. Blocks and work days, checked per day against the fresh data.
        let rest = suggestions.filter { $0.kind == .block || $0.kind == .assignment }
        for (day, daySuggestions) in Dictionary(grouping: rest, by: \.day) {
            var dayBlocks: [PlanSuggestion] = []
            for block in daySuggestions where block.kind == .block {
                if let change = block.dependsOn, pendingChanges.contains(change), !resolved.contains(change) {
                    result.errors.append(Self.needsLongerDayMessage)
                } else {
                    dayBlocks.append(block)
                }
            }
            if !dayBlocks.isEmpty {
                let (valid, invalid) = recheck(dayBlocks, scope: .day, day: day)
                result.failures.merge(invalid) { first, _ in first }
                for suggestion in valid {
                    switch applyBlock(suggestion) {
                    case .success(let event):
                        result.undo.createdBlocks.append(event)
                        resolved.insert(suggestion.id)
                        result.applied += 1
                    case .failure(let error):
                        result.errors.append(error.message)
                    }
                }
            }
            let assignments = daySuggestions.filter { $0.kind == .assignment }
            if !assignments.isEmpty {
                let (valid, invalid) = recheck(assignments, scope: .week, day: day)
                result.failures.merge(invalid) { first, _ in first }
                for suggestion in valid {
                    let previous = suggestion.taskID.flatMap { planning.planStore.assignment(for: $0) }
                    if let error = applyAssignment(suggestion) { result.errors.append(error) } else {
                        if let id = suggestion.taskID { result.undo.assignments.append((id, previous)) }
                        resolved.insert(suggestion.id)
                        result.applied += 1
                    }
                }
            }
        }
        await saveEstimates(for: suggestions.filter { resolved.contains($0.id) })

        // Accepted ones leave the batch; failed ones move to "Nicht eingeplant" with their reason.
        // Suggestions that hit a write error (e.g. no plan calendar) stay for another try.
        let failed = result.failures
        for var batch in planning.suggestionBatches {
            let touched = Set(batch.suggestions.map(\.id)).filter { resolved.contains($0) || failed[$0] != nil }
            guard !touched.isEmpty else { continue }
            for id in touched {
                guard let entry = failed[id], !batch.unscheduled.contains(where: { $0.taskKey == entry.taskKey }) else { continue }
                batch.unscheduled.append(entry)
            }
            batch.suggestions.removeAll { touched.contains($0.id) }
            batch.revisionUndo = nil  // would bring accepted suggestions back
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
                                                     reason: violation.reason.text)
        }
        return (suggestions.filter { invalid[$0.id] == nil }, invalid)
    }

    struct ApplyError: Error {
        let message: String
    }

    private func applyBlock(_ suggestion: PlanSuggestion) -> Result<CalendarEvent, ApplyError> {
        guard let task = task(for: suggestion), let startMinutes = suggestion.startMinutes, let minutes = suggestion.minutes else {
            return .failure(ApplyError(message: String(localized: "Die Aufgabe gibt es nicht mehr.")))
        }
        // Built from calendar fields, so days with a clock change keep the suggested time.
        var components = DateComponents(year: suggestion.day.year, month: suggestion.day.month, day: suggestion.day.day)
        components.hour = startMinutes / 60
        components.minute = startMinutes % 60
        guard let start = planning.calendar.date(from: components) else { return .failure(ApplyError(message: String(localized: "Die Uhrzeit ist ungültig."))) }
        do {
            return .success(try planning.blocks.createBlock(for: task, start: start, minutes: minutes))
        } catch {
            return .failure(ApplyError(message: TaskListModel.message(for: error)))
        }
    }

    /// Sets the work day; future blocks move along, as when planning by hand (accepting is the user's decision).
    private func applyAssignment(_ suggestion: PlanSuggestion) -> String? {
        guard let id = suggestion.taskID else { return String(localized: "Die Aufgabe gibt es nicht mehr.") }
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
        var completed = false
        let instructions = Self.instructions(scope, longerDays: longerDays(), language: language()) + Self.preferenceText(preferences())
        for try await event in responder.respond(model: model, instructions: instructions, input: input,
                                                  tools: [], jsonSchema: schema) {
            switch event {
            case .textDelta(let delta): text += delta
            case .completed: completed = true
            case .functionCall: break
            }
        }
        // "Abbrechen" ends the stream early: a partial answer is never used.
        try Task.checkCancellation()
        guard completed else { throw ChatGPTError.incomplete }
        return text
    }

    private func decode(_ text: String, scope: PlanScope) throws -> PlanOutput {
        try PlanOutput.decode(Data(text.utf8), scope: scope)
    }

    static func instructions(_ scope: PlanScope, longerDays: LongerDays = .forDeadlines, language: VoiceLanguage) -> String {
        let longer: String = switch longerDays {
        case .never: "(b) Schlage keine längeren Tage vor (dayChanges bleibt leer)."
        case .forDeadlines: """
            (b) Passen danach Aufgaben mit P1 oder mit Fälligkeit, Deadline oder latestStart bis übermorgen nicht, \
            schlage einen längeren Tag vor (dayChanges, neuer Beginn und neues Ende in Schritten von 30 Minuten) bis \
            normalMaximumHours Stunden Arbeitszeit. (c) Bis emergencyMaximumHours Stunden oder an einem freien Tag nur, \
            wenn eine Frist innerhalb von 24 Stunden sonst reißt; dann sagt der Grund das ausdrücklich.
            """
        case .emergencyOnly: """
            (b) Längere Tage (dayChanges) nur, wenn eine Frist innerhalb von 24 Stunden sonst reißt, bis \
            emergencyMaximumHours Stunden; der Grund sagt das ausdrücklich.
            """
        }
        let common = """
        Du planst die Arbeit einer Person in der App Tagwerk. Antworte nur im vorgegebenen Format, Begründungen \
        kurz und auf \(language.promptName). taskId ist immer die id der Aufgabe. Die Aufgaben stehen in der Reihenfolge ihrer \
        Wichtigkeit (überfällig, heute, P1, nach Termin).
        Regeln, in dieser Reihenfolge:
        1. Ist eine Aufgabe überfällig oder bis übermorgen fällig, geht sie vor; sonst P1 vor P2 vor allem anderen.
        2. Große Aufwände werden verteilt: remainingMinutes ist der offene Aufwand, latestStart der späteste Tag, \
        an dem die Arbeit beginnen muss, sessionMinutes der Anteil für einen Tag. Plane für solche Aufgaben einen \
        Block von sessionMinutes, sobald latestStart erreicht oder überschritten ist, auch bei niedriger Priorität.
        3. Ein Block je Aufgabe und Tag, Dauer = remainingMinutes (oder sessionMinutes, oder deine Schätzung in \
        estimates), mindestens 15 Minuten.
        4. Ist es zu voll, in dieser Reihenfolge: (a) Aufgaben mit P3 oder ohne Priorität, die erst nach dem Zieltag \
        fällig sind, auf einen Zieltag mit freier Zeit verschieben (moves); nie P1 oder Wichtiges. \(longer) \
        (d) Der Rest steht mit konkretem Grund in unscheduled.
        5. summary: immer ein bis zwei Sätze – was zählt, was wartet, ob vorgearbeitet wird; nenne omittedCount, \
        wenn es größer als 0 ist.
        """
        switch scope {
        case .day:
            return common + """

            Tagesplan: Nutze nur freeSlots des Tages; rechne keine eigenen Lücken. Zuerst Blöcke für Aufgaben, die \
            schon auf dem Tag liegen (plannedDay), dann die übrigen in Listenreihenfolge. Jeder P1, der in eine freie \
            Lücke passt, bekommt einen Block; passt keiner, steht er mit Grund in unscheduled. Ist Luft, ziehe \
            Aufgaben der nächsten Tage vor und sage das. laterDays sind nur Ziele für moves.
            """
        case .week, .month:
            return common + """

            Wochen- und Monatsplan: Ordne Aufgaben ohne plannedDay Arbeitstagen zu (assignments, day im Format \
            YYYY-MM-DD, nur Tage aus days, freeMinutes beachten). Aufgaben mit plannedDay liegen auf überbuchten \
            Tagen; sie darfst du nur per moves auf andere Tage verschieben.
            """
        }
    }

    /// The user's standing preferences as a paragraph of the instructions; empty without any.
    static func preferenceText(_ preferences: [String]) -> String {
        let lines = preferences.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return "" }
        return "\nVorgaben der Person, beachte sie:\n" + lines.map { "- \($0)" }.joined(separator: "\n")
    }

    /// The next two working days within five calendar days: move targets of a day plan.
    func laterDays(after anchor: PlanDay) async -> [PlanInputDay] {
        let calendar = planning.calendar
        let candidates = await planning.planInputs(in: anchor.adding(days: 1, calendar: calendar)...anchor.adding(days: 5, calendar: calendar))
        return Array(candidates.filter { $0.hours.map { $0.minutes > 0 } ?? false }.prefix(2))
    }

    /// Open suggestions the user moved by hand in the batches a new plan of `scope` over `days` replaces.
    private func pinnedSuggestions(replacedBy scope: PlanScope, days: Set<PlanDay>) -> [PlanSuggestion] {
        store.batches()
            .filter { ($0.scope == .day) == (scope == .day) && $0.days.contains(where: days.contains) }
            .flatMap(\.suggestions)
            .filter { suggestion in
                // Only while the task is still open; a finished task's suggestion goes with the old plan.
                suggestion.isMovedByUser && planning.taskList.items.contains { $0.id.key == suggestion.taskKey && !$0.isCompleted }
            }
    }

    static func violationMessage(_ violations: [PlanViolation]) -> String {
        let lines = violations.map { "- \($0.taskId): \($0.reason.text)" }.joined(separator: "\n")
        return "Diese Vorschläge verletzen die Regeln:\n\(lines)\nKorrigiere den Plan und antworte wieder vollständig im vorgegebenen Format."
    }

    // MARK: Input and batches

    func makeInput(scope: PlanScope, only: Set<TaskID>?, lookahead: Set<PlanDay> = [], excluding: Set<TaskID> = []) -> PlanInput {
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
        // Recurring reminders take part with their effort of the day (their time is reserved for them).
        let tasks = planning.taskList.items.map { task -> TaskItem in
            guard let recurring = planning.recurringItem(for: task, on: planning.today) else { return task }
            var copy = task
            copy.estimateMinutes = recurring.minutes
            return copy
        }
        return makePlanInput(
            scope: scope, days: days, tasks: tasks,
            assignments: planning.planStore.assignments(in: everything), anchors: deadlineAnchors(),
            today: today, nowMinutes: Int(now.timeIntervalSince(dayStart) / 60),
            timeZoneID: planning.calendar.timeZone.identifier, defaultTaskMinutes: planning.defaultTaskMinutes,
            only: only,
            excluding: excluding,
            lookaheadDays: workAhead() ? lookahead : [],
            blockedMinutes: planning.blockedMinutesByTask,
            calendar: planning.calendar
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
        let (summary, moves, dayChanges): (String, [PlanMove], [PlanDayChange]) = switch output {
        case .day(let plan): (plan.summary, plan.moves, plan.dayChanges)
        case .period(let plan): (plan.summary, plan.moves, plan.dayChanges)
        }
        // Longer days (issue #72): blocks in the added time depend on them (mockup AB1).
        for change in dayChanges {
            guard let day = Self.planDay(change.day), let start = Self.minutes(change.start), let end = Self.minutes(change.end) else { continue }
            let suggestion = PlanSuggestion(id: UUID(), kind: .dayChange, taskKey: "day:\(change.day)",
                                            title: Self.dayChangeTitle(day: day, start: start, end: end, calendar: planning.calendar),
                                            day: day, startMinutes: start, minutes: nil, reason: change.reason, endMinutes: end)
            let original = input.days.first { $0.day == day }?.hours
            for index in suggestions.indices where suggestions[index].kind == .block && suggestions[index].day == day {
                guard let blockStart = suggestions[index].startMinutes else { continue }
                let blockEnd = blockStart + (suggestions[index].minutes ?? 0)
                if original.map({ blockStart < $0.startMinutes || blockEnd > $0.endMinutes }) ?? true {
                    suggestions[index].dependsOn = suggestion.id
                }
            }
            suggestions.insert(suggestion, at: 0)
        }
        // Moves away from a full day ("↷").
        let planned = Dictionary(input.tasks.map { ($0.id, $0.plannedDay) }, uniquingKeysWith: { first, _ in first })
        for move in moves {
            guard let day = Self.planDay(move.day) else { continue }
            suggestions.append(PlanSuggestion(id: UUID(), kind: .move, taskKey: move.taskId, title: title(move.taskId), day: day,
                                              startMinutes: nil, minutes: nil, reason: move.reason,
                                              fromDay: (planned[move.taskId] ?? nil) ?? input.days.first?.day))
        }
        for violation in violations where titles[violation.taskId] != nil
            && !unscheduled.contains(where: { $0.taskKey == violation.taskId })
            && !suggestions.contains(where: { $0.taskKey == violation.taskId }) {
            unscheduled.append(UnscheduledTask(taskKey: violation.taskId, title: title(violation.taskId),
                                               reason: violation.reason.text))
        }
        return SuggestionBatch(id: UUID(), scope: scope, days: input.days.map(\.day), createdAt: planning.now(),
                               suggestions: suggestions, unscheduled: unscheduled, risks: risks,
                               estimates: Dictionary(estimates.map { ($0.taskId, $0.minutes) }, uniquingKeysWith: { first, _ in first }),
                               summary: summary.isEmpty ? nil : summary)
    }

    private func task(for suggestion: PlanSuggestion) -> TaskItem? {
        planning.taskList.items.first { $0.id.key == suggestion.taskKey }
    }

    // MARK: Formats

    /// "Mi bis 20:00 arbeiten · +2 h" or, on a day off, "Sa arbeiten · 14:00 bis 17:00" (mockups AO1, FT1).
    static func dayChangeTitle(day: PlanDay, start: Int, end: Int, calendar: Calendar) -> String {
        let weekday = day.startDate(in: calendar).formatted(.dateTime.weekday(.abbreviated))
        let from = DateText.time(minutes: start, calendar: calendar), to = DateText.time(minutes: end, calendar: calendar)
        return String(localized: "\(weekday) \(from) bis \(to) arbeiten")
    }

    nonisolated static func minutes(_ time: String) -> Int? {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...24).contains(hour), (0...59).contains(minute), hour * 60 + minute <= 24 * 60 else { return nil }
        return hour * 60 + minute
    }

    nonisolated static func time(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    nonisolated static func dayString(_ day: PlanDay) -> String { String(format: "%04d-%02d-%02d", day.year, day.month, day.day) }

    nonisolated static func planDay(_ text: String) -> PlanDay? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        // Only real calendar days ("2026-02-30" is none).
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "UTC") ?? .current
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard (1...12).contains(parts[1]), (1...31).contains(parts[2]), components.isValidDate(in: gregorian) else { return nil }
        return PlanDay(year: parts[0], month: parts[1], day: parts[2])
    }

    /// "3 Vorschläge übernommen, 1 passt nicht mehr.": one sentence per case, so that translations can inflect it.
    private static func partialAcceptNotice(applied: Int, failed: Int) -> String {
        let accepted = String(localized: "\(applied) Vorschläge übernommen")
        let rest = failed == 1 ? String(localized: "1 passt nicht mehr") : String(localized: "\(failed) passen nicht mehr")
        return "\(accepted), \(rest)."
    }
}
