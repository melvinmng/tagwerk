import AIKit
import Foundation
import TagwerkCore

/// Moving suggestions by hand and talking about them (mockups VM1, VK1, VA1).
///
/// Both change suggestions only; nothing reaches a calendar or a source before "Übernehmen". Every change is
/// checked locally against fresh data: only violations the change itself causes count, so a suggestion that
/// was already in the past or over capacity does not block others. Moving by hand calls nothing (§8.4); a
/// conversation call happens only on "Senden" or a quick reply.
extension AIPlanner {
    static var suggestionGoneMessage: String { String(localized: "Den Vorschlag gibt es nicht mehr.") }

    // MARK: Moving by hand

    /// Moves a suggestion to `day` (and, in a day plan, to `start` with `minutes`). It stays a suggestion,
    /// remembers where the AI had put it and is pinned from then on. Returns why it does not fit, if so.
    func moveSuggestion(_ suggestion: PlanSuggestion, day: PlanDay, start: Int?, minutes: Int?) async -> String? {
        guard var batch = batch(containing: suggestion.id),
              let index = batch.suggestions.firstIndex(where: { $0.id == suggestion.id }) else { return Self.suggestionGoneMessage }
        let original = batch.suggestions[index]
        let target: SuggestionPosition
        switch position(for: original, in: batch, day: day, start: start, minutes: minutes) {
        case .success(let position): target = position
        case .failure(let error): return error.message
        }
        var revised = batch.suggestions
        revised[index].place(at: target, fromDay: batch.days.first)
        if revised[index].aiPosition == nil { revised[index].aiPosition = original.position }
        if revised[index].position == revised[index].aiPosition { revised[index].aiPosition = nil }
        revised[index].previousPosition = nil
        let rejected = await newViolations(in: batch, revised: &revised, changed: [original.id])
        if let reason = rejected[original.id] { return reason }
        batch.suggestions = revised
        batch.revisionUndo = nil  // "Rückgängig" of an answer would also undo this move
        save(batch)
        await planning.reload()
        return nil
    }

    /// "Zurück zum Vorschlag der KI": back to where the AI had put it.
    func resetSuggestion(_ suggestion: PlanSuggestion) async {
        guard var batch = batch(containing: suggestion.id),
              let index = batch.suggestions.firstIndex(where: { $0.id == suggestion.id }),
              let position = batch.suggestions[index].aiPosition else { return }
        batch.suggestions[index].place(at: position, fromDay: batch.suggestions[index].fromDay ?? batch.days.first)
        batch.suggestions[index].aiPosition = nil
        var revised = batch.suggestions
        _ = await newViolations(in: batch, revised: &revised, changed: [])
        batch.suggestions = revised
        save(batch)
        await planning.reload()
    }

    // MARK: Conversation

    /// Sends `comment` about `suggestion` and applies the answer to the open suggestions of its planning
    /// (mockup VA1): only the suggestions the answer names change, those the user moved stay unless they
    /// are the one commented on, and changes that do not fit are named instead of applied.
    func revise(_ suggestion: PlanSuggestion, comment: String) async {
        let comment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard revisingID == nil, !comment.isEmpty, let batch = batch(containing: suggestion.id) else { return }
        revisingID = suggestion.id
        revisionError = nil
        defer { revisingID = nil }
        let refs = Self.refs(for: batch)
        do {
            let model = try await model()
            let request = try await revisionRequest(batch: batch, about: suggestion, comment: comment, refs: refs)
            let instructions = Self.instructions(batch.scope, longerDays: longerDays()) + Self.preferenceText(preferences())
                + "\n" + Self.revisionInstructions
            var text = ""
            var completed = false
            for try await event in responder.respond(model: model, instructions: instructions, input: [.user(request)], tools: [],
                                                      jsonSchema: (name: "suggestion_revision", schema: Self.revisionSchema)) {
                switch event {
                case .textDelta(let delta): text += delta
                case .completed: completed = true
                case .functionCall: break
                }
            }
            try Task.checkCancellation()
            guard completed else { throw ChatGPTError.incomplete }
            let answer = try JSONDecoder().decode(RevisionAnswer.self, from: Data(text.utf8))
            await apply(answer, to: batch, about: suggestion, comment: comment, refs: refs)
        } catch is CancellationError {
            return
        } catch let error as ChatGPTError {
            revisionError = error.userMessage
        } catch {
            revisionError = Self.invalidAnswerMessage
        }
    }

    /// "Rückgängig" after an answer: the suggestions as they were before it.
    func undoRevision(of batchID: UUID) async {
        guard var batch = store.batches().first(where: { $0.id == batchID }), let before = batch.revisionUndo else { return }
        batch.suggestions = before
        batch.revisionUndo = nil
        save(batch)
        await planning.reload()
    }

    // MARK: Applying an answer

    private struct RevisionAnswer: Decodable {
        struct Change: Decodable {
            let ref: String
            let day: String
            let start: String?
            let minutes: Int?
        }
        let reply: String
        let changes: [Change]
    }

    private func apply(_ answer: RevisionAnswer, to batch: SuggestionBatch, about suggestion: PlanSuggestion, comment: String,
                       refs: [String: UUID]) async {
        // The batch may have changed while waiting (accepted, dismissed, moved): work on the fresh one.
        guard var batch = self.batch(containing: suggestion.id) ?? store.batches().first(where: { $0.id == batch.id }) else { return }
        var revised = batch.suggestions.map { var copy = $0; copy.previousPosition = nil; return copy }
        var changed: [UUID] = []
        var rejected: [String] = []
        for change in answer.changes {
            guard let id = refs[change.ref], let index = revised.firstIndex(where: { $0.id == id }) else { continue }
            let current = revised[index]
            if current.isMovedByUser && id != suggestion.id {
                rejected.append(String(localized: "\(current.title): hast du selbst verschoben, bleibt."))
                continue
            }
            guard let day = Self.planDay(change.day) else { continue }
            switch position(for: current, in: batch, day: day, start: change.start.flatMap(Self.minutes), minutes: change.minutes) {
            case .success(let position):
                guard position != current.position else { continue }
                revised[index].place(at: position, fromDay: current.fromDay ?? batch.days.first)
                revised[index].previousPosition = current.position
                changed.append(id)
            case .failure(let error):
                rejected.append(String(localized: "\(current.title): \(error.message)"))
            }
        }
        let violations = await newViolations(in: batch, revised: &revised, changed: changed)
        for id in changed {
            guard let reason = violations[id], let title = batch.suggestions.first(where: { $0.id == id })?.title else { continue }
            rejected.append(String(localized: "\(title): \(reason)"))
        }
        let applied = revised.filter { changed.contains($0.id) && violations[$0.id] == nil }
        let lines = applied.compactMap { new -> String? in
            guard let old = new.previousPosition else { return nil }
            let from = Self.positionText(old, calendar: planning.calendar), to = Self.positionText(new.position, calendar: planning.calendar)
            return String(localized: "\(new.title) \(from) → \(to)")
        }
        if !applied.isEmpty { batch.revisionUndo = batch.suggestions }
        batch.suggestions = revised
        var conversation = batch.conversation ?? []
        conversation.append(SuggestionMessage(role: .user, text: comment, suggestionID: suggestion.id))
        conversation.append(SuggestionMessage(role: .assistant, text: answer.reply, suggestionID: suggestion.id,
                                              changes: lines, rejected: rejected))
        batch.conversation = conversation
        save(batch)
        await planning.reload()
    }

    // MARK: Positions and checks

    struct PositionError: Error {
        let message: String
    }

    /// Where a suggestion goes when it is moved to `day`: in a day plan a block on the plan's day (with time)
    /// or a move to a later working day; in a week or month plan a work day of the plan.
    private func position(for suggestion: PlanSuggestion, in batch: SuggestionBatch, day: PlanDay, start: Int?,
                          minutes: Int?) -> Result<SuggestionPosition, PositionError> {
        guard suggestion.kind != .dayChange else {
            return .failure(PositionError(message: String(localized: "Die Arbeitszeit änderst du im Vorschlag selbst.")))
        }
        guard day >= planning.today else { return .failure(PositionError(message: String(localized: "Der Tag liegt in der Vergangenheit."))) }
        if batch.scope == .day, let planDay = batch.days.first {
            if day == planDay {
                let earlier = suggestion.kind == .block ? suggestion : nil
                guard let start = start ?? earlier?.startMinutes ?? suggestion.aiPosition?.startMinutes,
                      let length = minutes ?? earlier?.minutes ?? suggestion.aiPosition?.minutes else {
                    return .failure(PositionError(message: String(localized: "Der Beginn fehlt.")))
                }
                guard length >= 15, start >= 0, start + length <= 24 * 60 else {
                    return .failure(PositionError(message: String(localized: "Die Zeit ist ungültig.")))
                }
                return .success(SuggestionPosition(kind: .block, day: day, startMinutes: start, minutes: length))
            }
            guard day > planning.today, day > planDay else {
                return .failure(PositionError(message: String(localized: "Nur auf einen späteren Tag verschiebbar.")))
            }
            return .success(SuggestionPosition(kind: .move, day: day, startMinutes: nil, minutes: nil))
        }
        guard batch.days.contains(day) else { return .failure(PositionError(message: String(localized: "Nur Tage dieser Planung.")))}
        return .success(SuggestionPosition(kind: suggestion.kind == .move ? .move : .assignment, day: day,
                                           startMinutes: nil, minutes: nil))
    }

    /// Checks `revised` against fresh data and reverts each change that causes a violation the batch did not
    /// have before; returns the reasons by suggestion. Recomputes which blocks need a suggested longer day.
    private func newViolations(in batch: SuggestionBatch, revised: inout [PlanSuggestion], changed: [UUID]) async -> [UUID: String] {
        var rejected: [UUID: String] = [:]
        var open = changed
        let originals = Dictionary(batch.suggestions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let inputs = await checkInputs(for: batch)
        let baseline = Set(violations(of: batch.suggestions, batch: batch, inputs: inputs).map { "\($0.taskId)|\($0.reason)" })
        while true {
            let found = violations(of: Self.unchangedFirst(revised, changed: open), batch: batch, inputs: inputs)
                .filter { !baseline.contains("\($0.taskId)|\($0.reason)") }
            guard !found.isEmpty, !open.isEmpty else { break }
            // Blame a changed suggestion of the violating task, else the last change (capacity is order-dependent).
            let blamed = open.last { id in found.contains { $0.taskId == revised.first { $0.id == id }?.taskKey } } ?? open.last!
            let reason = found.first { $0.taskId == revised.first { $0.id == blamed }?.taskKey }?.reason ?? found[0].reason
            rejected[blamed] = reason.text
            if let index = revised.firstIndex(where: { $0.id == blamed }), let original = originals[blamed] {
                revised[index] = original
                revised[index].previousPosition = nil
            }
            open.removeAll { $0 == blamed }
        }
        revised = dependencies(revised, inputs: inputs)
        // A suggested longer day that no block needs any more has no effect (mockup AB1): it goes.
        let neededBefore = Set(batch.suggestions.compactMap(\.dependsOn))
        let neededNow = Set(revised.compactMap(\.dependsOn))
        revised.removeAll { $0.kind == .dayChange && neededBefore.contains($0.id) && !neededNow.contains($0.id) }
        return rejected
    }

    /// Fresh plan input of the batch's days (with a suggested longer day applied), for checks.
    private func checkInputs(for batch: SuggestionBatch) async -> [PlanInputDay] {
        guard let first = batch.days.min(), let last = batch.days.max() else { return [] }
        let days = Set(batch.days)
        let changes = batch.suggestions.filter { $0.kind == .dayChange }
        return await planning.planInputs(in: first...last).filter { days.contains($0.day) }.map { day in
            guard let change = changes.first(where: { $0.day == day.day }), let start = change.startMinutes, let end = change.endMinutes else {
                return day
            }
            var extended = day.withHours(WorkHours(startMinutes: start, endMinutes: end))
            extended.blocks = day.blocks
            return extended
        }
    }

    private func violations(of suggestions: [PlanSuggestion], batch: SuggestionBatch, inputs: [PlanInputDay]) -> [PlanViolation] {
        let ids = Set(suggestions.compactMap(\.taskID))
        if batch.scope == .day {
            let blocks = suggestions.filter { $0.kind == .block }
            guard let day = inputs.first, !blocks.isEmpty else { return [] }
            var input = makeInput(scope: .day, only: ids)
            input.days = [day]
            let output = PlanOutput.day(DayPlanOutput(blocks: blocks.map {
                PlanBlock(taskId: $0.taskKey, start: Self.time($0.startMinutes ?? 0), minutes: $0.minutes ?? 0, reason: $0.reason)
            }, unscheduled: [], risks: [], estimates: []))
            return validate(output, input: input).violations
        }
        let assignments = suggestions.filter { $0.kind == .assignment }
        guard !assignments.isEmpty else { return [] }
        var input = makeInput(scope: .week, only: ids)
        input.days = inputs
        let output = PlanOutput.period(PeriodPlanOutput(assignments: assignments.map {
            PlanAssignment(taskId: $0.taskKey, day: Self.dayString($0.day), reason: $0.reason)
        }, unscheduled: [], risks: [], estimates: []))
        return validate(output, input: input).violations
    }

    /// Unchanged suggestions first: load is counted in order, so a change is the one that tips a day over.
    private static func unchangedFirst(_ suggestions: [PlanSuggestion], changed: [UUID]) -> [PlanSuggestion] {
        suggestions.filter { !changed.contains($0.id) } + suggestions.filter { changed.contains($0.id) }
    }

    /// A block depends on a suggested longer day when it lies outside the day's normal hours (mockup AB1).
    private func dependencies(_ suggestions: [PlanSuggestion], inputs: [PlanInputDay]) -> [PlanSuggestion] {
        let changes = suggestions.filter { $0.kind == .dayChange }
        return suggestions.map { suggestion in
            var copy = suggestion
            guard copy.kind == .block, let start = copy.startMinutes,
                  let change = changes.first(where: { $0.day == copy.day }) else {
                if copy.kind != .block { copy.dependsOn = nil }
                return copy
            }
            let end = start + (copy.minutes ?? 0)
            let normal = planning.workHours(on: copy.day)
            copy.dependsOn = normal.map { start < $0.startMinutes || end > $0.endMinutes } ?? true ? change.id : nil
            return copy
        }
    }

    // MARK: Request

    /// Short names for the suggestions the model may change ("s1", "s2" …); longer days are left out.
    static func refs(for batch: SuggestionBatch) -> [String: UUID] {
        var refs: [String: UUID] = [:]
        for (index, suggestion) in batch.suggestions.filter({ $0.kind != .dayChange }).enumerated() {
            refs["s\(index + 1)"] = suggestion.id
        }
        return refs
    }

    private func revisionRequest(batch: SuggestionBatch, about: PlanSuggestion, comment: String, refs: [String: UUID]) async throws -> String {
        let refByID = Dictionary(refs.map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let suggestions: [[String: Any]] = batch.suggestions.compactMap { suggestion in
            guard let ref = refByID[suggestion.id] else { return nil }
            var entry: [String: Any] = ["ref": ref, "taskId": suggestion.taskKey, "title": suggestion.title,
                                        "kind": suggestion.kind.rawValue, "day": Self.dayString(suggestion.day),
                                        "status": suggestion.isMovedByUser ? "movedByUser" : "open"]
            if let start = suggestion.startMinutes { entry["start"] = Self.time(start) }
            if let minutes = suggestion.minutes { entry["minutes"] = minutes }
            if let ai = suggestion.aiPosition {
                entry["aiDay"] = Self.dayString(ai.day)
                if let start = ai.startMinutes { entry["aiStart"] = Self.time(start) }
                if let minutes = ai.minutes { entry["aiMinutes"] = minutes }
            }
            if !suggestion.reason.isEmpty { entry["reason"] = suggestion.reason }
            return entry
        }
        let later = batch.scope == .day ? await laterDays(after: batch.days.first ?? planning.today) : []
        var input = makeInput(scope: batch.scope, only: Set(batch.suggestions.compactMap(\.taskID)))
        input.days = await checkInputs(for: batch)
        input.laterDays = later
        let planningJSON = try JSONSerialization.jsonObject(with: input.modelJSON())
        let conversation = (batch.conversation ?? []).suffix(20).map { ["role": $0.role.rawValue, "text": $0.text] }
        let body: [String: Any] = [
            "comment": comment,
            "about": refByID[about.id] ?? "",
            "conversation": conversation,
            "suggestions": suggestions,
            "allowedDays": (batch.days + later.map(\.day)).map(Self.dayString),
            "planning": planningJSON,
        ]
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    static let revisionInstructions = """
    Jetzt besprichst du die offenen Vorschläge einer Planung. Die Person kommentiert den Vorschlag about. \
    Antworte im Format suggestion_revision: reply (ein bis zwei Sätze in der Sprache des Kommentars, Deutsch oder Englisch, was du geändert hast und warum) \
    und changes (nur die Vorschläge, die sich ändern, mit ref, day, start, minutes). Ändere nur, was der Kommentar \
    verlangt; andere Vorschläge nur, wenn es dafür nötig ist (zum Beispiel ein Tausch). Vorschläge mit status \
    movedByUser hat die Person selbst gesetzt (aiStart war deine Zeit): lass sie unverändert, außer about verweist \
    auf sie. Nutze nur freeSlots und Tage aus allowedDays. Im Tagesplan haben Blöcke start (HH:MM) und minutes; \
    ein Block auf einem anderen Tag aus laterDays wird zur Verschiebung, dann sind start und minutes null. In Wochen- \
    und Monatsplänen sind start und minutes immer null. Längere Arbeitstage (dayChanges) änderst du hier nicht. \
    Keine neuen Vorschläge, keine gestrichenen. Passt nichts, lass changes leer und sag es in reply.
    """

    static var revisionSchema: Data {
        let change: [String: Any] = [
            "type": "object", "additionalProperties": false, "required": ["ref", "day", "start", "minutes"],
            "properties": [
                "ref": ["type": "string"],
                "day": ["type": "string"],
                "start": ["type": ["string", "null"]],
                "minutes": ["type": ["integer", "null"]],
            ],
        ]
        let schema: [String: Any] = [
            "type": "object", "additionalProperties": false, "required": ["reply", "changes"],
            "properties": ["reply": ["type": "string"], "changes": ["type": "array", "items": change]],
        ]
        return (try? JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    // MARK: Helpers

    private func batch(containing id: UUID) -> SuggestionBatch? {
        store.batches().first { $0.suggestions.contains { $0.id == id } }
    }

    /// Stores a changed batch; the "Widerrufen" capsules of earlier actions would restore stale batches.
    private func save(_ batch: SuggestionBatch) {
        clearDismissUndo()
        clearAcceptUndo()
        store.update(batch)
    }

    /// "14:00", "Do 19." or "Do 19. 14:00" for the change card.
    static func positionText(_ position: SuggestionPosition, calendar: Calendar) -> String {
        let day = SuggestionFacts.weekdayDay(position.day, calendar: calendar)
        switch position.kind {
        case .block: return position.startMinutes.map { DateText.time(minutes: $0, calendar: calendar) } ?? day
        case .move, .assignment, .dayChange: return day
        }
    }
}
