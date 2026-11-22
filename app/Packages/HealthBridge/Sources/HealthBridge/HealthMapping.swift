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

    /// The nutrient samples of a meal.
    public enum Nutrient: String, Sendable, CaseIterable {
        case energy, protein, carbs, fat

        var shareKind: HealthShareKind {
            switch self {
            case .energy: .energy
            case .protein: .protein
            case .carbs: .carbs
            case .fat: .fat
            }
        }

        var identifier: HKQuantityTypeIdentifier {
            switch self {
            case .energy: .dietaryEnergyConsumed
            case .protein: .dietaryProtein
            case .carbs: .dietaryCarbohydrates
            case .fat: .dietaryFatTotal
            }
        }

        var unit: HKUnit { self == .energy ? .kilocalorie() : .gram() }
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

    /// Nutrients above zero are written; the others are removed, so an edit to 0 leaves no stale sample.
    static func nutrientPlan(for meal: HealthMeal) -> (writes: [(nutrient: Nutrient, value: Double)], removals: [Nutrient]) {
        var writes: [(nutrient: Nutrient, value: Double)] = []
        var removals: [Nutrient] = []
        for nutrient in Nutrient.allCases {
            let value = switch nutrient {
            case .energy: meal.kcal
            case .protein: meal.protein
            case .carbs: meal.carbs
            case .fat: meal.fat
            }
            if value > 0 { writes.append((nutrient, value)) } else { removals.append(nutrient) }
        }
        return (writes, removals)
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
