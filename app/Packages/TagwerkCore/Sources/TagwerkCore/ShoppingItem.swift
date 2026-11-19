import Foundation

/// An entry of the shopping list as the interface shows it. It mirrors a reminder and is never stored.
public struct ShoppingItem: Sendable, Hashable, Identifiable {
    /// Identifier of the reminder.
    public var id: String
    /// Title of the reminder.
    public var name: String
    /// First line of the reminder's notes.
    public var quantity: String?
    public var isCompleted: Bool
    public var completedAt: Date?
    public var createdAt: Date?
    /// The notes hold more than the quantity line; the quantity is then read-only.
    public var hasLongNotes: Bool

    public init(id: String, name: String, quantity: String? = nil, isCompleted: Bool = false, completedAt: Date? = nil,
                createdAt: Date? = nil, hasLongNotes: Bool = false) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.hasLongNotes = hasLongNotes
    }

    /// The quantity is the first line of the notes (trimmed, `nil` when empty). Notes are long when
    /// anything follows the first line; such notes are never overwritten by a quantity.
    public static func quantity(fromNotes notes: String?) -> (quantity: String?, hasLongNotes: Bool) {
        guard let notes else { return (nil, false) }
        let lines = notes.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let first = lines.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        let hasMore = lines.dropFirst().contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return (first.isEmpty ? nil : first, hasMore)
    }
}
