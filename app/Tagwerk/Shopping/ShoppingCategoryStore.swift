import Foundation
import Observation
import SwiftData
import TagwerkCore

/// Categories of the shopping list and the learned assignments of item names to them.
/// The only place that writes `ShoppingCategory` and `ShoppingAssignment`.
@MainActor
@Observable
final class ShoppingCategoryStore {
    static let manualSource = "manual"
    static let aiSource = "ai"

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let now: () -> Date
    /// Bumped by every write, so views that read the categories follow.
    private(set) var revision = 0

    init(context: ModelContext, settings: AppSettings, now: @escaping () -> Date = Date.init) {
        self.context = context
        self.settings = settings
        self.now = now
    }

    /// All categories by `sortIndex`, ties by creation date.
    func categories() -> [ShoppingCategoryInfo] {
        _ = revision
        return records().map { ShoppingCategoryInfo(id: $0.id, name: $0.name, sortIndex: $0.sortIndex, builtinKey: $0.builtinKey) }
    }

    /// Name key → assignment.
    func assignments() -> [String: ShoppingAssignmentInfo] {
        _ = revision
        let all = (try? context.fetch(FetchDescriptor<ShoppingAssignment>())) ?? []
        return Dictionary(all.map { ($0.nameKey, ShoppingAssignmentInfo(categoryID: $0.categoryID,
                                                                         isManual: $0.sourceRaw == Self.manualSource)) },
                          uniquingKeysWith: { first, _ in first })
    }

    /// Creates the built-in categories once, named in the app language of this moment. Categories deleted
    /// later do not come back through this.
    func seedIfNeeded() {
        guard !settings.shoppingCategoriesSeeded else { return }
        settings.shoppingCategoriesSeeded = true
        if records().isEmpty {
            for (index, builtin) in ShoppingBuiltinCategory.allCases.enumerated() {
                context.insert(ShoppingCategory(name: builtin.localizedName, sortIndex: index, builtinKey: builtin.rawValue,
                                                createdAt: now()))
            }
        }
        save()
    }

    /// Adds a category at the end. Throws `ShoppingCategoryRules.NameError`.
    @discardableResult
    func add(name: String) throws -> ShoppingCategoryInfo {
        let existing = records()
        let validated = try ShoppingCategoryRules.validatedName(name, existing: existing.map(\.name), isNew: true)
        let record = ShoppingCategory(name: validated, sortIndex: (existing.map(\.sortIndex).max() ?? -1) + 1, createdAt: now())
        context.insert(record)
        save()
        return ShoppingCategoryInfo(id: record.id, name: record.name, sortIndex: record.sortIndex, builtinKey: nil)
    }

    /// Renames a category; a built-in one keeps its key, so the dictionary still sorts into it.
    func rename(_ id: UUID, to name: String) throws {
        let all = records()
        guard let record = all.first(where: { $0.id == id }) else { return }
        record.name = try ShoppingCategoryRules.validatedName(name, existing: all.filter { $0.id != id }.map(\.name), isNew: false)
        save()
    }

    /// Moves categories like `Array.move(fromOffsets:toOffset:)` and renumbers all of them.
    func move(fromOffsets: IndexSet, toOffset: Int) {
        var ordered = records()
        let moving = fromOffsets.filter { ordered.indices.contains($0) }.map { ordered[$0] }
        guard !moving.isEmpty else { return }
        let target = toOffset - fromOffsets.filter { $0 < toOffset }.count
        for offset in fromOffsets.reversed() where ordered.indices.contains(offset) { ordered.remove(at: offset) }
        ordered.insert(contentsOf: moving, at: min(max(target, 0), ordered.count))
        for (index, record) in ordered.enumerated() { record.sortIndex = index }
        save()
    }

    /// Removes the category and every assignment that points to it. Items of that category are sorted
    /// again like new ones; the reminders are not touched.
    func delete(_ id: UUID) {
        for record in records() where record.id == id { context.delete(record) }
        let pointing = (try? context.fetch(FetchDescriptor<ShoppingAssignment>())) ?? []
        for assignment in pointing where assignment.categoryID == id { context.delete(assignment) }
        save()
    }

    /// Appends the built-in categories that are missing; existing and own categories stay as they are.
    /// A built-in whose name is taken by another category, or that would exceed the limit, is left out.
    func restoreBuiltins() {
        var existing = records()
        for builtin in ShoppingBuiltinCategory.allCases where !existing.contains(where: { $0.builtinKey == builtin.rawValue }) {
            guard let name = try? ShoppingCategoryRules.validatedName(builtin.localizedName, existing: existing.map(\.name),
                                                                      isNew: true) else { continue }
            let record = ShoppingCategory(name: name, sortIndex: (existing.map(\.sortIndex).max() ?? -1) + 1,
                                          builtinKey: builtin.rawValue, createdAt: now())
            context.insert(record)
            existing.append(record)
        }
        save()
    }

    /// Remembers the category of an item name. A suggestion (`manual == false`) never replaces a choice of the user.
    func assign(nameKey: String, to categoryID: UUID?, manual: Bool) {
        guard !nameKey.isEmpty else { return }
        let matching = (try? context.fetch(FetchDescriptor<ShoppingAssignment>(predicate: #Predicate { $0.nameKey == nameKey }))) ?? []
        if !manual, matching.contains(where: { $0.sourceRaw == Self.manualSource }) { return }
        let source = manual ? Self.manualSource : Self.aiSource
        if let existing = matching.first {
            existing.categoryID = categoryID
            existing.sourceRaw = source
            existing.updatedAt = now()
            for duplicate in matching.dropFirst() { context.delete(duplicate) }
        } else {
            context.insert(ShoppingAssignment(nameKey: nameKey, categoryID: categoryID, sourceRaw: source, updatedAt: now()))
        }
        save()
    }

    private func records() -> [ShoppingCategory] {
        let all = (try? context.fetch(FetchDescriptor<ShoppingCategory>())) ?? []
        return all.sorted { $0.sortIndex != $1.sortIndex ? $0.sortIndex < $1.sortIndex : $0.createdAt < $1.createdAt }
    }

    private func save() {
        try? context.save()
        revision += 1
    }
}
