import Foundation
import HealthKit
import TagwerkCore

/// Pure mapping between Tagwerk entries and HealthKit metadata, types and identifiers.
public enum HealthMapping {
    /// Every Tagwerk sample carries its entry UUID, so one predicate finds all samples of an entry.
    public static let entryIDKey = "TagwerkEntryID"
    /// Marks samples written by Tagwerk (in addition to the source check).
    public static let markerKey = "TagwerkEntry"
    /// Marks values that came from an AI estimate.
    public static let estimatedKey = "TagwerkEstimated"

    /// The nutrient samples of a meal. The first four belong to the core group (`HealthShareKind`); the others are written
    /// only with the permission of their own group (`HealthAccessGroup.moreNutrients`).
    public enum Nutrient: String, Sendable, CaseIterable {
        case energy, protein, carbs, fat, fiber, sugar, saturatedFat, sodium

        /// The core write kind, `nil` for the nutrients of the group `moreNutrients`.
        var shareKind: HealthShareKind? {
            switch self {
            case .energy: .energy
            case .protein: .protein
            case .carbs: .carbs
            case .fat: .fat
            case .fiber, .sugar, .saturatedFat, .sodium: nil
            }
        }

        var isCore: Bool { shareKind != nil }

        var identifier: HKQuantityTypeIdentifier {
            switch self {
            case .energy: .dietaryEnergyConsumed
            case .protein: .dietaryProtein
            case .carbs: .dietaryCarbohydrates
            case .fat: .dietaryFatTotal
            case .fiber: .dietaryFiber
            case .sugar: .dietarySugar
            case .saturatedFat: .dietaryFatSaturated
            case .sodium: .dietarySodium
            }
        }

        /// The unit of the written value; sodium is stored in milligrams.
        var unit: HKUnit {
            switch self {
            case .energy: .kilocalorie()
            case .sodium: .gramUnit(with: .milli)
            default: .gram()
            }
        }
    }

    /// "tagwerk.<kind>.<UUID>[.<part>]".
    public static func syncIdentifier(_ kind: HealthEntryKind, id: UUID, part: String? = nil) -> String {
        "tagwerk.\(kind.rawValue).\(id.uuidString)" + (part.map { ".\($0)" } ?? "")
    }

    /// Metadata of one sample. Created and consumed locally; never crosses a concurrency boundary.
    static func metadata(syncIdentifier: String, entryID: UUID, version: Int, estimated: Bool,
                         userEntered: Bool) -> [String: Any] {
        var metadata: [String: Any] = [
            HKMetadataKeySyncIdentifier: syncIdentifier,
            HKMetadataKeySyncVersion: version,
            entryIDKey: entryID.uuidString,
            markerKey: 1,
        ]
        if estimated { metadata[estimatedKey] = 1 }
        if userEntered { metadata[HKMetadataKeyWasUserEntered] = true }
        return metadata
    }

    /// Nutrients above zero are written; the others are removed, so an edit to 0 or to "unknown" leaves no stale sample.
    /// Values are in the unit of the nutrient (`Nutrient.unit`): salt becomes sodium in milligrams.
    static func nutrientPlan(for meal: HealthMeal) -> (writes: [(nutrient: Nutrient, value: Double)], removals: [Nutrient]) {
        var writes: [(nutrient: Nutrient, value: Double)] = []
        var removals: [Nutrient] = []
        for nutrient in Nutrient.allCases {
            let value: Double? = switch nutrient {
            case .energy: meal.kcal
            case .protein: meal.protein
            case .carbs: meal.carbs
            case .fat: meal.fat
            case .fiber: meal.fiber
            case .sugar: meal.sugar
            case .saturatedFat: meal.saturatedFat
            case .sodium: meal.salt.map { NutrientValues.sodiumGrams(fromSalt: $0) * 1000 }
            }
            if let value, value > 0 { writes.append((nutrient, value)) } else { removals.append(nutrient) }
        }
        return (writes, removals)
    }

    /// What a save of a meal does with the permissions at hand: only permitted nutrients are written or removed. A meal counts as
    /// mirrored (`isComplete`) unless it has core values and none of them may be written; a nutrient of an optional group that is
    /// not allowed is skipped without keeping the meal marked for retry. (A later grant resets the meals, see `IntakeStore`.)
    static func mealWrite(plan: (writes: [(nutrient: Nutrient, value: Double)], removals: [Nutrient]),
                          mayWrite: (Nutrient) -> Bool)
        -> (writes: [(nutrient: Nutrient, value: Double)], removals: [Nutrient], isComplete: Bool) {
        let writes = plan.writes.filter { mayWrite($0.nutrient) }
        let removals = plan.removals.filter(mayWrite)
        let hasCoreValues = plan.writes.contains { $0.nutrient.isCore }
        let isComplete = !hasCoreValues || writes.contains { $0.nutrient.isCore }
        return (writes, removals, isComplete)
    }

    /// Quantity types of an entry kind outside the core `HealthShareKind` list; deleting an entry removes them as well.
    static func extraDeleteIdentifiers(for kind: HealthEntryKind) -> [HKQuantityTypeIdentifier] {
        switch kind {
        case .meal: Nutrient.allCases.filter { !$0.isCore }.map(\.identifier)
        case .drink, .workout: []
        }
    }

    static func activityType(_ activity: WorkoutActivity) -> HKWorkoutActivityType {
        switch activity {
        case .strength: .traditionalStrengthTraining
        case .running: .running
        case .cycling: .cycling
        case .walking: .walking
        case .hiking: .hiking
        case .swimming: .swimming
        case .yoga: .yoga
        case .hiit: .highIntensityIntervalTraining
        case .other: .other
        }
    }

    /// The Tagwerk activity for a Health type, if one fits.
    static func activity(for type: HKWorkoutActivityType) -> WorkoutActivity? {
        switch type {
        case .traditionalStrengthTraining, .functionalStrengthTraining: .strength
        case .running: .running
        case .cycling: .cycling
        case .walking: .walking
        case .hiking: .hiking
        case .swimming: .swimming
        case .yoga: .yoga
        case .highIntensityIntervalTraining: .hiit
        default: nil
        }
    }

    /// Name of a Health workout type in the app language; common types only, otherwise "Training".
    static func activityName(_ type: HKWorkoutActivityType) -> String {
        if let activity = activity(for: type) { return activity.displayName }
        return switch type {
        case .elliptical: String(localized: "Crosstrainer", bundle: .module)
        case .rowing: String(localized: "Rudern", bundle: .module)
        case .stairClimbing, .stairs: String(localized: "Treppensteigen", bundle: .module)
        case .dance, .socialDance, .cardioDance: String(localized: "Tanzen", bundle: .module)
        case .pilates: String(localized: "Pilates", bundle: .module)
        case .coreTraining: String(localized: "Rumpftraining", bundle: .module)
        case .crossTraining: String(localized: "Cross-Training", bundle: .module)
        case .mixedCardio: String(localized: "Gemischtes Cardio", bundle: .module)
        case .soccer: String(localized: "Fußball", bundle: .module)
        case .tennis: String(localized: "Tennis", bundle: .module)
        case .climbing: String(localized: "Klettern", bundle: .module)
        case .cooldown: String(localized: "Cool-down", bundle: .module)
        default: String(localized: "Training", bundle: .module)
        }
    }

    /// Whether a sample was written by Tagwerk: by its source first, by the marker as a fallback.
    static func isOwn(metadata: [String: Any]?, sourceBundleID: String, ownBundleID: String?) -> Bool {
        if let ownBundleID, sourceBundleID == ownBundleID { return true }
        return metadata?[markerKey] != nil
    }

    /// The access row state from the request status and the share types that are not authorized.
    static func access(shouldRequest: Bool, denied: Set<HealthShareKind>) -> HealthAccess {
        if shouldRequest { return .notDetermined }
        if denied.isEmpty { return .authorized }
        if denied.count == HealthShareKind.allCases.count { return .denied }
        return .partial(HealthShareKind.allCases.filter(denied.contains))
    }

    /// A group counts as asked once iOS would no longer show its sheet; an unknown status does not bring the button back.
    static func groupAccess(_ status: HKAuthorizationRequestStatus) -> HealthGroupAccess {
        status == .shouldRequest ? .notAsked : .asked
    }

    /// Steps count as asked once iOS would no longer show the sheet; an unknown status does not bring the button back.
    static func stepsAccess(_ status: HKAuthorizationRequestStatus) -> StepsAccess {
        status == .shouldRequest ? .notAsked : .asked
    }

    /// Day sums rounded to whole steps; days without statistics are dropped (no value, not 0).
    static func dailySteps(_ sums: [(start: Date, count: Double?)]) -> [DailySteps] {
        sums.compactMap { sum in sum.count.map { DailySteps(start: sum.start, count: Int($0.rounded())) } }
    }
}
