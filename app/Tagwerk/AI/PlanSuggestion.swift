import Foundation
import SwiftData
import TagwerkCore

/// One AI suggestion that waits for the user's answer: a time block (day plan) or a work day (week/month).
struct PlanSuggestion: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case block, assignment, move, dayChange }

    var id: UUID
    var kind: Kind
    var taskKey: String
    var title: String
    var day: PlanDay
    /// Minutes since midnight; blocks only.
    var startMinutes: Int?
    var minutes: Int?
    var reason: String
    /// Day changes: the new end of work (minutes since midnight); `startMinutes` is the new start.
    var endMinutes: Int?
    /// Moves: the day the task leaves.
    var fromDay: PlanDay?
    /// Blocks in time that only a longer day provides: the day-change suggestion they need (mockup AB1).
    var dependsOn: UUID?
    /// Where the AI had put it, set when the user moves it by hand (mockup VM1); such a suggestion is pinned:
    /// the AI leaves it where it is unless the user talks about it.
    var aiPosition: SuggestionPosition?
    /// Where it was before the AI changed it in a conversation (mockup VA1, "geändert").
    var previousPosition: SuggestionPosition?

    var taskID: TaskID? { TaskID(key: taskKey) }
    var isMovedByUser: Bool { aiPosition != nil }
    var position: SuggestionPosition {
        SuggestionPosition(kind: kind, day: day, startMinutes: startMinutes, minutes: minutes)
    }

    /// Puts the suggestion at `position`; a block moved to another day of a day plan is a move (`fromDay`).
    mutating func place(at position: SuggestionPosition, fromDay origin: PlanDay?) {
        kind = position.kind
        day = position.day
        startMinutes = position.startMinutes
        minutes = position.minutes
        fromDay = position.kind == .move ? origin : nil
    }
}

/// Kind, day and time of a suggestion: what moving by hand or a conversation changes.
struct SuggestionPosition: Codable, Hashable {
    var kind: PlanSuggestion.Kind
    var day: PlanDay
    var startMinutes: Int?
    var minutes: Int?
}

/// One message of the conversation about a planning (mockup VK1). The answer lists what changed.
struct SuggestionMessage: Codable, Hashable, Identifiable {
    enum Role: String, Codable { case user, assistant }

    var id = UUID()
    var role: Role
    var text: String
    /// The suggestion the user commented on.
    var suggestionID: UUID?
    /// "Mail an Prüfungsamt 18:00 → 16:00", answers only.
    var changes: [String]?
    /// Changes Tagwerk did not take, with the reason, answers only.
    var rejected: [String]?
}

/// A task the AI (or the local check) left out, with the reason shown under "Nicht eingeplant".
struct UnscheduledTask: Codable, Hashable {
    var taskKey: String
    var title: String
    var reason: String
}

/// The answer of one planning call that is still open.
struct SuggestionBatch: Codable, Hashable, Identifiable {
    var id: UUID
    var scope: PlanScope
    var days: [PlanDay]
    var createdAt: Date
    var suggestions: [PlanSuggestion]
    var unscheduled: [UnscheduledTask]
    var risks: [String]
    /// The model's effort estimates (`TaskID.key` → minutes), stored locally only on acceptance.
    var estimates: [String: Int]
    /// The model's assessment of the period (one or two sentences).
    var summary: String?
    /// The conversation about this planning (mockup VK1).
    var conversation: [SuggestionMessage]?
    /// The suggestions before the last answer of the conversation, for "Rückgängig".
    var revisionUndo: [PlanSuggestion]?

    var isEmpty: Bool { suggestions.isEmpty && unscheduled.isEmpty && risks.isEmpty }
}

/// SwiftData record holding one batch as JSON.
@Model
final class PlanSuggestionRecord {
    var batchID: UUID = UUID()
    var firstDayKey: Int = 0
    var lastDayKey: Int = 0
    var payload: Data = Data()

    init(batchID: UUID, firstDayKey: Int, lastDayKey: Int, payload: Data) {
        self.batchID = batchID
        self.firstDayKey = firstDayKey
        self.lastDayKey = lastDayKey
        self.payload = payload
    }
}

/// Open AI suggestions, kept until accepted or dismissed. A new plan replaces the batches it overlaps.
@MainActor
final class SuggestionStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    static func key(_ day: PlanDay) -> Int { day.year * 10_000 + day.month * 100 + day.day }

    func batches() -> [SuggestionBatch] {
        records().compactMap { try? JSONDecoder().decode(SuggestionBatch.self, from: $0.payload) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Batches that touch `range`.
    func batches(in range: ClosedRange<PlanDay>) -> [SuggestionBatch] {
        batches().filter { batch in batch.days.contains { range.contains($0) } }
    }

    func suggestions(on day: PlanDay) -> [PlanSuggestion] {
        batches().flatMap(\.suggestions).filter { $0.day == day }
    }

    /// Stores `batch` and drops older batches of the same kind (day plan vs. week/month plan) whose days
    /// overlap it; planning the week keeps open day suggestions.
    func replace(with batch: SuggestionBatch) {
        let days = Set(batch.days)
        for record in records() {
            guard let old = try? JSONDecoder().decode(SuggestionBatch.self, from: record.payload),
                  (old.scope == .day) == (batch.scope == .day),
                  old.days.contains(where: days.contains) else { continue }
            context.delete(record)
        }
        write(batch)
    }

    /// Writes a changed batch; an empty batch is removed.
    func update(_ batch: SuggestionBatch) {
        for record in records() where record.batchID == batch.id { context.delete(record) }
        if batch.isEmpty { save() } else { write(batch) }
    }

    func remove(_ batchID: UUID) {
        for record in records() where record.batchID == batchID { context.delete(record) }
        save()
    }

    private func write(_ batch: SuggestionBatch) {
        guard let payload = try? JSONEncoder().encode(batch) else { return }
        let keys = batch.days.map(Self.key)
        context.insert(PlanSuggestionRecord(batchID: batch.id, firstDayKey: keys.min() ?? 0,
                                            lastDayKey: keys.max() ?? 0, payload: payload))
        save()
    }

    private func records() -> [PlanSuggestionRecord] {
        (try? context.fetch(FetchDescriptor<PlanSuggestionRecord>())) ?? []
    }

    private func save() {
        try? context.save()
    }
}
