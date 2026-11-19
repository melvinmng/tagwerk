import Foundation
import SwiftData
import TagwerkCore

/// The reminder list of one entry that replaces the default (plan P4, assumption A2). Lives in Tagwerk only.
/// Schema rule: later attributes must be optional or have a default value.
@Model
final class ReminderOverrideRecord {
    /// `itemKey`, scope and scope value joined by a unit separator; never parsed.
    @Attribute(.unique) var key: String
    /// `ReminderOverride.key(task:)` or `ReminderOverride.key(deadlineSeries:)`.
    var itemKey: String = ""
    /// "always", "onlyDue", "occurrence" or "seriesFrom".
    var scopeRaw: String = "always"
    /// The due date (JSON) for "onlyDue", the occurrence ID, or the first day (JSON) for "seriesFrom".
    var scopeValue: String?
    /// `ReminderOverride.Storage` raw value.
    var storageRaw: String = "tagwerk"
    /// JSON of `[ReminderOffset]`.
    var offsetsData: Data = Data()
    var updatedAt: Date = Date.now

    init(_ override: ReminderOverride, updatedAt: Date = .now) {
        let (raw, value) = Self.encode(override.scope)
        self.key = Self.key(itemKey: override.itemKey, scope: override.scope)
        self.itemKey = override.itemKey
        self.scopeRaw = raw
        self.scopeValue = value
        self.storageRaw = override.storage.rawValue
        self.offsetsData = (try? JSONEncoder().encode(override.offsets)) ?? Data()
        self.updatedAt = updatedAt
    }

    /// The rule the record stores; `nil` when its data cannot be read (such a record is ignored, never fatal).
    var override: ReminderOverride? {
        guard let scope = Self.decode(raw: scopeRaw, value: scopeValue),
              let offsets = try? JSONDecoder().decode([ReminderOffset].self, from: offsetsData) else { return nil }
        return ReminderOverride(itemKey: itemKey, scope: scope, storage: ReminderOverride.Storage(rawValue: storageRaw) ?? .tagwerk,
                                offsets: offsets)
    }

    /// Replaces the stored values with those of `override` (same key).
    func update(from override: ReminderOverride, at date: Date) {
        storageRaw = override.storage.rawValue
        offsetsData = (try? JSONEncoder().encode(override.offsets)) ?? Data()
        updatedAt = date
    }

    static func key(itemKey: String, scope: ReminderOverride.Scope) -> String {
        let (raw, value) = encode(scope)
        return [itemKey, raw, value ?? ""].joined(separator: "\u{1F}")
    }

    private static func encode(_ scope: ReminderOverride.Scope) -> (String, String?) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        func json<Value: Encodable>(_ value: Value) -> String? {
            (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) }
        }
        switch scope {
        case .always: return ("always", nil)
        case .onlyDue(let due): return ("onlyDue", json(due))
        case .occurrence(let id): return ("occurrence", id)
        case .seriesFrom(let day): return ("seriesFrom", json(day))
        }
    }

    private static func decode(raw: String, value: String?) -> ReminderOverride.Scope? {
        let data = Data((value ?? "").utf8)
        switch raw {
        case "always": return .always
        case "onlyDue": return (try? JSONDecoder().decode(DueDate.self, from: data)).map { .onlyDue($0) }
        case "occurrence": return value.map { .occurrence($0) }
        case "seriesFrom": return (try? JSONDecoder().decode(PlanDay.self, from: data)).map { .seriesFrom($0) }
        default: return nil
        }
    }
}
