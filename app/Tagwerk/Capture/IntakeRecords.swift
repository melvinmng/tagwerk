import Foundation
import SwiftData
import HealthBridge
import TagwerkCore

// Entries of the "Erfassen" tab. Tagwerk is the source of truth; Health holds mirrored copies (phase 3 design §3).
// Schema rule: later attributes must be optional or have a default value.

@Model
final class MealRecord {
    @Attribute(.unique) var id: UUID
    var date: Date
    var kindRaw: String
    var title: String
    /// JSON of `[MealItem]`.
    var itemsData: Data
    var originRaw: String
    /// When ChatGPT produced the values; `nil` for typed meals.
    var estimatedAt: Date?
    /// Sync version in Health; increases with every edit.
    var healthVersion: Int = 1
    var healthSynced: Bool = false

    init(_ value: MealValue, estimatedAt: Date?, healthVersion: Int = 1) {
        self.id = value.id
        self.date = value.date
        self.kindRaw = value.kind.rawValue
        self.title = value.title
        self.itemsData = (try? JSONEncoder().encode(value.items)) ?? Data("[]".utf8)
        self.originRaw = value.origin.rawValue
        self.estimatedAt = estimatedAt
        self.healthVersion = healthVersion
    }

    var value: MealValue {
        MealValue(id: id, date: date, kind: MealKind(rawValue: kindRaw) ?? .snack, title: title,
                  items: (try? JSONDecoder().decode([MealItem].self, from: itemsData)) ?? [],
                  origin: MealOrigin(rawValue: originRaw) ?? .manual)
    }

    func apply(_ value: MealValue) {
        date = value.date
        kindRaw = value.kind.rawValue
        title = value.title
        itemsData = (try? JSONEncoder().encode(value.items)) ?? itemsData
        originRaw = value.origin.rawValue
    }
}

@Model
final class DrinkRecord {
    @Attribute(.unique) var id: UUID
    var date: Date
    var milliliters: Int
    var healthVersion: Int = 1
    var healthSynced: Bool = false

    init(_ value: DrinkValue, healthVersion: Int = 1) {
        self.id = value.id
        self.date = value.date
        self.milliliters = value.milliliters
        self.healthVersion = healthVersion
    }

    var value: DrinkValue { DrinkValue(id: id, date: date, milliliters: milliliters) }
}

@Model
final class WorkoutRecord {
    @Attribute(.unique) var id: UUID
    var activityRaw: String
    var start: Date
    var minutes: Int
    var kilocalories: Double?
    var healthVersion: Int = 1
    var healthSynced: Bool = false

    init(id: UUID, activity: WorkoutActivity, start: Date, minutes: Int, kilocalories: Double?, healthVersion: Int = 1) {
        self.id = id
        self.activityRaw = activity.rawValue
        self.start = start
        self.minutes = minutes
        self.kilocalories = kilocalories
        self.healthVersion = healthVersion
    }

    var value: WorkoutValue {
        WorkoutValue(id: id.uuidString, activity: WorkoutActivity(rawValue: activityRaw) ?? .other, start: start,
                     minutes: minutes, kilocalories: kilocalories, sourceName: nil, isOwn: true)
    }
}

/// A Health deletion that has not happened yet: it waits for the undo window, or Health was not reachable.
@Model
final class PendingHealthDeletion {
    @Attribute(.unique) var entryID: UUID
    var notBefore: Date
    /// `HealthEntryKind` raw value; limits the deletion to the types of the entry.
    var kindRaw: String = "meal"

    init(entryID: UUID, notBefore: Date, kind: HealthEntryKind) {
        self.entryID = entryID
        self.notBefore = notBefore
        self.kindRaw = kind.rawValue
    }
}
