import Foundation
import TagwerkCore

/// Kind of a Tagwerk entry mirrored to Health; part of every sync identifier.
public enum HealthEntryKind: String, Sendable {
    case meal, drink, workout

    /// The Health types an entry of this kind can have samples in.
    public var shareKinds: [HealthShareKind] {
        switch self {
        case .meal: [.energy, .protein, .carbs, .fat]
        case .drink: [.water]
        case .workout: [.workouts, .activeEnergy]
        }
    }
}

/// A meal as written to Health: numbers only, never titles or item names.
public struct HealthMeal: Sendable, Hashable {
    public var id: UUID
    public var date: Date
    /// Increases with every edit; Health replaces a sample only for a higher version.
    public var version: Int
    public var kcal: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var estimated: Bool

    public init(id: UUID, date: Date, version: Int, kcal: Double, protein: Double, carbs: Double, fat: Double, estimated: Bool) {
        self.id = id
        self.date = date
        self.version = version
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.estimated = estimated
    }
}

public struct HealthDrink: Sendable, Hashable {
    public var id: UUID
    public var date: Date
    public var version: Int
    public var milliliters: Int

    public init(id: UUID, date: Date, version: Int, milliliters: Int) {
        self.id = id
        self.date = date
        self.version = version
        self.milliliters = milliliters
    }
}

public struct HealthWorkout: Sendable, Hashable {
    public var id: UUID
    public var version: Int
    public var activity: WorkoutActivity
    public var start: Date
    public var end: Date
    public var kilocalories: Double?

    public init(id: UUID, version: Int, activity: WorkoutActivity, start: Date, end: Date, kilocalories: Double?) {
        self.id = id
        self.version = version
        self.activity = activity
        self.start = start
        self.end = end
        self.kilocalories = kilocalories
    }
}

/// A workout another app (e.g. the Apple Watch) wrote to Health.
public struct ForeignWorkout: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var activityName: String
    /// The matching Tagwerk activity, for the symbol; `nil` when there is none.
    public var activity: WorkoutActivity?
    public var start: Date
    public var end: Date
    public var kilocalories: Double?
    public var sourceName: String

    public init(id: UUID, activityName: String, activity: WorkoutActivity?, start: Date, end: Date, kilocalories: Double?,
                sourceName: String) {
        self.id = id
        self.activityName = activityName
        self.activity = activity
        self.start = start
        self.end = end
        self.kilocalories = kilocalories
        self.sourceName = sourceName
    }
}

/// The data types Tagwerk writes to Health.
public enum HealthShareKind: String, Sendable, CaseIterable, Hashable {
    case energy, protein, carbs, fat, water, workouts, activeEnergy

    public var displayName: String {
        switch self {
        case .energy: String(localized: "Kalorien", bundle: .module)
        case .protein: String(localized: "Eiweiß", bundle: .module)
        case .carbs: String(localized: "Kohlenhydrate", bundle: .module)
        case .fat: String(localized: "Fett", bundle: .module)
        case .water: String(localized: "Wasser", bundle: .module)
        case .workouts: String(localized: "Trainings", bundle: .module)
        case .activeEnergy: String(localized: "Trainingskalorien", bundle: .module)
        }
    }
}

/// What the "Health" access row shows. Only write access is visible; iOS hides whether reading was denied.
public enum HealthAccess: Sendable, Hashable {
    case unavailable
    case notDetermined
    case authorized
    /// Some types may not be written; listed in `HealthShareKind` order.
    case partial([HealthShareKind])
    case denied

    /// Whether Tagwerk may try to write or read (permission was asked at least once).
    public var wasAsked: Bool {
        switch self {
        case .unavailable, .notDetermined: false
        case .authorized, .partial, .denied: true
        }
    }
}
