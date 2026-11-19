import Foundation
import Observation
import SwiftData
import TagwerkCore

/// Reads and writes the per-entry reminder lists (plan P4). Reading never inserts a record.
@MainActor
@Observable
final class ReminderOverrideStore {
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let now: () -> Date
    /// Counts every change, so the notification plan can notice that an override changed.
    private(set) var revision = 0

    init(context: ModelContext, now: @escaping () -> Date = Date.init) {
        self.context = context
        self.now = now
    }

    /// All readable overrides by `itemKey`.
    func overrides() -> [String: [ReminderOverride]] {
        let records = (try? context.fetch(FetchDescriptor<ReminderOverrideRecord>())) ?? []
        return Dictionary(grouping: records.compactMap(\.override), by: \.itemKey)
    }

    func overrides(for itemKey: String) -> [ReminderOverride] {
        overrides()[itemKey] ?? []
    }

    /// Stores the override, replacing one with the same item and scope.
    func save(_ override: ReminderOverride) throws {
        let key = ReminderOverrideRecord.key(itemKey: override.itemKey, scope: override.scope)
        if let existing = try fetch(key: key) {
            existing.update(from: override, at: now())
        } else {
            context.insert(ReminderOverrideRecord(override, updatedAt: now()))
        }
        try context.save()
        revision += 1
    }

    func remove(itemKey: String, scope: ReminderOverride.Scope) throws {
        guard let existing = try fetch(key: ReminderOverrideRecord.key(itemKey: itemKey, scope: scope)) else { return }
        context.delete(existing)
        try context.save()
        revision += 1
    }

    func removeAll(itemKey: String) throws {
        guard Self.deleteRecords(itemKey: itemKey, in: context) > 0 else { return }
        try context.save()
        revision += 1
    }

    /// Removes "only this one" overrides of repeating tasks whose due date lies before `today`: the series moved on.
    @discardableResult
    func removeStaleOnlyDue(today: PlanDay) -> Int {
        let records = (try? context.fetch(FetchDescriptor<ReminderOverrideRecord>())) ?? []
        var removed = 0
        for record in records {
            guard case .onlyDue(let due)? = record.override?.scope, PlanDay(due) < today else { continue }
            context.delete(record)
            removed += 1
        }
        if removed > 0, (try? context.save()) != nil { revision += 1 }
        return removed
    }

    /// Deletes every record of an entry without saving (used by the deletion of a local task, which saves itself).
    @discardableResult
    static func deleteRecords(itemKey: String, in context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<ReminderOverrideRecord>(predicate: #Predicate { $0.itemKey == itemKey })
        let records = (try? context.fetch(descriptor)) ?? []
        for record in records { context.delete(record) }
        return records.count
    }

    private func fetch(key: String) throws -> ReminderOverrideRecord? {
        var descriptor = FetchDescriptor<ReminderOverrideRecord>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
