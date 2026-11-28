import Foundation
import OSLog
import SwiftData
import TagwerkCore

/// Stores "Meine Lebensmittel" in SwiftData. The list stays on the device and is part of the backup.
@MainActor
final class FoodStore {
    private let context: ModelContext
    private let logger = Logger(subsystem: "local.tagwerk", category: "food")
    private let now: () -> Date

    init(context: ModelContext, now: @escaping () -> Date = { Date() }) {
        self.context = context
        self.now = now
    }

    /// All foods, sorted by name.
    func foods() -> [FoodValue] {
        let records = (try? context.fetch(FetchDescriptor<FoodRecord>())) ?? []
        return records.map(\.value).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The foods whose name contains every word of `query`; all foods for an empty query.
    func search(_ query: String) -> [FoodValue] { FoodSearch.matching(foods(), query: query) }

    func food(_ id: UUID) -> FoodValue? { record(id)?.value }

    /// The food with this barcode, compared in its normalized form (a UPC-A code matches the EAN-13 code with a leading zero). When
    /// several foods carry the same code, the one created last wins. `nil` for an unknown or invalid code.
    func food(barcode: String) -> FoodValue? {
        guard let key = Barcode.comparisonKey(barcode) else { return nil }
        let records = (try? context.fetch(FetchDescriptor<FoodRecord>())) ?? []
        return records
            .filter { $0.barcode.flatMap(Barcode.comparisonKey) == key }
            .max { $0.createdAt < $1.createdAt }?
            .value
    }

    var isEmpty: Bool {
        var descriptor = FetchDescriptor<FoodRecord>()
        descriptor.fetchLimit = 1
        return ((try? context.fetchCount(descriptor)) ?? 0) == 0
    }

    /// Adds a food, or replaces the one with the same identity. An invalid food (no name, negative energy) is not stored,
    /// and `false` is returned when saving failed.
    @discardableResult
    func save(_ value: FoodValue) -> Bool {
        guard value.isValid else { return false }
        var food = value
        food.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = record(food.id) {
            existing.apply(food)
        } else {
            context.insert(FoodRecord(food, createdAt: now()))
        }
        return persist()
    }

    func delete(_ id: UUID) {
        guard let existing = record(id) else { return }
        context.delete(existing)
        persist()
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            try context.save()
            return true
        } catch {
            logger.error("Saving foods failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func record(_ id: UUID) -> FoodRecord? {
        let descriptor = FetchDescriptor<FoodRecord>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }
}
