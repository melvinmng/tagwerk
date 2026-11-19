import Foundation
import SwiftData

/// A category of the shopping list. Items are not stored; they stay in Apple Reminders.
/// Schema rule: every attribute has a default value, nothing is unique, no relationships.
@Model
final class ShoppingCategory {
    var id: UUID = UUID()
    var name: String = ""
    var sortIndex: Int = 0
    /// Raw value of `ShoppingBuiltinCategory` for the categories Tagwerk created; `nil` for the user's own.
    var builtinKey: String? = nil
    var createdAt: Date = Date.now

    init(name: String, sortIndex: Int, builtinKey: String? = nil, createdAt: Date = .now) {
        self.name = name
        self.sortIndex = sortIndex
        self.builtinKey = builtinKey
        self.createdAt = createdAt
    }
}

/// Learned assignment "item name → category". It applies to every item with that name, now and later.
/// The name key is kept unique by `ShoppingCategoryStore`, not by the schema.
@Model
final class ShoppingAssignment {
    /// Normalized item name (`ShoppingName.key`).
    var nameKey: String = ""
    /// `nil` places the name under "Sonstiges".
    var categoryID: UUID? = nil
    /// "manual" (chosen by the user) or "ai" (applied suggestion from ChatGPT).
    var sourceRaw: String = "manual"
    var updatedAt: Date = Date.now

    init(nameKey: String, categoryID: UUID?, sourceRaw: String, updatedAt: Date = .now) {
        self.nameKey = nameKey
        self.categoryID = categoryID
        self.sourceRaw = sourceRaw
        self.updatedAt = updatedAt
    }
}
